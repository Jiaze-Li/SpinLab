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
    /// Called when the user commits a title/axis override change; triggers rerender.
    var onTitleOverride: ((String) -> Void)? = nil
    var onXLabelOverride: ((String) -> Void)? = nil
    var onYLabelOverride: ((String) -> Void)? = nil
    /// Current series label overrides (for chip display and inline rename pre-fill).
    var activeSeriesLabelOverrides: [String: String] = [:]
    /// Called with (labelKey, newLabel) when the user renames a series chip.
    var onRenameSeriesLabel: ((String, String) -> Void)? = nil
    @ViewBuilder var extraContent: () -> Extra

    var body: some View {
        WorkbenchPlotControlsPanel(
            seriesRenderMode: $seriesRenderMode,
            chartStyleOverrides: $chartStyleOverrides,
            onStyleChange: onChange,
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)

                Text("Gap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0.15", value: $minGapFraction, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                    .font(.caption)
                    .onSubmit { onChange?() }
            }

            // Row 2: Title template + Grid
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
            }

            // Row 3: Label overrides — visible when any override callback is wired up
            if onTitleOverride != nil || onXLabelOverride != nil || onYLabelOverride != nil {
                labelOverrideRow
            }

            // Workflow-specific extra rows
            extraContent()
        }
        .onChange(of: activeTab) { _, _ in onChange?() }
    }

    @ViewBuilder
    private var labelOverrideRow: some View {
        HStack(spacing: 10) {
            if let cb = onTitleOverride {
                LabelOverrideField(label: "Title", currentValue: activeTitleOverride, onCommit: { cb($0); onChange?() })
            }
            if let cb = onXLabelOverride {
                LabelOverrideField(label: "X", currentValue: activeXLabelOverride, onCommit: { cb($0); onChange?() })
            }
            if let cb = onYLabelOverride {
                LabelOverrideField(label: "Y", currentValue: activeYLabelOverride, onCommit: { cb($0); onChange?() })
            }
        }
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
        chartStyleOverrides: Binding<[String: String]>,
        seriesOrderPayload: WorkbenchPlotPayload? = nil,
        currentSeriesOrder: [String]? = nil,
        canReorderSeries: Bool = false,
        onSeriesOrderCommit: (([String]) -> Void)? = nil,
        onChange: (() -> Void)? = nil,
        activeTitleOverride: String = "",
        activeXLabelOverride: String = "",
        activeYLabelOverride: String = "",
        onTitleOverride: ((String) -> Void)? = nil,
        onXLabelOverride: ((String) -> Void)? = nil,
        onYLabelOverride: ((String) -> Void)? = nil,
        activeSeriesLabelOverrides: [String: String] = [:],
        onRenameSeriesLabel: ((String, String) -> Void)? = nil
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
        self._chartStyleOverrides = chartStyleOverrides
        self.seriesOrderPayload = seriesOrderPayload
        self.currentSeriesOrder = currentSeriesOrder
        self.canReorderSeries = canReorderSeries
        self.onSeriesOrderCommit = onSeriesOrderCommit
        self.onChange = onChange
        self.activeTitleOverride = activeTitleOverride
        self.activeXLabelOverride = activeXLabelOverride
        self.activeYLabelOverride = activeYLabelOverride
        self.onTitleOverride = onTitleOverride
        self.onXLabelOverride = onXLabelOverride
        self.onYLabelOverride = onYLabelOverride
        self.activeSeriesLabelOverrides = activeSeriesLabelOverrides
        self.onRenameSeriesLabel = onRenameSeriesLabel
        self.extraContent = { EmptyView() }
    }
}

// MARK: - LabelOverrideField

/// Compact commit-on-submit text field for title/axis label overrides.
/// Does not fire on every keystroke — only on Return or focus-loss commit.
struct LabelOverrideField: View {
    let label: String
    let currentValue: String
    let onCommit: (String) -> Void

    @State private var editText: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
            TextField(label, text: $editText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(minWidth: 60, maxWidth: 140)
                .focused($focused)
                .onSubmit { onCommit(editText) }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { onCommit(editText) }
                }
        }
        .task(id: currentValue) {
            if !focused { editText = currentValue }
        }
    }
}
