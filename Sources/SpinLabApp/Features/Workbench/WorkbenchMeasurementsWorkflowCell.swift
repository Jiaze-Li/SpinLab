import SwiftUI

struct WorkbenchMeasurementsWorkflowCell: View {
    let summary: WorkflowWorkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(summary.status.badgeLabel)
                .font(WorkbenchUIStyle.minimumReadableFont.weight(.medium))
                .foregroundStyle(summary.status.badgeForeground)
                .padding(.horizontal, WorkbenchUIStyle.chipHorizontalPadding)
                .padding(.vertical, WorkbenchUIStyle.chipVerticalPadding)
                .background(summary.status.badgeForeground.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: WorkbenchUIStyle.chipCornerRadius))

            if summary.fileCount > 0 {
                Text(summary.countLabel)
                    .font(WorkbenchUIStyle.minimumReadableFont)
                    .foregroundStyle(WorkbenchUIStyle.secondaryTextColor)
            }
        }
        .frame(minWidth: 68, alignment: .leading)
    }
}

private extension SampleWorkStatus {
    var badgeLabel: String {
        switch self {
        case .noData:   return "no data"
        case .todo:     return "todo"
        case .partial:  return "partial"
        case .hasChart: return "done"
        }
    }

    var badgeForeground: Color {
        switch self {
        case .noData:   return .secondary
        case .todo:     return .orange
        case .partial:  return .blue
        case .hasChart: return .green
        }
    }
}

private extension WorkflowWorkSummary {
    var countLabel: String {
        if chartLinkedFileCount > 0 {
            return "\(chartLinkedFileCount)/\(fileCount) linked"
        }
        return "\(fileCount) file\(fileCount == 1 ? "" : "s")"
    }
}
