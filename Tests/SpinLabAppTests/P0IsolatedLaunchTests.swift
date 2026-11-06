import Foundation
import Testing
@testable import SpinLabApp

/// P0 Library data safety, Phase 2: the isolated launch contract is fail-closed.
/// All fixtures are synthetic temp directories; nothing here touches real data.
@Suite("P0 isolated launch")
struct P0IsolatedLaunchTests {
    private let fm = FileManager.default

    // MARK: - Fixtures

    private func makeSandbox() throws -> URL {
        let url = fm.temporaryDirectory.appending(path: "p0-iso-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeRoot(_ name: String, in sandbox: URL, marker: Bool = true) throws -> URL {
        let url = sandbox.appending(path: name, directoryHint: .isDirectory)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        if marker {
            try IsolatedLaunch.markerContents.write(
                to: url.appending(path: IsolatedLaunch.markerFileName), atomically: true, encoding: .utf8)
        }
        return url
    }

    private func args(config: String?, library: String?) -> [String] {
        var result = ["SpinLab"]
        if let config { result += [IsolatedLaunch.configDirectoryArgument, config] }
        if let library { result += [IsolatedLaunch.libraryRootArgument, library] }
        return result
    }

    private func resolve(
        _ arguments: [String],
        environment: [String: String] = [:],
        protected: [URL] = []
    ) -> Result<IsolatedLaunch.Configuration?, IsolatedLaunch.Refusal> {
        IsolatedLaunch.resolve(arguments: arguments, environment: environment, protectedPaths: protected)
    }

    private func refusal(_ result: Result<IsolatedLaunch.Configuration?, IsolatedLaunch.Refusal>) -> IsolatedLaunch.Refusal? {
        if case let .failure(r) = result { return r }
        return nil
    }

    // MARK: - AC10: ordinary launch is untouched

    @Test("No flags and no environment: ordinary launch, nothing activated")
    func ordinaryLaunchUnchanged() {
        #expect(refusal(resolve(["SpinLab"])) == nil)
        if case let .success(config) = resolve(["SpinLab", "-NSDocumentRevisionsDebugMode", "YES"]) {
            #expect(config == nil)
        } else {
            Issue.record("ordinary launch must not be refused")
        }
        #expect(!IsolatedLaunch.isRequested(arguments: ["SpinLab"], environment: ["HOME": "/x"]))
        let base = fm.temporaryDirectory
        #expect(AppInternalPaths.userDataDirectory(in: base, isolation: nil).deletingLastPathComponent().path == base.path)
    }

    // MARK: - AC6 / AC9: both explicit paths are required, never a fallback

    @Test("Missing config or library (or only the self-test flag) is refused")
    func missingPathsRefused() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)

