import Foundation

final class WorkflowDefinitionStore {
    private let fixedFileURL: URL?
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fixedFileURL = fileURL
    }

    func load() -> [WorkflowDefinition] {
        guard let url = fixedFileURL ?? RuleLoader.currentBookPaths?.workflowURL,
              FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
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
