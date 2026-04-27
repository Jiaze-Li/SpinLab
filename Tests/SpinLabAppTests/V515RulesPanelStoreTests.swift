import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesPanel Store", .serialized)
struct V515RulesPanelStoreTests {

    // MARK: - Isolation (same strategy as old V515 tests)

    private static let backupExtension = "v515-store-backup"

    private struct IsolationContext {
        let dir: URL
        let backup: URL?
    }

    private func acquireIsolation() throws -> IsolationContext {
        purgeStaleBackups()
        let dir = RulesConfigPaths().configDirectoryURL
        let fm = FileManager.default
        var backup: URL? = nil
        if fm.fileExists(atPath: dir.path) {
            let candidate = dir.appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: dir, to: candidate)
            backup = candidate
        }
        return IsolationContext(dir: dir, backup: backup)
    }

    private func releaseIsolation(_ context: IsolationContext) {
        let fm = FileManager.default
        if fm.fileExists(atPath: context.dir.path) {
            try? fm.removeItem(at: context.dir)
        }
        if let backup = context.backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: context.dir)
        }
        _ = RuleLoader.shared.reloadCached()
    }

    private func purgeStaleBackups() {
        let dir = RulesConfigPaths().configDirectoryURL
        let parent = dir.deletingLastPathComponent()
        let prefix = dir.lastPathComponent + "." + Self.backupExtension
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
        for entry in entries where entry.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(entry, isDirectory: true))
        }
    }

    // MARK: - Seed helpers

    private func seedAll() throws -> RulesConfigPaths {
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        try? fm.removeItem(at: paths.configDirectoryURL)
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)

        try seedImportFilters(at: paths.importFiltersURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)
        try seedSampleIdentification(at: paths.sampleIdentificationURL)
        try seedWorkflow(at: paths.workflowURL)
        try seedMeasuringCondition(at: paths.measuringConditionURL)
        return paths
    }

    private func seedImportFilters(at url: URL) throws {
        try """
        {"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":["gph"]}}
        """.data(using: .utf8)!.write(to: url)
    }

    private func seedFilenameTokenization(at url: URL) throws {
        try """
        {"version":1,"tokenization":{"separators":"_- ()","caseFold":"preserve"},"sources":["file","parent"],"channel":{"aliases":{}}}
        """.data(using: .utf8)!.write(to: url)
    }

    private func seedSampleIdentification(at url: URL) throws {
        try """
        {"version":4,"sampleId":{"batchPrefixes":["PN","PT"]},"substrate":{"materials":[{"displayName":"STO","matches":[{"type":"equals","value":"STO"}]}],"treatments":[],"orientations":[{"displayName":"111","matches":[{"type":"equals","value":"111"}]}]}}
        """.data(using: .utf8)!.write(to: url)
    }

    private func seedWorkflow(at url: URL) throws {
        try """
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: url)
    }

    private func seedMeasuringCondition(at url: URL) throws {
        try """
        {"version":2,"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^-?\\\\d+(?:\\\\.\\\\d+)?(?:K)$"}]}
        """.data(using: .utf8)!.write(to: url)
    }

    // MARK: - Tests: load

    @Test("present() loads all 5 section drafts")
    func presentLoadsAllDrafts() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        _ = try seedAll()

        let store = RulesManagementStore()
        store.present()

        #expect(store.importFiltersDraft != nil)
        #expect(store.filenameTokenizationDraft != nil)
        #expect(store.sampleIdentificationDraft != nil)
        #expect(store.workflowDraft != nil)
        #expect(store.measuringConditionDraft != nil)
        #expect(!store.availableConditionFieldIDs.isEmpty)
    }

    @Test("availableConditionFieldIDs refreshes when measuringCondition is updated")
    func availableConditionFieldIDsRefreshes() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        _ = try seedAll()

        let store = RulesManagementStore()
        store.present()

        let initial = store.availableConditionFieldIDs
        #expect(initial.contains("temperature"))

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", label: "Field", kind: "unit_suffix",
                                                unitPattern: "^-?\\d+T$", tokenMap: nil))
        store.updateMeasuringCondition(draft)

        #expect(store.availableConditionFieldIDs.contains("field"))
        #expect(store.dirtySections.contains(.measuringCondition))
    }

    @Test("update marks section dirty, discard clears it")
    func updateAndDiscard() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        _ = try seedAll()

        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions.append("dat")
        store.updateImportFilters(draft)
        #expect(store.dirtySections.contains(.importFilters))

        store.selectSection(.importFilters)
        store.discardCurrent()
        #expect(!store.dirtySections.contains(.importFilters))
        #expect(store.importFiltersDraft?.config.supportedFileExtensions.contains("dat") == false)
    }

    @Test("reloadAfterExternalChange drops dirty state and refreshes draft")
    func reloadAfterExternalChange() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let paths = try seedAll()

        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.filenameTokenizationDraft)
        draft.tokenization.separators = "EDITED"
        store.updateFilenameTokenization(draft)
        #expect(store.dirtySections.contains(.filenameTokenization))

        // External update
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)
        store.reloadAfterExternalChange(section: .filenameTokenization)

        #expect(!store.dirtySections.contains(.filenameTokenization))
        #expect(store.filenameTokenizationDraft?.tokenization.separators != "EDITED")
    }

    @Test("Save All iterates in allCases order (not Set order)")
    func saveAllOrderIsStable() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        _ = try seedAll()

        var hookOrder: [String] = []
        let store = RulesManagementStore(onRulesSaved: {})
        store.persistenceHook = RulesPersistenceHook(didPersist: { sectionID, _, _, _, _ in
            hookOrder.append(sectionID)
        })
        store.present()

        // Dirty all 5 sections
        if var d = store.importFiltersDraft { store.updateImportFilters(d) }
        if var d = store.filenameTokenizationDraft { store.updateFilenameTokenization(d) }
        if var d = store.sampleIdentificationDraft { store.updateSampleIdentification(d) }
        if var d = store.measuringConditionDraft { store.updateMeasuringCondition(d) }
        // Workflow depends on measuringCondition, must be after
        if var d = store.workflowDraft { store.updateWorkflow(d) }

        // Simulate Save All in allCases order
        for section in RulesPanelSection.allCases where store.dirtySections.contains(section) {
            store.selectSection(section)
            let outcome = store.saveCurrent()
            if case .validationFailed = outcome { break }
            if case .ioError = outcome { break }
        }

        let expected = RulesPanelSection.allCases.map(\.rawValue)
        #expect(hookOrder == expected)
    }

    @Test("persist fires hook, clears dirty, records new hash")
    func persistFiresHook() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let paths = try seedAll()

        var hookCalls: [(String, URL, Int, String, DualWriteOutcome)] = []
        let store = RulesManagementStore()
        store.persistenceHook = RulesPersistenceHook(didPersist: { s, u, v, c, o in
            hookCalls.append((s, u, v, c, o))
        })
        store.present()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions.append("txt")
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)
        let outcome = store.saveCurrent()

        guard case .saved = outcome else {
            Issue.record("Expected .saved, got \(outcome)")
            return
        }
        #expect(!store.dirtySections.contains(.importFilters))
        #expect(hookCalls.count == 1)
        #expect(hookCalls.first?.0 == "importFilters")

        let onDisk = try JSONDecoder().decode(
            ImportFiltersFileDraft.self,
            from: Data(contentsOf: paths.importFiltersURL)
        )
        #expect(onDisk.config.supportedFileExtensions.contains("txt"))
    }

    @Test("hash precondition: external mutation triggers externalConflict")
    func hashPreconditionConflict() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let paths = try seedAll()

        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions.append("mine")
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)

        // External write with DIFFERENT content to change the file hash
        try """
        {"version":1,"import":{"supportedFileExtensions":["external_changed"],"ignoredFileExtensions":[]}}
        """.data(using: .utf8)!.write(to: paths.importFiltersURL)

        let outcome = store.saveCurrent()
        guard case .externalConflict = outcome else {
            Issue.record("Expected .externalConflict, got \(outcome)")
            return
        }
        #expect(store.dirtySections.contains(.importFilters))
    }

    @Test("override after conflict succeeds and writes draft")
    func overrideAfterConflict() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        let paths = try seedAll()

        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions = ["mine"]
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)

        try seedImportFilters(at: paths.importFiltersURL)
        _ = store.saveCurrent() // triggers conflict

        let outcome = store.overrideWithCurrentDraft(section: .importFilters)
        guard case .saved = outcome else {
            Issue.record("Expected .saved on override, got \(outcome)")
            return
        }
        let onDisk = try JSONDecoder().decode(
            ImportFiltersFileDraft.self,
            from: Data(contentsOf: paths.importFiltersURL)
        )
        #expect(onDisk.config.supportedFileExtensions == ["mine"])
        #expect(!store.dirtySections.contains(.importFilters))
    }
}
