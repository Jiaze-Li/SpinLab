import SwiftUI

/// Shown when a Rule Book workflow has no workspace implementation yet.
struct NotImplementedWorkflowView: View {
    let label: String

    init(workflowKey: WorkflowKey) {
        self.label = workflowKey.rawValue
    }

    init(workflowID: String) {
        self.label = workflowID
    }

    var body: some View {
        ContentUnavailableView(
            "\(label) — Not Implemented",
            systemImage: "clock.badge.questionmark",
            description: Text("The \(label) workflow is recognized but has no workspace implementation yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