        #expect(refusal(resolve(args(config: nil, library: library.path))) == .missingConfigDirectory)
        #expect(refusal(resolve(args(config: config.path, library: nil))) == .missingLibraryRoot)
        #expect(refusal(resolve(["SpinLab", IsolatedLaunch.selfTestArgument])) == .missingConfigDirectory)
        #expect(refusal(resolve(args(config: "", library: library.path))) == .missingConfigDirectory)
        #expect(refusal(resolve(["SpinLab"], environment: [IsolatedLaunch.libraryRootEnvironmentKey: library.path])) == .missingConfigDirectory)
    }

    @Test("Valid explicit paths activate isolation with canonical locations")
    func validConfigurationResolves() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)

        let viaArgs = resolve(args(config: config.path, library: library.path))
        guard case let .success(.some(resolved)) = viaArgs else {
            Issue.record("expected success, got \(viaArgs)")
            return
        }
        #expect(resolved.configDirectory == IsolatedLaunch.canonical(config))
        #expect(resolved.libraryRoot == IsolatedLaunch.canonical(library))

        let viaEnv = resolve(["SpinLab"], environment: [
            IsolatedLaunch.configDirectoryEnvironmentKey: config.path,
            IsolatedLaunch.libraryRootEnvironmentKey: library.path
        ])
        #expect(viaEnv == .success(resolved))

        let viaEquals = resolve(["SpinLab", "\(IsolatedLaunch.configDirectoryArgument)=\(config.path)", "\(IsolatedLaunch.libraryRootArgument)=\(library.path)"])
        #expect(viaEquals == .success(resolved))
    }

    @Test("Argument and environment that disagree are refused")
    func conflictingSourcesRefused() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let other = try makeRoot("other", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        let result = resolve(args(config: config.path, library: library.path),
                             environment: [IsolatedLaunch.configDirectoryEnvironmentKey: other.path])
        #expect(refusal(result) == .conflictingSources(IsolatedLaunch.configDirectoryArgument))
    }

    // MARK: - AC8: invalid, escaping and production-overlapping paths

    @Test("Relative, unnormalized, missing and non-directory paths are refused")
    func invalidPathsRefused() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        let file = sandbox.appending(path: "file.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        #expect(refusal(resolve(args(config: "relative/cfg", library: library.path))) == .notAbsolute("relative/cfg"))
        #expect(refusal(resolve(args(config: "~/cfg", library: library.path))) == .notAbsolute("~/cfg"))
        let dotted = config.path + "/../cfg"
        #expect(refusal(resolve(args(config: dotted, library: library.path))) == .notAbsolute(dotted))
        let missing = sandbox.appending(path: "missing").path
        #expect(refusal(resolve(args(config: missing, library: library.path))) == .notFound(missing))
        #expect(refusal(resolve(args(config: config.path, library: file.path))) == .notDirectory(file.path))
    }

    @Test("A symbolic link as the root, or a link escaping the root, is refused")
    func symlinkEscapesRefused() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        let protectedLike = try makeRoot("pretend-production", in: sandbox)

        // Leaf is a symlink to a perfectly valid, marked directory.
        let linkLeaf = sandbox.appending(path: "libLink")
        try fm.createSymbolicLink(at: linkLeaf, withDestinationURL: library)
        #expect(refusal(resolve(args(config: config.path, library: linkLeaf.path))) == .symlinkLeaf(linkLeaf.path))

        // A link inside the isolated root that points at production data.
        let escape = library.appending(path: "batches-link")
        try fm.createSymbolicLink(at: escape, withDestinationURL: protectedLike)
        let result = resolve(args(config: config.path, library: library.path))
        let expected = IsolatedLaunch.canonical(library).appending(path: "batches-link").path
        #expect(refusal(result) == .symlinkEscape(expected))
    }

    @Test("A directory without the explicit isolation marker is refused (protects a real Library)")
    func markerRequired() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let realLooking = try makeRoot("real-looking-library", in: sandbox, marker: false)
        try fm.createDirectory(at: realLooking.appending(path: "index"), withIntermediateDirectories: true)
        try "{}".write(to: realLooking.appending(path: "index/library_index.json"), atomically: true, encoding: .utf8)

        let result = resolve(args(config: config.path, library: realLooking.path))
        #expect(refusal(result) == .markerMissing(IsolatedLaunch.canonical(realLooking).path))

        // A wrong marker body does not count either.
        try "something-else".write(to: realLooking.appending(path: IsolatedLaunch.markerFileName), atomically: true, encoding: .utf8)
        #expect(refusal(resolve(args(config: config.path, library: realLooking.path))) == .markerMissing(IsolatedLaunch.canonical(realLooking).path))
    }

    @Test("Roots equal to, inside, or containing a production location are refused")
    func productionOverlapRefused() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let production = try makeRoot("AppSupport-SpinLab", in: sandbox) // even a marked dir is refused
        let inside = try makeRoot("nested", in: production)
        let library = try makeRoot("lib", in: sandbox)
        let containing = try makeRoot("parent", in: sandbox)
        let productionBelow = try makeRoot("prod-below", in: containing)

        let equalCase = resolve(args(config: production.path, library: library.path), protected: [production])
        #expect(refusal(equalCase) == .overlapsProduction(IsolatedLaunch.canonical(production).path))
        let insideCase = resolve(args(config: inside.path, library: library.path), protected: [production])
        #expect(refusal(insideCase) == .overlapsProduction(IsolatedLaunch.canonical(inside).path))
        let libraryInside = resolve(args(config: library.path, library: inside.path), protected: [production])
        #expect(refusal(libraryInside) == .overlapsProduction(IsolatedLaunch.canonical(inside).path))
        let containingCase = resolve(args(config: containing.path, library: library.path), protected: [productionBelow])
        #expect(refusal(containingCase) == .overlapsProduction(IsolatedLaunch.canonical(containing).path))
    }

    @Test("The real production locations are always on the protected list")
    func realProductionLocationsProtected() {
        let paths = IsolatedLaunch.productionProtectedPaths().map { $0.path }
        #expect(paths.contains { $0.hasSuffix("/Library/Application Support/SpinLab") })
        #expect(paths.contains { $0.hasSuffix("/Library/Application Support/com.spinlab.app") })
    }

    @Test("Config and Library must be separate directories")
    func configAndLibraryMustNotOverlap() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let nested = try makeRoot("lib", in: config)
        #expect(refusal(resolve(args(config: config.path, library: config.path))) == .configAndLibraryOverlap)
        #expect(refusal(resolve(args(config: config.path, library: nested.path))) == .configAndLibraryOverlap)
    }

    @Test("A directory with more entries than the cap is refused (cap lowered to force it)")
    func oversizedRootRefused() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        for i in 0..<6 { try fm.createDirectory(at: library.appending(path: "d\(i)"), withIntermediateDirectories: true) }
        let a = args(config: config.path, library: library.path)
        // Under the cap: accepted. Over the cap: the very same fixture is refused.
        #expect(refusal(IsolatedLaunch.resolve(arguments: a, environment: [:], protectedPaths: [], maxEntries: 50)) == nil)
        let over = refusal(IsolatedLaunch.resolve(arguments: a, environment: [:], protectedPaths: [], maxEntries: 5))
        guard case .tooLargeForFixture = over else {
            Issue.record("expected tooLargeForFixture, got \(String(describing: over))")
            return
        }
    }

    // MARK: - Real Library protection (read-only look at saved settings; synthetic only)

    private func writeSettings(_ json: String, in sandbox: URL, name: String = "prod_settings.json") throws -> URL {
        let url = sandbox.appending(path: name)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func resolveVsProduction(
        _ a: [String],
        settings: [URL],
        readData: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) -> IsolatedLaunch.Refusal? {
        refusal(IsolatedLaunch.resolveAgainstProduction(
            arguments: a, environment: [:], settingsFiles: settings, fixedProtected: [], readData: readData))
    }

    @Test("Isolated roots inside or covering the saved real Library Root are refused")
    func savedLibraryRootProtected() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let fakeReal = try makeRoot("real", in: sandbox)          // has a marker: marker alone is not enough
        let config = try makeRoot("cfg", in: sandbox)
        let other = try makeRoot("other", in: sandbox)
        let settings = try writeSettings(#"{"rootPath": "\#(fakeReal.path)", "allowedBatchPrefixes": []}"#, in: sandbox)

        // exact match
        guard case .overlapsProduction = resolveVsProduction(args(config: config.path, library: fakeReal.path), settings: [settings]) else {
            Issue.record("exact real root must be refused"); return
        }
        // nested inside the real root
        let nested = try makeRoot("real/inner", in: sandbox)
        guard case .overlapsProduction = resolveVsProduction(args(config: config.path, library: nested.path), settings: [settings]) else {
            Issue.record("path inside real root must be refused"); return
        }
        // an unrelated marked root is fine
        #expect(resolveVsProduction(args(config: config.path, library: other.path), settings: [settings]) == nil)
    }

    @Test("Backup and registry paths from saved settings are protected as well")
    func otherSavedPathsProtected() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let backup = try makeRoot("backup", in: sandbox)
        let other = try makeRoot("other", in: sandbox)
        let settings = try writeSettings(#"{"backupPath": "\#(backup.path)", "allowedBatchPrefixes": []}"#, in: sandbox)
        guard case .overlapsProduction = resolveVsProduction(args(config: config.path, library: backup.path), settings: [settings]) else {
            Issue.record("backup path must be protected"); return
        }
        #expect(resolveVsProduction(args(config: config.path, library: other.path), settings: [settings]) == nil)
    }

    @Test("A saved security-scoped bookmark target is protected; an unresolvable one fails closed")
    func savedBookmarkProtected() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let bookmarked = try makeRoot("bm", in: sandbox)
        let data = try bookmarked.bookmarkData()
        let settings = try writeSettings(#"{"rootBookmarkData": "\#(data.base64EncodedString())", "allowedBatchPrefixes": []}"#, in: sandbox)
        guard case .overlapsProduction = resolveVsProduction(args(config: config.path, library: bookmarked.path), settings: [settings]) else {
            Issue.record("bookmark target must be protected"); return
        }
        let bad = try writeSettings(#"{"rootBookmarkData": "bm90LWEtYm9va21hcms=", "allowedBatchPrefixes": []}"#, in: sandbox, name: "bad.json")
        let other = try makeRoot("other", in: sandbox)
        guard case .productionLibraryUnknown = resolveVsProduction(args(config: config.path, library: other.path), settings: [bad]) else {
            Issue.record("unresolvable bookmark must fail closed"); return
        }
    }

    @Test("Unreadable, corrupt, or dangling saved settings fail closed; absent settings do not")
    func unknowableProductionFailsClosed() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        let a = args(config: config.path, library: library.path)

        let corrupt = try writeSettings("not json {", in: sandbox, name: "corrupt.json")
        guard case .productionLibraryUnknown = resolveVsProduction(a, settings: [corrupt]) else {
            Issue.record("corrupt settings must fail closed"); return
        }
        let relative = try writeSettings(#"{"rootPath": "relative/dir"}"#, in: sandbox, name: "rel.json")
        guard case .productionLibraryUnknown = resolveVsProduction(a, settings: [relative]) else {
            Issue.record("relative saved path must fail closed"); return
        }
        let dangling = sandbox.appending(path: "dangling.json")
        try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: sandbox.appending(path: "nowhere").path)
        guard case .productionLibraryUnknown = resolveVsProduction(a, settings: [dangling]) else {
            Issue.record("dangling settings link must fail closed"); return
        }
        // Deterministic read failure (identical for root and non-root): the reader itself throws.
        let locked = try writeSettings(#"{"allowedBatchPrefixes": []}"#, in: sandbox, name: "locked.json")
        let failing: (URL) throws -> Data = { _ in throw CocoaError(.fileReadNoPermission) }
        guard case .productionLibraryUnknown = resolveVsProduction(a, settings: [locked], readData: failing) else {
            Issue.record("unreadable settings must fail closed"); return
        }
        // No settings file at all: nothing to protect, launch proceeds.
        #expect(resolveVsProduction(a, settings: [sandbox.appending(path: "absent.json")]) == nil)
    }

    // MARK: - AC7 / AC9: stored settings can't redirect outside the isolation

    @Test("Stored settings or Rules Book pointing outside the isolated roots are refused")
    func storedSettingsOutsideRefused() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        let elsewhere = sandbox.appending(path: "elsewhere").path
        let settingsURL = config.appending(path: "library_settings.json")

        try #"{"rootPath": "\#(elsewhere)", "allowedBatchPrefixes": []}"#.write(to: settingsURL, atomically: true, encoding: .utf8)
        #expect(refusal(resolve(args(config: config.path, library: library.path)))
                == .settingsOutsideIsolation(field: "rootPath", path: elsewhere))

        try #"{"backupPath": "\#(elsewhere)", "allowedBatchPrefixes": []}"#.write(to: settingsURL, atomically: true, encoding: .utf8)
        #expect(refusal(resolve(args(config: config.path, library: library.path)))
                == .settingsOutsideIsolation(field: "backupPath", path: elsewhere))

        try "{ not json".write(to: settingsURL, atomically: true, encoding: .utf8)
        #expect(refusal(resolve(args(config: config.path, library: library.path)))
                == .settingsUnreadable(IsolatedLaunch.canonical(config).appending(path: "library_settings.json").path))

        try fm.removeItem(at: settingsURL)
        try #"{"rulesBookPath": "\#(elsewhere)"}"#.write(to: config.appending(path: "rules_book.json"), atomically: true, encoding: .utf8)
        #expect(refusal(resolve(args(config: config.path, library: library.path)))
                == .settingsOutsideIsolation(field: "rulesBookPath", path: elsewhere))

        // Settings inside the isolated roots are accepted.
        try #"{"rootPath": "\#(library.path)", "backupPath": "\#(config.path)/bk", "allowedBatchPrefixes": []}"#
            .write(to: settingsURL, atomically: true, encoding: .utf8)
        try #"{"rulesBookPath": "\#(config.path)/rules"}"#.write(to: config.appending(path: "rules_book.json"), atomically: true, encoding: .utf8)
        #expect(refusal(resolve(args(config: config.path, library: library.path))) == nil)
    }

    // MARK: - AC7 / AC9: path routing under isolation

    @Test("Every user-data location resolves into the isolated config directory")
    func userDataRoutesIntoConfigDirectory() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        guard case let .success(.some(iso)) = resolve(args(config: config.path, library: library.path)) else {
            Issue.record("expected valid isolation"); return
        }
        // Whatever Application Support the caller passes (the real one included) is ignored.
        let realLooking = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        #expect(AppInternalPaths.userDataDirectory(in: realLooking, isolation: iso) == iso.configDirectory)
    }

    @Test("Settings load never falls back to production: Root is forced, bookmarks and outside paths are stripped")
    func settingsStoreEnforcesIsolation() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        guard case let .success(.some(iso)) = resolve(args(config: config.path, library: library.path)) else {
            Issue.record("expected valid isolation"); return
        }
        let settingsURL = iso.configDirectory.appending(path: "library_settings.json")

        // No settings file at all: defaults, but the Library Root is the isolated one.
        let fresh = LibrarySettingsStore(settingsURL: settingsURL, isolation: iso).load()
        #expect(fresh.rootPath == iso.libraryRoot.path)

        // A hostile settings file (production-looking root + bookmark + backup) cannot redirect.
        var hostile = LibrarySettings.default
        hostile.rootPath = "/Users/someone/RealLibrary"
        hostile.rootBookmarkData = Data([1, 2, 3])
        hostile.backupPath = "/Volumes/Real/backup"
        hostile.registrySourcePath = iso.configDirectory.appending(path: "registry/r.xlsx").path
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(hostile).write(to: settingsURL)

        let loaded = LibrarySettingsStore(settingsURL: settingsURL, isolation: iso).load()
        #expect(loaded.rootPath == iso.libraryRoot.path)
        #expect(loaded.rootBookmarkData == nil)
        #expect(loaded.backupPath == nil)
        #expect(loaded.registrySourcePath == hostile.registrySourcePath, "authorized paths are kept")

        // Without isolation the store is unchanged (AC10).
        let plain = LibrarySettingsStore(settingsURL: settingsURL).load()
        #expect(plain.rootPath == "/Users/someone/RealLibrary")
    }

    @Test("Authorization helpers only accept the isolated Library Root and isolated subpaths")
    func authorizationHelpers() throws {
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let config = try makeRoot("cfg", in: sandbox)
        let library = try makeRoot("lib", in: sandbox)
        guard case let .success(.some(iso)) = resolve(args(config: config.path, library: library.path)) else {
            Issue.record("expected valid isolation"); return
        }
        #expect(iso.authorizesLibraryRoot(library))
        #expect(!iso.authorizesLibraryRoot(config))
        #expect(!iso.authorizesLibraryRoot(library.appending(path: "batches")))
        #expect(iso.authorizes(library.appending(path: "batches/x")))
        #expect(iso.authorizes(config.appending(path: "logs")))
        #expect(!iso.authorizes(URL(fileURLWithPath: NSHomeDirectory())))
        #expect(!iso.authorizes(sandbox.appending(path: "sibling")))
        // A sibling that merely shares a name prefix is not inside.
        #expect(!iso.authorizes(sandbox.appending(path: "lib-evil")))
    }
}
