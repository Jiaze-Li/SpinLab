import SwiftUI

// MARK: - WorkbenchAxisRangeControls

/// Shell-level X/Y axis range override controls shared by all Cartesian XY workflows.
///
/// Shows the current resolved auto range (from the last rendered layout) when no manual
/// override is active. Editing a field creates a per-tab manual override; clearing returns
/// that bound to auto. Invalid numbers or min ≥ max are silently discarded on commit.
struct WorkbenchAxisRangeControls: View {
    /// Layout from the most recent render — provides the displayed auto range.
    var activeLayout: WorkbenchPlotLayout?
    /// Current per-tab axis range override (nil = all bounds are auto). Used for display only.
    var axisRangeOverride: AxisRangeOverride?
    /// Token that changes when the analyzed source changes; forces field state to reset.
    var sourceResetToken: String
    /// Called with the bound that changed and its new value (nil = clear to auto).
    /// Validation and state merging are handled by the receiver (TabRenderManager.updateAxisBound).
    var onBoundUpdate: (AxisRangeBound, Double?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("X")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            AxisBoundField(
                placeholder: formatAuto(activeLayout?.axisXMin),
                currentValue: axisRangeOverride?.xMin,
                sourceResetToken: sourceResetToken,
                onCommit: { onBoundUpdate(.xMin, $0) }
            )
            Text("–")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            AxisBoundField(
                placeholder: formatAuto(activeLayout?.axisXMax),
                currentValue: axisRangeOverride?.xMax,
                sourceResetToken: sourceResetToken,
                onCommit: { onBoundUpdate(.xMax, $0) }
            )

            Spacer(minLength: 8).frame(maxWidth: 12)

            Text("Y")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            AxisBoundField(
                placeholder: formatAuto(activeLayout?.axisYMin),
                currentValue: axisRangeOverride?.yMin,
                sourceResetToken: sourceResetToken,
                onCommit: { onBoundUpdate(.yMin, $0) }
            )
            Text("–")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            AxisBoundField(
                placeholder: formatAuto(activeLayout?.axisYMax),
                currentValue: axisRangeOverride?.yMax,
                sourceResetToken: sourceResetToken,
                onCommit: { onBoundUpdate(.yMax, $0) }
            )
        }
    }

    private func formatAuto(_ v: Double?) -> String {
        guard let v else { return "" }
        if v == 0 { return "0" }
        let abs = Swift.abs(v)
        if abs >= 0.001 && abs < 100_000 {
            let s = String(format: "%g", v)
            return s
        }
        return String(format: "%.3e", v)
    }
}

// MARK: - AxisBoundField

/// Single numeric text field for an axis range bound.
///
/// Shows the auto range value (dimmed) when no override is set.
/// Clearing the field removes the override for that bound.
private struct AxisBoundField: View {
    let placeholder: String
    let currentValue: Double?
    let sourceResetToken: String
    let onCommit: (Double?) -> Void

    @State private var editText: String = ""
    @State private var isDirty: Bool = false
    @FocusState private var focused: Bool

    private var hasOverride: Bool { currentValue != nil }
    private var displayText: String {
        if let v = currentValue { return formatBound(v) }
        return placeholder
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: dirtyBinding)
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .foregroundStyle(hasOverride ? Color.primary : Color.secondary)
                .frame(width: 60)
                .focused($focused)
                .onSubmit { commitIfDirty() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commitIfDirty() }
                }
            if hasOverride {
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
            set: { editText = $0; isDirty = true }
        )
    }

    private func commitIfDirty() {
        guard isDirty else { return }
        isDirty = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == placeholder {
            onCommit(nil)
        } else if let v = Double(trimmed) {
            onCommit(v)
        }
        // invalid input: leave current state unchanged
    }

    private func formatBound(_ v: Double) -> String {
        if v == 0 { return "0" }
        let abs = Swift.abs(v)
        if abs >= 0.001 && abs < 100_000 { return String(format: "%g", v) }
        return String(format: "%.3e", v)
    }
}
