import SwiftUI

// MARK: - WorkbenchPlotControlsPluginSection

/// Divider-delimited slot for workflow-specific ("plugin") plot controls.
///
/// A Plot Controls panel is split into two parts: shared common controls
/// (title/font/style/range/ticks/series, rendered by `WorkbenchPlotControlsPanel`
/// and `WorkbenchStandardPlotControls`) followed by controls unique to the active
/// workflow/tab. This type formalizes the boundary between the two: a leading
/// `Divider()` plus a leading-aligned `VStack`, matching the layout already used by
/// the 3ω scaling controls. Always rendered expanded — no collapsing, no
/// `ViewThatFits` probing.
///
/// Compose workflow-specific rows inside using the shared `ControlRow` primitive
/// (or a workflow-local row type where alignment must diverge, as documented on
/// `ThreeOmegaFieldRow`).
///
/// Controls only — this is not a result/status/info surface. Things like 3ω Scaling
/// Status, Fit Results, or Last Run Trace belong in the right result column, not here,
/// even when they sit visually near workflow-specific controls. See
/// `docs/architecture/workbench/modules/PLOT_SYSTEM.md` → "Plot Controls Shell Blocks".
struct WorkbenchPlotControlsPluginSection<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Divider()
            content()
        }
    }
}
