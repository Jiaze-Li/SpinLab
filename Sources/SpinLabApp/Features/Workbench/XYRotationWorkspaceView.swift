import SwiftUI

/// XY Rotation workflow workspace.
///
/// Left column: search + controls + results list.
/// Right column: plot canvas + status.
struct XYRotationWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell {
            VStack(alignment: .leading, spacing: 12) {
                Text("XY Rotation")
                    .font(.headline)
                    .padding(.horizontal)
                ContentUnavailableView(
                    "Workspace under construction",
                    systemImage: "rotate.3d",
                    description: Text("XY Rotation analysis will be available in a future update.")
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } rightColumn: {
            ContentUnavailableView(
                "No plot yet",
                systemImage: "chart.xyaxis.line",
                description: Text("Select measurements and run analysis to generate plots.")
            )
        }
    }
}
