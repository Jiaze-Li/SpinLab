import Foundation

struct SelectedHitDisplayInfo: Sendable {
    let id: String
    let workflowDisplayName: String
    let sampleBatchAndSubstrate: String
    let conditionSummary: String
    let shortFilename: String

    init(from hit: WorkflowMeasurementSearchHit) {
        id = hit.id
        workflowDisplayName = hit.workflowDisplayName
        sampleBatchAndSubstrate = hit.sampleBatchAndSubstrate
        conditionSummary = hit.conditionSummary
        shortFilename = URL(fileURLWithPath: hit.measurementFilePath).lastPathComponent
    }
}

@MainActor
@Observable
final class WorkbenchSelectionRuntime {
    private var selectedIDsByWorkflow: [WorkbenchWorkflowID: Set<String>] = [:]
    private var displayCacheByWorkflow: [WorkbenchWorkflowID: [String: SelectedHitDisplayInfo]] = [:]

    func selectedIDs(for wf: WorkbenchWorkflowID) -> Set<String> {
        selectedIDsByWorkflow[wf] ?? []
    }

    func selectedCount(for wf: WorkbenchWorkflowID) -> Int {
        (selectedIDsByWorkflow[wf] ?? []).count
    }

    /// Returns true only when every denominator hit ID is in the selected set.
    func isAllSelected(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) -> Bool {
        guard !denominator.isEmpty else { return false }
        let selected = selectedIDsByWorkflow[wf] ?? []
        return denominator.allSatisfy { selected.contains($0.id) }
    }

    func toggle(_ id: String, for wf: WorkbenchWorkflowID, displayInfo: SelectedHitDisplayInfo? = nil) {
        var ids = selectedIDsByWorkflow[wf] ?? []
        var cache = displayCacheByWorkflow[wf] ?? [:]
        if ids.contains(id) {
            ids.remove(id)
            cache.removeValue(forKey: id)
        } else {
            ids.insert(id)
            if let info = displayInfo { cache[id] = info }
        }
        selectedIDsByWorkflow[wf] = ids
        displayCacheByWorkflow[wf] = cache
    }

    /// Unions current search result IDs into the existing selection without dropping previously selected hits.
    func selectAll(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) {
        var ids = selectedIDsByWorkflow[wf] ?? []
        var cache = displayCacheByWorkflow[wf] ?? [:]
        for hit in denominator {
            ids.insert(hit.id)
            cache[hit.id] = SelectedHitDisplayInfo(from: hit)
        }
        selectedIDsByWorkflow[wf] = ids
        displayCacheByWorkflow[wf] = cache
    }

    /// Removes only the specified current-result IDs; previously selected hits from other searches are kept.
    func deselectCurrentResults(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) {
        var ids = selectedIDsByWorkflow[wf] ?? []
        var cache = displayCacheByWorkflow[wf] ?? [:]
        for hit in denominator {
            ids.remove(hit.id)
            cache.removeValue(forKey: hit.id)
        }
        selectedIDsByWorkflow[wf] = ids
        displayCacheByWorkflow[wf] = cache
    }

    /// Clears the entire selection basket for the workflow (used by tray Clear button).
    func deselectAll(for wf: WorkbenchWorkflowID) {
        selectedIDsByWorkflow[wf] = []
        displayCacheByWorkflow[wf] = [:]
    }

    /// Returns cached display info for all selected hits, in stable ID-sorted order.
    func selectedHitDisplayInfos(for wf: WorkbenchWorkflowID) -> [SelectedHitDisplayInfo] {
        let ids = selectedIDsByWorkflow[wf] ?? []
        let cache = displayCacheByWorkflow[wf] ?? [:]
        return ids.sorted().compactMap { cache[$0] }
    }

    /// Seed selection from pack restore; does not trigger any observable side-effects beyond state change.
    func seed(_ ids: Set<String>, for wf: WorkbenchWorkflowID) {
        selectedIDsByWorkflow[wf] = ids
        // Display cache not seeded — info becomes available when hits reappear in search results.
    }
}
