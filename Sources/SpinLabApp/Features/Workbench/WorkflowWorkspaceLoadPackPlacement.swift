import SwiftUI

struct WorkflowWorkspaceLoadPackPlacement<Store: WorkbenchWorkspaceProviding>: View {
    let workflowID: String
    let store: Store

    var body: some View {
        WorkbenchLoadPackPopover(workflowID: workflowID, store: store)
    }
}
