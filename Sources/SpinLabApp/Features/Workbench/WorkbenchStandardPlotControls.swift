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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)

                Text("Gap")
                    .font(.system(size: 12))
                TextField("0.15", value: $minGapFraction, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                    .font(.system(size: 12))
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
        HStack(spacing: 16) {
            if let cb = onTitleOverride {
                LabelOverrideField(label: "Title", renderedDefault: renderedTitle, currentValue: activeTitleOverride, sourceResetToken: sourceResetToken, onCommit: { cb($0); onChange?() }, fieldMaxWidth: 200)
            }
            if let cb = onXLabelOverride {
                LabelOverrideField(label: "X", renderedDefault: renderedXLabel, currentValue: activeXLabelOverride, sourceResetToken: sourceResetToken, onCommit: { cb($0); onChange?() }, fieldMaxWidth: 80)
            }
            if let cb = onYLabelOverride {
                LabelOverrideField(label: "Y", renderedDefault: renderedYLabel, currentValue: activeYLabelOverride, sourceResetToken: sourceResetToken, onCommit: { cb($0); onChange?() }, fieldMaxWidth: 80)
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
        renderedTitle: String = "",
        renderedXLabel: String = "",
        renderedYLabel: String = "",
        sourceResetToken: String = "",
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
        self.renderedTitle = renderedTitle
        self.renderedXLabel = renderedXLabel
        self.renderedYLabel = renderedYLabel
        self.sourceResetToken = sourceResetToken
        self.onTitleOverride = onTitleOverride
        self.onXLabelOverride = onXLabelOverride
        self.onYLabelOverride = onYLabelOverride
        self.activeSeriesLabelOverrides = activeSeriesLabelOverrides
        self.onRenameSeriesLabel = onRenameSeriesLabel
        self.extraContent = { EmptyView() }
    }
}

// MARK: - LabelOverrideField

/// Compact text field for title/axis label overrides.
///
/// Displays the rendered default (from layout) when no override is set; switches to
/// primary styling when an override is active. Commits only when the user has actually
/// edited the field (isDirty gate prevents spurious focus-loss commits). A clear button
/// removes the override when one is active.
struct LabelOverrideField: View {
    let label: String
    /// Text currently rendered on the chart — shown (dimmed) when no override is set.
    let renderedDefault: String
    /// Active override value (empty = no override).
    let currentValue: String
    /// Token that changes when the analyzed source backing the field changes.
    /// This forces stale edit state to reset before any focus-loss commit can fire.
    let sourceResetToken: String
    let onCommit: (String) -> Void
    /// Maximum width for the text input field. Title uses a wider value than X/Y axis fields.
    var fieldMaxWidth: CGFloat = 120

    @State private var editText: String = ""
    @State private var isDirty: Bool = false
    @FocusState private var focused: Bool

    private var hasOverride: Bool { !currentValue.isEmpty }
    private var displayValue: String { currentValue.isEmpty ? renderedDefault : currentValue }
    private var committedTextBinding: Binding<String> {
        Binding(
            get: { editText },
            set: { newValue in
                editText = newValue
                isDirty = true
            }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 12)).fixedSize()
            TextField("", text: committedTextBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 40, maxWidth: fieldMaxWidth)
                .focused($focused)
                .onSubmit { commitIfDirty() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commitIfDirty() }
                }
            if hasOverride {
                Button {
                    onCommit("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }
        }
        .task(id: displayValue) {
            LabelOverrideFieldSync.applyDisplayValueChange(
                editText: &editText,
                isDirty: &isDirty,
                focused: focused,
                displayValue: displayValue
            )
        }
        .task(id: sourceResetToken) {
            LabelOverrideFieldSync.applySourceReset(
                editText: &editText,
                isDirty: &isDirty,
                focused: &focused,
                displayValue: displayValue
            )
        }
    }

    private func commitIfDirty() {
        guard isDirty else { return }
        isDirty = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Typing the rendered default back is treated as clearing the override
        let toCommit = trimmed == renderedDefault ? "" : trimmed
        onCommit(toCommit)
    }
}

enum LabelOverrideFieldSync {
    static func applyDisplayValueChange(
        editText: inout String,
        isDirty: inout Bool,
        focused: Bool,
        displayValue: String
    ) {
        guard !focused else { return }
        editText = displayValue
        isDirty = false
    }

    static func applySourceReset(
        editText: inout String,
        isDirty: inout Bool,
        focused: inout Bool,
        displayValue: String
    ) {
        editText = displayValue
        isDirty = false
        focused = false
    }

    static func commitIfDirty(
        editText: String,
        isDirty: inout Bool,
        renderedDefault: String,
        onCommit: (String) -> Void
    ) {
        guard isDirty else { return }
        isDirty = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        let toCommit = trimmed == renderedDefault ? "" : trimmed
        onCommit(toCommit)
    }
}
