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
    /// Full hit objects keyed by ID, so snapshot building survives search changes.
    private var hitCacheByWorkflow: [WorkbenchWorkflowID: [String: WorkflowMeasurementSearchHit]] = [:]

    func selectedIDs(for wf: WorkbenchWorkflowID) -> Set<String> {
        selectedIDsByWorkflow[wf] ?? []
    }

    func selectedCount(for wf: WorkbenchWorkflowID) -> Int {
        (selectedIDsByWorkflow[wf] ?? []).count
    }

    func selectedHitCache(for wf: WorkbenchWorkflowID) -> [String: WorkflowMeasurementSearchHit] {
        hitCacheByWorkflow[wf] ?? [:]
    }

    /// Returns true only when every denominator hit ID is in the selected set.
    func isAllSelected(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) -> Bool {
        guard !denominator.isEmpty else { return false }
        let selected = selectedIDsByWorkflow[wf] ?? []
        return denominator.allSatisfy { selected.contains($0.id) }
    }

    func toggle(_ id: String, for wf: WorkbenchWorkflowID, hit: WorkflowMeasurementSearchHit? = nil) {
        var ids = selectedIDsByWorkflow[wf] ?? []
        var displayCache = displayCacheByWorkflow[wf] ?? [:]
        var hitCache = hitCacheByWorkflow[wf] ?? [:]
        if ids.contains(id) {
            ids.remove(id)
            displayCache.removeValue(forKey: id)
            hitCache.removeValue(forKey: id)
        } else {
            ids.insert(id)
            if let hit {
                displayCache[id] = SelectedHitDisplayInfo(from: hit)
                hitCache[id] = hit
            }
        }
        selectedIDsByWorkflow[wf] = ids
        displayCacheByWorkflow[wf] = displayCache
        hitCacheByWorkflow[wf] = hitCache
    }

    /// Unions current search result IDs into the existing selection without dropping previously selected hits.
    func selectAll(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) {
        var ids = selectedIDsByWorkflow[wf] ?? []
        var displayCache = displayCacheByWorkflow[wf] ?? [:]
        var hitCache = hitCacheByWorkflow[wf] ?? [:]
        for hit in denominator {
            ids.insert(hit.id)
            displayCache[hit.id] = SelectedHitDisplayInfo(from: hit)
            hitCache[hit.id] = hit
        }
        selectedIDsByWorkflow[wf] = ids
        displayCacheByWorkflow[wf] = displayCache
        hitCacheByWorkflow[wf] = hitCache
    }

    /// Removes only the specified current-result IDs; previously selected hits from other searches are kept.
    func deselectCurrentResults(for wf: WorkbenchWorkflowID, denominator: [WorkflowMeasurementSearchHit]) {
        var ids = selectedIDsByWorkflow[wf] ?? []
        var displayCache = displayCacheByWorkflow[wf] ?? [:]
        var hitCache = hitCacheByWorkflow[wf] ?? [:]
        for hit in denominator {
            ids.remove(hit.id)
            displayCache.removeValue(forKey: hit.id)
            hitCache.removeValue(forKey: hit.id)
        }
        selectedIDsByWorkflow[wf] = ids
        displayCacheByWorkflow[wf] = displayCache
        hitCacheByWorkflow[wf] = hitCache
    }

    /// Clears the entire selection basket for the workflow (used by tray Clear button).
    func deselectAll(for wf: WorkbenchWorkflowID) {
        selectedIDsByWorkflow[wf] = []
        displayCacheByWorkflow[wf] = [:]
        hitCacheByWorkflow[wf] = [:]
    }

    /// Returns cached display info for all selected hits, in stable ID-sorted order.
    func selectedHitDisplayInfos(for wf: WorkbenchWorkflowID) -> [SelectedHitDisplayInfo] {
        let ids = selectedIDsByWorkflow[wf] ?? []
        let cache = displayCacheByWorkflow[wf] ?? [:]
        return ids.sorted().compactMap { cache[$0] }
    }

    /// Seed selection from pack restore; does not trigger any observable side-effects beyond state change.
    /// Hit cache is NOT seeded — full hit objects become available again when hits reappear in search results.
    func seed(_ ids: Set<String>, for wf: WorkbenchWorkflowID) {
        selectedIDsByWorkflow[wf] = ids
    }
}
