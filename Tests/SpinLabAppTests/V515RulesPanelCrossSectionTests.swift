import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesPanel Cross-Section", .serialized)
struct V515RulesPanelCrossSectionTests {

    private static let backupExtension = "v515-cross-backup"

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

    private func setupStore(conditionIDs: [String] = ["temperature", "field"]) throws -> RulesManagementStore {
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
        {"version":3,"sampleId":{"patterns":[]},"substrate":{"substrateTagRules":[],"materials":[],"treatments":[],"orientations":{"pattern":"\\\\d{3}","rows":[]}}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        // workflow references first conditionID
        let firstID = conditionIDs.first ?? "temperature"
        try """
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["\(firstID)"]}],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        // measuringCondition defines all conditionIDs
        let defs = conditionIDs.map { id in
            "{\"id\":\"\(id)\",\"label\":\"\(id)\",\"kind\":\"unit_suffix\",\"unitPattern\":\"^\\\\d+$\"}"
        }.joined(separator: ",")
        try """
        {"version":2,"conditionDefinitions":[\(defs)]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        let store = RulesManagementStore()
        store.present()
        return store
    }

    // MARK: - Tests

    @Test("workflow save uses dirty measuringCondition draft for cross-section validation")
    func workflowSaveUsesDirtyMeasuringCondition() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try setupStore(conditionIDs: ["temperature"])

        // Add a new condition only in the draft (not yet saved to disk)
        var mcDraft = try #require(store.measuringConditionDraft)
        mcDraft.conditionDefinitions.append(.init(id: "field", label: "Field", kind: "unit_suffix",
                                                  unitPattern: "^\\d+T$", tokenMap: nil))
        store.updateMeasuringCondition(mcDraft)

        // Workflow references the new "field" condition that exists only in draft
        var wfDraft = try #require(store.workflowDraft)
        wfDraft.workflows[0].conditionFieldIDs = ["temperature", "field"]
        store.updateWorkflow(wfDraft)
        store.selectSection(.workflow)

        // Should succeed because "field" is in dirty measuringCondition draft
        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved — workflow should see dirty measuringCondition draft"); return
        }
    }

    @Test("workflow save fails when conditionFieldID not in disk or draft")
    func workflowSaveFailsForUnknownCondition() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try setupStore(conditionIDs: ["temperature"])

        var wfDraft = try #require(store.workflowDraft)
        wfDraft.workflows[0].conditionFieldIDs = ["temperature", "completely_unknown"]
        store.updateWorkflow(wfDraft)
        store.selectSection(.workflow)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed for unknown conditionFieldID"); return
        }
        #expect(errors.contains(where: { $0.message.contains("completely_unknown") }))
    }

    @Test("Save All with workflow + measuringCondition both dirty uses allCases order")
    func saveAllOrderWithBothDirty() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try setupStore(conditionIDs: ["temperature"])

        var hookOrder: [String] = []
        store.persistenceHook = RulesPersistenceHook(didPersist: { sectionID, _, _, _, _ in
            hookOrder.append(sectionID)
        })

        // Mark both measuringCondition and workflow dirty
        if let mc = store.measuringConditionDraft { store.updateMeasuringCondition(mc) }
        if let wf = store.workflowDraft { store.updateWorkflow(wf) }

        // Save All in allCases order
        for section in RulesPanelSection.allCases where store.dirtySections.contains(section) {
            store.selectSection(section)
            _ = store.saveCurrent()
        }

        // measuringCondition (index 4) must appear before workflow (index 3) is not the case —
        // allCases order is importFilters < filenameTokenization < sampleIdentification < workflow < measuringCondition
        // so workflow saves BEFORE measuringCondition, but the cross-section check reads dirty draft
        let workflowPos = hookOrder.firstIndex(of: "workflow")
        let measuringPos = hookOrder.firstIndex(of: "measuringCondition")
        if let wp = workflowPos, let mp = measuringPos {
            #expect(wp < mp, "workflow must save before measuringCondition in allCases order")
        }
    }

    @Test("workflow conditionFieldIDs cross-validation with measuringCondition dirty draft")
    func crossSectionValidationWithDirtyDraft() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try setupStore(conditionIDs: ["temperature"])

        // The disk has only "temperature". Add "device" to the dirty draft only.
        var mcDraft = try #require(store.measuringConditionDraft)
        mcDraft.conditionDefinitions.append(.init(id: "device", label: "Device", kind: "unit_suffix",
                                                  unitPattern: "^wafer$", tokenMap: nil))
        store.updateMeasuringCondition(mcDraft)

        // Workflow references "device" (only in dirty draft)
        var wfDraft = try #require(store.workflowDraft)
        wfDraft.workflows[0].conditionFieldIDs = ["device"]
        store.updateWorkflow(wfDraft)
        store.selectSection(.workflow)

        // Should pass because store reads dirty measuringConditionDraft
        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved — cross-section should use dirty draft"); return
        }
    }
}
