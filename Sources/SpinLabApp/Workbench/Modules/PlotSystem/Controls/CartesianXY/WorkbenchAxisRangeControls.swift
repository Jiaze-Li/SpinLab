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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                rangeLabel
                axisRangeRow(
                    axisLabel: "X",
                    minDebugName: "xMin",
                    maxDebugName: "xMax",
                    minPlaceholder: formatAxisRangeValue(activeLayout?.axisXMin),
                    maxPlaceholder: formatAxisRangeValue(activeLayout?.axisXMax),
                    minValue: axisRangeOverride?.xMin,
                    maxValue: axisRangeOverride?.xMax,
                    minBound: .xMin,
                    maxBound: .xMax
                )
                axisRangeRow(
                    axisLabel: "Y",
                    minDebugName: "yMin",
                    maxDebugName: "yMax",
                    minPlaceholder: formatAxisRangeValue(activeLayout?.axisYMin),
                    maxPlaceholder: formatAxisRangeValue(activeLayout?.axisYMax),
                    minValue: axisRangeOverride?.yMin,
                    maxValue: axisRangeOverride?.yMax,
                    minBound: .yMin,
                    maxBound: .yMax
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    rangeLabel
                    axisRangeRow(
                        axisLabel: "X",
                        minDebugName: "xMin",
                        maxDebugName: "xMax",
                        minPlaceholder: formatAxisRangeValue(activeLayout?.axisXMin),
                        maxPlaceholder: formatAxisRangeValue(activeLayout?.axisXMax),
                        minValue: axisRangeOverride?.xMin,
                        maxValue: axisRangeOverride?.xMax,
                        minBound: .xMin,
                        maxBound: .xMax
                    )
                }
                axisRangeRow(
                    axisLabel: "Y",
                    minDebugName: "yMin",
                    maxDebugName: "yMax",
                    minPlaceholder: formatAxisRangeValue(activeLayout?.axisYMin),
                    maxPlaceholder: formatAxisRangeValue(activeLayout?.axisYMax),
                    minValue: axisRangeOverride?.yMin,
                    maxValue: axisRangeOverride?.yMax,
                    minBound: .yMin,
                    maxBound: .yMax
                )
            }
        }
    }

    private var rangeLabel: some View {
        Text("Range")
            .font(WorkbenchUIStyle.controlLabelFont)
            .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            .fixedSize()
    }

    /// Builds one "X [min] – [max]" row via the shared `AxisRangeFieldRow` atom, wiring in
    /// debug logging. Kept as a thin wrapper so `CompactPlotStyleRow` can build the same rows
    /// directly (see `AxisRangeFieldRow`) without composing this view's own `ViewThatFits`.
    private func axisRangeRow(
        axisLabel: String,
        minDebugName: String,
        maxDebugName: String,
        minPlaceholder: String,
        maxPlaceholder: String,
        minValue: Double?,
        maxValue: Double?,
        minBound: AxisRangeBound,
        maxBound: AxisRangeBound
    ) -> AxisRangeFieldRow {
        AxisRangeFieldRow(
            axisLabel: axisLabel,
            minDebugName: minDebugName,
            maxDebugName: maxDebugName,
            minPlaceholder: minPlaceholder,
            maxPlaceholder: maxPlaceholder,
            minValue: minValue,
            maxValue: maxValue,
            sourceResetToken: sourceResetToken,
            onCommitMin: { v in
                AxisRangeDebug.log("WorkbenchAxisRangeControls onBoundUpdate bound=\(minBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onBoundUpdate(minBound, v)
            },
            onCommitMax: { v in
                AxisRangeDebug.log("WorkbenchAxisRangeControls onBoundUpdate bound=\(maxBound) value=\(axisRangeFmtD(v)) | axisRangeOverride=\(String(describing: axisRangeOverride)) | layout \(axisRangeLayoutDebugStr(activeLayout))")
                onBoundUpdate(maxBound, v)
            }
        )
    }
}

// MARK: - AxisRangeFieldRow

/// One "label [min] – [max]" range row: an axis letter plus two bound fields.
///
/// Shared by `WorkbenchAxisRangeControls` and `CompactPlotStyleRow`'s compact Range+Ticks
/// row, so the latter can lay X/Y range fields directly alongside tick controls without
/// nesting `WorkbenchAxisRangeControls`'s own `ViewThatFits` inside another one.
struct AxisRangeFieldRow: View {
    let axisLabel: String
    let minDebugName: String
    let maxDebugName: String
    let minPlaceholder: String
    let maxPlaceholder: String
    let minValue: Double?
    let maxValue: Double?
    let sourceResetToken: String
    let onCommitMin: (Double?) -> Void
    let onCommitMax: (Double?) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(axisLabel)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            AxisBoundField(
                debugName: minDebugName,
                placeholder: minPlaceholder,
                currentValue: minValue,
                sourceResetToken: sourceResetToken,
                onCommit: onCommitMin
            )
            Text("–")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            AxisBoundField(
                debugName: maxDebugName,
                placeholder: maxPlaceholder,
                currentValue: maxValue,
                sourceResetToken: sourceResetToken,
                onCommit: onCommitMax
            )
        }
    }
}

// MARK: - Shared axis range formatting/debug helpers

