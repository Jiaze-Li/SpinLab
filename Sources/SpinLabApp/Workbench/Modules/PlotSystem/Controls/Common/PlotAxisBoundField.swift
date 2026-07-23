import SwiftUI

// MARK: - PlotAxisBoundRole

/// Which side of a min–max pair a bound field edits. Determines the direction
/// of the effective-opposite-bound comparison on commit: a `.lower` field's
/// submitted value must stay below the effective opposite bound, an `.upper`
/// field's must stay above it.
enum PlotAxisBoundRole: Sendable, Equatable {
    case lower
    case upper
}

// MARK: - PlotAxisBoundIdentity

/// Typed identity for a single axis-range bound field. Carries only what the
/// leaf needs for debug logging and commit-direction — never a workflow name
/// or type.
struct PlotAxisBoundIdentity: Sendable, Equatable {
    let debugName: String
    let role: PlotAxisBoundRole
}

// MARK: - PlotAxisBoundFieldWidth

/// Width policy for the field's `TextField`, matching the two strategies
/// previously duplicated across `AxisBoundField` (fixed) and
/// `CompactNumericField` (fixed or compressible).
enum PlotAxisBoundFieldWidth: Sendable, Equatable {
    case fixed(CGFloat)
    case flexible(min: CGFloat, ideal: CGFloat, max: CGFloat)
}

// MARK: - PlotAxisBoundField

/// Single numeric text field for one Cartesian XY or Dual Axis range bound.
///
/// Shows the auto/layout value (dimmed) as a placeholder when no override is
/// set. Clearing the field removes the override for that bound. Rejects
/// non-finite input and any value that would cross the effective opposite
/// bound (the caller's explicit override on that side, or its auto/layout
/// value otherwise) before ever calling `onCommit`. No-op commits — including
/// nil → nil — never call `onCommit`.
///
/// Shared by every Cartesian XY and Dual Axis workflow. Does not know about
/// reset-all-ranges — that capability lives one level up, at the panel.
struct PlotAxisBoundField: View {
    let identity: PlotAxisBoundIdentity
    let placeholder: String
    let currentValue: Double?
    /// The bound this field's submitted value is validated against: the
    /// opposite side's explicit override when present, its auto/layout value
    /// otherwise. `nil` skips the crossing check (opposite side unresolved).
    let effectiveOppositeBound: Double?
    /// Token that changes when the analyzed source/tab/sample context
    /// changes; forces edit state to drop focus and resync from `placeholder`/`currentValue`.
    let sourceResetToken: String
    var width: PlotAxisBoundFieldWidth = .fixed(60)
    var showsClearButton: Bool = true
    /// Optional injected debug hook. Cartesian XY wires this to the existing
    /// `AxisRangeDebug` logger; other callers may leave it nil.
    var debugLog: ((String) -> Void)? = nil
    let onCommit: (Double?) -> Void

    @State private var editText: String = ""
    @State private var isDirty: Bool = false
    @FocusState private var focused: Bool

    private var hasOverride: Bool { currentValue != nil }
    private var displayText: String {
        if let currentValue { return formatPlotAxisRangeValue(currentValue) }
        return placeholder
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: dirtyBinding)
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .foregroundStyle(hasOverride ? Color.primary : Color.secondary)
                .modifier(PlotAxisBoundFieldWidthFrame(width: width))
                .focused($focused)
                .onSubmit { commitIfDirty() }
                .onChange(of: focused) { _, isFocused in
                    debugLog?("PlotAxisBoundField[\(identity.debugName)] \(isFocused ? "focusGained" : "focusLost") | editText='\(editText)' currentValue=\(currentValue.map { "\($0)" } ?? "nil") isDirty=\(isDirty)")
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
            debugLog?("PlotAxisBoundField[\(identity.debugName)] sourceResetToken changed | new token='\(sourceResetToken)'")
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
        let decision = plotAxisBoundCommitDecision(
            trimmed: trimmed,
            currentValue: currentValue,
            role: identity.role,
            effectiveOppositeBound: effectiveOppositeBound
        )
        debugLog?("PlotAxisBoundField[\(identity.debugName)] committing | trimmed='\(trimmed)' decision=\(decision)")
        switch decision {
        case .noOp:
            break
        case .clear:
            onCommit(nil)
        case .setValue(let v):
            onCommit(v)
        }
    }
}

/// Applies either a single fixed width or a compressible min/ideal/max frame.
private struct PlotAxisBoundFieldWidthFrame: ViewModifier {
    let width: PlotAxisBoundFieldWidth

    func body(content: Content) -> some View {
        switch width {
        case .fixed(let value):
            content.frame(width: value)
        case .flexible(let min, let ideal, let max):
            content.frame(minWidth: min, idealWidth: ideal, maxWidth: max)
        }
    }
}

// MARK: - Commit decision (pure, testable)

enum PlotAxisBoundCommitDecision: Equatable, CustomStringConvertible {
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

/// Pure decision function for `PlotAxisBoundField.commitIfDirty`.
///
/// - trimmed: editText after whitespace trimming (caller has already confirmed isDirty)
/// - currentValue: the active override for this bound, nil = auto
/// - role: which side of the pair this field is (`.lower` validates `parsed < effectiveOppositeBound`,
///   `.upper` validates `parsed > effectiveOppositeBound`)
/// - effectiveOppositeBound: the opposite side's explicit override if present, else its
///   auto/layout value; nil skips the crossing check
///
/// Rejects non-finite parses (NaN, +Infinity, -Infinity) and any value that would cross the
/// effective opposite bound. Clears only on explicit empty-field gesture. Treats a typed value
/// that matches the placeholder (auto range shown dimmed) as a real value — the user
/// re-confirmed the override by typing it. Skips onCommit when the value is already set to the
/// same number (including nil → nil).
func plotAxisBoundCommitDecision(
    trimmed: String,
    currentValue: Double?,
    role: PlotAxisBoundRole,
    effectiveOppositeBound: Double?
) -> PlotAxisBoundCommitDecision {
    if trimmed.isEmpty {
        return currentValue != nil ? .clear : .noOp
    }
    guard let parsed = Double(trimmed), parsed.isFinite else { return .noOp }
    if let cv = currentValue, parsed == cv { return .noOp }
    if let opposite = effectiveOppositeBound {
        switch role {
        case .lower:
            guard parsed < opposite else { return .noOp }
        case .upper:
            guard parsed > opposite else { return .noOp }
        }
    }
    return .setValue(parsed)
}
