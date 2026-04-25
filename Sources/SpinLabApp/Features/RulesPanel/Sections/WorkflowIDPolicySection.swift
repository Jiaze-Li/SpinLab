import SwiftUI

struct WorkflowIDPolicySection: View {
    let store: RulesManagementStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(RulesPanelSection.workflowIDPolicy.displayName)
                .font(AppFontScale.sectionHeader)

            if let summary = store.workflowIDPolicySummary {
                LabeledContent("Version") {
                    Text("\(summary.version)")
                }
                LabeledContent("Preferred Alphabet") {
                    Text(summary.preferredAlphabet ?? "-")
                }
                LabeledContent("Fallback Prefix") {
                    Text(summary.fallbackPrefix ?? "-")
                }
            } else {
                Text("No workflow ID policy summary available.")
                    .foregroundStyle(.secondary)
            }

            if let note = RulesPanelSection.workflowIDPolicy.sessionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}
