import SwiftUI

// MARK: - WorkbenchPlotTabPicker

/// Generic tab picker — the "which plot am I looking at" control shared by every
/// stacked-curve workflow. Extracted from `WorkbenchPlotNavigationStrip` so callers that
/// only need the picker (e.g. a workspace-level action bar slot) don't have to pull in the
/// stack/gap controls too. No workflow-specific types leak into this signature.
struct WorkbenchPlotTabPicker<Tab: Identifiable & Hashable>: View {
    @Binding var activeTab: Tab
    let tabs: [Tab]
    let tabLabel: (Tab) -> String
    /// Called with (oldTab, newTab) after the active tab changes.
    var onChange: ((Tab, Tab) -> Void)? = nil
    var pickerWidth: CGFloat? = nil

    var body: some View {
        Picker("Tab", selection: $activeTab) {
            ForEach(tabs) { tab in
                Text(tabLabel(tab)).tag(tab)
            }
        }
        .labelsHidden()
        .frame(width: pickerWidth, alignment: .leading)
        .onChange(of: activeTab) { oldValue, newValue in onChange?(oldValue, newValue) }
    }
}

// MARK: - WorkbenchPlotSpacingInlineControls

/// Parsing and display of the Gap field. Pure, so the accepted range is unit-testable: a Gap is
/// any non-negative finite decimal, kept exactly as typed (no quantizing to a step).
enum WorkbenchGapInput {
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value   // "-0" is stored as plain 0
    }

    /// Shortest faithful text for a stored Gap (0.125 → "0.125", 0.11 → "0.11").
    static func format(_ value: Double) -> String {
        String(format: "%.12g", value)
    }
}

private enum WorkbenchPlotSpacingInlineControlsLayout {
    static let gapFieldWidth: CGFloat = WorkbenchInputWidth.gap
    static let rowSpacing: CGFloat = 8
}

/// The single Gap input — "how far apart are stacked traces" — shared by every stacked-curve
/// workflow. Gap = 0 leaves curves where they are; Gap > 0 stacks them with a uniform net gap of
/// max peak-to-peak × Gap. While a loaded legacy Stack × Gap layout is unmigrated the field is
/// disabled — it is not the new control until the migration prompt is accepted.
struct WorkbenchPlotSpacingInlineControls: View {
    @Binding var gap: Double
    /// false while an unmigrated legacy layout is in effect.
    var isEditable = true
    /// Called after a valid Gap has been committed.
    var onGapSubmit: () -> Void = {}

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: WorkbenchPlotSpacingInlineControlsLayout.rowSpacing) {
            Text("Gap")
                .workbenchTextRole(.label)
                .fixedSize()
                .workbenchPairMember("gap")
            TextField("0", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .frame(width: WorkbenchPlotSpacingInlineControlsLayout.gapFieldWidth)
                .focused($focused)
                .workbenchControl(.textField)
                .workbenchPairMember("gap")
                .accessibilityLabel("Gap")
                .disabled(!isEditable)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        }
        .onAppear { text = WorkbenchGapInput.format(gap) }
        .onChange(of: gap) { _, value in if !focused { text = WorkbenchGapInput.format(value) } }
    }

    /// A valid edit is stored; anything else (empty, negative, NaN, text) restores the saved
    /// value and leaves the configuration untouched.
    private func commit() {
        let saved = WorkbenchGapInput.format(gap)
        guard text != saved else { return }
        guard let value = WorkbenchGapInput.parse(text) else {
            text = saved
            return
        }
        gap = value
        text = WorkbenchGapInput.format(value)
        onGapSubmit()
    }
}
