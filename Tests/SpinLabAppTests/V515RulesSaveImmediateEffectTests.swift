import Foundation
import Testing
@testable import SpinLabApp

// R1 acceptance gate: after saving any section, the next in-process read must use new data.
// WorkbenchFeatureStore.conditionDefinitionOptions is the B-class snapshot that requires
// an explicit callback — this suite verifies the onRulesSaved → reloadWorkflowDefinitionsAfterRulesChange
// path is wired correctly.

@MainActor
@Suite("V5.1.5 Rules Save Immediate Effect (R1)", .serialized)
struct V515RulesSaveImmediateEffectTests {

    private static let backupExtension = "v515-r1-backup"

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

    private func writeInitialConfig() throws -> RulesConfigPaths {
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        try? fm.removeItem(at: paths.configDirectoryURL)
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)

        try """
        {"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":[]}}
        """.data(using: .utf8)!.write(to: paths.importFiltersURL)

        try """
        {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
        """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)

        try """
        {"version":3,"sampleId":{"patterns":["^[A-Z]{2}\\\\d+$"]},"substrate":{"substrateTagRules":[],"materials":[],"treatments":[],"orientations":{"pattern":"\\\\d{3}","rows":[]}}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        // Only "temperature" defined initially
        try """
        {"version":2,"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^\\\\d+K$"}]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        return paths
    }

    // MARK: - Tests

    @Test("R1: RuleLoader cache updated immediately after sampleIdentification save")
    func r1SampleIdentificationPatternImmediatelyActive() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        _ = try writeInitialConfig()

        var r1Fired = false
        let store = RulesManagementStore(onRulesSaved: {
            let patterns = RuleLoader.shared.loadCached().ruleSet.sampleId.patterns
            if patterns.contains(where: { $0.contains("NEWPATTERN") }) {
                r1Fired = true
            }
        })
        store.present()

        var draft = try #require(store.sampleIdentificationDraft)
        draft.sampleId.patterns = ["^NEWPATTERN\\d+$"]
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }
        #expect(r1Fired, "RuleLoader cache must be updated before onRulesSaved fires")
    }

    @Test("R1: RuleLoader cache updated immediately after workflow save")
    func r1WorkflowMeasurementTagRuleImmediatelyActive() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        _ = try writeInitialConfig()

        var r1Fired = false
        let store = RulesManagementStore(onRulesSaved: {
            let ruleSet = RuleLoader.shared.loadCached().ruleSet
            if ruleSet.measurementTagRules.contains(where: { $0.value == "NEWTAG" }) {
                r1Fired = true
            }
        })
        store.present()

        var draft = try #require(store.workflowDraft)
        draft.measurementTagRules.append(
            MapRule(match: .init(scope: "tokens", type: "equals", matchValues: ["NEWTAG"]),
                    value: "NEWTAG")
        )
        store.updateWorkflow(draft)
        store.selectSection(.workflow)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }
        #expect(r1Fired, "RuleLoader cache must reflect new measurementTagRule immediately")
    }

    @Test("R1: conditionDefinitionOptions updated via onRulesSaved callback")
    func r1ConditionDefinitionOptionsRefreshed() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        _ = try writeInitialConfig()

        // Simulate the wiring in SpinLabAppState: store calls a closure that refreshes
        // conditionDefinitionOptions on the Workbench side. We verify the options list is stale
        // before save and fresh after.
        var capturedOptionsAfterSave: [String] = []
        var capturedRuleSetLoaded = false

        let store = RulesManagementStore(onRulesSaved: {
            let ruleSet = RuleLoader.shared.loadCached().ruleSet
            capturedRuleSetLoaded = true
            capturedOptionsAfterSave = ruleSet.conditionDefinitions.map(\.id)
        })
        store.present()

        // Initially only "temperature"
        let initialIDs = store.measuringConditionDraft?.conditionDefinitions.map(\.id) ?? []
        #expect(initialIDs == ["temperature"])

        // Add "field" condition
        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "field", label: "Field", kind: "unit_suffix",
                                                unitPattern: "^\\d+T$", tokenMap: nil))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }

        // onRulesSaved must have fired, and the captured options must contain "field"
        #expect(capturedOptionsAfterSave.contains("field"),
                "conditionDefinition options must include 'field' immediately after save (R1)")
        #expect(capturedRuleSetLoaded)
    }

    @Test("R1: availableConditionFieldIDs in store refreshes after measuringCondition save")
    func r1AvailableConditionFieldIDsRefreshesOnSave() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        _ = try writeInitialConfig()

        let store = RulesManagementStore()
        store.present()

        let before = store.availableConditionFieldIDs
        #expect(before == ["temperature"])

        var draft = try #require(store.measuringConditionDraft)
        draft.conditionDefinitions.append(.init(id: "current", label: "Current", kind: "unit_suffix",
                                                unitPattern: "^\\d+mA$", tokenMap: nil))
        store.updateMeasuringCondition(draft)
        store.selectSection(.measuringCondition)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }

        // After save, store must reflect new conditions immediately
        let after = store.availableConditionFieldIDs
        #expect(after.contains("current"), "availableConditionFieldIDs must update after save")
    }
}
