import SwiftUI

struct WorkflowWorkspaceRightColumn<Store: WorkbenchWorkspaceProviding, RightExtra: View>: View {
    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    let rightExtra: RightExtra

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                WorkflowWorkspaceResultArea(
                    workflowID: workflowID,
                    store: store,
                    workbench: workbench
                )
                rightExtra
                WorkbenchTracePanel(trace: store.currentRunTrace)
                WorkbenchWarningPanel(entries: store.warningLog.entries)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xs)
        }
    }
}
