import SwiftUI

struct MeasurementTagRulesSection: View {
    let store: RulesManagementStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(RulesPanelSection.measurementTag.displayName)
                .font(AppFontScale.sectionHeader)

            if let summary = store.measurementTagSummary {
                LabeledContent("Version") {
                    Text("\(summary.version)")
                }
                LabeledContent("Rule Count") {
                    Text("\(summary.ruleCount)")
                }
                if summary.previewValues.isEmpty {
                    Text("No preview values.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Preview")
                            .font(AppFontScale.groupHeader)
                        ForEach(summary.previewValues, id: \.self) { value in
                            Text("• \(value)")
                        }
                    }
                }
            } else {
                Text("No measurement tag summary available.")
                    .foregroundStyle(.secondary)
            }

            if let note = RulesPanelSection.measurementTag.sessionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}
