import SwiftUI

// MARK: - ControlRow

/// Shared inline row chrome for plot controls.
struct ControlRow<Content: View>: View {
    let label: String?
    var labelWidth: CGFloat? = nil
    var spacing: CGFloat = 8
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: alignment, spacing: spacing) {
            if let label {
                Text(label)
                    .font(WorkbenchUIStyle.controlLabelFont)
                    .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                    .fixedSize()
                    .frame(width: labelWidth, alignment: .trailing)
            }
            content()
        }
    }
}
