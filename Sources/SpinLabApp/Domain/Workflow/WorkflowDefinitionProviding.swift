import Foundation

protocol WorkflowDefinitionProviding {
    func load() -> [WorkflowDefinition]
}

extension WorkflowDefinitionStore: WorkflowDefinitionProviding {}
