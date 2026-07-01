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
        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                content()
                // Shell-level: render mode + tick density in one row
                HStack(spacing: 8) {
                    Text("Draw")
                        .font(WorkbenchUIStyle.controlLabelFont)
                        .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                    Picker("", selection: $seriesRenderMode) {
                        Text("Line").tag(SeriesRenderMode.line)
                        Text("Scatter").tag(SeriesRenderMode.scatter)
                        Text("Line+Scatter").tag(SeriesRenderMode.lineAndScatter)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: seriesRenderMode) { _, _ in onStyleChange?() }
                    Spacer(minLength: 8)
                    Text("Ticks")
                        .font(WorkbenchUIStyle.controlLabelFont)
                        .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                        .fixedSize()
                    tickDensityStepper(label: "X", key: "tickTargetX", fallback: 6)
                    tickDensityStepper(label: "Y", key: "tickTargetY", fallback: 5)
                }
                // Shell-level: line/scatter appearance + axis range overrides on one row
                HStack(spacing: 12) {
                    WorkbenchSeriesAppearanceControls(
                        globalPlotDefaults: $globalPlotDefaults,
                        onStyleChange: onStyleChange
                    )
                    if onAxisBoundUpdate != nil {
                        WorkbenchAxisRangeControls(
                            activeLayout: activeLayout,
                            axisRangeOverride: axisRangeOverride,
                            sourceResetToken: sourceResetToken,
                            onBoundUpdate: { bound, value in
                                onAxisBoundUpdate?(bound, value)
                            }
                        )
                    }
                }
                // Shell-level controls: font sizes
                fontSizeRow
                supplementalContent()
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var fontSizeRow: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        HStack(spacing: 10) {
            SharedPlotFontSizePicker(
                label: "Legend",
                key: "legendFontSize",
                current: style.legendFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange,
                labelFont: .system(size: 12)
            )
            SharedPlotFontSizePicker(
                label: "Point",
                key: "pointLabelFontSize",
                current: style.pointLabelFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange,
                labelFont: .system(size: 12)
            )
        }
    }

    @ViewBuilder
    private func tickDensityStepper(label: String, key: String, fallback: Int) -> some View {
        let current = chartStyleOverrides[key].flatMap { Int($0) } ?? fallback
        HStack(spacing: 4) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            Stepper(
                value: Binding<Int>(
                    get: { current },
                    set: { newVal in
                        chartStyleOverrides[key] = "\(newVal)"
                        onStyleChange?()
                    }
                ),
                in: 2...20
            ) {
                Text("\(current)")
                    .font(WorkbenchUIStyle.controlValueFont)
                    .frame(width: 20)
            }
                .frame(width: 90)
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
