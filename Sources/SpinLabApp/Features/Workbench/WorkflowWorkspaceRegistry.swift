import SwiftUI

/// Central dispatch table: `workflowID` → workspace view.
///
/// ## Adding a new workflow
/// 1. Create `<Name>WorkspaceView` conforming to `WorkflowWorkspaceProvider`.
/// 2. Add a `case "<id>":` branch below.
/// No other file needs to change.
enum WorkflowWorkspaceRegistry {

    @ViewBuilder
    static func workspace(for workflowID: String) -> some View {
        switch workflowID {
        case "ahe":
            AHEWorkspaceView()
        // case "RT":
        //     RTWorkspaceView()
        case "3w":
            ThreeOmegaWorkspaceView()
        case "xy":
            XYRotationWorkspaceView()
        default:
            UnsupportedWorkspaceView(workflowID: workflowID)
        }
    }
}

// MARK: - Fallback

private struct UnsupportedWorkspaceView: View {
    let workflowID: String

    var body: some View {
        ContentUnavailableView(
            "Unsupported Workflow",
            systemImage: "questionmark.circle",
            description: Text("No workspace registered for workflow ID \"\(workflowID)\".")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
