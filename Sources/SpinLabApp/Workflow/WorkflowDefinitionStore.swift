import Foundation

final class WorkflowDefinitionStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()

    init(fileURL: URL = RulesConfigPaths().workflowURL) {
        self.fileURL = fileURL
    }

    func load() -> [WorkflowDefinition] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let draft = try decoder.decode(WorkflowFileDraft.self, from: data)
            return draft.workflows.map { entry in
                WorkflowDefinition(
                    id: entry.id,
                    displayName: entry.displayName,
                    conditionFields: entry.conditionFieldIDs.map { WorkflowConditionField(definitionID: $0) }
                )
            }
        } catch {
            fputs("[WorkflowDefinitionStore] load failed: \(error)\n", stderr)
            return []
        }
    }
}
