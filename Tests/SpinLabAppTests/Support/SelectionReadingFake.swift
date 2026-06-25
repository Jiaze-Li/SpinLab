import Foundation
@testable import SpinLabApp

@MainActor
final class SelectionReadingFake: SelectionReading {
    var idsByWorkflow: [WorkflowKey: Set<String>] = [:]
    func selectedIDs(for wf: WorkflowKey) -> Set<String> { idsByWorkflow[wf] ?? [] }
}
