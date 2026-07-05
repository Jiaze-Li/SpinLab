import SwiftUI

// MARK: - WorkbenchPlotNavigationStrip

/// Tab picker + stack offset slider + gap input — the single row shared by every
/// stacked-curve workflow's plot controls.
///
/// Most workflows (AHE/IV/XY/RT) render this inline via `WorkbenchStandardPlotControls`.
/// 3ω renders it once at the workspace level (`ThreeOmegaWorkspaceTabStrip`) so the same
/// row stays visible above per-plot-type controls (temperatureDependence/scaling/RAHE),
/// then suppresses the inline copy via `WorkbenchStandardPlotControls(hideTabRow: true)`.
/// Both call sites share this type so picker/slider/gap alignment stays identical.
struct WorkbenchPlotNavigationStrip<Tab: Hashable & Identifiable>: View {
    @Binding var activeTab: Tab
    let tabs: [Tab]
    let tabLabel: (Tab) -> String
    @Binding var stackOffset: Double
    var stackRange: ClosedRange<Double> = 0...1.6
    @Binding var minGapFraction: Double
    /// Called with (oldTab, newTab) after the active tab changes. Standard inline usage
    /// leaves this nil since the owning workspace view already observes the tab binding
    /// directly via its own `.onChange`.
    var onTabChange: ((Tab, Tab) -> Void)? = nil
    /// Called when the stack offset slider changes, and — absent `onGapSubmit` — when the
    /// gap field is submitted too.
    var onChange: (() -> Void)? = nil
    /// Called when the gap field is submitted. Falls back to `onChange` when nil, matching
    /// callers that don't need to distinguish the two (AHE/IV/XY/RT all pass one `onChange`
    /// for both); 3ω passes distinct callbacks to preserve its separate trace-source tags.
    var onGapSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Picker("Tab", selection: $activeTab) {
                ForEach(tabs) { tab in
                    Text(tabLabel(tab)).tag(tab)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
            .onChange(of: activeTab) { oldValue, newValue in onTabChange?(oldValue, newValue) }

            Slider(value: $stackOffset, in: stackRange, step: 0.1)
                .onChange(of: stackOffset) { _, _ in onChange?() }
            Text(String(format: "%.1f×", stackOffset))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Text("Gap")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            TextField("0.15", value: $minGapFraction, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .font(.system(size: 12))
                .onSubmit { (onGapSubmit ?? onChange)?() }
        }
    }
}
