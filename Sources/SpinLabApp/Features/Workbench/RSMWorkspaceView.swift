import SwiftUI

/// RSM workflow workspace — left column (search/action bar/controls/results).
struct RSMWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.rsmWorkspace
        @Bindable var workbench = appState.workbench

        WorkflowWorkspaceLeftColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            controls: store.controlsDescriptor(
                appState: appState,
                globalPlotDefaults: $workbench.globalPlotDefaults
            ),
            searchExtra: { EmptyView() },
            leftExtra: { EmptyView() },
            actionBarTrailing: { EmptyView() }
        )
    }
}
