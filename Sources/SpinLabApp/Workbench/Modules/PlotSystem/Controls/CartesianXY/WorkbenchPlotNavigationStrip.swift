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

/// Generic stack-offset slider + gap field — the "how are traces spaced" controls shared
/// by every stacked-curve workflow. Extracted from `WorkbenchPlotNavigationStrip` so callers
/// that render the tab picker elsewhere (e.g. 3ω's action-bar slot) can still show this row
/// inline next to the title template field.
private enum WorkbenchPlotSpacingInlineControlsLayout {
    static let stackValueWidth: CGFloat = 28
    static let gapLabelWidth: CGFloat = 32
    static let gapFieldWidth: CGFloat = 48
    static let rowSpacing: CGFloat = 8
}

struct WorkbenchPlotSpacingInlineControls: View {
    @Binding var stackOffset: Double
    var stackRange: ClosedRange<Double> = 0...1.6
    @Binding var minGapFraction: Double
    /// Called when the stack offset slider changes, and — absent `onGapSubmit` — when the
    /// gap field is submitted too.
    var onStackChange: (() -> Void)? = nil
    /// Called when the gap field is submitted. Falls back to `onStackChange` when nil.
    var onGapSubmit: (() -> Void)? = nil
    var sliderWidth: CGFloat = 110

    var body: some View {
        HStack(spacing: WorkbenchPlotSpacingInlineControlsLayout.rowSpacing) {
            Slider(value: $stackOffset, in: stackRange, step: 0.1)
                .frame(maxWidth: sliderWidth)
                .onChange(of: stackOffset) { _, _ in onStackChange?() }
            Text(String(format: "%.1f×", stackOffset))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: WorkbenchPlotSpacingInlineControlsLayout.stackValueWidth, alignment: .trailing)

            Text("Gap")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .frame(width: WorkbenchPlotSpacingInlineControlsLayout.gapLabelWidth, alignment: .leading)
            TextField("0.15", value: $minGapFraction, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: WorkbenchPlotSpacingInlineControlsLayout.gapFieldWidth)
                .font(.system(size: 12))
                .onSubmit { (onGapSubmit ?? onStackChange)?() }
        }
    }
}
