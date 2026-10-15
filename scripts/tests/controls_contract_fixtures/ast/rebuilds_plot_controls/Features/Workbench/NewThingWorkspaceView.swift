import SwiftUI
struct NewThingWorkspaceView: View {
    var body: some View {
        WorkflowWorkspaceLeftColumn(workflowID: "x", store: store, workbench: wb,
            searchExtra: { EmptyView() }, leftExtra: { EmptyView() }, actionBarTrailing: { EmptyView() }) {
            HeatmapPlotControls(model: m)
        }
    }
}
