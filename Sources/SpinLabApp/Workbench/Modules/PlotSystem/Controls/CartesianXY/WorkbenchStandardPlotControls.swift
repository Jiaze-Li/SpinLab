import SwiftUI

// MARK: - WorkbenchStandardPlotControls

/// Two-row plot controls layout shared by all stacked-curve workflows.
///
/// Row 1: Tab picker + Stack offset slider + Gap input
/// Row 2: Title template field + Grid toggle
/// Row 3: Label overrides (title, X axis, Y axis) — shown when callbacks are non-nil
///
/// Workflow-specific controls (e.g. RAHE method picker) go in `extraContent`.
struct WorkbenchStandardPlotControls<Tab: CaseIterable & Hashable & Identifiable, Extra: View>: View
    where Tab.AllCases: RandomAccessCollection
{
    @Binding var activeTab: Tab
    let tabLabel: (Tab) -> String
    @Binding var stackOffset: Double
    var stackRange: ClosedRange<Double> = 0...1.6
    @Binding var minGapFraction: Double
    @Binding var showGrid: Bool
    @Binding var titleTemplate: String
    let numericDisplayCache: [String: [String: String]]
    @Binding var seriesRenderMode: SeriesRenderMode
    @Binding var globalPlotDefaults: [String: String]
    @Binding var chartStyleOverrides: [String: String]
    var seriesOrderPayload: WorkbenchPlotPayload? = nil
    var currentSeriesOrder: [String]? = nil
    var canReorderSeries: Bool = false
    var onSeriesOrderCommit: (([String]) -> Void)? = nil
    var onChange: (() -> Void)? = nil
    /// Current title override for the active tab (empty = no override).
    var activeTitleOverride: String = ""
    /// Current X-axis label override for the active tab.
    var activeXLabelOverride: String = ""
    /// Current Y-axis label override for the active tab.
    var activeYLabelOverride: String = ""
    /// Rendered default title from the active layout (shown in the field when no override is set).
    var renderedTitle: String = ""
    /// Rendered default X-axis label from the active layout.
    var renderedXLabel: String = ""
    /// Rendered default Y-axis label from the active layout.
    var renderedYLabel: String = ""
    /// Identity token for the analyzed source backing the active tab.
    /// When this changes, inline text fields must discard stale local edit state.
    var sourceResetToken: String = ""
    /// Called when the user commits a title/axis override change; triggers rerender.
    var onTitleOverride: ((String) -> Void)? = nil
    var onXLabelOverride: ((String) -> Void)? = nil
    var onYLabelOverride: ((String) -> Void)? = nil
    /// Current series label overrides (for chip display and inline rename pre-fill).
    var activeSeriesLabelOverrides: [String: String] = [:]
    /// Called with (labelKey, newLabel) when the user renames a series chip.
    var onRenameSeriesLabel: ((String, String) -> Void)? = nil
    /// Layout from the most recent render — provides auto axis ranges for the range controls.
    var activeLayout: WorkbenchPlotLayout? = nil
    /// Current per-tab axis range override.
    var axisRangeOverride: AxisRangeOverride? = nil
    /// Called when the user edits a single axis range bound. Triggers a re-render.
    var onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil
    /// Current per-tab point tag visibility. Only read when onPointTagsToggle is non-nil.
    var showPointTagsForActiveTab: Bool = false
    /// Called when the user toggles "Point Tags". Non-nil enables the toggle.
    var onPointTagsToggle: ((Bool) -> Void)? = nil
    @ViewBuilder var extraContent: () -> Extra

    var body: some View {
        WorkbenchPlotControlsPanel(
            seriesRenderMode: $seriesRenderMode,
            globalPlotDefaults: $globalPlotDefaults,
            chartStyleOverrides: $chartStyleOverrides,
            onStyleChange: onChange,
            activeLayout: activeLayout,
            axisRangeOverride: axisRangeOverride,
            onAxisBoundUpdate: onAxisBoundUpdate,
            sourceResetToken: sourceResetToken,
            supplementalContent: {
                if canReorderSeries {
                    WorkbenchSeriesOrderPanel(
                        payload: seriesOrderPayload,
                        currentSeriesOrder: currentSeriesOrder,
                        isVisible: canReorderSeries,
                        onCommit: { order in
                            onSeriesOrderCommit?(order)
                            onChange?()
                        },
                        seriesLabelOverrides: activeSeriesLabelOverrides,
                        onRenameLabel: onRenameSeriesLabel.map { callback in
                            { key, label in
                                callback(key, label)
                                onChange?()
                            }
                        }
                    )
                } else {
                    EmptyView()
                }
            }
        ) {
            // Row 1: Tab + Stack + Gap
            HStack(spacing: 8) {
                Picker("Tab", selection: $activeTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tabLabel(tab)).tag(tab)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)

                Slider(value: $stackOffset, in: stackRange, step: 0.1)
                    .onChange(of: stackOffset) { _, _ in onChange?() }
                Text(String(format: "%.1f×", stackOffset))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)

                Text("Gap")
                    .font(WorkbenchUIStyle.controlLabelFont)
                    .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                TextField("0.15", value: $minGapFraction, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                    .font(.system(size: 12))
                    .onSubmit { onChange?() }
            }

            // Row 2: Title template + Grid + Point Tags (when supported by active tab)
            HStack(alignment: .top, spacing: 12) {
                WorkbenchTitleTemplateField(
                    titleTemplate: $titleTemplate,
                    numericDisplayCache: numericDisplayCache,
                    onChange: onChange
                )
                Toggle("Grid", isOn: $showGrid)
                    .toggleStyle(.checkbox)
                    .onChange(of: showGrid) { _, _ in onChange?() }
                    .padding(.top, 2)
                if let toggle = onPointTagsToggle {
                    Toggle("Point Tags", isOn: Binding(
                        get: { showPointTagsForActiveTab },
                        set: { toggle($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
                }
            }

            // Row 3: Label overrides — visible when any override callback is wired up
            if onTitleOverride != nil || onXLabelOverride != nil || onYLabelOverride != nil {
                SharedPlotTextControls(
                    titleOverride: activeTitleOverride,
                    xLabelOverride: activeXLabelOverride,
                    yLabelOverride: activeYLabelOverride,
                    renderedTitle: renderedTitle,
                    renderedXLabel: renderedXLabel,
                    renderedYLabel: renderedYLabel,
                    sourceResetToken: sourceResetToken,
                    onTitleOverride: { onTitleOverride?($0); onChange?() },
                    onXLabelOverride: { onXLabelOverride?($0); onChange?() },
                    onYLabelOverride: { onYLabelOverride?($0); onChange?() }
                )
            }

            // Workflow-specific extra rows
            extraContent()
        }
        .onChange(of: activeTab) { _, _ in onChange?() }
    }

}

extension WorkbenchStandardPlotControls where Extra == EmptyView {
    init(
        activeTab: Binding<Tab>,
        tabLabel: @escaping (Tab) -> String,
        stackOffset: Binding<Double>,
        stackRange: ClosedRange<Double> = 0...3,
        minGapFraction: Binding<Double>,
        showGrid: Binding<Bool>,
        titleTemplate: Binding<String>,
        numericDisplayCache: [String: [String: String]],
        seriesRenderMode: Binding<SeriesRenderMode>,
        globalPlotDefaults: Binding<[String: String]>,
        chartStyleOverrides: Binding<[String: String]>,
        seriesOrderPayload: WorkbenchPlotPayload? = nil,
        currentSeriesOrder: [String]? = nil,
        canReorderSeries: Bool = false,
        onSeriesOrderCommit: (([String]) -> Void)? = nil,
        onChange: (() -> Void)? = nil,
        activeTitleOverride: String = "",
        activeXLabelOverride: String = "",
        activeYLabelOverride: String = "",
        renderedTitle: String = "",
        renderedXLabel: String = "",
        renderedYLabel: String = "",
        sourceResetToken: String = "",
        onTitleOverride: ((String) -> Void)? = nil,
        onXLabelOverride: ((String) -> Void)? = nil,
        onYLabelOverride: ((String) -> Void)? = nil,
        activeSeriesLabelOverrides: [String: String] = [:],
        onRenameSeriesLabel: ((String, String) -> Void)? = nil,
        activeLayout: WorkbenchPlotLayout? = nil,
        axisRangeOverride: AxisRangeOverride? = nil,
        onAxisBoundUpdate: ((AxisRangeBound, Double?) -> Void)? = nil,
        showPointTagsForActiveTab: Bool = false,
        onPointTagsToggle: ((Bool) -> Void)? = nil
    ) {
        self._activeTab = activeTab
        self.tabLabel = tabLabel
        self._stackOffset = stackOffset
        self.stackRange = stackRange
        self._minGapFraction = minGapFraction
        self._showGrid = showGrid
        self._titleTemplate = titleTemplate
        self.numericDisplayCache = numericDisplayCache
        self._seriesRenderMode = seriesRenderMode
        self._globalPlotDefaults = globalPlotDefaults
        self._chartStyleOverrides = chartStyleOverrides
        self.seriesOrderPayload = seriesOrderPayload
        self.currentSeriesOrder = currentSeriesOrder
        self.canReorderSeries = canReorderSeries
        self.onSeriesOrderCommit = onSeriesOrderCommit
        self.onChange = onChange
        self.activeTitleOverride = activeTitleOverride
        self.activeXLabelOverride = activeXLabelOverride
        self.activeYLabelOverride = activeYLabelOverride
        self.renderedTitle = renderedTitle
        self.renderedXLabel = renderedXLabel
        self.renderedYLabel = renderedYLabel
        self.sourceResetToken = sourceResetToken
        self.onTitleOverride = onTitleOverride
        self.onXLabelOverride = onXLabelOverride
        self.onYLabelOverride = onYLabelOverride
        self.activeSeriesLabelOverrides = activeSeriesLabelOverrides
        self.onRenameSeriesLabel = onRenameSeriesLabel
        self.activeLayout = activeLayout
        self.axisRangeOverride = axisRangeOverride
        self.onAxisBoundUpdate = onAxisBoundUpdate
        self.showPointTagsForActiveTab = showPointTagsForActiveTab
        self.onPointTagsToggle = onPointTagsToggle
        self.extraContent = { EmptyView() }
    }
}
