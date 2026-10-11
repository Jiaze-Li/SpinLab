import SwiftUI

/// Heatmap plot controls surface owned by the Heatmap module.
///
/// RSM mounts this panel but does not implement the heatmap scale UI itself.
///
/// `pluginControls` is a generic, workflow-owned contribution slot rendered after all common
/// Heatmap controls — analogous to the `extraContent` slot on the Cartesian XY plot-controls
/// shell. It defaults to `EmptyView` (see the `PluginControls == EmptyView` extension below), so
/// existing callers that don't pass it render identically to before this slot existed. Heatmap
/// never inspects what a workflow puts here; workflows should wrap their own content in
/// `WorkbenchPlotControlsPluginSection` for the standard divider + row layout.
struct HeatmapPlotControlsPanel<PluginControls: View>: View {
    @Binding var globalPlotDefaults: [String: String]
    let colorScaleMode: PlotScaleTransform
    let interpolationMode: HeatmapInterpolationMode
    let zDomainState: HeatmapZDomainState
    let showColorbar: Bool
    let showTitle: Bool
    let xTickCount: Int
    let yTickCount: Int
    let titleOverride: String
    let xLabelOverride: String
    let yLabelOverride: String
    let zLabelOverride: String
    let renderedTitle: String
    let renderedXLabel: String
    let renderedYLabel: String
    let renderedZLabel: String
    let sourceResetToken: String
    /// Optional Heatmap-module control for clamping the Z/intensity domain.
    /// Workflows opt in when their Assembly wants user-facing intensity clipping.
    let showsZRangeControl: Bool
    let onColorScaleModeChange: (PlotScaleTransform) -> Void
    let onInterpolationModeChange: (HeatmapInterpolationMode) -> Void
    let onZDomainStateChange: (HeatmapZDomainState) -> Void
    let onShowColorbarChange: (Bool) -> Void
    let onShowTitleChange: (Bool) -> Void
    let onXTickCountChange: (Int) -> Void
    let onYTickCountChange: (Int) -> Void
    let onTitleOverride: (String) -> Void
    let onXLabelOverride: (String) -> Void
    let onYLabelOverride: (String) -> Void
    let onZLabelOverride: (String) -> Void
    let onStyleChange: () -> Void
    /// Called instead of `onStyleChange` for tick-count edits: `xTickCount`/`yTickCount` live
    /// only in the caller's per-workflow display state (e.g. RSM's `heatmapDisplayState`), not
    /// in `SpinLabInteractionSnapshot` — unlike the font-size controls below, which write into
    /// the shared `globalPlotDefaults` snapshot field. Falls back to `onStyleChange` when nil,
    /// preserving current behavior for callers that haven't opted in.
    var onTickCountRenderChange: (() -> Void)? = nil
    /// Workflow-owned controls rendered after all common Heatmap controls. Defaults to
    /// `EmptyView` via the constrained convenience `init` below.
    @ViewBuilder var pluginControls: () -> PluginControls
    /// False for figure-style workflows (AFM) that draw no axes or Z title: hides the tick
    /// count, X/Y/Z label and axis/tick font-size controls. Default true keeps RSM unchanged.
    private(set) var showsAxisControls: Bool = true

    /// Axis-free variant: only the controls that still affect such a figure (scale mode,
    /// interpolation, title text/size, colorbar, height range). Unused axis state is inert.
    init(
        globalPlotDefaults: Binding<[String: String]>,
        colorScaleMode: PlotScaleTransform,
        interpolationMode: HeatmapInterpolationMode,
        zDomainState: HeatmapZDomainState,
        showColorbar: Bool,
        showTitle: Bool,
        titleOverride: String,
        renderedTitle: String,
        sourceResetToken: String,
        onColorScaleModeChange: @escaping (PlotScaleTransform) -> Void,
        onInterpolationModeChange: @escaping (HeatmapInterpolationMode) -> Void,
        onZDomainStateChange: @escaping (HeatmapZDomainState) -> Void,
        onShowColorbarChange: @escaping (Bool) -> Void,
        onShowTitleChange: @escaping (Bool) -> Void,
        onTitleOverride: @escaping (String) -> Void,
        onStyleChange: @escaping () -> Void,
        @ViewBuilder pluginControls: @escaping () -> PluginControls
    ) {
        self.init(
            globalPlotDefaults: globalPlotDefaults,
            colorScaleMode: colorScaleMode,
            interpolationMode: interpolationMode,
            zDomainState: zDomainState,
            showColorbar: showColorbar,
            showTitle: showTitle,
            xTickCount: PlotTickConfiguration.defaultValue.xTargetCount,
            yTickCount: PlotTickConfiguration.defaultValue.yTargetCount,
            titleOverride: titleOverride,
            xLabelOverride: "",
            yLabelOverride: "",
            zLabelOverride: "",
            renderedTitle: renderedTitle,
            renderedXLabel: "",
            renderedYLabel: "",
            renderedZLabel: "",
            sourceResetToken: sourceResetToken,
            showsZRangeControl: true,
            onColorScaleModeChange: onColorScaleModeChange,
            onInterpolationModeChange: onInterpolationModeChange,
            onZDomainStateChange: onZDomainStateChange,
            onShowColorbarChange: onShowColorbarChange,
            onShowTitleChange: onShowTitleChange,
            onXTickCountChange: { _ in },
            onYTickCountChange: { _ in },
            onTitleOverride: onTitleOverride,
            onXLabelOverride: { _ in },
            onYLabelOverride: { _ in },
            onZLabelOverride: { _ in },
            onStyleChange: onStyleChange,
            pluginControls: pluginControls
        )
        self.showsAxisControls = false
    }

