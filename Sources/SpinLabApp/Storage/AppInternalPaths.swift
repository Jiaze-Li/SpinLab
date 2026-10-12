import Foundation

/// Application Support paths for app-internal state (NOT user-editable rule files).
/// Rule JSON files live in the user-configured Rules Book directory (see RulesBookSettings).
struct AppInternalPaths {
    let appSupportDirectoryURL: URL

    var ruleSetStateURL: URL {
        appSupportDirectoryURL.appendingPathComponent("rule_set_state.json")
    }

    var rulesBookSettingsURL: URL {
        appSupportDirectoryURL.appendingPathComponent("rules_book.json")
    }

    var migrationStateURL: URL {
        appSupportDirectoryURL.appendingPathComponent(".migration_state.json")
    }

    var migrationFailedURL: URL {
        appSupportDirectoryURL.appendingPathComponent(".migration_failed.json")
    }

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMainApp = bundleID?.caseInsensitiveCompare("com.spinlab.app") == .orderedSame
        let appFolder: String
        if !RulesConfigPaths.isRunningTests() && isMainApp {
            appFolder = "SpinLab"
        } else if let bundleID, !bundleID.isEmpty {
            appFolder = bundleID
        } else {
            TestStorageLifecycle.start(in: base)
            appFolder = TestStorageLifecycle.ownFolderName
        }
        appSupportDirectoryURL = base.appendingPathComponent(appFolder, isDirectory: true)
    }

    init(appSupportDirectoryURL: URL) {
        self.appSupportDirectoryURL = appSupportDirectoryURL
    }

    /// The per-user SpinLab data folder (`pending_imports.json`, `interaction_snapshot.json`,
    /// `logs/`, `library_settings.json`, registry, ...) for code that defaults to the real
    /// location. It is `<appSupport>/SpinLab` in the real app; while tests run it is a
    /// per-process folder instead, so a test that builds a default-configured store or logger
    /// can never read or overwrite the real user's data. Explicitly injected paths must bypass this.
    static func userDataDirectory(in appSupportURL: URL) -> URL {
        let folder: String
        if RulesConfigPaths.isRunningTests() {
            TestStorageLifecycle.start(in: appSupportURL)
            folder = TestStorageLifecycle.ownFolderName
        } else {
            folder = "SpinLab"
        }
        return appSupportURL.appending(path: folder, directoryHint: .isDirectory)
    }
}

/// Lifecycle of the per-process `com.spinlab.tests.<pid>` folders that test runs create under
/// Application Support. Active only while tests run (it is started from the test-only branches
/// above): a test process (1) discards any leftover folder carrying its own pid, (2) reaps
/// folders orphaned by crashed or killed runs, and (3) deletes its own folder when it exits.
/// The folder is only ever removed when its name, owner, age, owning process and contents all
/// prove it is a stale test artifact; anything else is left alone.
enum TestStorageLifecycle {
    static let folderPrefix = "com.spinlab.tests."
    /// Orphaned folders younger than this are left alone (a dead pid may still be mid-teardown).
    static let staleAge: TimeInterval = 3600
    /// Folders kept only for their diagnostic logs live longer.
    static let diagnosticRetention: TimeInterval = 24 * 3600

    private static let knownEntries: Set<String> = [
        "rule_set_state.json", "rules_book.json", ".migration_state.json", ".migration_failed.json",
        "config", "registry", "projects.json", "pending_imports.json", "archived_records.json",
        "interaction_snapshot.json", "library_settings.json", "logs", ".DS_Store"
    ]
    private static let knownEntryPrefixes = ["config.v515-"]

    static var ownFolderName: String {
        folderPrefix + String(ProcessInfo.processInfo.processIdentifier)
    }

    private static var startedBases: [URL] = []
    private static var exitHookInstalled = false
    private static let startLock = NSLock()

    static func start(in base: URL) {
        startLock.lock()
        defer { startLock.unlock() }
        guard !startedBases.contains(base) else { return }
        startedBases.append(base)
        let fm = FileManager.default
        let pid = ProcessInfo.processInfo.processIdentifier
        // Anything already under this pid's name predates this process (pid reuse): discard it.
        removeIfStaleTestFolder(base.appendingPathComponent(ownFolderName, isDirectory: true), fileManager: fm)
        reapStale(in: base, currentPID: pid)
        if !exitHookInstalled {
            exitHookInstalled = true
            atexit { TestStorageLifecycle.cleanUpOwnFoldersAtExit() }
        }
    }

    private static func cleanUpOwnFoldersAtExit() {
        cleanUpOwnFolders(in: startedBases)
    }

