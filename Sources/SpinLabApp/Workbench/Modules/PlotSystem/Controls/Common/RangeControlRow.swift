import SwiftUI

// MARK: - RangeControlRow

/// Shared compact min/max numeric row with optional reset action.
struct RangeControlRow: View {
    let label: String
    var labelWidth: CGFloat = 52
    let minPlaceholder: String
    let maxPlaceholder: String
    let minValue: Double?
    let maxValue: Double?
    let sourceResetToken: String
    var fieldWidth: CGFloat = 64
    var onReset: (() -> Void)? = nil
    let onMinCommit: (Double?) -> Void
    let onMaxCommit: (Double?) -> Void

    var body: some View {
        ControlRow(label: label, labelWidth: labelWidth, spacing: 6) {
            CompactNumericField(
                placeholder: minPlaceholder,
                currentValue: minValue,
                sourceResetToken: sourceResetToken,
                width: fieldWidth,
                onCommit: onMinCommit
            )
            Text("–")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            CompactNumericField(
                placeholder: maxPlaceholder,
                currentValue: maxValue,
                sourceResetToken: sourceResetToken,
                width: fieldWidth,
                onCommit: onMaxCommit
            )
            if let onReset {
                Button("Reset") {
                    onReset()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }
}
