import SwiftUI

/// RT workflow workspace — left column (search/action bar/controls/results).
/// RT has no Specific controls, so the Surface renders only Common and Plot.
struct RTWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.rtWorkspace
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
        .onChange(of: store.tabs.activeTab) { _, _ in
            // Active tab is per-session render state, not a snapshot field — no flush.
            store.rerenderForStyleChange()
        }
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=RT")
        }
    }
}

extension RTWorkspaceStore {
    /// RT has no Specific controls, so the Surface renders only Common and Plot.
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        standardControlsDescriptor(
            appState: appState,
            globalPlotDefaults: globalPlotDefaults,
            flushSource: "rtStyleChange",
            canReorderSeries: canReorderSeries,
            currentSeriesOrder: activeSeriesOrder,
            rendererTitleTokens: ["tab", "device"]
        )
    }
}
