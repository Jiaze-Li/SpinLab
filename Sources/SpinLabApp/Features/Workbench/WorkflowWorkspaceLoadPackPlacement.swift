import SwiftUI

struct WorkflowWorkspaceLoadPackPlacement<Store: WorkbenchWorkspaceProviding>: View {
    let workflowID: WorkbenchWorkflowID
    let store: Store

    var body: some View {
        WorkbenchLoadPackPopover(workflowID: workflowID.rawValue, store: store)
    }
}
