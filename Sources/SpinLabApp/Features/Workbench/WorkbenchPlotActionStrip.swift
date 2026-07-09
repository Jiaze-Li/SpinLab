import SwiftUI

// MARK: - WorkbenchPlotActionStrip

/// Shared Workbench result-shell action strip for plot-level actions.
///
/// The strip owns the Clear Plot affordance layout and its enabled-state wiring,
/// but it does not own workflow semantics or clear behavior.
struct WorkbenchPlotActionStrip: View {
    let onClearPlot: () -> Void
    let hasActiveImageData: Bool
    let isAnalyzing: Bool

    private var isClearPlotDisabled: Bool {
        !hasActiveImageData && !isAnalyzing
    }

    var body: some View {
        HStack(spacing: 8) {
            Button("Clear Plot") {
                onClearPlot()
            }
            .buttonStyle(.bordered)
            .disabled(isClearPlotDisabled)
        }
    }
}
