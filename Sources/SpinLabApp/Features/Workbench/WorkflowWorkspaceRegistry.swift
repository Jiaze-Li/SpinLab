import SwiftUI

/// Central dispatch table: Rule Book workflow id → workspace view.
///
/// Dispatch compares the route workflowID against each workspace store's workflowID.
/// Route matching is purely by string identity.
///
/// ## Adding a new workflow
/// This is one of the registration surfaces that must all be updated.
/// See `docs/architecture/workbench/ADDING_WORKFLOW.md` for the full checklist.
enum WorkflowWorkspaceRegistry {

    @ViewBuilder
    static func workspace(for workflowID: String, featureStore: WorkbenchFeatureStore) -> some View {
        if workflowID == featureStore.aheWorkspace.workflowID {
            AHEWorkspaceView()
        } else if workflowID == featureStore.threeOmegaWorkspace.workflowID {
            ThreeOmegaWorkspaceView()
        } else if workflowID == featureStore.xyRotationWorkspace.workflowID {
            XYRotationWorkspaceView()
        } else if workflowID == featureStore.ivWorkspace.workflowID {
            IVWorkspaceView()
        } else if workflowID == featureStore.rsmWorkspace.workflowID {
            RSMWorkspaceView()
        } else if workflowID == featureStore.rtWorkspace.workflowID {
            RTWorkspaceView()
        } else {
            NotImplementedWorkflowView(workflowID: workflowID)
        }
    }
}
