import Foundation

/// Fail-closed isolated launch mode for development and GUI testing.
///
/// Normal launches never see this type: with none of the flags below present,
/// `resolve` returns `nil` and every path resolver keeps its production behavior.
///
/// When any flag is present the launch is an isolated test launch. It is only
/// allowed to proceed when BOTH an isolated configuration directory and an
/// isolated Library Root were supplied explicitly, and every check passes.
/// Anything else is a refusal that happens before any live service is built,
/// so no production settings, logs, snapshots, registry or Library are read or
/// written. There is deliberately no fallback to production locations.
///
/// Changing HOME, the bundle identifier or copying the .app does NOT isolate
/// anything (Application Support resolves through the user record), which is
/// why isolation is an explicit path contract instead.
enum IsolatedLaunch {
    static let configDirectoryArgument = "--spinlab-isolated-config"
    static let libraryRootArgument = "--spinlab-isolated-library"
    static let selfTestArgument = "--spinlab-isolated-selftest"
    static let configDirectoryEnvironmentKey = "SPINLAB_ISOLATED_CONFIG_DIR"
    static let libraryRootEnvironmentKey = "SPINLAB_ISOLATED_LIBRARY_ROOT"

    /// A directory only counts as an authorized isolated root when it carries
    /// this marker, which the test harness creates deliberately. A real research
    /// Library never has it, so pointing test mode at one is refused without
    /// having to read any production settings.
    static let markerFileName = ".spinlab-isolated-test-root"
    static let markerContents = "spinlab-isolated-test-root-v1"
    /// A synthetic fixture is small; anything bigger is refused as "not a fixture".
    static let maxFixtureEntries = 50_000
    /// Exit code used when the process refuses to start (EX_CONFIG).
    static let refusalExitCode: Int32 = 78

    struct Configuration: Equatable, Sendable {
        /// Canonical (symlink-free) isolated configuration directory.
        let configDirectory: URL
        /// Canonical (symlink-free) isolated Library Root.
        let libraryRoot: URL

        func authorizesLibraryRoot(_ url: URL) -> Bool {
            IsolatedLaunch.canonical(url).path == libraryRoot.path
        }

        /// True when `url` is inside (or is) the isolated config directory or Library Root.
        func authorizes(_ url: URL) -> Bool {
            let target = IsolatedLaunch.canonical(url)
            return IsolatedLaunch.isInside(target, of: configDirectory)
                || IsolatedLaunch.isInside(target, of: libraryRoot)
        }

        /// Forces the Library Root and strips anything that could redirect to
        /// production (bookmarks, paths outside the isolated roots).
        func enforced(on settings: LibrarySettings) -> LibrarySettings {
            var result = settings
            result.rootPath = libraryRoot.path
            result.rootBookmarkData = nil
            func keepIfAuthorized(_ value: String?) -> String? {
                guard let value, !value.isEmpty else { return nil }
                return authorizes(URL(fileURLWithPath: value)) ? value : nil
            }
            result.registryInternalPath = keepIfAuthorized(result.registryInternalPath)
            result.registrySourcePath = keepIfAuthorized(result.registrySourcePath)
            result.backupPath = keepIfAuthorized(result.backupPath)
            result.obsidianExperimentVaultPath = keepIfAuthorized(result.obsidianExperimentVaultPath)
            return result
        }
    }

    enum Refusal: Error, Equatable, CustomStringConvertible {
        case missingConfigDirectory
        case missingLibraryRoot
        case conflictingSources(String)
        case notAbsolute(String)
        case notFound(String)
        case notDirectory(String)
        case symlinkLeaf(String)
        case symlinkEscape(String)
        case tooLargeForFixture(String)
        case markerMissing(String)
        case overlapsProduction(String)
        case productionLibraryUnknown(String)
        case configAndLibraryOverlap
        case settingsUnreadable(String)
        case settingsOutsideIsolation(field: String, path: String)

