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
    static let gapFieldWidth: CGFloat = WorkbenchInputWidth.compact
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
    var sliderWidth: CGFloat = WorkbenchInputWidth.sliderIdeal

    /// Slider + read-out and Gap are two pairs. They share one line when they fit; otherwise
    /// Gap wraps below while the slider keeps its VC-4 minimum (CS-23, CS-35).
    var body: some View {
        WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
            HStack(spacing: WorkbenchPlotSpacingInlineControlsLayout.rowSpacing) {
                Slider(value: $stackOffset, in: stackRange, step: 0.1)
                    .frame(minWidth: WorkbenchInputWidth.sliderMinimum, idealWidth: sliderWidth, maxWidth: WorkbenchInputWidth.sliderMaximum)
                    .workbenchControl(.slider)
                    .workbenchPairMember("stack")
                    .onChange(of: stackOffset) { _, _ in onStackChange?() }
                Text(String(format: "%.1f×", stackOffset))
                    .workbenchTextRole(.value)
                    .frame(width: WorkbenchPlotSpacingInlineControlsLayout.stackValueWidth, alignment: .trailing)
                    .workbenchPairMember("stack")
            }
            .workbenchFlowFill(maxGrowth: WorkbenchInputWidth.sliderMaximum - sliderWidth)
            HStack(spacing: WorkbenchPlotSpacingInlineControlsLayout.rowSpacing) {
                Text("Gap")
                    .workbenchTextRole(.label)
                    .fixedSize()
                    .workbenchPairMember("gap")
                TextField("0.15", value: $minGapFraction, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(WorkbenchUIStyle.controlValueFont)
                    .frame(width: WorkbenchPlotSpacingInlineControlsLayout.gapFieldWidth)
                    .workbenchControl(.textField)
                    .workbenchPairMember("gap")
                    .onSubmit { (onGapSubmit ?? onStackChange)?() }
            }
        }
    }
}
