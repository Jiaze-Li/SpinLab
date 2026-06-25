import SwiftUI

struct WorkbenchMeasurementsSampleRow: View {
    let summary: SampleWorkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .center, spacing: AppSpacing.xs) {
                Text(summary.displayTitle)
                    .font(WorkbenchUIStyle.controlLabelFont)
                    .foregroundStyle(WorkbenchUIStyle.primaryTextColor)

                if !summary.unknownWorkflowIDs.isEmpty {
                    Label(
                        "Unknown: \(summary.unknownWorkflowIDs.joined(separator: ", "))",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(WorkbenchUIStyle.minimumReadableFont)
                    .foregroundStyle(WorkbenchUIStyle.warningColor)
                }

                Spacer()
            }

            if !summary.workflowRows.isEmpty {
                HStack(alignment: .top, spacing: AppSpacing.lg) {
                    ForEach(summary.workflowRows) { row in
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(row.workflowDisplayName)
                                .font(WorkbenchUIStyle.minimumReadableFont)
                                .foregroundStyle(WorkbenchUIStyle.secondaryTextColor)
                            WorkbenchMeasurementsWorkflowCell(summary: row)
                        }
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
