import SwiftUI

// MARK: - LabelOverrideField

/// Compact text field for title/axis label overrides.
///
/// Displays the rendered default (from layout) when no override is set; switches to
/// primary styling when an override is active. Commits only when the user has actually
/// edited the field (isDirty gate prevents spurious focus-loss commits). A clear button
/// removes the override when one is active.
struct LabelOverrideField: View {
    let label: String
    /// Text currently rendered on the chart — shown (dimmed) when no override is set.
    let renderedDefault: String
    /// Active override value (empty = no override).
    let currentValue: String
    /// Token that changes when the analyzed source backing the field changes.
    /// This forces stale edit state to reset before any focus-loss commit can fire.
    let sourceResetToken: String
    let onCommit: (String) -> Void
    /// Maximum width for the text input field. Plot title uses a wider value than X/Y axis fields.
    var fieldMaxWidth: CGFloat = 120

    @State private var editText: String = ""
    @State private var isDirty: Bool = false
    @FocusState private var focused: Bool

    private var hasOverride: Bool { !currentValue.isEmpty }
    private var displayValue: String { currentValue.isEmpty ? renderedDefault : currentValue }
    private var committedTextBinding: Binding<String> {
        Binding(
            get: { editText },
            set: { newValue in
                editText = newValue
                isDirty = true
            }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            SharedPlotTextFieldRow(
                label: label,
                placeholder: "",
                text: committedTextBinding,
                fieldMinWidth: 40,
                fieldMaxWidth: fieldMaxWidth
            )
            .focused($focused)
            .onSubmit { commitIfDirty() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commitIfDirty() }
            }
            if hasOverride {
                Button {
                    onCommit("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }
        }
        .task(id: displayValue) {
            LabelOverrideFieldSync.applyDisplayValueChange(
                editText: &editText,
                isDirty: &isDirty,
                focused: focused,
                displayValue: displayValue
            )
        }
        .task(id: sourceResetToken) {
            LabelOverrideFieldSync.applySourceReset(
                editText: &editText,
                isDirty: &isDirty,
                focused: &focused,
                displayValue: displayValue
            )
        }
    }

    private func commitIfDirty() {
        LabelOverrideFieldSync.commitIfDirty(
            editText: editText,
            isDirty: &isDirty,
            renderedDefault: renderedDefault,
            onCommit: onCommit
        )
    }
}

enum LabelOverrideFieldSync {
    static func applyDisplayValueChange(
        editText: inout String,
        isDirty: inout Bool,
        focused: Bool,
        displayValue: String
    ) {
        guard !focused else { return }
        editText = displayValue
        isDirty = false
    }

    static func applySourceReset(
        editText: inout String,
        isDirty: inout Bool,
        focused: inout Bool,
        displayValue: String
    ) {
        editText = displayValue
        isDirty = false
        focused = false
    }

    static func commitIfDirty(
        editText: String,
        isDirty: inout Bool,
        renderedDefault: String,
        onCommit: (String) -> Void
    ) {
        guard isDirty else { return }
        isDirty = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = renderedDefault.trimmingCharacters(in: .whitespacesAndNewlines)
        let committed = trimmed.isEmpty ? fallback : trimmed
        onCommit(committed)
    }
}
