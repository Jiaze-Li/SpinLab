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
    /// Fixed ideal width so the row's measured size never depends on the typed text.
    var fieldIdealWidth: CGFloat? = nil
    var fieldMaxWidth: CGFloat? = nil
    var onTextChange: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(WorkbenchUIStyle.controlLabelFont)
                    .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                    .fixedSize()
            }
            TextField(placeholder, text: textBinding)
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .foregroundStyle(Color.primary)
                .frame(minWidth: fieldMinWidth, idealWidth: fieldIdealWidth, maxWidth: fieldMaxWidth)
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
