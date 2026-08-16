import SwiftUI

/// Central dispatch table: Rule Book workflow id → workspace left/right column content.
///
/// Dispatch classifies the route workflowID exactly once, via
/// `WorkbenchFeatureStore.workflowKind(for:)` — see `WorkbenchWorkflowKind` for the
/// canonical identity this switches on. Everything below `workflowKind(for:)` is type-specific
/// rendering (which concrete View/store for a given kind), not identity classification.
///
/// Split into `leftContent`/`rightContent` (rather than one `workspace(for:)` returning
/// a full two-column view) so `WorkbenchPrimaryView`/`WorkbenchDetailView` can feed the
/// single, stable app-wide `AppWorkspaceShell` across workflow switches and only swap the
/// pane *content* — see `docs/architecture/workbench/WORKBENCH_LAYOUT_OWNERSHIP_AUDIT.md`
/// for why a fresh split-owning shell per workflow corrupted the persisted split width.
///
/// ## Adding a new workflow
/// Add a case to `WorkbenchWorkflowKind` and handle it in `WorkbenchFeatureStore.workflowKind(for:)`
/// — the compiler will then point at every exhaustive switch below that needs a new case.
/// See `docs/architecture/workbench/ADDING_WORKFLOW.md` for the full checklist.
@MainActor
enum WorkflowWorkspaceRegistry {

    @ViewBuilder
    static func leftContent(for workflowID: String, featureStore: WorkbenchFeatureStore) -> some View {
        switch featureStore.workflowKind(for: workflowID) {
        case .ahe:
            AHEWorkspaceView()
        case .threeOmega:
            ThreeOmegaWorkspaceView()
        case .xyRotation:
            XYRotationWorkspaceView()
        case .iv:
            IVWorkspaceView()
        case .rsm:
            RSMWorkspaceView()
        case .rt:
            RTWorkspaceView()
        case nil:
            NotImplementedWorkflowView(workflowID: workflowID)
        }
    }

    @ViewBuilder
    static func rightContent(for workflowID: String, featureStore: WorkbenchFeatureStore) -> some View {
        switch featureStore.workflowKind(for: workflowID) {
        case .ahe:
            WorkflowWorkspaceRightColumn(
                workflowID: featureStore.aheWorkspace.workflowID,
                store: featureStore.aheWorkspace,
                workbench: featureStore,
                rightExtra: { EmptyView() }
            )
        case .threeOmega:
            // Non-trivial rightExtra (conditional scaling panels) — kept as a
            // dedicated wrapper. See `ThreeOmegaWorkspaceRightView`.
            ThreeOmegaWorkspaceRightView()
        case .xyRotation:
            WorkflowWorkspaceRightColumn(
                workflowID: featureStore.xyRotationWorkspace.workflowID,
                store: featureStore.xyRotationWorkspace,
                workbench: featureStore,
                rightExtra: { EmptyView() }
            )
        case .iv:
            WorkflowWorkspaceRightColumn(
                workflowID: featureStore.ivWorkspace.workflowID,
                store: featureStore.ivWorkspace,
                workbench: featureStore,
                rightExtra: { EmptyView() }
            )
        case .rsm:
            WorkflowWorkspaceRightColumn(
                workflowID: featureStore.rsmWorkspace.workflowID,
                store: featureStore.rsmWorkspace,
                workbench: featureStore,
                rightExtra: { EmptyView() }
            )
        case .rt:
            WorkflowWorkspaceRightColumn(
                workflowID: featureStore.rtWorkspace.workflowID,
                store: featureStore.rtWorkspace,
                workbench: featureStore,
                rightExtra: { EmptyView() }
            )
        case nil:
            EmptyView()
        }
    }
}
