import SwiftUI
struct NewThingWorkspaceView: View {
    var body: some View {
        WorkflowWorkspaceLeftColumn(
            workflowID: "x", store: store, workbench: wb,
            controls: WorkbenchControlsDescriptor(common: c, plot: .heatmap(h), specific: .empty),
            searchExtra: { EmptyView() }, leftExtra: { EmptyView() }, actionBarTrailing: { EmptyView() })
    }
}