    init(
        globalPlotDefaults: Binding<[String: String]>,
        colorScaleMode: PlotScaleTransform,
        interpolationMode: HeatmapInterpolationMode,
        zDomainState: HeatmapZDomainState,
        showColorbar: Bool,
        showTitle: Bool,
        xTickCount: Int,
        yTickCount: Int,
        titleOverride: String,
        xLabelOverride: String,
        yLabelOverride: String,
        zLabelOverride: String,
        renderedTitle: String,
        renderedXLabel: String,
        renderedYLabel: String,
        renderedZLabel: String,
        sourceResetToken: String,
        showsZRangeControl: Bool = true,
        onColorScaleModeChange: @escaping (PlotScaleTransform) -> Void,
        onInterpolationModeChange: @escaping (HeatmapInterpolationMode) -> Void,
        onZDomainStateChange: @escaping (HeatmapZDomainState) -> Void,
        onShowColorbarChange: @escaping (Bool) -> Void,
        onShowTitleChange: @escaping (Bool) -> Void,
        onXTickCountChange: @escaping (Int) -> Void,
        onYTickCountChange: @escaping (Int) -> Void,
        onTitleOverride: @escaping (String) -> Void,
        onXLabelOverride: @escaping (String) -> Void,
        onYLabelOverride: @escaping (String) -> Void,
        onZLabelOverride: @escaping (String) -> Void,
        onStyleChange: @escaping () -> Void,
        onTickCountRenderChange: (() -> Void)? = nil,
        @ViewBuilder pluginControls: @escaping () -> PluginControls
    ) {
        self._globalPlotDefaults = globalPlotDefaults
        self.colorScaleMode = colorScaleMode
        self.interpolationMode = interpolationMode
        self.zDomainState = zDomainState
        self.showColorbar = showColorbar
        self.showTitle = showTitle
        self.xTickCount = xTickCount
        self.yTickCount = yTickCount
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.zLabelOverride = zLabelOverride
        self.renderedTitle = renderedTitle
        self.renderedXLabel = renderedXLabel
        self.renderedYLabel = renderedYLabel
        self.renderedZLabel = renderedZLabel
        self.sourceResetToken = sourceResetToken
        self.showsZRangeControl = showsZRangeControl
        self.onColorScaleModeChange = onColorScaleModeChange
        self.onInterpolationModeChange = onInterpolationModeChange
        self.onZDomainStateChange = onZDomainStateChange
        self.onShowColorbarChange = onShowColorbarChange
        self.onShowTitleChange = onShowTitleChange
        self.onXTickCountChange = onXTickCountChange
        self.onYTickCountChange = onYTickCountChange
        self.onTitleOverride = onTitleOverride
        self.onXLabelOverride = onXLabelOverride
        self.onYLabelOverride = onYLabelOverride
        self.onZLabelOverride = onZLabelOverride
        self.onStyleChange = onStyleChange
        self.onTickCountRenderChange = onTickCountRenderChange
        self.pluginControls = pluginControls
    }

