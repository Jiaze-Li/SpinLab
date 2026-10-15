import Foundation

/// Canonical typed identity for the six concrete Workbench workflows.
///
/// `WorkbenchFeatureStore.workflowKind(for:)` is the single owner of the mapping from a
/// raw Rule Book workflow id string to one of these cases. Both view dispatch
/// (`WorkflowWorkspaceRegistry`) and state/business access (`WorkbenchFeatureStore`'s own
/// accessors) switch on this typed value instead of independently re-deriving the same
/// `workflowID ==` string chain.
///
/// ## Adding a new workflow
/// Add a case here, then handle it in every downstream exhaustive switch — the compiler
/// will point at each one. See `docs/architecture/workbench/ADDING_WORKFLOW.md`.
enum WorkbenchWorkflowKind {
    case ahe
    case threeOmega
    case xyRotation
    case iv
    case rsm
    case rt
    case afm
}

extension WorkbenchWorkflowKind {
    /// Selection cardinality policy for this workflow — see `WorkbenchSelectionMode`.
    /// RSM and AFM are semantically single-file (each analyzes exactly one selected hit);
    /// every other workflow keeps its current unbounded multi-select basket.
    var selectionMode: WorkbenchSelectionMode {
        switch self {
        case .rsm, .afm:
            return .single
        case .ahe, .threeOmega, .xyRotation, .iv, .rt:
            return .multiple
        }
    }
}
