import SwiftUI

/// Central dispatch table: Rule Book workflow id → workspace view.
///
/// Every WorkflowKey case must appear in the switch below.
/// Implemented workflows dispatch to their workspace view.
/// Unimplemented workflows (MR, RT standalone) dispatch to NotImplementedWorkflowView.
///
/// ## Adding a new workflow
/// This is one of the registration surfaces that must all be updated.
/// See `docs/architecture/workbench/ADDING_WORKFLOW.md` for the full checklist.
enum WorkflowWorkspaceRegistry {

    @ViewBuilder
    static func workspace(for workflowID: String) -> some View {
        // WorkflowKey used here only for workspace UI dispatch (view routing), not for matching or persistence.
        if let key = WorkflowKey(rawValue: workflowID) {
            switch key {
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
            case .mr:
                NotImplementedWorkflowView(workflowKey: .mr)
            }
        } else {
            NotImplementedWorkflowView(workflowID: workflowID)
        }
    }
}