    static func cleanUpOwnFolders(in bases: [URL]) {
        for base in bases { cleanUpOwnFolder(in: base) }
    }

    private static func cleanUpOwnFolder(in base: URL) {
        let fm = FileManager.default
        let own = base.appendingPathComponent(ownFolderName, isDirectory: true)
        guard isOwnedTestFolder(own, fileManager: fm) else { return }
        // Keep only the logs, and only when they recorded an error, so a failing run stays diagnosable.
        let events = own.appendingPathComponent("logs/app_events.log")
        let hasErrors = (try? String(contentsOf: events, encoding: .utf8))?.contains("\"level\":\"error\"") == true
        if hasErrors, let children = try? fm.contentsOfDirectory(atPath: own.path) {
            for name in children where name != "logs" {
                try? fm.removeItem(at: own.appendingPathComponent(name))
            }
        } else {
            try? fm.removeItem(at: own)
        }
    }

    /// Removes folders left by dead test processes. Returns the removed and the kept names.
    @discardableResult
    static func reapStale(
        in base: URL,
        currentPID: Int32,
        now: Date = Date(),
        isProcessAlive: (Int32) -> Bool = processIsAlive,
        dryRun: Bool = false,
        fileManager fm: FileManager = .default
    ) -> (removed: [String], kept: [String]) {
        var removed: [String] = []
        var kept: [String] = []
        let names = (try? fm.contentsOfDirectory(atPath: base.path)) ?? []
        var diagnostics: [(name: String, modified: Date)] = []
        for name in names.sorted() where name.hasPrefix(folderPrefix) {
            let url = base.appendingPathComponent(name, isDirectory: true)
            guard let pid = pid(fromFolderName: name), pid != currentPID, !isProcessAlive(pid),
                  isOwnedTestFolder(url, fileManager: fm),
                  let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            else { kept.append(name); continue }
            let logsOnly = (try? fm.contentsOfDirectory(atPath: url.path)) == ["logs"]
            let minAge = logsOnly ? diagnosticRetention : staleAge
            if logsOnly, now.timeIntervalSince(modified) < minAge {
                diagnostics.append((name, modified))
                continue
            }
            guard now.timeIntervalSince(modified) >= minAge else { kept.append(name); continue }
            if !dryRun { try? fm.removeItem(at: url) }
            removed.append(name)
        }
        // Diagnostics: keep only the most recent log-only folder so runs do not accumulate.
        let newest = diagnostics.max { $0.modified < $1.modified }?.name
        for (name, _) in diagnostics {
            if name == newest { kept.append(name); continue }
            if !dryRun { try? fm.removeItem(at: base.appendingPathComponent(name, isDirectory: true)) }
            removed.append(name)
        }
        return (removed.sorted(), kept.sorted())
    }

    static func pid(fromFolderName name: String) -> Int32? {
        guard name.hasPrefix(folderPrefix) else { return nil }
        let digits = name.dropFirst(folderPrefix.count)
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return Int32(digits)
    }

    /// True while `pid` may still be a test process. A pid that the system has since reused for an
    /// unrelated program (readable executable path that is not a test host) counts as gone, so its
    /// leftover folder is not protected forever. When unsure, the process is treated as alive.
    static func processIsAlive(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return mayBeTestProcess(executablePath: length > 0 ? String(cString: buffer) : nil)
    }

    /// Decision for a pid that exists. An unknown executable path means "may be a test process".
    static func mayBeTestProcess(executablePath path: String?) -> Bool {
        // Fail closed: only an executable under a system location that is not a test host proves reuse.
        guard let path else { return true }
        let isSystemProgram = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/"].contains { path.hasPrefix($0) }
        let isTestHost = ["swiftpm-testing-helper", "xctest", "PackageTests", "swift-test", "swift-build"]
            .contains { path.contains($0) }
        return !isSystemProgram || isTestHost
    }

    /// A real (non-symlink) directory owned by this user whose top-level entries are all known test artifacts.
    static func isOwnedTestFolder(_ url: URL, fileManager fm: FileManager) -> Bool {
        guard pid(fromFolderName: url.lastPathComponent) != nil,
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeDirectory,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let children = try? fm.contentsOfDirectory(atPath: url.path)
        else { return false }
        return children.allSatisfy { child in
            knownEntries.contains(child) || knownEntryPrefixes.contains { child.hasPrefix($0) }
        }
    }

    private static func removeIfStaleTestFolder(_ url: URL, fileManager fm: FileManager) {
        if isOwnedTestFolder(url, fileManager: fm) { try? fm.removeItem(at: url) }
    }
}
