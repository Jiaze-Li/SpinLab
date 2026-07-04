import SwiftUI

// MARK: - WorkbenchPlotControlsPanel

/// 通用 Plot Controls 容器。
/// 提供统一的 GroupBox 标题、内部 VStack 间距和 padding。
/// 所有 workflow 的 PlotControlsPanel 必须以此为容器，workflow 专属控件通过 ViewBuilder 注入。
/// Shell 级控件（绘图模式、字号、tick 密度）自动附加在底部。
struct WorkbenchPlotControlsPanel<Content: View, Supplemental: View>: View {
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
    /// Source identity token — resets axis range fields when the analyzed data changes.
    var sourceResetToken: String = ""
    @ViewBuilder var supplementalContent: () -> Supplemental
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
                CompactPlotStyleRow(
                    seriesRenderMode: $seriesRenderMode,
                    globalPlotDefaults: $globalPlotDefaults,
                    chartStyleOverrides: $chartStyleOverrides,
                    onStyleChange: onStyleChange,
                    activeLayout: activeLayout,
                    axisRangeOverride: axisRangeOverride,
                    onAxisBoundUpdate: onAxisBoundUpdate,
                    sourceResetToken: sourceResetToken
                )
                CompactTypographyRow(
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange
                )
                supplementalContent()
            }
            .padding(.vertical, 4)
        }
    }
}

extension WorkbenchPlotControlsPanel where Supplemental == EmptyView {
    init(
        seriesRenderMode: Binding<SeriesRenderMode>,
        globalPlotDefaults: Binding<[String: String]>,
        chartStyleOverrides: Binding<[String: String]>,
        onStyleChange: (() -> Void)? = nil,
        activeLayout: WorkbenchPlotLayout? = nil,
        axisRangeOverride: AxisRangeOverride? = nil,
        onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil,
        sourceResetToken: String = "",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._seriesRenderMode = seriesRenderMode
        self._globalPlotDefaults = globalPlotDefaults
        self._chartStyleOverrides = chartStyleOverrides
        self.onStyleChange = onStyleChange
        self.activeLayout = activeLayout
        self.axisRangeOverride = axisRangeOverride
        self.onAxisBoundUpdate = onAxisBoundUpdate
        self.sourceResetToken = sourceResetToken
        self.supplementalContent = { EmptyView() }
        self.content = content
    }
}
