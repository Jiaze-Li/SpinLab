import SwiftUI

/// Heatmap plot controls surface owned by the Heatmap module.
///
/// RSM mounts this panel but does not implement the heatmap scale UI itself.
struct HeatmapPlotControlsPanel: View {
    @Binding var globalPlotDefaults: [String: String]
    let colorScaleMode: PlotScaleTransform
    let titleOverride: String
    let xLabelOverride: String
    let yLabelOverride: String
    let zLabelOverride: String
    let renderedTitle: String
    let renderedXLabel: String
    let renderedYLabel: String
    let renderedZLabel: String
    let sourceResetToken: String
    let onColorScaleModeChange: (PlotScaleTransform) -> Void
    let onTitleOverride: (String) -> Void
    let onXLabelOverride: (String) -> Void
    let onYLabelOverride: (String) -> Void
    let onZLabelOverride: (String) -> Void
    let onStyleChange: () -> Void

    var body: some View {
        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                HeatmapColorScaleControls(
                    colorScaleMode: colorScaleMode,
                    onColorScaleModeChange: onColorScaleModeChange
                )
                SharedPlotTextControls(
                    titleOverride: titleOverride,
                    xLabelOverride: xLabelOverride,
                    yLabelOverride: yLabelOverride,
                    renderedTitle: renderedTitle,
                    renderedXLabel: renderedXLabel,
                    renderedYLabel: renderedYLabel,
                    sourceResetToken: sourceResetToken,
                    onTitleOverride: onTitleOverride,
                    onXLabelOverride: onXLabelOverride,
                    onYLabelOverride: onYLabelOverride
                )
                HeatmapZLabelControl(
                    renderedDefault: renderedZLabel,
                    currentValue: zLabelOverride,
                    sourceResetToken: sourceResetToken,
                    onCommit: onZLabelOverride
                )
                SharedPlotFontSizeControls(
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange
                )
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }
}
