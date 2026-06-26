import Foundation
@testable import SpinLabApp

@MainActor
final class SelectionReadingFake: SelectionReading {
    var idsByWorkflow: [String: Set<String>] = [:]
    func selectedIDs(for wf: String) -> Set<String> { idsByWorkflow[wf] ?? [] }
}
