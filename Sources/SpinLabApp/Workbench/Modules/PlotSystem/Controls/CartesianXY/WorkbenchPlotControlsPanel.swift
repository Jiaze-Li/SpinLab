import SwiftUI

// MARK: - WorkbenchPlotControlsPanel

/// 通用 Plot Controls 容器。
/// 提供统一的 GroupBox 标题、内部 VStack 间距和 padding。
/// 所有 workflow 的 PlotControlsPanel 必须以此为容器，workflow 专属控件通过 ViewBuilder 注入。
/// Shell 级控件（绘图模式、字号、tick 密度）自动附加在底部，始终展开显示。
///
/// This is currently the CartesianXY plot-controls shell only (used via
/// `WorkbenchStandardPlotControls`). Do not treat it as a universal shell for
/// Heatmap/DualAxis without a real need — see
/// `docs/architecture/workbench/modules/PLOT_SYSTEM.md` → "Plot Controls Shell Blocks".
struct WorkbenchPlotControlsPanel<Content: View, Supplemental: View, Extra: View, DrawTrailing: View>: View {
    @Binding var seriesRenderMode: SeriesRenderMode
    @Binding var globalPlotDefaults: [String: String]
    @Binding var chartStyleOverrides: [String: String]
    var onStyleChange: (() -> Void)? = nil
    /// Layout from the most recent render, used to display auto axis ranges.
    var activeLayout: WorkbenchPlotLayout? = nil
    /// Current per-tab axis range override.
    var axisRangeOverride: AxisRangeOverride? = nil
    /// Called when the user edits a single axis range bound.
    var onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil
    /// Capability to clear every manual axis-range override in the current plot
    /// context in one atomic action. Non-nil shows the shared reset control;
    /// nil omits it. Not a workflow-name check — purely presence-of-capability.
    var onResetRanges: (() -> Void)? = nil
    /// Current per-tab Cartesian XY tick-count override.
    var tickOverride: PlotTickOverride? = nil
    /// Called when the user edits the tick count for one axis.
    var onTickCountUpdate: ((PlotTickAxis, Int) -> Void)? = nil
    /// Source identity token — resets axis range fields when the analyzed data changes.
    var sourceResetToken: String = ""
    /// Global Title visibility toggle, rendered at the trailing end of the Font row.
    var showTitle: Binding<Bool>? = nil
    @ViewBuilder var supplementalContent: () -> Supplemental
    /// Workflow-specific controls (e.g. transport geometry, fit ranges). Rendered last,
    /// after every common control, so specialized rows never precede Draw/Range/Font.
    @ViewBuilder var extraContent: () -> Extra
    /// Rendered at the trailing edge of the Draw row, after the Draw/Line/Scatter
    /// controls. Lets callers (e.g. the Grid toggle) share the Draw row instead of
    /// crowding the title-template row.
    @ViewBuilder var drawRowTrailingContent: () -> DrawTrailing
    @ViewBuilder let content: () -> Content

    /// Resolves the displayed X tick count with the same precedence the render
    /// pipeline uses: typed `tickOverride` first, then the legacy
    /// `chartStyleOverrides["tickTargetX"]` string (read-only, for display
    /// compatibility with packs saved before the typed override existed), then default.
    private var resolvedXTickCount: Int {
        tickOverride?.x
            ?? chartStyleOverrides["tickTargetX"].flatMap(Int.init)
            ?? 6
    }

    /// Y-axis counterpart of `resolvedXTickCount`.
    private var resolvedYTickCount: Int {
        tickOverride?.y
            ?? chartStyleOverrides["tickTargetY"].flatMap(Int.init)
            ?? 5
    }

