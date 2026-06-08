import Foundation

@MainActor
@Observable
final class WorkbenchSelectionRuntime {
    private var selectedIDsByWorkflow: [WorkbenchWorkflowID: Set<String>] = [:]

    func selectedIDs(for wf: WorkbenchWorkflowID) -> Set<String> {
        selectedIDsByWorkflow[wf] ?? []
    }

    func selectedCount(for wf: WorkbenchWorkflowID) -> Int {
        (selectedIDsByWorkflow[wf] ?? []).count
    }

    func isAllSelected(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) -> Bool {
        guard !denominator.isEmpty else { return false }
        return (selectedIDsByWorkflow[wf] ?? []).count == denominator.count
    }

    func toggle(_ id: String, for wf: WorkbenchWorkflowID) {
        var ids = selectedIDsByWorkflow[wf] ?? []
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        selectedIDsByWorkflow[wf] = ids
    }

    func selectAll(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) {
        selectedIDsByWorkflow[wf] = Set(denominator.map(\.id))
    }

    func deselectAll(for wf: WorkbenchWorkflowID) {
        selectedIDsByWorkflow[wf] = []
    }

    /// Seed selection from pack restore; does not trigger any observable side-effects beyond state change.
    func seed(_ ids: Set<String>, for wf: WorkbenchWorkflowID) {
        selectedIDsByWorkflow[wf] = ids
    }
}