        var description: String {
            switch self {
            case .missingConfigDirectory:
                return "isolated launch requires --spinlab-isolated-config <existing directory>"
            case .missingLibraryRoot:
                return "isolated launch requires --spinlab-isolated-library <existing directory>"
            case let .conflictingSources(what):
                return "\(what) was given twice with different values (argument vs environment)"
            case let .notAbsolute(path):
                return "path must be absolute and normalized: \(path)"
            case let .notFound(path):
                return "path does not exist: \(path)"
            case let .notDirectory(path):
                return "path is not a directory: \(path)"
            case let .symlinkLeaf(path):
                return "path is a symbolic link: \(path)"
            case let .symlinkEscape(path):
                return "a symbolic link inside the isolated root points outside it: \(path)"
            case let .tooLargeForFixture(path):
                return "too many entries to be a synthetic fixture: \(path)"
            case let .markerMissing(path):
                return "missing \(IsolatedLaunch.markerFileName) marker: \(path)"
            case let .overlapsProduction(path):
                return "overlaps a production location: \(path)"
            case let .productionLibraryUnknown(reason):
                return "cannot determine the real Library location safely (\(reason)); refusing to start"
            case .configAndLibraryOverlap:
                return "config directory and Library Root must be separate directories"
            case let .settingsUnreadable(path):
                return "isolated settings file is unreadable: \(path)"
            case let .settingsOutsideIsolation(field, path):
                return "isolated settings field \(field) points outside the isolated roots: \(path)"
            }
        }
    }

    // MARK: - Process-wide active configuration

