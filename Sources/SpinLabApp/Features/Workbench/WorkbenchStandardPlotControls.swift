import SwiftUI

// MARK: - WorkbenchStandardPlotControls

/// Two-row plot controls layout shared by all stacked-curve workflows.
///
/// Row 1: Tab picker + Stack offset slider + Gap input
/// Row 2: Title template field + Grid toggle
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
    var onChange: (() -> Void)? = nil
    @ViewBuilder var extraContent: () -> Extra

    var body: some View {
        WorkbenchPlotControlsPanel(
            seriesRenderMode: $seriesRenderMode,
            chartStyleOverrides: $chartStyleOverrides,
            onStyleChange: onChange
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
        chartStyleOverrides: Binding<[String: String]>,
        onChange: (() -> Void)? = nil
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
        self.onChange = onChange
        self.extraContent = { EmptyView() }
    }
}
