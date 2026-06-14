import Foundation

/// Read surface for workflow-selected hits.
struct WorkbenchSelectedHitsSnapshot: Sendable {
    enum SelectionSource: Sendable {
        case canonicalSnapshot
    }

    let workflowID: WorkbenchWorkflowID
    let queryText: String
    let selectedIDs: Set<String>
    let selectedHits: [WorkflowMeasurementSearchHit]
    let sourceHitCount: Int
    let selectionSource: SelectionSource

    var isEmpty: Bool { selectedHits.isEmpty }
}
