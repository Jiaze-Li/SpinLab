import SwiftUI

// MARK: - SharedPlotTextFieldRow

/// Shared label + rounded text-field row used by plot-control primitives.
///
/// This component only owns the common row chrome. Callers keep their own
/// bindings, commit semantics, validation, and surrounding layout.
struct SharedPlotTextFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var fieldMinWidth: CGFloat? = 40
    var fieldMaxWidth: CGFloat? = nil
    var onTextChange: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            TextField(placeholder, text: textBinding)
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .foregroundStyle(Color.primary)
                .frame(minWidth: fieldMinWidth, maxWidth: fieldMaxWidth)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = newValue
                onTextChange?()
            }
        )
    }
}
