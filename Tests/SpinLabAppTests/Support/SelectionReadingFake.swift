import Foundation
@testable import SpinLabApp

@MainActor
final class SelectionReadingFake: SelectionReading {
    var idsByWorkflow: [WorkbenchWorkflowID: Set<String>] = [:]
    func selectedIDs(for wf: WorkbenchWorkflowID) -> Set<String> { idsByWorkflow[wf] ?? [] }
}
