import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Stub writer

final class StubAtomicFileWriter: AtomicFileWritingCapability {
    enum Mode {
        case realWrite
        case failAll(Error)
        case failOnCallN(Int, Error)
    }

    var mode: Mode
    private var callCount = 0

    init(mode: Mode = .realWrite) {
        self.mode = mode
    }

    func commit(_ entries: [AtomicWriteEntry]) throws {
        callCount += 1
        switch mode {
        case .realWrite:
            let fm = FileManager.default
            for entry in entries {
                try fm.createDirectory(at: entry.destinationURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try entry.data.write(to: entry.destinationURL)
            }
        case .failAll(let error):
            throw error
        case .failOnCallN(let n, let error):
            if callCount == n {
                throw error
            }
            let fm = FileManager.default
            for entry in entries {
                try fm.createDirectory(at: entry.destinationURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try entry.data.write(to: entry.destinationURL)
            }
        }
    }

    func write(_ data: Data, to destinationURL: URL) throws {
        try commit([AtomicWriteEntry(destinationURL: destinationURL, data: data)])
    }
}

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let base = FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("v515-sync-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeFakeGitRepo(at root: URL) throws -> URL {
    let gitDir = root.appendingPathComponent(".git", isDirectory: true)
    let configDir = root.appendingPathComponent("Sources/SpinLabApp/config", isDirectory: true)
    try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    return configDir
}

private func makePointerJSON(repoConfigDir: URL, repoRoot: URL) throws -> Data {
    let dict: [String: Any] = [
        "version": 1,
        "repository_config_dir": repoConfigDir.standardizedFileURL.resolvingSymlinksInPath().path,
        "repo_root": repoRoot.standardizedFileURL.resolvingSymlinksInPath().path,
        "set_at": "2026-04-26T12:00:00+08:00"
    ]
    return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
}

private let sampleData = Data("""
{"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":[]}}
""".utf8)

private let sampleDataV2 = Data("""
{"version":1,"import":{"supportedFileExtensions":["csv","xlsx"],"ignoredFileExtensions":[]}}
""".utf8)

// MARK: - Test suite

@MainActor
@Suite("V5.1.5 RulesSyncEngine", .serialized)
struct V515RulesSyncEngineTests {

    // MARK: - Case 1: valid pointer + mirror writable → .mirrored

    @Test("valid pointer with writable mirror produces .mirrored and both files match")
    func case1_validPointerMirrored() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        let runtimeURL = runtimeDir.appendingPathComponent("import_filters.json")
        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDir)
        let outcome = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "importFilters")