    private final class ActiveBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Configuration?
        func get() -> Configuration? { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ new: Configuration?) { lock.lock(); value = new; lock.unlock() }
    }

    private static let box = ActiveBox()

    /// The configuration of this process, or nil for an ordinary launch.
    static var active: Configuration? { box.get() }

    /// True if the launch arguments/environment ask for isolated mode at all.
    static func isRequested(arguments: [String], environment: [String: String]) -> Bool {
        let flags = [configDirectoryArgument, libraryRootArgument, selfTestArgument]
        if arguments.contains(where: { arg in flags.contains(where: { arg == $0 || arg.hasPrefix($0 + "=") }) }) {
            return true
        }
        return environment[configDirectoryEnvironmentKey] != nil
            || environment[libraryRootEnvironmentKey] != nil
    }

    /// Resolves and activates isolation for this process. Call exactly once, first thing at launch.
    @discardableResult
    static func bootstrap(
        arguments: [String],
        environment: [String: String]
    ) -> Result<Configuration?, Refusal> {
        let result = resolveAgainstProduction(
            arguments: arguments,
            environment: environment,
            settingsFiles: productionSettingsFiles(),
            fixedProtected: productionProtectedPaths()
        )
        if case let .success(configuration) = result {
            box.set(configuration)
        }
        return result
    }

    // MARK: - Resolution (pure; no global state)

    /// `resolve` plus the read-only look at the real saved settings. Any location
    /// those settings name is protected; if they cannot be understood, refuse.
    static func resolveAgainstProduction(
        arguments: [String],
        environment: [String: String],
        settingsFiles: [URL],
        fixedProtected: [URL],
        maxEntries: Int = IsolatedLaunch.maxFixtureEntries
    ) -> Result<Configuration?, Refusal> {
        guard isRequested(arguments: arguments, environment: environment) else { return .success(nil) }
        switch configuredProductionLocations(settingsFiles: settingsFiles) {
        case let .success(configured):
            return resolve(arguments: arguments, environment: environment,
                           protectedPaths: fixedProtected + configured, maxEntries: maxEntries)
        case let .failure(refusal):
            return .failure(refusal)
        }
    }

    static func resolve(
        arguments: [String],
        environment: [String: String],
        protectedPaths: [URL],
        fileManager: FileManager = .default,
        maxEntries: Int = IsolatedLaunch.maxFixtureEntries
    ) -> Result<Configuration?, Refusal> {
        guard isRequested(arguments: arguments, environment: environment) else {
            return .success(nil)
        }
        do {
            let rawConfig = try value(of: configDirectoryArgument, envKey: configDirectoryEnvironmentKey,
                                      arguments: arguments, environment: environment)
            let rawLibrary = try value(of: libraryRootArgument, envKey: libraryRootEnvironmentKey,
                                       arguments: arguments, environment: environment)
            guard let rawConfig else { throw Refusal.missingConfigDirectory }
            guard let rawLibrary else { throw Refusal.missingLibraryRoot }

            let config = try validatedRoot(rawConfig, protectedPaths: protectedPaths, fileManager: fileManager, maxEntries: maxEntries)
            let library = try validatedRoot(rawLibrary, protectedPaths: protectedPaths, fileManager: fileManager, maxEntries: maxEntries)
            if config.path == library.path
                || isInside(config, of: library) || isInside(library, of: config) {
                throw Refusal.configAndLibraryOverlap
            }
            let configuration = Configuration(configDirectory: config, libraryRoot: library)
            try validateStoredSettings(configuration, fileManager: fileManager)
            return .success(configuration)
        } catch let refusal as Refusal {
            return .failure(refusal)
        } catch {
            return .failure(.settingsUnreadable(error.localizedDescription))
        }
    }

    private static func value(
        of flag: String,
        envKey: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> String? {
        var fromArgument: String?
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            if arg == flag {
                fromArgument = index + 1 < arguments.count ? arguments[index + 1] : ""
                index += 1
            } else if arg.hasPrefix(flag + "=") {
                fromArgument = String(arg.dropFirst(flag.count + 1))
            }
            index += 1
        }
        let fromEnvironment = environment[envKey]
        if let fromArgument, let fromEnvironment, fromArgument != fromEnvironment {
            throw Refusal.conflictingSources(flag)
        }
        let chosen = fromArgument ?? fromEnvironment
        guard let chosen, !chosen.isEmpty else { return nil }
        return chosen
    }

    private static func validatedRoot(
        _ raw: String,
        protectedPaths: [URL],
        fileManager fm: FileManager,
        maxEntries: Int
    ) throws -> URL {
        guard raw.hasPrefix("/"),
              !raw.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else {
            throw Refusal.notAbsolute(raw)
        }
        let given = URL(fileURLWithPath: raw)
        if let type = (try? fm.attributesOfItem(atPath: given.path))?[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            throw Refusal.symlinkLeaf(raw)
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: given.path, isDirectory: &isDir) else { throw Refusal.notFound(raw) }
        guard isDir.boolValue else { throw Refusal.notDirectory(raw) }

        let resolved = canonical(given)

        for protected in protectedPaths {
            let p = canonical(protected)
            if resolved.path == p.path || isInside(resolved, of: p) || isInside(p, of: resolved) {
                throw Refusal.overlapsProduction(resolved.path)
            }
        }

        let marker = resolved.appending(path: markerFileName)
        let markerType = (try? fm.attributesOfItem(atPath: marker.path))?[.type] as? FileAttributeType
        guard markerType == .typeRegular,
              let data = try? Data(contentsOf: marker),
              String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == markerContents else {
            throw Refusal.markerMissing(resolved.path)
        }

        try rejectEscapingSymlinks(in: resolved, fileManager: fm, maxEntries: maxEntries)
        return resolved
    }

    private static func rejectEscapingSymlinks(in root: URL, fileManager fm: FileManager, maxEntries: Int) throws {
        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return }
        var count = 0
        for case let url as URL in walker {
            count += 1
            if count > maxEntries { throw Refusal.tooLargeForFixture(root.path) }
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true else { continue }
            // Resolve the link's own destination (works for dangling links too, which
            // would otherwise let a write create a file outside the root).
            guard let destination = try? fm.destinationOfSymbolicLink(atPath: url.path) else {
                throw Refusal.symlinkEscape(url.path)
            }
            let absolute = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : url.deletingLastPathComponent().appending(path: destination)
            if !isInside(canonical(absolute), of: root) { throw Refusal.symlinkEscape(url.path) }
        }
    }

    /// Stored settings inside the isolated config dir must not point outside the isolated roots.
    private static func validateStoredSettings(_ configuration: Configuration, fileManager fm: FileManager) throws {
        func readObject(_ name: String) throws -> [String: Any]? {
            let url = configuration.configDirectory.appending(path: name)
            guard fm.fileExists(atPath: url.path) else { return nil }
            guard let data = try? Data(contentsOf: url),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw Refusal.settingsUnreadable(url.path)
            }
            return object
        }
        if let settings = try readObject("library_settings.json") {
            if let root = settings["rootPath"] as? String, !root.isEmpty,
               !configuration.authorizesLibraryRoot(URL(fileURLWithPath: root)) {
                throw Refusal.settingsOutsideIsolation(field: "rootPath", path: root)
            }
            for field in ["registryInternalPath", "registrySourcePath", "backupPath", "obsidianExperimentVaultPath"] {
                if let value = settings[field] as? String, !value.isEmpty,
                   !configuration.authorizes(URL(fileURLWithPath: value)) {
                    throw Refusal.settingsOutsideIsolation(field: field, path: value)
                }
            }
        }
        if let rules = try readObject("rules_book.json"),
           let value = rules["rulesBookPath"] as? String, !value.isEmpty,
           !configuration.authorizes(URL(fileURLWithPath: value)) {
            throw Refusal.settingsOutsideIsolation(field: "rulesBookPath", path: value)
        }
    }

    // MARK: - Path helpers

    /// Symlink-free absolute form. Uses realpath so system links such as /var and
    /// /tmp resolve consistently; a not-yet-existing tail is appended unresolved.
    static func canonical(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while true {
            if let resolved = realPath(existing.path) {
                var result = URL(fileURLWithPath: resolved)
                for component in tail.reversed() { result.append(path: component) }
                // Not standardizedFileURL: it strips the /private prefix again.
                return result
            }
            if existing.path == "/" || existing.pathComponents.count <= 1 { break }
            tail.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return url.standardizedFileURL
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func isInside(_ child: URL, of parent: URL) -> Bool {
        // NSString components: URL.pathComponents keeps a trailing "/" for directory URLs.
        let c = (child.path as NSString).pathComponents
        let p = (parent.path as NSString).pathComponents
        return c.count > p.count && Array(c.prefix(p.count)) == p
    }

    /// The real settings files an ordinary launch would read.
    static func productionSettingsFiles(fileManager fm: FileManager = .default) -> [URL] {
        productionProtectedPaths(fileManager: fm).map { $0.appending(path: "library_settings.json") }
    }

    /// Read-only: collects every real location the user's saved settings point at
    /// (Library Root, bookmark target, backup, registry, vault). Nothing is written,
    /// no security scope is started. A settings file that exists but cannot be
    /// read, parsed, or whose bookmark cannot be resolved makes the answer
    /// unknowable, so the result is a refusal.
    static func configuredProductionLocations(settingsFiles: [URL]) -> Result<[URL], Refusal> {
        let fm = FileManager.default
        var found: [URL] = []
        for file in settingsFiles {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: file.path, isDirectory: &isDir) else {
                // A dangling link reports "missing" but may still lead somewhere: unknowable.
                if (try? fm.destinationOfSymbolicLink(atPath: file.path)) != nil {
                    return .failure(.productionLibraryUnknown("settings link is unresolvable: \(file.path)"))
                }
                continue
            }
            guard !isDir.boolValue, let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else {
                return .failure(.productionLibraryUnknown("settings unreadable: \(file.path)"))
            }
            for (key, value) in dict {
                if key.hasSuffix("Path"), let text = value as? String, !text.isEmpty {
                    guard text.hasPrefix("/") else {
                        return .failure(.productionLibraryUnknown("relative path in settings: \(key)"))
                    }
                    found.append(URL(fileURLWithPath: text))
                }
                if key.hasSuffix("BookmarkData"), !(value is NSNull) {
                    guard let encoded = value as? String, let bookmark = Data(base64Encoded: encoded) else {
                        return .failure(.productionLibraryUnknown("bookmark unreadable: \(key)"))
                    }
                    var stale = false
                    guard let url = try? URL(
                        resolvingBookmarkData: bookmark,
                        options: [.withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale
                    ) else {
                        return .failure(.productionLibraryUnknown("bookmark cannot be resolved: \(key)"))
                    }
                    found.append(url)
                }
            }
        }
        return .success(found)
    }

    /// Fixed production locations a test launch may never overlap. The real
    /// Library Root is user-configured; it is added from the saved settings
    /// (see `configuredProductionLocations`) and also needs the marker.
    static func productionProtectedPaths(fileManager fm: FileManager = .default) -> [URL] {
        var homes: [URL] = [URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)]
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            homes.append(URL(fileURLWithPath: String(cString: dir), isDirectory: true))
        }
        var supports = homes.map { $0.appending(path: "Library/Application Support", directoryHint: .isDirectory) }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            supports.append(support)
        }
        var result: [URL] = []
        for support in supports {
            result.append(support.appending(path: "SpinLab", directoryHint: .isDirectory))
            result.append(support.appending(path: "com.spinlab.app", directoryHint: .isDirectory))
        }
        return result
    }
}

