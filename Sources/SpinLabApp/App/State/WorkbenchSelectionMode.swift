import Foundation

/// Cardinality policy for a workflow's Workbench selection basket.
///
/// `WorkbenchWorkflowKind.selectionMode` is the single owner of which workflows get which
/// policy. `WorkbenchFeatureStore`'s selection facade enforces the policy on top of the
/// generic, cardinality-agnostic `WorkbenchSelectionRuntime` rather than teaching the
/// runtime or any individual workflow store about it.
enum WorkbenchSelectionMode {
    /// Basket count is always 0 or 1: selecting a new hit replaces any previously selected
    /// hit for that workflow, and `Select All` is not an actionable operation.
    case single
    /// Unbounded multi-hit basket — current behavior for AHE / 3ω / XY / IV / RT.
    case multiple
}
