import Foundation

final class WorkflowDefinitionStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()

    init(fileURL: URL = RulesConfigPaths().workflowURL) {
        self.fileURL = fileURL
    }

    func load() -> [WorkflowDefinition] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let draft = try? decoder.decode(WorkflowFileDraft.self, from: data) else {
            return []
        }
        return draft.workflows.map { entry in
            WorkflowDefinition(
                id: entry.id,
                displayName: entry.displayName,
                conditionFields: entry.conditionFieldIDs.map { WorkflowConditionField(definitionID: $0) }
            )
        }
    }
}
