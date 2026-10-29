import SwiftUI
import AppKit

/// AHE workflow workspace — left column (search/action bar/controls/results).
struct AHEWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace
        @Bindable var workbench = appState.workbench

        WorkflowWorkspaceLeftColumn(
            workflowID: ahe.workflowID,
            store: ahe,
            workbench: appState.workbench,
            controls: ahe.controlsDescriptor(
                appState: appState,
                globalPlotDefaults: $workbench.globalPlotDefaults
            ),
            searchExtra: { EmptyView() },
            leftExtra: { EmptyView() },
            actionBarTrailing: { EmptyView() }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=AHE")
        }
    }
}
