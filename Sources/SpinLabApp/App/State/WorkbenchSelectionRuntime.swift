import Foundation

/// Read-only surface for querying selection state from workspace stores.
/// Declared class-constrained so stores can hold a weak reference.
@MainActor
protocol SelectionReading: AnyObject {
    func selectedIDs(for wf: String) -> Set<String>
}

/// One rendered series' presentation as shown in the Selected-hits tray: `finalLabel` is the
/// user-visible legend text (which duplicate series may legitimately share), while
/// `seriesIdentityKey` (from `ResolvedSeriesPresentation.identityKey`) is the stable per-series
/// identity that must be used for SwiftUI `ForEach` — never `finalLabel` itself, since duplicate
/// labels would collide as SwiftUI identity.
struct ResolvedSeriesLabel: Sendable, Hashable {
    let seriesIdentityKey: String
    let finalLabel: String
}

struct SelectedHitDisplayInfo: Sendable {
    let id: String
    let workflowDisplayName: String
    let sampleBatchAndSubstrate: String
    let conditionSummary: String
    let shortFilename: String
    /// Final legend-resolved label(s) for this hit's rendered series in the active tab, joined
    /// in by `WorkbenchFeatureStore.selectedHitDisplayInfos(for:)` via a direct dictionary
    /// lookup keyed by `ResolvedSeriesPresentation.hitID == hit.id` — never sourceRef/sampleID
    /// fallback matching. Plural because one hit can legitimately produce multiple series in
    /// the same tab (e.g. AHE's per-channel fan-out): each element carries that series'
    /// stable identity alongside its finalLabel, since two series from the same hit may share an
    /// identical finalLabel. Empty when the hit has no matching rendered series (not part of the
    /// active tab, nothing rendered yet, or the tab has no per-hit series at all) — callers must
    /// fall back to `sampleBatchAndSubstrate`. Never set by re-invoking LegendResolver.
    var resolvedLabels: [ResolvedSeriesLabel] = []

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
    private var selectedIDsByWorkflow: [String: Set<String>] = [:]
    private var displayCacheByWorkflow: [String: [String: SelectedHitDisplayInfo]] = [:]
    /// Full hit objects keyed by ID, so snapshot building survives search changes.
    private var hitCacheByWorkflow: [String: [String: WorkflowMeasurementSearchHit]] = [:]

    func selectedIDs(for wf: String) -> Set<String> {
        selectedIDsByWorkflow[wf] ?? []
    }

    /// Visible-selection count: the size of the selected-ID set intersected with `denominator`
    /// (the current canonical result set). IDs selected from a superseded search do not inflate
    /// this count even though they remain in the internal cross-search basket.
    func selectedCount(for wf: String, denominator: [WorkflowMeasurementSearchHit]) -> Int {
        guard !denominator.isEmpty else { return 0 }
        let selected = selectedIDsByWorkflow[wf] ?? []
        return denominator.reduce(into: 0) { count, hit in
            if selected.contains(hit.id) { count += 1 }
        }
    }

    func selectedHitCache(for wf: String) -> [String: WorkflowMeasurementSearchHit] {
        hitCacheByWorkflow[wf] ?? [:]
    }

    /// Returns true only when every denominator hit ID is in the selected set.
    func isAllSelected(for wf: String, denominator: [WorkflowMeasurementSearchHit]) -> Bool {
        guard !denominator.isEmpty else { return false }
        let selected = selectedIDsByWorkflow[wf] ?? []
        return denominator.allSatisfy { selected.contains($0.id) }
    }

    func toggle(_ id: String, for wf: String, hit: WorkflowMeasurementSearchHit? = nil) {
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
    func selectAll(for wf: String, denominator: [WorkflowMeasurementSearchHit]) {
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
    func deselectCurrentResults(for wf: String, denominator: [WorkflowMeasurementSearchHit]) {
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
    func deselectAll(for wf: String) {
        selectedIDsByWorkflow[wf] = []
        displayCacheByWorkflow[wf] = [:]
        hitCacheByWorkflow[wf] = [:]
    }

    /// Returns cached display info for all selected hits, in stable ID-sorted order.
    func selectedHitDisplayInfos(for wf: String) -> [SelectedHitDisplayInfo] {
        let ids = selectedIDsByWorkflow[wf] ?? []
        let cache = displayCacheByWorkflow[wf] ?? [:]
        return ids.sorted().compactMap { cache[$0] }
    }

    /// Seed selection from pack restore and hydrate display/hit caches from the provided available hits.
    /// IDs with no matching hit in availableHits are kept in the selection but remain cache-dark until
    /// they reappear in a search (graceful degradation — no crash).
    func seed(ids: Set<String>, for wf: String, availableHits: [WorkflowMeasurementSearchHit]) {
        selectedIDsByWorkflow[wf] = ids
        var displayCache: [String: SelectedHitDisplayInfo] = [:]
        var hitCache: [String: WorkflowMeasurementSearchHit] = [:]
        for hit in availableHits where ids.contains(hit.id) {
            displayCache[hit.id] = SelectedHitDisplayInfo(from: hit)
            hitCache[hit.id] = hit
        }
        displayCacheByWorkflow[wf] = displayCache
        hitCacheByWorkflow[wf] = hitCache
    }

    /// Restore selection from a persisted pack, reconciled against the pack's own restored hit set.
    /// Unlike `seed(ids:for:availableHits:)`, IDs with no matching hit in `availableHits` are
    /// DROPPED, not kept cache-dark — a restored pack's `availableHits` is the reconciliation
    /// boundary for this phase (no live library re-query), so an ID that isn't in it no longer
    /// exists and must not remain selected indefinitely.
    func seedRestored(ids: Set<String>, for wf: String, availableHits: [WorkflowMeasurementSearchHit]) {
        let availableIDs = Set(availableHits.map(\.id))
        let reconciledIDs = ids.intersection(availableIDs)
        selectedIDsByWorkflow[wf] = reconciledIDs
        var displayCache: [String: SelectedHitDisplayInfo] = [:]
        var hitCache: [String: WorkflowMeasurementSearchHit] = [:]
        for hit in availableHits where reconciledIDs.contains(hit.id) {
            displayCache[hit.id] = SelectedHitDisplayInfo(from: hit)
            hitCache[hit.id] = hit
        }
        displayCacheByWorkflow[wf] = displayCache
        hitCacheByWorkflow[wf] = hitCache
    }
}

// selectedIDs(for:) is already defined above; the empty extension only declares protocol conformance.
extension WorkbenchSelectionRuntime: SelectionReading {}
