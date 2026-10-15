import SwiftUI

// MARK: - PlotRangeResetControl

/// Shared panel-level "Reset ranges" action, used by both the Cartesian XY and
/// Dual Axis plot-controls panels. Deliberately lives outside the per-bound
/// numeric leaf: the atomic clear + redraw + persistence flush is a container
/// concern, not something the individual min/max field reasons about.
///
/// Visibility is driven by an injected `(() -> Void)?` capability rather than a
/// workflow-name check — callers that want the control simply pass a non-nil
/// `onReset`; callers that don't pass nil and this view renders nothing.
struct PlotRangeResetControl: View {
    /// Whether any bound in the current plot context is currently overridden.
    /// The button only renders when there's something to reset.
    let hasActiveOverride: Bool
    let onReset: () -> Void
    /// Controls Surface sections (spec CS-12) keep the standard control present and only
    /// disable it when nothing is overridden; the legacy panels hide it instead.
    var alwaysPresent: Bool = false

    var body: some View {
        if hasActiveOverride || alwaysPresent {
            Button("Reset ranges", action: onReset)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!hasActiveOverride)
        }
    }
}
