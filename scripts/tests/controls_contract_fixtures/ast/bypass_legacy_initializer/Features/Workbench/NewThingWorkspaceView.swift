import SwiftUI
struct NewThingWorkspaceView: View {
    var body: some View {
        WorkflowWorkspaceLeftColumn(
            workflowID: "x", store: store, workbench: wb,
            searchExtra: { EmptyView() },
            legacyPlotControls: { Text("mine") },
            leftExtra: { EmptyView() })
    }
}
