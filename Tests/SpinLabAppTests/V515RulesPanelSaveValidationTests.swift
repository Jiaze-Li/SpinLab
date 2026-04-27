import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesPanel Save Validation", .serialized)
struct V515RulesPanelSaveValidationTests {

    private static let backupExtension = "v515-validation-backup"

    private func acquireIsolation() throws -> (dir: URL, backup: URL?) {
        let dir = RulesConfigPaths().configDirectoryURL
        let fm = FileManager.default
        var backup: URL? = nil
        if fm.fileExists(atPath: dir.path) {
            let candidate = dir.appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: dir, to: candidate)
            backup = candidate
        }
        return (dir, backup)
    }

    private func releaseIsolation(dir: URL, backup: URL?) {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        if let backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: dir)
        }
        _ = RuleLoader.shared.reloadCached()
    }

    private func makeStore() throws -> (RulesManagementStore, RulesConfigPaths) {
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        try? fm.removeItem(at: paths.configDirectoryURL)
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)

        try """
        {"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":["gph"]}}
        """.data(using: .utf8)!.write(to: paths.importFiltersURL)

        try """
        {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
        """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)

        try """
        {"version":3,"sampleId":{"patterns":["^[A-Z]+$"]},"substrate":{"substrateTagRules":[],"materials":[{"id":"STO","tokens":["STO"],"aliases":[],"displayName":"STO"}],"treatments":[],"orientations":{"pattern":"\\\\d{3}","rows":[{"id":"111","tokens":["111"],"aliases":[]}]}}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        try """
        {"version":2,"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^\\\\d+K$"}]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        let store = RulesManagementStore()
        store.present()
        return (store, paths)
    }

    // MARK: - Import Filters

    @Test("importFilters: extension with space fails")
    func importFiltersSpaceInExtension() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions = ["c sv"]
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("space") }))
    }

    @Test("importFilters: extension starting with dot fails")
    func importFiltersDotPrefix() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions = [".csv"]
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("'.'") }))
    }

    @Test("importFilters: overlap between supported and ignored fails")
    func importFiltersOverlap() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions = ["csv", "txt"]
        draft.config.ignoredFileExtensions = ["txt"]
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("txt") }))
    }

    @Test("importFilters: valid save succeeds")
    func importFiltersValid() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions = ["csv", "dat"]
        draft.config.ignoredFileExtensions = ["gph"]
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }
    }

    // MARK: - Filename Tokenization

    @Test("filenameTokenization: empty separators fails")
    func tokenizationEmptySeparators() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.filenameTokenizationDraft)
        draft.tokenization.separators = ""
        store.updateFilenameTokenization(draft)
        store.selectSection(.filenameTokenization)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("separators") }))
    }

    @Test("filenameTokenization: unknown source fails")
    func tokenizationUnknownSource() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.filenameTokenizationDraft)
        draft.sources = ["file", "unknown_source"]
        store.updateFilenameTokenization(draft)
        store.selectSection(.filenameTokenization)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("unknown_source") }))
    }

    @Test("filenameTokenization: empty sources fails")
    func tokenizationEmptySources() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.filenameTokenizationDraft)
        draft.sources = []
        store.updateFilenameTokenization(draft)
        store.selectSection(.filenameTokenization)

        guard case .validationFailed = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
    }

    // MARK: - Sample Identification

    @Test("sampleIdentification: invalid regex in patterns fails")
    func sampleIDInvalidRegex() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        draft.sampleId.patterns = ["[unclosed"]
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("patterns") }))
    }

    @Test("sampleIdentification: duplicate treatment ID fails")
    func sampleIDDuplicateTreatmentID() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        let t1 = SampleIdentificationFileDraft.TreatmentDefinition(
            id: "HF", displayName: "HF", keywords: ["HF"], standaloneTokens: [], containsTokens: []
        )
        let t2 = SampleIdentificationFileDraft.TreatmentDefinition(
            id: "HF", displayName: "HF2", keywords: ["HF2"], standaloneTokens: [], containsTokens: []
        )
        draft.substrate.treatments = [t1, t2]
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") && $0.message.contains("HF") }))
    }

    // MARK: - Workflow

    @Test("workflow: empty workflow ID fails")
    func workflowEmptyID() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.workflowDraft)
        draft.workflows[0].id = ""
        store.updateWorkflow(draft)
        store.selectSection(.workflow)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("id") }))
    }

    @Test("workflow: duplicate workflow ID fails")
    func workflowDuplicateID() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.workflowDraft)
        draft.workflows.append(.init(id: "MR", displayName: "MR2",
                                     matchRules: [.init(scope: "tokens", type: "equals", matchValues: ["MR2"])],
                                     conditionFieldIDs: []))
        store.updateWorkflow(draft)
        store.selectSection(.workflow)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") }))
    }

    @Test("workflow: conditionFieldID not in measuringCondition hard-fails")
    func workflowDanglingConditionFieldID() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.workflowDraft)
        draft.workflows[0].conditionFieldIDs = ["temperature", "nonexistent_condition"]
        store.updateWorkflow(draft)
        store.selectSection(.workflow)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("nonexistent_condition") }))
    }

    // MARK: - Measuring Condition

    @Test("measuringCondition: duplicate conditionDefinition ID fails")
    func measuringConditionDuplicateID() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "temperature", label: nil, kind: "unit_suffix",
                                                unitPattern: "^\\d+K$", tokenMap: nil))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") }))
    }

    @Test("measuringCondition: unit_suffix with invalid regex fails")
    func measuringConditionUnitSuffixInvalidRegex() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions[0].unitPattern = "[bad"
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("temperature") || $0.field.contains("unitPattern") }))
    }

    @Test("measuringCondition: unit_suffix missing extraConditions entry fails")
    func measuringConditionUnitSuffixMissingEntry() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", label: nil, kind: "unit_suffix",
                                                unitPattern: "", tokenMap: nil))
        // Empty unitPattern for "field" — unit_suffix requires a non-empty pattern
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("field") }))
    }

    @Test("measuringCondition: valid condition saves successfully")
    func measuringConditionValidSave() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", label: "Field", kind: "unit_suffix",
                                                unitPattern: "^-?\\d+T$", tokenMap: nil))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }
        #expect(!store.dirtySections.contains(.measuringCondition))
    }
}