func formatAxisRangeValue(_ v: Double?) -> String {
    guard let v else { return "" }
    if v == 0 { return "0" }
    let abs = Swift.abs(v)
    if abs >= 0.001 && abs < 100_000 {
        return String(format: "%g", v)
    }
    return String(format: "%.3e", v)
}

func axisRangeFmtD(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "nil" }

func axisRangeLayoutDebugStr(_ layout: WorkbenchPlotLayout?) -> String {
    guard let layout else { return "xMin=nil xMax=nil yMin=nil yMax=nil" }
    return "xMin=\(String(format: "%g", layout.axisXMin)) xMax=\(String(format: "%g", layout.axisXMax)) yMin=\(String(format: "%g", layout.axisYMin)) yMax=\(String(format: "%g", layout.axisYMax))"
}

// MARK: - AxisBoundField

/// Single numeric text field for an axis range bound.
///
/// Shows the auto range value (dimmed) when no override is set.
/// Clearing the field removes the override for that bound.
private struct AxisBoundField: View {
    let debugName: String
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

    private func debugState(_ context: String) {
        AxisRangeDebug.log("AxisBoundField[\(debugName)] \(context) | editText='\(editText)' trimmed='\(editText.trimmingCharacters(in: .whitespacesAndNewlines))' parsed=\(Double(editText.trimmingCharacters(in: .whitespacesAndNewlines)).map { "\($0)" } ?? "nil") placeholder='\(placeholder)' currentValue=\(currentValue.map { "\($0)" } ?? "nil") hasOverride=\(hasOverride) isDirty=\(isDirty) focused=\(focused) sourceResetToken='\(sourceResetToken)' displayText='\(displayText)'")
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
                    debugState(isFocused ? "focusGained" : "focusLost")
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
            AxisRangeDebug.log("AxisBoundField[\(debugName)] displayTextSync (not focused) | old editText='\(editText)' new displayText='\(displayText)' placeholder='\(placeholder)' currentValue=\(currentValue.map { "\($0)" } ?? "nil") hasOverride=\(hasOverride) isDirty=\(isDirty) sourceResetToken='\(sourceResetToken)'")
            editText = displayText
            isDirty = false
        }
        .task(id: sourceResetToken) {
            AxisRangeDebug.log("AxisBoundField[\(debugName)] sourceResetToken changed | new token='\(sourceResetToken)' displayText='\(displayText)' placeholder='\(placeholder)' currentValue=\(currentValue.map { "\($0)" } ?? "nil") isDirty=\(isDirty) focused=\(focused)")
            editText = displayText
            isDirty = false
            focused = false
        }
    }

    private var dirtyBinding: Binding<String> {
        Binding(
            get: { editText },
            set: { newVal in
                let old = editText
                editText = newVal
                isDirty = true
                AxisRangeDebug.log("AxisBoundField[\(debugName)] textChange '\(old)'->'\(newVal)' | placeholder='\(placeholder)' currentValue=\(currentValue.map { "\($0)" } ?? "nil") hasOverride=\(hasOverride) isDirty=true focused=\(focused) sourceResetToken='\(sourceResetToken)'")
            }
        )
    }

    private func commitIfDirty() {
        AxisRangeDebug.log("AxisBoundField[\(debugName)] commitIfDirty called | isDirty=\(isDirty) editText='\(editText)' placeholder='\(placeholder)' currentValue=\(currentValue.map { "\($0)" } ?? "nil") hasOverride=\(hasOverride) focused=\(focused) sourceResetToken='\(sourceResetToken)'")
        guard isDirty else { return }
        isDirty = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = axisCommitDecision(trimmed: trimmed, currentValue: currentValue)
        AxisRangeDebug.log("AxisBoundField[\(debugName)] committing | trimmed='\(trimmed)' decision=\(decision) placeholder='\(placeholder)'")
        switch decision {
        case .noOp:
            break
        case .clear:
            onCommit(nil)
        case .setValue(let v):
            onCommit(v)
        }
    }

    private func formatBound(_ v: Double) -> String {
        if v == 0 { return "0" }
        let abs = Swift.abs(v)
        if abs >= 0.001 && abs < 100_000 { return String(format: "%g", v) }
        return String(format: "%.3e", v)
    }
}

// MARK: - Axis commit logic (internal for testing)

enum AxisBoundCommitDecision: Equatable, CustomStringConvertible {
    case noOp
    case clear
    case setValue(Double)

    var description: String {
        switch self {
        case .noOp: return "noOp"
        case .clear: return "clear"
        case .setValue(let v): return "setValue(\(v))"
        }
    }
}

/// Pure decision function for AxisBoundField.commitIfDirty.
///
/// - trimmed: editText after whitespace trimming (caller has already confirmed isDirty)
/// - currentValue: the active override for this bound, nil = auto
///
/// Clears only on explicit empty-field gesture. Treats a typed value that matches the
/// placeholder (auto range shown dimmed) as a real value — the user re-confirmed the
/// override by typing it. Skips onCommit when the value is already set to the same number.
func axisCommitDecision(trimmed: String, currentValue: Double?) -> AxisBoundCommitDecision {
    if trimmed.isEmpty {
        return currentValue != nil ? .clear : .noOp
    }
    guard let parsed = Double(trimmed) else { return .noOp }
    if let cv = currentValue, parsed == cv { return .noOp }
    return .setValue(parsed)
}
