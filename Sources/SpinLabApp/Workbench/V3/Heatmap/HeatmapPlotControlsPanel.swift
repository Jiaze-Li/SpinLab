import SwiftUI

/// Heatmap plot controls surface owned by the Heatmap module.
///
/// RSM mounts this panel but does not implement the heatmap scale UI itself.
struct HeatmapPlotControlsPanel<HostControls: View>: View {
    let hostControls: HostControls
    @Binding var globalPlotDefaults: [String: String]
    let colorScaleMode: PlotScaleTransform
    let zDomainState: HeatmapZDomainState
    let showZLabel: Bool
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
    let onZDomainStateChange: (HeatmapZDomainState) -> Void
    let onShowZLabelChange: (Bool) -> Void
    let onTitleOverride: (String) -> Void
    let onXLabelOverride: (String) -> Void
    let onYLabelOverride: (String) -> Void
    let onZLabelOverride: (String) -> Void
    let onStyleChange: () -> Void

    init(
        hostControls: HostControls,
        globalPlotDefaults: Binding<[String: String]>,
        colorScaleMode: PlotScaleTransform,
        zDomainState: HeatmapZDomainState,
        showZLabel: Bool,
        titleOverride: String,
        xLabelOverride: String,
        yLabelOverride: String,
        zLabelOverride: String,
        renderedTitle: String,
        renderedXLabel: String,
        renderedYLabel: String,
        renderedZLabel: String,
        sourceResetToken: String,
        onColorScaleModeChange: @escaping (PlotScaleTransform) -> Void,
        onZDomainStateChange: @escaping (HeatmapZDomainState) -> Void,
        onShowZLabelChange: @escaping (Bool) -> Void,
        onTitleOverride: @escaping (String) -> Void,
        onXLabelOverride: @escaping (String) -> Void,
        onYLabelOverride: @escaping (String) -> Void,
        onZLabelOverride: @escaping (String) -> Void,
        onStyleChange: @escaping () -> Void
    ) {
        self.hostControls = hostControls
        self._globalPlotDefaults = globalPlotDefaults
        self.colorScaleMode = colorScaleMode
        self.zDomainState = zDomainState
        self.showZLabel = showZLabel
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.zLabelOverride = zLabelOverride
        self.renderedTitle = renderedTitle
        self.renderedXLabel = renderedXLabel
        self.renderedYLabel = renderedYLabel
        self.renderedZLabel = renderedZLabel
        self.sourceResetToken = sourceResetToken
        self.onColorScaleModeChange = onColorScaleModeChange
        self.onZDomainStateChange = onZDomainStateChange
        self.onShowZLabelChange = onShowZLabelChange
        self.onTitleOverride = onTitleOverride
        self.onXLabelOverride = onXLabelOverride
        self.onYLabelOverride = onYLabelOverride
        self.onZLabelOverride = onZLabelOverride
        self.onStyleChange = onStyleChange
    }

    var body: some View {
        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    hostControls
                    HeatmapColorScaleControls(
                        colorScaleMode: colorScaleMode,
                        onColorScaleModeChange: onColorScaleModeChange
                    )
                }
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
                HStack(alignment: .top, spacing: 12) {
                    HeatmapZLabelControl(
                        showZLabel: showZLabel,
                        onShowZLabelChange: onShowZLabelChange,
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
                HeatmapZRangeControl(
                    zDomainState: zDomainState,
                    onZDomainStateChange: onZDomainStateChange
                )
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }
}
