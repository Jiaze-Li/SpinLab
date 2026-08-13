import SwiftUI

struct WorkflowWorkspaceLeftColumn<
    Store: WorkbenchWorkspaceProviding,
    SearchExtra: View,
    PlotControls: View,
    LeftExtra: View,
    ActionBarTrailing: View
>: View {

    let workflowID: String
    let store: Store
    let workbench: WorkbenchFeatureStore

    @ViewBuilder let searchExtra: SearchExtra
    @ViewBuilder let plotControls: PlotControls
    @ViewBuilder let leftExtra: LeftExtra
    @ViewBuilder let actionBarTrailing: ActionBarTrailing

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                titleBar
                WorkflowWorkspaceSearchSection(
                    workflowID: workflowID,
                    store: store,
                    workbench: workbench,
                    searchExtra: searchExtra,
                    actionBarTrailing: actionBarTrailing
                )
                plotControls
                leftExtra
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)

            Divider()

            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    WorkflowWorkspaceResultsList(
                        workflowID: workflowID,
                        store: store,
                        workbench: workbench
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if workbench.basketSelectedCount(for: workflowID) > 0 {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(width: SelectedHitsLayout.separatorWidth)

                        SelectedHitsTray(workflowID: workflowID, workbench: workbench)
                            .frame(width: SelectedHitsLayout.width(primaryWidth: proxy.size.width))
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

extension WorkflowWorkspaceLeftColumn where ActionBarTrailing == EmptyView {
    init(
        workflowID: String,
        store: Store,
        workbench: WorkbenchFeatureStore,
        @ViewBuilder searchExtra: () -> SearchExtra,
        @ViewBuilder plotControls: () -> PlotControls,
        @ViewBuilder leftExtra: () -> LeftExtra
    ) {
        self.workflowID = workflowID
        self.store = store
        self.workbench = workbench
        self.searchExtra = searchExtra()
        self.plotControls = plotControls()
        self.leftExtra = leftExtra()
        self.actionBarTrailing = EmptyView()
    }
}
