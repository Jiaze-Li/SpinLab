import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesPanel Save Validation", .serialized)
struct V515RulesPanelSaveValidationTests {

    private struct IsolationContext {
        let dir: URL
        let paths: RulesConfigPaths
    }

    private func acquireIsolation() throws -> IsolationContext {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return IsolationContext(dir: dir, paths: RulesConfigPaths(configDirectoryURL: dir))
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        try? FileManager.default.removeItem(at: ctx.dir)
    }

    private func makeStore(_ ctx: IsolationContext) throws -> (RulesManagementStore, RulesConfigPaths) {
        let paths = ctx.paths
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
        {"version":4,"sampleId":{"batchPrefixes":["PN"]},"substrate":{"materials":[{"displayName":"STO","matches":[{"type":"equals","value":"STO"}]}],"treatments":[],"orientations":[{"displayName":"111","matches":[{"type":"equals","value":"111"}]}]}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        try """
        {"version":2,"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^\\\\d+K$"}]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        let store = RulesManagementStore(rulesBookPaths: paths)
        store.present()
        return (store, paths)
    }

    // MARK: - Import Filters

    @Test("importFilters: extension with space fails")
    func importFiltersSpaceInExtension() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.filenameTokenizationDraft)
        draft.sources = []
        store.updateFilenameTokenization(draft)
        store.selectSection(.filenameTokenization)

        guard case .validationFailed = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
    }

    // MARK: - Sample Identification

    @Test("sampleIdentification: empty material display name fails")
    func sampleIDEmptyMaterialDisplayName() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.sampleIdentificationDraft)
        draft.substrate.materials.append(.init(displayName: "", matches: []))
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("displayName") && $0.message.contains("empty") }))
    }

    @Test("sampleIdentification: duplicate treatment display name fails")
    func sampleIDDuplicateTreatmentDisplayName() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.sampleIdentificationDraft)
        let t1 = SampleIdentificationFileDraft.SubstrateEntry(displayName: "HF", matches: [])
        let t2 = SampleIdentificationFileDraft.SubstrateEntry(displayName: "HF", matches: [])
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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.workflowDraft)
        draft.workflows.append(.init(id: "MR", displayName: "MR2",
                                     matchRules: [.init(type: "equals", value: "MR2")],
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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "temperature", displayName: nil,
                                                matches: [MapRule(match: .init(type: "unit-suffix", value: "K"), value: "$MATCH")]))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") }))
    }

    @Test("measuringCondition: unit_suffix rule saves without regex validation")
    func measuringConditionUnitSuffixSavesWithoutRegexValidation() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", displayName: nil,
                                                matches: [MapRule(match: .init(type: "unit-suffix", value: "T"), value: "$MATCH")]))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved — unit-suffix rules have no regex to validate"); return
        }
    }

    @Test("measuringCondition: condition with regex op fails validation")
    func measuringConditionRegexRuleFails() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", displayName: nil,
                                                matches: [MapRule(match: .init(type: "regex", value: "[invalid"), value: "x")]))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("field") }))
    }

    @Test("measuringCondition: valid condition saves successfully")
    func measuringConditionValidSave() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", displayName: "Field",
                                                matches: [MapRule(match: .init(type: "unit-suffix", value: "T"), value: "$MATCH")]))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }
        #expect(!store.dirtySections.contains(.measuringCondition))
    }

    // MARK: - Workflow regex validation (s11)

    @Test("workflow: invalid regex in matchRules fails validation")
    func workflowMatchRulesInvalidRegex() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.workflowDraft)
        draft.workflows[0].matchRules = [
            .init(type: "regex", value: "[bad")
        ]
        store.updateWorkflow(draft)
        store.selectSection(.workflow)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("matchRules") && $0.message.contains("[bad") }))
    }

    @Test("workflow: invalid regex in measurementTagRules fails validation")
    func workflowMeasurementTagRulesInvalidRegex() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let (store, _) = try makeStore(ctx)

        var draft = try #require(store.workflowDraft)
        draft.measurementTagRules = [
            MapRule(match: .init(type: "regex", value: "[bad"), value: "TAG")
        ]
        store.updateWorkflow(draft)
        store.selectSection(.workflow)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("measurementTagRules") && $0.message.contains("[bad") }))
    }
}
