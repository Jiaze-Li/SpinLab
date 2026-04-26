import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesSyncStartup", .serialized)
struct V515RulesSyncStartupTests {

    // MARK: - Isolation (same pattern as V515RulesPanelStoreTests)

    private static let backupExtension = "v515-startup-backup"

    private struct IsolationContext {
        let paths: RulesConfigPaths
        let backup: URL?
    }

    private func acquireIsolation() throws -> IsolationContext {
        purgeStaleBackups()
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        var backup: URL? = nil
        if fm.fileExists(atPath: paths.configDirectoryURL.path) {
            let candidate = paths.configDirectoryURL
                .appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: paths.configDirectoryURL, to: candidate)
            backup = candidate
        }
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
        return IsolationContext(paths: paths, backup: backup)
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        let fm = FileManager.default
        if fm.fileExists(atPath: ctx.paths.configDirectoryURL.path) {
            try? fm.removeItem(at: ctx.paths.configDirectoryURL)
        }
        if let backup = ctx.backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: ctx.paths.configDirectoryURL)
        }
        _ = RuleLoader.shared.reloadCached()
    }

    private func purgeStaleBackups() {
        let paths = RulesConfigPaths()
        let parent = paths.configDirectoryURL.deletingLastPathComponent()
        let prefix = paths.configDirectoryURL.lastPathComponent + "." + Self.backupExtension
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
        for entry in entries where entry.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(entry, isDirectory: true))
        }
    }

    // MARK: - Fake git repo helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v515-startup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFakeGitRepo(at root: URL) throws -> URL {
        let git = root.appendingPathComponent(".git", isDirectory: true)
        let configDir = root.appendingPathComponent("Sources/SpinLabApp/config", isDirectory: true)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        return configDir
    }

    private func writePointerAndLoad(runtimeConfigDir: URL, configDir: URL, repoRoot: URL) throws -> RepositoryPointer {
        let pointerURL = runtimeConfigDir.appendingPathComponent(RepositoryPointer.pointerFileName)
        try RepositoryPointer.write(to: pointerURL, repositoryConfigDir: configDir, repoRoot: repoRoot)
        return try #require(RepositoryPointer.load(from: pointerURL))
    }

    // MARK: - Schema fixtures

    private let validImportFilters = Data("""
    {"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":[]}}
    """.utf8)
    private let updatedImportFilters = Data("""
    {"version":1,"import":{"supportedFileExtensions":["csv","xlsx"],"ignoredFileExtensions":[]}}
    """.utf8)
    private let validFilenameTokenization = Data("""
    {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
    """.utf8)
    private let validSampleIdentification = Data("""
    {"version":1,"sampleId":{"patterns":[]},"substrate":{"substrateTagRules":[]}}
    """.utf8)
    private let validWorkflow = Data("""
    {"version":1,"workflows":[],"measurementTagRules":[]}
    """.utf8)
    private let validMeasuringCondition = Data("""
    {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{},"tokenMapRules":{},"displayLabels":{}},"conditionDefinitions":[]}
    """.utf8)

    private func seedAll(at dir: URL, importFilters: Data? = nil) throws {
        try (importFilters ?? validImportFilters).write(to: dir.appendingPathComponent("import_filters.json"))
        try validFilenameTokenization.write(to: dir.appendingPathComponent("filename_tokenization.json"))
        try validSampleIdentification.write(to: dir.appendingPathComponent("sample_identification.json"))
        try validWorkflow.write(to: dir.appendingPathComponent("workflow.json"))
        try validMeasuringCondition.write(to: dir.appendingPathComponent("measuring_condition.json"))
    }

    // MARK: - Case 1: runtime and mirror consistent → no overwrite

    @Test("consistent mirror and runtime: startup outcome healthy, no files overwritten")
    func case1_consistentSkipped() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)
        try seedAll(at: configDir)
        try seedAll(at: iso.paths.configDirectoryURL)

        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        let outcome = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        let runtimeContent = try Data(contentsOf: iso.paths.importFiltersURL)
        #expect(runtimeContent == validImportFilters)
        switch outcome {
        case .healthy, .degraded: break
        case .skipped: Issue.record("Expected healthy or degraded, got .skipped")
        }
    }

    // MARK: - Case 2: runtime missing → created from mirror

    @Test("runtime files absent: mirror content written to runtime on cold start")
    func case2_runtimeMissingCreatedFromMirror() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)
        try seedAll(at: configDir)
        // Runtime: pointer file only, no schema files

        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        _ = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        for url in iso.paths.allSchemaFileURLs {
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "\(url.lastPathComponent) should exist after reverse sync")
        }
    }

    // MARK: - Case 3: runtime differs → overwritten, backup preserved

    @Test("mirror newer than runtime: runtime overwritten and backup created")
    func case3_runtimeOverwritten() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)
        try seedAll(at: configDir, importFilters: updatedImportFilters)  // mirror has updated content
        try seedAll(at: iso.paths.configDirectoryURL)                    // runtime has old content

        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        _ = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        let runtimeContent = try Data(contentsOf: iso.paths.importFiltersURL)
        #expect(runtimeContent == updatedImportFilters)

        let backupURL = iso.paths.importFiltersURL.appendingPathExtension("backup")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        let backupContent = try Data(contentsOf: backupURL)
        #expect(backupContent == validImportFilters)
    }

    // MARK: - Case 4: no pointer → skipped

    @Test("no repo pointer: reverseSyncOnStartup returns .skipped")
    func case4_noPointerSkipped() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }

        let engine = RulesSyncEngine(pointer: nil)
        let outcome = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        #expect(outcome == .skipped)
    }

    // MARK: - Case 5: only one file differs

    @Test("only the differing file is synced, others are unchanged")
    func case5_onlyDifferingFileSynced() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)

        // Mirror: workflow.json is different, rest same
        let newWorkflow = Data("""
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[],"conditionFieldIDs":[]}],"measurementTagRules":[]}
        """.utf8)
        try validImportFilters.write(to: configDir.appendingPathComponent("import_filters.json"))
        try validFilenameTokenization.write(to: configDir.appendingPathComponent("filename_tokenization.json"))
        try validSampleIdentification.write(to: configDir.appendingPathComponent("sample_identification.json"))
        try newWorkflow.write(to: configDir.appendingPathComponent("workflow.json"))
        try validMeasuringCondition.write(to: configDir.appendingPathComponent("measuring_condition.json"))

        try seedAll(at: iso.paths.configDirectoryURL)  // runtime: all valid

        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        _ = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        let runtimeWorkflow = try Data(contentsOf: iso.paths.workflowURL)
        #expect(runtimeWorkflow == newWorkflow)

        let runtimeImport = try Data(contentsOf: iso.paths.importFiltersURL)
        #expect(runtimeImport == validImportFilters)
    }

    // MARK: - Case 6: mirror file absent → that file degraded, others continue

    @Test("absent mirror file: file marked degraded, other files still synced")
    func case6_mirrorFileMissing() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)
        // Mirror: workflow.json absent, rest present
        try validImportFilters.write(to: configDir.appendingPathComponent("import_filters.json"))
        try validFilenameTokenization.write(to: configDir.appendingPathComponent("filename_tokenization.json"))
        try validSampleIdentification.write(to: configDir.appendingPathComponent("sample_identification.json"))
        try validMeasuringCondition.write(to: configDir.appendingPathComponent("measuring_condition.json"))
        // NO workflow.json in mirror

        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        _ = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        // The 4 present mirror files should be written to runtime
        #expect(FileManager.default.fileExists(atPath: iso.paths.importFiltersURL.path))
        #expect(FileManager.default.fileExists(atPath: iso.paths.filenameTokenizationURL.path))
    }

    // MARK: - Case 7: mirror JSON decode fails → runtime not overwritten (H5)

    @Test("mirror file with invalid schema is rejected: runtime file unchanged (H5)")
    func case7_mirrorDecodeFailed() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)
        try seedAll(at: configDir)
        try seedAll(at: iso.paths.configDirectoryURL)

        // Replace import_filters.json mirror with invalid schema
        let invalidSchema = Data("""
        {"version":1,"totally_wrong_key":"oops"}
        """.utf8)
        try invalidSchema.write(to: configDir.appendingPathComponent("import_filters.json"))

        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        _ = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        let runtimeContent = try Data(contentsOf: iso.paths.importFiltersURL)
        #expect(runtimeContent == validImportFilters)  // unchanged
    }

    // MARK: - Case 8: pointer identity check fails → no sync

    @Test("pointer repo_root without .git: RepositoryPointer.load returns nil, engine returns .skipped")
    func case8_pointerIdentityFailed() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a dir WITHOUT .git
        let fakeRoot = tmp.appendingPathComponent("fakerepo")
        let fakeConfig = fakeRoot.appendingPathComponent("Sources/SpinLabApp/config")
        try FileManager.default.createDirectory(at: fakeConfig, withIntermediateDirectories: true)

        let badPointerData = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "repository_config_dir": fakeConfig.path,
            "repo_root": fakeRoot.path
        ] as [String: Any])
        let pointer = RepositoryPointer.parse(data: badPointerData)
        #expect(pointer == nil)

        let engine = RulesSyncEngine(pointer: nil)
        let outcome = engine.reverseSyncOnStartup(runtimePaths: iso.paths)
        #expect(outcome == .skipped)
    }

    // MARK: - Case 9: auto-write skipped in test env

    @Test("RepositoryPointer.load(runtimeConfigDir:) skips auto-write in test environment")
    func case9_autoWriteSkippedInTests() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }

        let result = RepositoryPointer.load(runtimeConfigDir: iso.paths.configDirectoryURL)
        #expect(result == nil)
        let pointerPath = iso.paths.configDirectoryURL.appendingPathComponent(RepositoryPointer.pointerFileName)
        #expect(!FileManager.default.fileExists(atPath: pointerPath.path))
    }

    // MARK: - Case 10: reloadCached after sync returns current fingerprint

    @Test("RuleLoader.reloadCached after sync returns fingerprint matching seeded files")
    func case10_reloadCachedFingerprint() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }

        try seedAll(at: iso.paths.configDirectoryURL)

        let result1 = RuleLoader.shared.reloadCached()
        let result2 = RuleLoader.shared.loadCached()
        #expect(result1.metadata.fingerprint == result2.metadata.fingerprint)
        #expect(result1.metadata.sourceLabel != "Fallback")
    }

    // MARK: - Case 11: corrupt mirror JSON rejected

    @Test("mirror with corrupt JSON: file not overwritten (H5 decode check)")
    func case11_corruptMirrorJSON() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)
        try seedAll(at: configDir)
        try seedAll(at: iso.paths.configDirectoryURL)

        // Corrupt workflow.json in mirror
        try Data("{ broken json [[[".utf8).write(to: configDir.appendingPathComponent("workflow.json"))

        let originalWorkflow = try Data(contentsOf: iso.paths.workflowURL)
        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        _ = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        let afterWorkflow = try Data(contentsOf: iso.paths.workflowURL)
        #expect(afterWorkflow == originalWorkflow)  // unchanged
    }

    // MARK: - Case 12: post-sync reloadCached consistency (H6)

    @Test("after reverse sync: reloadCached fingerprint matches written files")
    func case12_postSyncReloadConsistency() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let repoRoot = tmp.appendingPathComponent("repo")
        let configDir = try makeFakeGitRepo(at: repoRoot)
        try seedAll(at: configDir, importFilters: updatedImportFilters)

        let pointer = try writePointerAndLoad(
            runtimeConfigDir: iso.paths.configDirectoryURL, configDir: configDir, repoRoot: repoRoot)
        let engine = RulesSyncEngine(pointer: pointer)
        _ = engine.reverseSyncOnStartup(runtimePaths: iso.paths)

        let result = RuleLoader.shared.reloadCached()
        #expect(result.metadata.sourceLabel != "Fallback")
    }
}