    var body: some View {
        if WorkbenchPerformanceDiagnostics.isEnabled {
            PerfCounters.controlsPanelBody += 1
            print("[PERF][count] WorkbenchPlotControlsPanel.body count=\(PerfCounters.controlsPanelBody)")
        }
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    CompactPlotStyleRow(
                        seriesRenderMode: $seriesRenderMode,
                        globalPlotDefaults: $globalPlotDefaults,
                        onStyleChange: onStyleChange
                    )
                    .equatable()
                    drawRowTrailingContent()
                }
                if let onAxisBoundUpdate {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        CompactAxisRangeRow(
                            activeLayout: activeLayout,
                            axisRangeOverride: axisRangeOverride,
                            onAxisBoundUpdate: onAxisBoundUpdate,
                            sourceResetToken: sourceResetToken
                        )
                        if let onTickCountUpdate {
                            CompactAxisTickCountRow(
                                xTickCount: resolvedXTickCount,
                                yTickCount: resolvedYTickCount,
                                onTickCountUpdate: onTickCountUpdate
                            )
                        }
                    }
                    if let onResetRanges {
                        PlotRangeResetControl(
                            hasActiveOverride: axisRangeOverride != nil,
                            onReset: onResetRanges
                        )
                    }
                }
                CompactTypographyRow(
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange,
                    showTitle: showTitle
                )
                .equatable()
                supplementalContent()
                extraContent()
            }
            .padding(.vertical, 4)
        }
    }
}

extension WorkbenchPlotControlsPanel where Supplemental == EmptyView, Extra == EmptyView, DrawTrailing == EmptyView {
    init(
        seriesRenderMode: Binding<SeriesRenderMode>,
        globalPlotDefaults: Binding<[String: String]>,
        chartStyleOverrides: Binding<[String: String]>,
        onStyleChange: (() -> Void)? = nil,
        activeLayout: WorkbenchPlotLayout? = nil,
        axisRangeOverride: AxisRangeOverride? = nil,
        onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil,
        onResetRanges: (() -> Void)? = nil,
        tickOverride: PlotTickOverride? = nil,
        onTickCountUpdate: ((PlotTickAxis, Int) -> Void)? = nil,
        sourceResetToken: String = "",
        showTitle: Binding<Bool>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._seriesRenderMode = seriesRenderMode
        self._globalPlotDefaults = globalPlotDefaults
        self._chartStyleOverrides = chartStyleOverrides
        self.onStyleChange = onStyleChange
        self.activeLayout = activeLayout
        self.axisRangeOverride = axisRangeOverride
        self.onAxisBoundUpdate = onAxisBoundUpdate
        self.onResetRanges = onResetRanges
        self.tickOverride = tickOverride
        self.onTickCountUpdate = onTickCountUpdate
        self.sourceResetToken = sourceResetToken
        self.showTitle = showTitle
        self.supplementalContent = { EmptyView() }
        self.extraContent = { EmptyView() }
        self.drawRowTrailingContent = { EmptyView() }
        self.content = content
    }
}

/// Covers callers (e.g. AHE) that supply real `supplementalContent`/`extraContent` but
/// don't need a Draw-row trailing slot — keeps them compiling without hand-wiring an
/// `EmptyView()` closure at every call site.
extension WorkbenchPlotControlsPanel where DrawTrailing == EmptyView {
    init(
        seriesRenderMode: Binding<SeriesRenderMode>,
        globalPlotDefaults: Binding<[String: String]>,
        chartStyleOverrides: Binding<[String: String]>,
        onStyleChange: (() -> Void)? = nil,
        activeLayout: WorkbenchPlotLayout? = nil,
        axisRangeOverride: AxisRangeOverride? = nil,
        onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil,
        onResetRanges: (() -> Void)? = nil,
        tickOverride: PlotTickOverride? = nil,
        onTickCountUpdate: ((PlotTickAxis, Int) -> Void)? = nil,
        sourceResetToken: String = "",
        showTitle: Binding<Bool>? = nil,
        @ViewBuilder supplementalContent: @escaping () -> Supplemental,
        @ViewBuilder extraContent: @escaping () -> Extra,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._seriesRenderMode = seriesRenderMode
        self._globalPlotDefaults = globalPlotDefaults
        self._chartStyleOverrides = chartStyleOverrides
        self.onStyleChange = onStyleChange
        self.activeLayout = activeLayout
        self.axisRangeOverride = axisRangeOverride
        self.onAxisBoundUpdate = onAxisBoundUpdate
        self.onResetRanges = onResetRanges
        self.tickOverride = tickOverride
        self.onTickCountUpdate = onTickCountUpdate
        self.sourceResetToken = sourceResetToken
        self.showTitle = showTitle
        self.supplementalContent = supplementalContent
        self.extraContent = extraContent
        self.drawRowTrailingContent = { EmptyView() }
        self.content = content
    }
}
