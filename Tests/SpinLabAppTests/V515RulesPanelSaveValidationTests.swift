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
        {"version":1,"sampleId":{"patterns":["^[A-Z]+$"]},"substrate":{"substrateTagRules":[],"shared":{"tokenSeparators":"_","originStandaloneTokens":[],"originContainsTokens":[],"treatmentKeywords":{},"materialTokens":["STO"],"materialAliases":{},"materialDisplayNames":{},"orientationTokens":["111"],"orientationAliases":{},"orientationPattern":"\\\\d{3}"}}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        try """
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{"temperature":"^\\\\d+K$"},"tokenMapRules":{},"displayLabels":{}},"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","binding":"conditions.extraConditions.temperature"}]}
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

    @Test("sampleIdentification: materialAlias pointing to unknown token fails")
    func sampleIDMaterialAliasUnknownTarget() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        draft.substrate.shared?.materialAliases = ["X": "NOTINLIST"]
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("materialAliases") }))
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
                                     matchRules: [.init(scope: "tokens", type: "equals", value: "MR2")],
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
                                                binding: "conditions.extraConditions.temperature"))
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
        draft.conditions.extraConditions["temperature"] = "[bad"
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("extraConditions") }))
    }

    @Test("measuringCondition: unit_suffix missing extraConditions entry fails")
    func measuringConditionUnitSuffixMissingEntry() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let (store, _) = try makeStore()

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", label: nil, kind: "unit_suffix",
                                                binding: "conditions.extraConditions.field"))
        // No entry in extraConditions for "field"
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
                                                binding: "conditions.extraConditions.field"))
        draft.conditions.extraConditions["field"] = "^-?\\d+T$"
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }
        #expect(!store.dirtySections.contains(.measuringCondition))
    }
}
