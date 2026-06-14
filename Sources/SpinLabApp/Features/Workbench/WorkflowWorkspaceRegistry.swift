import SwiftUI

/// Central dispatch table: `workflowID` → workspace view.
///
/// ## Adding a new workflow
/// This is one of five registration surfaces that must all be updated.
/// See `docs/architecture/workbench/ADDING_WORKFLOW.md` for the full checklist.
enum WorkflowWorkspaceRegistry {

    @ViewBuilder
    static func workspace(for workflowID: String) -> some View {
        switch workflowID.lowercased() {
        case "ahe":
            AHEWorkspaceView()
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
