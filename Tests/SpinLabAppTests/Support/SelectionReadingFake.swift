import Foundation
@testable import SpinLabApp

@MainActor
final class SelectionReadingFake: SelectionReading {
    var ids: Set<String> = []
    func selectedIDs(for wf: WorkbenchWorkflowID) -> Set<String> { ids }
}