        #expect(outcome == .mirrored)
        let runtimeContent = try Data(contentsOf: runtimeURL)
        let mirrorURL = mirrorDir.appendingPathComponent("import_filters.json")
        let mirrorContent = try Data(contentsOf: mirrorURL)
        #expect(runtimeContent == sampleData)
        #expect(mirrorContent == sampleData)
        #expect(runtimeContent == mirrorContent)
    }

    // MARK: - Case 2: no pointer → .runtimeOnly

    @Test("nil pointer without testOverrideMirrorURL produces .runtimeOnly")
    func case2_noPointerRuntimeOnly() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeURL = tmp.appendingPathComponent("import_filters.json")

        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: nil)
        let outcome = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "importFilters")

        // In test environment, isRunningTests() == true and no override → .runtimeOnly
        #expect(outcome == .runtimeOnly)
        let runtimeContent = try Data(contentsOf: runtimeURL)
        #expect(runtimeContent == sampleData)
    }

    // MARK: - Case 3: pointer JSON with empty repository_config_dir → RepositoryPointer.load returns nil

    @Test("pointer with empty repository_config_dir: load returns nil")
    func case3_emptyConfigDir() throws {
        let dict: [String: Any] = [
            "version": 1,
            "repository_config_dir": "",
            "repo_root": "/some/path"
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let pointer = RepositoryPointer.parse(data: data)
        #expect(pointer == nil)
    }

    // MARK: - Case 4: pointer pointing to nonexistent dir → load returns nil

    @Test("pointer repo_root pointing to nonexistent directory: load returns nil")
    func case4_nonexistentRepoRoot() throws {
        let dict: [String: Any] = [
            "version": 1,
            "repository_config_dir": "/nonexistent/repo/Sources/SpinLabApp/config",
            "repo_root": "/nonexistent/repo"
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let pointer = RepositoryPointer.parse(data: data)
        #expect(pointer == nil)
    }

    // MARK: - Case 5: mirror write fails (stub) → .mirrorFailedRuntimeOk, runtime updated

    @Test("stub mirror write failure produces .mirrorFailedRuntimeOk with runtime updated")
    func case5_mirrorWriteFails() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        let runtimeURL = runtimeDir.appendingPathComponent("import_filters.json")
        // Call 1 = runtime (success), call 2 = mirror (fail)
        let stub = StubAtomicFileWriter(mode: .failOnCallN(2, AppError.io("permission denied")))
        let engine = RulesSyncEngine(pointer: nil, atomicWriter: stub, testOverrideMirrorURL: mirrorDir)

        let outcome = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "importFilters")

        if case .mirrorFailedRuntimeOk = outcome { } else {
            Issue.record("Expected .mirrorFailedRuntimeOk, got \(outcome)")
        }
        let runtimeContent = try Data(contentsOf: runtimeURL)
        #expect(runtimeContent == sampleData)
    }

    // MARK: - Case 6: runtime write fails → throws AppError.io

    @Test("stub runtime write failure throws AppError.io and does not touch mirror")
    func case6_runtimeWriteFails() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        let runtimeURL = tmp.appendingPathComponent("import_filters.json")
        let stub = StubAtomicFileWriter(mode: .failAll(AppError.io("disk full")))
        let engine = RulesSyncEngine(pointer: nil, atomicWriter: stub, testOverrideMirrorURL: mirrorDir)

        #expect(throws: Error.self) {
            _ = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "importFilters")
        }
        let mirrorURL = mirrorDir.appendingPathComponent("import_filters.json")
        #expect(!FileManager.default.fileExists(atPath: mirrorURL.path))
    }

    // MARK: - Case 7: test environment default skip → .runtimeOnly

    @Test("test environment without testOverrideMirrorURL produces .runtimeOnly")
    func case7_testEnvSkip() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeURL = tmp.appendingPathComponent("workflow.json")

        // RulesConfigPaths.isRunningTests() == true → skips mirror
        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: nil)
        let outcome = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "workflow")

        #expect(outcome == .runtimeOnly)
    }

    // MARK: - Case 8: testOverrideMirrorURL in test env → .mirrored

    @Test("testOverrideMirrorURL bypasses test-env guard and produces .mirrored")
    func case8_testOverrideURL() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        let runtimeURL = runtimeDir.appendingPathComponent("workflow.json")
        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDir)
        let outcome = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "workflow")

        #expect(outcome == .mirrored)
        let mirrorURL = mirrorDir.appendingPathComponent("workflow.json")
        #expect(FileManager.default.fileExists(atPath: mirrorURL.path))
    }

    // MARK: - Case 9: backup contains previous content

    @Test("backup file contains old runtime content after dualWrite")
    func case9_backupContainsOldContent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        let runtimeURL = runtimeDir.appendingPathComponent("import_filters.json")
        // Seed initial content
        try sampleData.write(to: runtimeURL)

        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDir)
        _ = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleDataV2, sectionLabel: "importFilters")

        let backupURL = runtimeURL.appendingPathExtension("backup")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        let backupContent = try Data(contentsOf: backupURL)
        #expect(backupContent == sampleData)

        let runtimeContent = try Data(contentsOf: runtimeURL)
        #expect(runtimeContent == sampleDataV2)
    }

    // MARK: - Case 10: multiple writes — backup is always previous content

    @Test("multiple consecutive writes: backup tracks previous content, not original")
    func case10_multipleWritesBackupTracking() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        let runtimeURL = runtimeDir.appendingPathComponent("import_filters.json")
        try sampleData.write(to: runtimeURL)  // initial: A

        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDir)
        _ = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleDataV2, sectionLabel: "importFilters")  // write B

        let dataC = Data("""
        {"version":1,"import":{"supportedFileExtensions":["csv","xlsx","dat"],"ignoredFileExtensions":[]}}
        """.utf8)
        _ = try engine.dualWrite(runtimeURL: runtimeURL, data: dataC, sectionLabel: "importFilters")  // write C

        let backupURL = runtimeURL.appendingPathExtension("backup")
        let backupContent = try Data(contentsOf: backupURL)
        // backup should be B (not A)
        #expect(backupContent == sampleDataV2)
        #expect(backupContent != sampleData)
    }

    // MARK: - Case 11: pointer JSON corrupt → nil

    @Test("corrupt pointer JSON: RepositoryPointer.parse returns nil")
    func case11_corruptPointerJSON() throws {
        let data = Data("not valid json {{{".utf8)
        let pointer = RepositoryPointer.parse(data: data)
        #expect(pointer == nil)
    }

    // MARK: - Case 12: pointer missing repository_config_dir field → nil

    @Test("pointer JSON missing repository_config_dir: parse returns nil")
    func case12_missingConfigDirField() throws {
        let dict: [String: Any] = ["version": 1, "repo_root": "/some/path"]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let pointer = RepositoryPointer.parse(data: data)
        #expect(pointer == nil)
    }

    // MARK: - Case 13: pointer version != 1 → nil

    @Test("pointer version != 1: parse returns nil")
    func case13_unsupportedVersion() throws {
        let dict: [String: Any] = [
            "version": 99,
            "repository_config_dir": "/some/config",
            "repo_root": "/some"
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let pointer = RepositoryPointer.parse(data: data)
        #expect(pointer == nil)
    }

    // MARK: - Case 14: pointer repo_root has no .git → nil + warning

    @Test("pointer repo_root without .git directory: parse returns nil")
    func case14_noGitDirectory() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Create a dir without .git
        let fakeRoot = tmp.appendingPathComponent("fakerepo", isDirectory: true)
        let fakeConfig = fakeRoot.appendingPathComponent("Sources/SpinLabApp/config", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeConfig, withIntermediateDirectories: true)

        let dict: [String: Any] = [
            "version": 1,
            "repository_config_dir": fakeConfig.path,
            "repo_root": fakeRoot.path
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let pointer = RepositoryPointer.parse(data: data)
        #expect(pointer == nil)
    }

    // MARK: - Case 15: mirror path outside repo_root → nil

    @Test("pointer repository_config_dir outside repo_root: parse returns nil")
    func case15_configDirOutsideRepo() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fakeRoot = tmp.appendingPathComponent("repo", isDirectory: true)
        let gitDir = fakeRoot.appendingPathComponent(".git", isDirectory: true)
        let outsideConfig = tmp.appendingPathComponent("outside_config", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideConfig, withIntermediateDirectories: true)

        let dict: [String: Any] = [
            "version": 1,
            "repository_config_dir": outsideConfig.path,
            "repo_root": fakeRoot.path
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let pointer = RepositoryPointer.parse(data: data)
        #expect(pointer == nil)
    }

    // MARK: - Case 16: mirror parent doesn't exist → createDirectory succeeds → .mirrored

    @Test("nonexistent mirror parent directory is created and write succeeds")
    func case16_mirrorParentCreated() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        // Mirror dir does NOT exist yet
        let mirrorDir = tmp.appendingPathComponent("mirror_new/subdir", isDirectory: true)

        let runtimeURL = runtimeDir.appendingPathComponent("workflow.json")
        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDir)
        let outcome = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "workflow")

        #expect(outcome == .mirrored)
        let mirrorURL = mirrorDir.appendingPathComponent("workflow.json")
        #expect(FileManager.default.fileExists(atPath: mirrorURL.path))
    }

    // MARK: - Case 17: mirror parent creation fails → .mirrorFailedRuntimeOk

    @Test("blocking file at mirror parent path causes mirrorFailedRuntimeOk")
    func case17_mirrorParentCreationFails() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        // Place a FILE where the mirror dir should be — createDirectory will fail
        let mirrorDirPath = tmp.appendingPathComponent("mirror_conflict")
        try Data("blocker".utf8).write(to: mirrorDirPath)

        let runtimeURL = runtimeDir.appendingPathComponent("workflow.json")
        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDirPath)
        let outcome = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "workflow")

        if case .mirrorFailedRuntimeOk(let reason) = outcome {
            #expect(reason.contains("create parent failed"))
        } else {
            Issue.record("Expected .mirrorFailedRuntimeOk, got \(outcome)")
        }
        let runtimeContent = try Data(contentsOf: runtimeURL)
        #expect(runtimeContent == sampleData)
    }

    // MARK: - Case 18: idempotent save

    @Test("identical consecutive saves produce stable backup content")
    func case18_idempotentSave() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        let runtimeURL = runtimeDir.appendingPathComponent("import_filters.json")
        try sampleData.write(to: runtimeURL)

        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDir)
        _ = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "importFilters")
        _ = try engine.dualWrite(runtimeURL: runtimeURL, data: sampleData, sectionLabel: "importFilters")

        let backupURL = runtimeURL.appendingPathExtension("backup")
        let backupContent = try Data(contentsOf: backupURL)
        // backup should equal the previous write (which was also sampleData)
        #expect(backupContent == sampleData)
        let runtimeContent = try Data(contentsOf: runtimeURL)
        #expect(runtimeContent == sampleData)
    }

    // MARK: - Case 19: canonicalization — symlink path in pointer resolves to .mirrored

    @Test("symlink-based repository_config_dir path canonicalizes correctly")
    func case19_canonicalization() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let realMirrorDir = tmp.appendingPathComponent("real_mirror", isDirectory: true)
        let symlinkMirrorDir = tmp.appendingPathComponent("symlink_mirror")
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: realMirrorDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: symlinkMirrorDir,
            withDestinationURL: realMirrorDir
        )

        // Build a valid fake git repo
        let fakeRoot = tmp.appendingPathComponent("repo", isDirectory: true)
        let gitDir = fakeRoot.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        // Place mirror under fakeRoot
        let configUnderRepo = fakeRoot.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configUnderRepo, withIntermediateDirectories: true)
        // Symlink: symlinkConfigDir → configUnderRepo
        let symlinkConfigDir = tmp.appendingPathComponent("symlink_config")
        try FileManager.default.createSymbolicLink(at: symlinkConfigDir, withDestinationURL: configUnderRepo)

        let dict: [String: Any] = [
            "version": 1,
            "repository_config_dir": symlinkConfigDir.path,
            "repo_root": fakeRoot.path
        ]
        let pointerData = try JSONSerialization.data(withJSONObject: dict)
        let pointer = RepositoryPointer.parse(data: pointerData)
        // Canonicalization should resolve symlink → valid pointer
        #expect(pointer != nil)
        // If pointer resolves, verify repositoryConfigDir is the canonical path
        if let p = pointer {
            let canonical = configUnderRepo.standardizedFileURL.resolvingSymlinksInPath()
            // Compare paths (strip trailing slash difference between directory URLs)
            let actual = p.repositoryConfigDir.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let expected = canonical.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            #expect(actual == expected)
        }
    }

    // MARK: - Case 20: persistenceHook DualWriteOutcome field

    @Test("persistenceHook.didPersist receives correct DualWriteOutcome")
    func case20_hookOutcomeField() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runtimeDir = tmp.appendingPathComponent("runtime", isDirectory: true)
        let mirrorDir = tmp.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)

        // Seed all 5 schema files
        for name in ["import_filters.json", "filename_tokenization.json",
                     "sample_identification.json", "workflow.json", "measuring_condition.json"] {
            try Data("{}".utf8).write(to: runtimeDir.appendingPathComponent(name))
        }

        let engine = RulesSyncEngine(pointer: nil, testOverrideMirrorURL: mirrorDir)
        var capturedOutcome: DualWriteOutcome?
        let store = RulesManagementStore(onRulesSaved: {}, syncEngine: engine)
        store.persistenceHook = RulesPersistenceHook(didPersist: { _, _, _, _, outcome in
            capturedOutcome = outcome
        })

        // Override paths so store writes to our tmp runtime dir
        // Since RulesManagementStore uses RulesConfigPaths() which is test-isolated,
        // we seed those paths instead
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        var backup: URL?
        if fm.fileExists(atPath: paths.configDirectoryURL.path) {
            let candidate = paths.configDirectoryURL.appendingPathExtension("v515-eng-hook-\(UUID().uuidString)")
            try fm.moveItem(at: paths.configDirectoryURL, to: candidate)
            backup = candidate
        }
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: paths.configDirectoryURL)
            if let b = backup, fm.fileExists(atPath: b.path) {
                try? fm.moveItem(at: b, to: paths.configDirectoryURL)
            }
            _ = RuleLoader.shared.reloadCached()
        }

        // Seed valid schema files
        try Data("""
        {"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":[]}}
        """.utf8).write(to: paths.importFiltersURL)
        try Data("""
        {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
        """.utf8).write(to: paths.filenameTokenizationURL)
        try Data("""
        {"version":4,"sampleId":{"batchPrefixes":[]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}
        """.utf8).write(to: paths.sampleIdentificationURL)
        try Data("""
        {"version":1,"workflows":[],"measurementTagRules":[]}
        """.utf8).write(to: paths.workflowURL)
        try Data("""
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{},"tokenMapRules":{},"displayLabels":{}},"conditionDefinitions":[]}
        """.utf8).write(to: paths.measuringConditionURL)

        store.present()
        if var d = store.importFiltersDraft {
            d.config.supportedFileExtensions.append("txt")
            store.updateImportFilters(d)
        }
        store.selectSection(.importFilters)
        _ = store.saveCurrent()

        #expect(capturedOutcome != nil)
        // Engine uses testOverrideMirrorURL → should be .mirrored
        #expect(capturedOutcome == .mirrored)
    }
}
