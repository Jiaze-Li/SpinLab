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
