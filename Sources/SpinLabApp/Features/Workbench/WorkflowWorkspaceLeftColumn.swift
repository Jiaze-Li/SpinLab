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

    let searchExtra: SearchExtra
    let plotControls: PlotControls
    let leftExtra: LeftExtra
    let actionBarTrailing: ActionBarTrailing

    /// LEGACY migration path (bounded by `scripts/controls_contract_legacy_allowlist.txt`).
    /// New workflows must use the `controls:` initializer.
    init(
        workflowID: String,
        store: Store,
        workbench: WorkbenchFeatureStore,
        @ViewBuilder searchExtra: () -> SearchExtra,
        @ViewBuilder legacyPlotControls: () -> PlotControls,
        @ViewBuilder leftExtra: () -> LeftExtra,
        @ViewBuilder actionBarTrailing: () -> ActionBarTrailing
    ) {
        self.workflowID = workflowID
        self.store = store
        self.workbench = workbench
        self.searchExtra = searchExtra()
        self.plotControls = legacyPlotControls()
        self.leftExtra = leftExtra()
        self.actionBarTrailing = actionBarTrailing()
    }

    fileprivate init(
        workflowID: String,
        store: Store,
        workbench: WorkbenchFeatureStore,
        searchExtra: SearchExtra,
        surface: PlotControls,
        leftExtra: LeftExtra,
        actionBarTrailing: ActionBarTrailing
    ) {
        self.workflowID = workflowID
        self.store = store
        self.workbench = workbench
        self.searchExtra = searchExtra
        self.plotControls = surface
        self.leftExtra = leftExtra
        self.actionBarTrailing = actionBarTrailing
    }

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

                    // Single-selection workflows (AFM, RSM) hold at most one file, which the results list
                    // already shows; the Selected tray is only useful when several can accumulate.
                    if workbench.selectionMode(for: workflowID) == .multiple,
                       workbench.basketSelectedCount(for: workflowID) > 0 {
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
    /// LEGACY migration path (see above).
    init(
        workflowID: String,
        store: Store,
        workbench: WorkbenchFeatureStore,
        @ViewBuilder searchExtra: () -> SearchExtra,
        @ViewBuilder legacyPlotControls: () -> PlotControls,
        @ViewBuilder leftExtra: () -> LeftExtra
    ) {
        self.init(
            workflowID: workflowID, store: store, workbench: workbench,
            searchExtra: searchExtra, legacyPlotControls: legacyPlotControls,
            leftExtra: leftExtra, actionBarTrailing: { EmptyView() })
    }
}

/// Shared-Surface mounting: the workflow supplies a descriptor; Common and Plot are assembled
/// by `WorkbenchControlsSurface`.
extension WorkflowWorkspaceLeftColumn where PlotControls == WorkbenchControlsSurface {
    init(
        workflowID: String,
        store: Store,
        workbench: WorkbenchFeatureStore,
        controls: WorkbenchControlsDescriptor,
        @ViewBuilder searchExtra: () -> SearchExtra,
        @ViewBuilder leftExtra: () -> LeftExtra,
        @ViewBuilder actionBarTrailing: () -> ActionBarTrailing
    ) {
        self.init(
            workflowID: workflowID, store: store, workbench: workbench,
            searchExtra: searchExtra(), surface: WorkbenchControlsSurface(descriptor: controls),
            leftExtra: leftExtra(), actionBarTrailing: actionBarTrailing())
    }
}