    /// Row 1: colorbar scale, Title toggle, and Z (colorbar) toggle.
    /// Row 2: tick count steppers, then interpolation. Split into two fixed rows (no
    /// Spacer forcing extra width) so this stays narrow enough to avoid clipping into
    /// the Result panel.
    private var topControlsRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HeatmapColorScaleControls(
                    colorScaleMode: colorScaleMode,
                    onColorScaleModeChange: onColorScaleModeChange
                )
                Toggle("Title", isOn: Binding(
                    get: { showTitle },
                    set: { onShowTitleChange($0) }
                ))
                .toggleStyle(.checkbox)
                Toggle(showsAxisControls ? "Z" : "Colorbar", isOn: Binding(
                    get: { showColorbar },
                    set: { onShowColorbarChange($0) }
                ))
                .toggleStyle(.checkbox)
            }
            HStack(spacing: 12) {
                if showsAxisControls {
                    SharedPlotTickCountControls(
                        xTickCount: xTickCount,
                        yTickCount: yTickCount,
                        onXTickCountChange: { onXTickCountChange($0); (onTickCountRenderChange ?? onStyleChange)() },
                        onYTickCountChange: { onYTickCountChange($0); (onTickCountRenderChange ?? onStyleChange)() }
                    )
                }
                HeatmapInterpolationControls(
                    interpolationMode: interpolationMode,
                    onInterpolationModeChange: onInterpolationModeChange
                )
            }
        }
    }

    var body: some View {
        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                topControlsRows
                if showsAxisControls {
                    axisAwareTextControls
                } else {
                    titleOnlyControls
                }
                if showsZRangeControl {
                    HeatmapZRangeControl(
                        zDomainState: zDomainState,
                        onZDomainStateChange: onZDomainStateChange
                    )
                }
                pluginControls()
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var titleOnlyControls: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            LabelOverrideField(
                label: "Plot title",
                renderedDefault: renderedTitle,
                currentValue: titleOverride,
                sourceResetToken: sourceResetToken,
                onCommit: onTitleOverride,
                fieldMaxWidth: .infinity
            )
            SharedPlotFontSizePicker(
                label: "Title size",
                current: style.titleFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "titleFontSize"),
                onStyleChange: onStyleChange
            )
        }
    }

    @ViewBuilder
    private var axisAwareTextControls: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
    }
}

extension HeatmapPlotControlsPanel where PluginControls == EmptyView {
    init(
        globalPlotDefaults: Binding<[String: String]>,
        colorScaleMode: PlotScaleTransform,
        interpolationMode: HeatmapInterpolationMode,
        zDomainState: HeatmapZDomainState,
        showColorbar: Bool,
        showTitle: Bool,
        xTickCount: Int,
        yTickCount: Int,
        titleOverride: String,
        xLabelOverride: String,
        yLabelOverride: String,
        zLabelOverride: String,
        renderedTitle: String,
        renderedXLabel: String,
        renderedYLabel: String,
        renderedZLabel: String,
        sourceResetToken: String,
        showsZRangeControl: Bool = true,
        onColorScaleModeChange: @escaping (PlotScaleTransform) -> Void,
        onInterpolationModeChange: @escaping (HeatmapInterpolationMode) -> Void,
        onZDomainStateChange: @escaping (HeatmapZDomainState) -> Void,
        onShowColorbarChange: @escaping (Bool) -> Void,
        onShowTitleChange: @escaping (Bool) -> Void,
        onXTickCountChange: @escaping (Int) -> Void,
        onYTickCountChange: @escaping (Int) -> Void,
        onTitleOverride: @escaping (String) -> Void,
        onXLabelOverride: @escaping (String) -> Void,
        onYLabelOverride: @escaping (String) -> Void,
        onZLabelOverride: @escaping (String) -> Void,
        onStyleChange: @escaping () -> Void,
        onTickCountRenderChange: (() -> Void)? = nil
    ) {
        self.init(
            globalPlotDefaults: globalPlotDefaults,
            colorScaleMode: colorScaleMode,
            interpolationMode: interpolationMode,
            zDomainState: zDomainState,
            showColorbar: showColorbar,
            showTitle: showTitle,
            xTickCount: xTickCount,
            yTickCount: yTickCount,
            titleOverride: titleOverride,
            xLabelOverride: xLabelOverride,
            yLabelOverride: yLabelOverride,
            zLabelOverride: zLabelOverride,
            renderedTitle: renderedTitle,
            renderedXLabel: renderedXLabel,
            renderedYLabel: renderedYLabel,
            renderedZLabel: renderedZLabel,
            sourceResetToken: sourceResetToken,
            showsZRangeControl: showsZRangeControl,
            onColorScaleModeChange: onColorScaleModeChange,
            onInterpolationModeChange: onInterpolationModeChange,
            onZDomainStateChange: onZDomainStateChange,
            onShowColorbarChange: onShowColorbarChange,
            onShowTitleChange: onShowTitleChange,
            onXTickCountChange: onXTickCountChange,
            onYTickCountChange: onYTickCountChange,
            onTitleOverride: onTitleOverride,
            onXLabelOverride: onXLabelOverride,
            onYLabelOverride: onYLabelOverride,
            onZLabelOverride: onZLabelOverride,
            onStyleChange: onStyleChange,
            onTickCountRenderChange: onTickCountRenderChange,
            pluginControls: { EmptyView() }
        )
    }
}
