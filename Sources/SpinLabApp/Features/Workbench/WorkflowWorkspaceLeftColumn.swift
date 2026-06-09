import SwiftUI

struct WorkflowWorkspaceLeftColumn<
    Store: WorkbenchWorkspaceProviding,
    SearchExtra: View,
    PlotControls: View,
    LeftExtra: View
>: View {

    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    let searchExtra: SearchExtra
    let plotControls: PlotControls
    let leftExtra: LeftExtra

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                titleBar
                WorkflowWorkspaceSearchSection(
                    workflowID: workflowID,
                    store: store,
                    workbench: workbench,
                    searchExtra: searchExtra
                )
                plotControls
                leftExtra
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                WorkflowWorkspaceResultsList(
                    workflowID: workflowID,
                    store: store,
                    workbench: workbench
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if workbench.selectedCount(for: workflowID) > 0 {
                    Divider()
                    SelectedHitsTray(workflowID: workflowID, workbench: workbench)
                        .frame(minWidth: 250, maxWidth: 250, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(workbench.selectedWorkflowDefinition?.displayName ?? "Workflow")
                .font(AppFontScale.sectionTitle)
            Spacer()
        }
        .padding(.top, AppSpacing.xs)
    }
}