// MARK: - Headless self-test

extension IsolatedLaunch {
    /// Exercises the real startup path (live services, settings, logging, snapshot,
    /// Library load) without opening any window, prints a JSON report and exits.
    /// Only reachable after a successful isolated bootstrap.
    @MainActor
    static func runSelfTestAndExit(appState: SpinLabAppState) -> Never {
        guard let isolation = active else {
            fputs("self-test requires an isolated launch\n", stderr)
            exit(refusalExitCode)
        }
        appState.loadExistingDrawers()
        appState.validateLibraryCacheOnAppear()
        appState.flushInteractionSnapshotNow(source: "isolatedSelfTest")
        AppLogger.shared.info(.system, "Isolated self-test completed")
        let samples = appState.library.libraryExistingGroups.values.flatMap { $0 }.flatMap(\.samples)
        let report: [String: Any] = [
            "configDirectory": isolation.configDirectory.path,
            "libraryRoot": isolation.libraryRoot.path,
            "settingsFile": appState.library.librarySettingsStore.settingsURL.path,
            "effectiveRootPath": appState.library.librarySettings.rootPath ?? "",
            "sampleCount": samples.count,
            "sampleDisplayNames": samples.map(\.displayName).sorted(),
            "readIssues": appState.library.libraryReadIssues
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        fflush(stdout)
        exit(0)
    }
}
