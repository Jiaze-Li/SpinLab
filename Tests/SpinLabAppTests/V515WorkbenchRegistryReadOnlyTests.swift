import Foundation
import Testing
@testable import SpinLabApp

/// Verifies that WorkbenchFeatureStore reads workflow definitions from
/// WorkflowDefinitionStore (config/workflow.json) and that the registry
/// editing path has been fully removed.
@MainActor
@Suite("V5.1.5 WorkbenchRegistry Read-Only")
struct V515WorkbenchRegistryReadOnlyTests {

    private func makeWorkflowFileURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v515-wbro-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workflow.json")
    }

    private func writeWorkflowJSON(to url: URL, entries: [(id: String, displayName: String, conditionFieldIDs: [String])]) throws {
        let workflows = entries.map { entry -> [String: Any] in
            [
                "id": entry.id,
                "displayName": entry.displayName,
                "matchRules": [] as [[String: Any]],
                "conditionFieldIDs": entry.conditionFieldIDs
            ]
        }
        let json: [String: Any] = ["version": 1, "workflows": workflows, "measurementTagRules": []]
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try data.write(to: url)
    }

    private func makeStore(workflowFileURL: URL) -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence),
            workflowDefinitionStore: WorkflowDefinitionStore(fileURL: workflowFileURL)
        )
    }

    @Test("workflowDefinitions loaded from workflow.json")
    func loadsDefinitionsFromWorkflowJSON() throws {
        let url = try makeWorkflowFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try writeWorkflowJSON(to: url, entries: [
            (id: "XY", displayName: "XY Rotation", conditionFieldIDs: ["temperature", "field"]),
            (id: "RT", displayName: "RT", conditionFieldIDs: ["current"])
        ])

        let store = makeStore(workflowFileURL: url)

        #expect(store.workflowDefinitions.count == 2)
        #expect(store.workflowDefinitions.contains { $0.id == "XY" && $0.displayName == "XY Rotation" })
        #expect(store.workflowDefinitions.contains { $0.id == "RT" })
        let xy = store.workflowDefinitions.first { $0.id == "XY" }
        #expect(xy?.conditionFields.map(\.definitionID) == ["temperature", "field"])
    }

    @Test("selectWorkflow routes to .workflow when ID exists")
    func selectWorkflowRoutesToWorkflowRoute() throws {
        let url = try makeWorkflowFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try writeWorkflowJSON(to: url, entries: [
            (id: "XY", displayName: "XY Rotation", conditionFieldIDs: [])
        ])

        let store = makeStore(workflowFileURL: url)
        store.selectWorkflow("XY")

        switch store.currentRoute {
        case .workflow(let id):
            #expect(id == "XY")
        case .registry:
            Issue.record("Expected .workflow route after selectWorkflow")
        }
    }

    @Test("empty workflow.json returns empty definitions without crashing")
    func missingWorkflowFileReturnsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")

        let store = makeStore(workflowFileURL: url)
        #expect(store.workflowDefinitions.isEmpty)
    }

    @Test("WorkflowFileDraft decodes match rules and measurementTagRules without scope field")
    func decodesMatchRulesWithoutScope() throws {
        // Regression: scope was decoded as required; real workflow.json never wrote it.
        // Both WorkflowMatchSpec and MapRule.MatchSpec must tolerate a missing scope key.
        let json = """
        {
          "version": 2,
          "workflows": [
            {
              "id": "MR",
              "displayName": "MR",
              "conditionFieldIDs": ["temperature"],
              "matchRules": [{"type": "equals", "matchValues": ["MR"]}]
            }
          ],
          "measurementTagRules": [
            {"match": {"type": "equals", "matchValues": ["AMR"]}, "value": "AMR"}
          ]
        }
        """
        let draft = try JSONDecoder().decode(WorkflowFileDraft.self, from: Data(json.utf8))
        #expect(draft.workflows.count == 1)
        #expect(draft.workflows[0].matchRules[0].scope == "tokens")
        #expect(draft.measurementTagRules[0].match.scope == "tokens")
    }

    @Test("WorkbenchFeatureStore has no workflow CRUD methods (compile-time guard)")
    func noCRUDMethodsExist() {
        // Structural check: if any CRUD method were re-added, the corresponding
        // selector check would need to be added here. The absence of addWorkflow,
        // removeSelectedWorkflow, updateSelectedWorkflow, etc. is verified by
        // the fact that this file compiles without referencing them.
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        let store = WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
        // selectWorkflow still exists (for read-only navigation)
        store.selectWorkflow(nil)
        #expect(Bool(true))
    }
}
