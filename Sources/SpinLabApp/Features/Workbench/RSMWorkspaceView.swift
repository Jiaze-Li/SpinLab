import SwiftUI

/// RSM workflow workspace — shell-based layout.
struct RSMWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.rsmWorkspace
        @Bindable var bindableStore = appState.workbench.rsmWorkspace

        WorkflowWorkspaceShell(
            workflowID: .rsm,
            store: store,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                HStack(spacing: 8) {
                    Text("View")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $bindableStore.activeView) {
                        ForEach(RSMView.allCases, id: \.self) { view in
                            Text(view.rawValue.uppercased()).tag(view)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    .onChange(of: store.activeView) { _, _ in
                        store.rerenderForStyleChange()
                    }
                }
            },
            leftExtra: { EmptyView() },
            rightExtra: { EmptyView() }
        )
    }
}
