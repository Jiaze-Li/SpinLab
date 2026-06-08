import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 Rules Book State", .serialized)
struct V515RulesBookStateTests {

    // MARK: - notConfigured

    @Test("no paths → state is notConfigured")
    func noPathsIsNotConfigured() {
        let store = RulesManagementStore(rulesBookPaths: nil)
        #expect(store.rulesBookState == .notConfigured)
    }

    @Test("nil paths after present() → state stays notConfigured")
    func noPathsAfterPresentStaysNotConfigured() {
        let store = RulesManagementStore(rulesBookPaths: nil)
        store.present()
        #expect(store.rulesBookState == .notConfigured)
    }

    @Test("updateRulesBookPaths(nil) → reverts to notConfigured")
    func updateToNilRevertToNotConfigured() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-state-nil-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let paths = RulesConfigPaths(configDirectoryURL: dir)
        let store = RulesManagementStore(rulesBookPaths: paths)
        // starts incompleteBook since dir is empty
        guard case .incompleteBook = store.rulesBookState else {
            Issue.record("Expected .incompleteBook with empty dir"); return
        }

        store.updateRulesBookPaths(nil)
        #expect(store.rulesBookState == .notConfigured)
    }

    // MARK: - incompleteBook

    @Test("empty dir → state is incompleteBook with all 5 filenames")
    func emptyDirIsIncompleteBook() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-state-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = RulesManagementStore(rulesBookPaths: RulesConfigPaths(configDirectoryURL: dir))
        guard case .incompleteBook(let missing) = store.rulesBookState else {
            Issue.record("Expected .incompleteBook for empty dir"); return
        }
        #expect(missing.count == 5)
        #expect(missing.contains("import_filters.json"))
        #expect(missing.contains("filename_tokenization.json"))
        #expect(missing.contains("sample_identification.json"))
        #expect(missing.contains("workflow.json"))
        #expect(missing.contains("measuring_condition.json"))
    }

    @Test("4-of-5 files present → incompleteBook lists only missing file")
    func fourOfFiveFilesIsIncompleteBook() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-state-partial-\(UUID().uuidString)", isDirectory: true)
        let paths = RulesConfigPaths(configDirectoryURL: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write 4 of 5 files — omit workflow.json
        for url in [paths.importFiltersURL, paths.filenameTokenizationURL,
                    paths.sampleIdentificationURL, paths.measuringConditionURL] {
            try Data("{}".utf8).write(to: url)
        }

        let store = RulesManagementStore(rulesBookPaths: paths)
        guard case .incompleteBook(let missing) = store.rulesBookState else {
            Issue.record("Expected .incompleteBook with one file missing"); return
        }
        #expect(missing == ["workflow.json"])
    }

    @Test("all 5 files present → state is ready")
    func allFilesReadyState() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-state-ready-\(UUID().uuidString)", isDirectory: true)
        let paths = RulesConfigPaths(configDirectoryURL: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for url in paths.allSchemaFileURLs {
            try Data("{}".utf8).write(to: url)
        }

        let store = RulesManagementStore(rulesBookPaths: paths)
        #expect(store.rulesBookState == .ready)
    }

    // MARK: - RuleLoader source isolation
    //
    // These tests mutate the global RuleLoader.shared configuration.
    // Save the current book paths and restore them in a defer to avoid
    // affecting concurrently-running Swift Testing suites.

    @Test("RuleLoader only reads from configured book path")
    func ruleLoaderOnlyReadsFromConfiguredBook() throws {
        let savedPaths = RuleLoader.currentBookPaths
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-isolation-\(UUID().uuidString)", isDirectory: true)
        let paths = RulesConfigPaths(configDirectoryURL: dir)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: dir)
            RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths())
        }

        // Seed a minimal but complete rules book
        try """
        {"version":1,"import":{"supportedFileExtensions":["dat"],"ignoredFileExtensions":[]}}
        """.data(using: .utf8)!.write(to: paths.importFiltersURL)
        try """
        {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
        """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)
        try """
        {"version":4,"sampleId":{"batchPrefixes":["ISOLATION"]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
        try """
        {"version":1,"workflows":[],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)
        try """
        {"version":2,"conditionDefinitions":[]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        let internalPaths = AppInternalPaths(appSupportDirectoryURL: dir)
        RuleLoader.configure(bookPaths: paths, internalPaths: internalPaths)
        let result = RuleLoader.shared.reloadCached()

        // importRules is the cleanest cross-check: "dat" is only in this isolated book, not the bundle
        #expect(result.ruleSet.importRules?.supportedFileExtensions.contains("dat") == true)
        #expect(result.metadata.sourceLabel == "RulesBook")
        #expect(result.metadata.sourcePath.contains(dir.path))
    }

    @Test("RuleLoader.load() with no configured paths returns NotConfigured metadata")
    func ruleLoaderNotConfiguredMetadata() {
        let savedPaths = RuleLoader.currentBookPaths
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        RuleLoader.configure(bookPaths: nil, internalPaths: AppInternalPaths())
        let result = RuleLoader.shared.load()
        #expect(result.metadata.sourceLabel == "NotConfigured")
        #expect(result.metadata.sourcePath == "not-configured")
        #expect(result.warnings.contains(where: { $0.contains("No Rules Book") }))
    }
}
