import SwiftUI

// MARK: - CompactNumericField

/// Compact numeric input with source-reset and optional clear button.
struct CompactNumericField: View {
    let placeholder: String
    let currentValue: Double?
    let sourceResetToken: String
    var width: CGFloat = 64
    var showsClearButton: Bool = true
    let onCommit: (Double?) -> Void

    @State private var editText: String = ""
    @State private var isDirty: Bool = false
    @FocusState private var focused: Bool

    private var hasOverride: Bool { currentValue != nil }
    private var displayText: String {
        if let currentValue { return formatBound(currentValue) }
        return placeholder
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: dirtyBinding)
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .foregroundStyle(hasOverride ? Color.primary : Color.secondary)
                .frame(width: width)
                .focused($focused)
                .onSubmit { commitIfDirty() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commitIfDirty() }
                }
            if showsClearButton && hasOverride {
                Button {
                    onCommit(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }
        }
        .task(id: displayText) {
            guard !focused else { return }
            editText = displayText
            isDirty = false
        }
        .task(id: sourceResetToken) {
            editText = displayText
            isDirty = false
            focused = false
        }
    }

    private var dirtyBinding: Binding<String> {
        Binding(
            get: { editText },
            set: { newValue in
                editText = newValue
                isDirty = true
            }
        )
    }

    private func commitIfDirty() {
        guard isDirty else { return }
        isDirty = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onCommit(nil)
            return
        }
        guard let parsed = Double(trimmed) else { return }
        if parsed == currentValue { return }
        onCommit(parsed)
    }

    private func formatBound(_ value: Double) -> String {
        if value == 0 { return "0" }
        let absValue = Swift.abs(value)
        if absValue >= 0.001 && absValue < 100_000 { return String(format: "%g", value) }
        return String(format: "%.3e", value)
    }
}
