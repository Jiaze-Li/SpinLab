import SwiftUI

/// Left-aligned cell for use in `WorkbenchPluginControlsGrid`.
///
/// Ensures consistent leading alignment and styling across all workflow module controls.
struct WorkbenchPluginControlCell<Content: View>: View {
    let label: String?
    var labelWidth: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            if let label {
                Text(label)
                    .font(WorkbenchUIStyle.controlLabelFont)
                    .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                    .fixedSize()
                    .frame(width: labelWidth, alignment: .leading)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Reusable two-column grid layout for workflow-specific module controls.
///
/// Maintains leading alignment and consistent spacing across rows and columns.
struct WorkbenchPluginControlsGrid<Content: View>: View {
    var horizontalSpacing: CGFloat = AppSpacing.lg
    var verticalSpacing: CGFloat = AppSpacing.md
    @ViewBuilder let content: () -> Content

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: horizontalSpacing, alignment: .leading),
            GridItem(.flexible(), spacing: horizontalSpacing, alignment: .leading)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
