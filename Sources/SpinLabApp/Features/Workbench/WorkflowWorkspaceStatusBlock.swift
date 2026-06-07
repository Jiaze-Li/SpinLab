import SwiftUI

struct WorkflowWorkspaceStatusBlock: View {
    let trace: WorkbenchRunTraceProjection?
    let warningEntries: [WorkbenchWarningEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            WorkbenchTracePanel(trace: trace)
            WorkbenchWarningPanel(entries: warningEntries)
        }
    }
}
