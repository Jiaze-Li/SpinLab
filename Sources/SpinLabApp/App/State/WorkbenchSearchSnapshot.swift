import Foundation

/// Read surface for WorkbenchFeatureStore search shell state.
/// Aggregates all per-workflow search fields into a single immutable value.
struct WorkbenchSearchSnapshot: Sendable {
    let workflowID: WorkbenchWorkflowID
    let queryText: String
    let results: [WorkflowMeasurementSearchHit]
    let isRunning: Bool
    let message: String?
}
