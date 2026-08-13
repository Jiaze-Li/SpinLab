import SwiftUI

/// 3ω workflow workspace — left column (search/action bar/plot controls/results).
struct ThreeOmegaWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

        WorkflowWorkspaceLeftColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            searchExtra: {
                ThreeOmegaRTSearchField()
                    .environment(appState)
            },
            plotControls: {
                ThreeOmegaPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() },
            actionBarTrailing: {
                ThreeOmegaActionBarTabPicker()
                    .environment(appState)
            }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=ThreeOmega")
        }
    }
}

/// 3ω workflow workspace — right column (results/status/scaling law summary).
struct ThreeOmegaWorkspaceRightView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

        WorkflowWorkspaceRightColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            rightExtra: {
                if store.tabs.activeTab == .scaling {
                    VStack(alignment: .leading, spacing: 12) {
                        ThreeOmegaTransportStatusPanel(status: store.transportDerivedStatus)
                            .equatable()
                        if let sr = store.scalingResult {
                            ThreeOmegaScalingResultPanel(result: sr)
                                .equatable()
                        }
                    }
                }
            }
        )
    }
}

// MARK: - Action-bar tab picker (all 3ω tabs)

/// Tab picker only — rendered in the workflow action bar's trailing slot, after Load.
/// Stack offset / gap live inline next to the title template field instead (see
/// `ThreeOmegaSpacingInlineControls` below); this keeps the two halves of the old
/// `WorkbenchPlotNavigationStrip` row visible in their new locations without duplicating
/// either control.
private struct ThreeOmegaActionBarTabPicker: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        WorkbenchPlotTabPicker(
            activeTab: $store.tabs.activeTab,
            tabs: ThreeOmegaWorkbenchTab.visibleTabs,
            tabLabel: { $0.rawValue },
            onChange: { oldValue, newValue in
                print("[PERF][tabs] activeTab changed old=\(oldValue) new=\(newValue)")
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "threeOmegaTabSwitch")
            }
        )
    }
}

/// Stack offset slider + gap field only — rendered next to the title template row on
/// whichever plot-controls path is active (temperature dependence vs. scaling/RAHE).
/// Both paths bind the same workspace-level `stackOffsetMultiplier`/`minGapFraction`, so
/// this is the single place either path renders them — never both at once.
private struct ThreeOmegaSpacingInlineControls: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        WorkbenchPlotSpacingInlineControls(
            stackOffset: $store.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $store.minGapFraction,
            onStackChange: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "threeOmegaStackOffsetChange")
            },
            onGapSubmit: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "threeOmegaGapSubmit")
            },
            sliderWidth: 110
        )
    }
}

// MARK: - Plot Controls Panel (3ω-specific: RAHE method + overlays)

private struct ThreeOmegaPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace
        @Bindable var workbench = appState.workbench

        VStack(alignment: .leading, spacing: 0) {
            if store.tabs.activeTab == .temperatureDependence {
                ThreeOmegaTemperatureDependencePlotControlsPanel()
                    .environment(appState)
            } else {
                WorkbenchStandardPlotControls(
                    activeTab: $store.tabs.activeTab,
                    tabLabel: { $0.rawValue },
                    stackOffset: $store.stackOffsetMultiplier,
                    stackRange: 0...1.6,
                    minGapFraction: $store.minGapFraction,
                    showGrid: $store.tabs.showPlotGrid,
                    showTitle: Binding(
                        get: { store.tabs.activeState.showTitle },
                        set: { store.tabs.updateShowTitle($0) }
                    ),
                    titleTemplate: $store.titleTemplate,
                    numericDisplayCache: store.cachedSampleNumericDisplay,
                    seriesRenderMode: $store.tabs.seriesRenderMode,
                    globalPlotDefaults: $workbench.globalPlotDefaults,
                    chartStyleOverrides: $store.tabs.chartStyleOverrides,
                    seriesOrderPayload: store.activeChartManifestPayload,
                    seriesControlModel: store.tabs.activeOutput.seriesControlModel,
                    currentSeriesOrder: store.activeSeriesOrder,
                    canReorderSeries: store.canReorderSeries,
                    onSeriesOrderCommit: { order in store.updateSeriesOrder(order) },
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "threeOmegaStyleChange")
                    },
                    activeTitleOverride: store.tabs.activeState.titleOverride,
                    activeXLabelOverride: store.tabs.activeState.xLabelOverride,
                    activeYLabelOverride: store.tabs.activeState.yLabelOverride,
                    renderedTitle: store.tabs.activeLayout?.chartTitle ?? "",
                    renderedXLabel: store.tabs.activeLayout?.xAxisLabel ?? "",
                    renderedYLabel: store.tabs.activeLayout?.yAxisLabel ?? "",
                    sourceResetToken: store.tabs.activeSourceIdentityKey,
                    onTitleOverride: { store.updatePlotTitle($0) },
                    onXLabelOverride: { store.updateXAxisLabel($0) },
                    onYLabelOverride: { store.updateYAxisLabel($0) },
                    activeSeriesLabelOverrides: store.seriesLabelOverrides,
                    activeSeriesHiddenKeys: store.tabs.activeState.hiddenSeriesKeys,
                    onRenameSeriesLabel: { key, label in store.updateSeriesLabel(identityKey: key, newLabel: label) },
                    onVisibilityChange: { key, isVisible in store.updateSeriesVisibility(identityKey: key, isVisible: isVisible) },
                    activeLayout: store.tabs.activeLayout,
                    axisRangeOverride: store.tabs.activeState.axisRangeOverride,
                    onAxisBoundUpdate: { bound, value in
                        store.updateAxisBound(bound, value: value)
                        appState.scheduleInteractionSnapshotFlush(source: "threeOmegaAxisBound")
                    },
                    onResetRanges: {
                        store.resetAxisRanges()
                        appState.scheduleInteractionSnapshotFlush(source: "threeOmegaAxisRangesReset")
                    },
                    tickOverride: store.tabs.activeState.tickOverride,
                    onTickCountUpdate: { axis, count in
                        store.updateTickCount(axis: axis, count: count)
                        appState.scheduleInteractionSnapshotFlush(source: "threeOmegaTickCount")
                    },
                    hideTabRow: true,
                    titleRowTrailingContent: {
                        ThreeOmegaSpacingInlineControls()
                            .environment(appState)
                    },
                    extraContent: {
                        VStack(alignment: .leading, spacing: 8) {
                            if store.tabs.activeTab == .scaling {
                                WorkbenchPlotControlsPluginSection {
                                    ThreeOmegaGeometryPanel()
                                }
                            }

                            if store.tabs.activeTab == .rahe1omegaVsDevice || store.tabs.activeTab == .rahe3omegaVsDevice {
                                WorkbenchPlotControlsPluginSection {
                                    HStack {
                                        Picker("RAHE Method", selection: Binding<ThreeOmegaV3Method>(
                                            get: { store.activeRAHEMethod ?? .highField },
                                            set: { store.updateRAHEMethod($0) }
                                        )) {
                                            ForEach(ThreeOmegaV3Method.allCases) { method in
                                                Text(method.rawValue).tag(method)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: 220)
                                    }
                                }
                            }
                        }
                    }
                )
            }
        }
    }
}

private struct ThreeOmegaTemperatureDependencePlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace
        @Bindable var bindableStore = appState.workbench.threeOmegaWorkspace
        @Bindable var workbench = appState.workbench
        let renderedPayload = store.tabs.output(for: .temperatureDependence).dualAxisPayload

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                DualAxisPlotControlsPanel(
                    displayState: $bindableStore.temperatureDependenceDisplayState,
                    titleTemplate: $bindableStore.titleTemplate,
                    globalPlotDefaults: $workbench.globalPlotDefaults,
                    chartStyleOverrides: $bindableStore.tabs.chartStyleOverrides,
                    numericDisplayCache: store.cachedSampleNumericDisplay,
                    activeLayout: store.tabs.output(for: .temperatureDependence).dualAxisLayout,
                    sourceResetToken: store.tabs.activeSourceIdentityKey,
                    renderedTitle: renderedPayload?.title ?? "",
                    renderedXLabel: renderedPayload?.xLabel ?? "",
                    renderedLeftYLabel: renderedPayload?.leftYLabel ?? "",
                    renderedRightYLabel: renderedPayload?.rightYLabel ?? "",
                    onDisplayStateChange: {
                        store.rerenderTemperatureDependenceForDualAxisControlChange()
                        appState.scheduleInteractionSnapshotFlush(source: "threeOmegaDualAxisControlChange")
                    },
                    onResetRanges: {
                        bindableStore.temperatureDependenceDisplayState.axisRangeOverride = nil
                        store.rerenderTemperatureDependenceForDualAxisControlChange()
                        appState.scheduleInteractionSnapshotFlush(source: "threeOmegaDualAxisRangesReset")
                    },
                    titleRowTrailingContent: {
                        ThreeOmegaSpacingInlineControls()
                            .environment(appState)
                    }
                )
                WorkbenchPlotControlsPluginSection {
                    ThreeOmegaTransportGeometryFields(
                        geometry: $bindableStore.geometry,
                        v3Method: $bindableStore.v3Method,
                        onCommit: {
                            print("[PERF][scaling] geometry commit")
                            store.refreshTransportDerivedPlots(reason: "geometry changed")
                            appState.scheduleInteractionSnapshotFlush(source: "threeOmegaGeometryChange")
                        }
                    )
                    .equatable()
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Geometry Panel (Scaling tab: full geometry + fit-range editor)
//
// Geometry fields (Lxx/Lxy/d/method) are shared by Scaling and Temperature Dependence —
// both tabs derive their plotted values from `scalingResult`, which is computed from
// `geometry`. The fit-range editor below only affects Scaling's linear-fit segments
// (`ThreeOmegaScalingResult.segments`) and has no effect on Temperature Dependence, which
// only reads `ThreeOmegaScalingResult.points` — so it is Scaling-only and TD does not
// embed the full panel, only `ThreeOmegaTransportGeometryFields` above.

private struct ThreeOmegaGeometryPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace
        let _ = { if WorkbenchPerformanceDiagnostics.isEnabled { print("[PERF][scaling] build geometryPanel") } }()

        let commitFitRanges = {
            print("[PERF][scaling] fitRange commit")
            store.refreshTransportDerivedPlots(reason: "fit ranges changed")
            appState.scheduleInteractionSnapshotFlush(source: "threeOmegaFitRangesChange")
        }

        VStack(alignment: .leading, spacing: 8) {
            ThreeOmegaTransportGeometryFields(
                geometry: $store.geometry,
                v3Method: $store.v3Method,
                onCommit: {
                    print("[PERF][scaling] geometry commit")
                    store.refreshTransportDerivedPlots(reason: "geometry changed")
                    appState.scheduleInteractionSnapshotFlush(source: "threeOmegaGeometryChange")
                }
            )
            .equatable()
            ThreeOmegaFitRangeEditor(
                fitRanges: $store.fitRanges,
                onAdd: {
                    store.addFitRange()
                    commitFitRanges()
                },
                onRemove: { id in
                    store.removeFitRange(id: id)
                    commitFitRanges()
                },
                onCommit: commitFitRanges
            )
            .equatable()
        }
    }
}

private extension ThreeOmegaV3Method {
    var geometryDisplayLabel: String {
        switch self {
        case .highField:
            return "HFE"
        case .window:
            return "WA"
        }
    }
}

/// Local row chrome for the ThreeOmega geometry/fit block only.
///
/// Unlike the shared `ControlRow` (whose label is trailing-aligned within its fixed
/// width, indenting short labels like "Lxx"/"Fit" relative to flush-left labels like
/// "Range"/"Font" above), this leading-aligns the label so its left edge sits flush
/// with the container, matching the common controls above it.
private struct ThreeOmegaFieldRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat
    var spacing: CGFloat = 6
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
                .frame(width: labelWidth, alignment: .leading)
                .layoutPriority(1)
            content()
        }
    }
}

/// Fixed, always-expanded single-row layout — no `ViewThatFits` width probing.
/// Takes narrow bindings + a commit callback rather than the whole store, so an
/// `Equatable` conformance (see below) can skip rebuilds driven by unrelated
/// store changes (tab switch, style/font edits, scaling result updates).
private struct ThreeOmegaTransportGeometryFields: View {
    @Binding var geometry: ThreeOmegaGeometry
    @Binding var v3Method: ThreeOmegaV3Method
    let onCommit: () -> Void

    var body: some View {
        let _ = { if WorkbenchPerformanceDiagnostics.isEnabled { print("[PERF][scaling] build geometryFields") } }()
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            geometryNumberFieldRow(
                label: "Lxx",
                value: $geometry.lxx,
                placeholder: "26",
                unit: "μm",
                labelWidth: 36,
                fieldMinWidth: 44,
                fieldIdealWidth: 60,
                fieldMaxWidth: 60
            )
            geometryNumberFieldRow(
                label: "Lxy",
                value: $geometry.lxy,
                placeholder: "21",
                unit: "μm",
                labelWidth: 36,
                fieldMinWidth: 44,
                fieldIdealWidth: 60,
                fieldMaxWidth: 60
            )
            geometryNumberFieldRow(
                label: "d",
                value: $geometry.dNm,
                placeholder: "30",
                unit: "nm",
                labelWidth: 24,
                fieldMinWidth: 40,
                fieldIdealWidth: 52,
                fieldMaxWidth: 52
            )
            geometryMethodField(
                value: $v3Method,
                labelWidth: 52
            )
        }
        .onChange(of: v3Method) { _, _ in onCommit() }
    }

    @ViewBuilder
    private func geometryNumberFieldRow(
        label: String,
        value: Binding<Double>,
        placeholder: String,
        unit: String,
        labelWidth: CGFloat,
        fieldMinWidth: CGFloat,
        fieldIdealWidth: CGFloat,
        fieldMaxWidth: CGFloat
    ) -> some View {
        ThreeOmegaFieldRow(label: label, labelWidth: labelWidth) {
            GeometryValueField(
                placeholder: placeholder,
                value: value,
                fieldMinWidth: fieldMinWidth,
                fieldIdealWidth: fieldIdealWidth,
                fieldMaxWidth: fieldMaxWidth,
                onCommit: onCommit
            )
            Text(unit)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func geometryMethodField(value: Binding<ThreeOmegaV3Method>, labelWidth: CGFloat) -> some View {
        ThreeOmegaFieldRow(label: "V(3ω)", labelWidth: labelWidth) {
            Picker("", selection: value) {
                ForEach(ThreeOmegaV3Method.allCases) { method in
                    Text(method.geometryDisplayLabel).tag(method)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 84, idealWidth: 104, maxWidth: 104, alignment: .leading)
            .help(value.wrappedValue.rawValue)
            .accessibilityLabel("V(3ω) method \(value.wrappedValue.rawValue)")
        }
    }
}

extension ThreeOmegaTransportGeometryFields: Equatable {
    static func == (lhs: ThreeOmegaTransportGeometryFields, rhs: ThreeOmegaTransportGeometryFields) -> Bool {
        lhs.geometry == rhs.geometry && lhs.v3Method == rhs.v3Method
    }
}

/// Text field for a required Double geometry value. Edits accumulate in local
/// text state and only write back to `value` (and trigger `onCommit`, which
/// refreshes derived plots + flushes the snapshot) when the user submits —
/// not on every keystroke. Commits on Return AND on focus loss (matching
/// `PlotAxisBoundField`'s pattern) — without the focus-loss commit, clicking
/// away from an edited field silently discards the edit: the text field still
/// *shows* the typed value, but `value` (and every downstream calculation)
/// keeps the old one, with no visual indication anything is wrong.
private struct GeometryValueField: View {
    let placeholder: String
    @Binding var value: Double
    let fieldMinWidth: CGFloat
    let fieldIdealWidth: CGFloat
    let fieldMaxWidth: CGFloat
    let onCommit: () -> Void

    @State private var text: String = ""
    @State private var didAppear = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: fieldMinWidth, idealWidth: fieldIdealWidth, maxWidth: fieldMaxWidth)
            .focused($focused)
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                text = Self.format(value)
            }
            .onChange(of: value) { _, newValue in
                let formatted = Self.format(newValue)
                if text != formatted { text = formatted }
            }
            .onSubmit {
                commit()
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let parsed = Double(trimmed) else {
            text = Self.format(value)
            return
        }
        guard parsed != value else { return }
        value = parsed
        onCommit()
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Matches the "Lxx"/"Lxy" label width in `ThreeOmegaTransportGeometryFields` so the
/// Fit row's fields start at the same column, whether Fit is on the inline row or
/// wraps to its own continuation line (the wrapped "to" line's Spacer is derived
/// from this, not a magic number).
private let threeOmegaFitLabelWidth: CGFloat = 36

/// Fixed, always-expanded grouped layout — no `ViewThatFits` width probing.
/// Fit ranges render two-per-row (Fit 1/Fit 2, Fit 3/Fit 4, …) with no dividers
/// between them, reading as one compact grouped list rather than separate
/// sections. Takes a narrow `fitRanges` binding + callbacks rather than the
/// whole store, so `Equatable` (below) can skip rebuilds driven by unrelated
/// store changes.
private struct ThreeOmegaFitRangeEditor: View {
    @Binding var fitRanges: [ThreeOmegaFitRange]
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void
    let onCommit: () -> Void

    var body: some View {
        let _ = { if WorkbenchPerformanceDiagnostics.isEnabled { print("[PERF][scaling] build fitRangeEditor") } }()

        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: fitRanges.count, by: 2)), id: \.self) { rowStart in
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    fitRangeInlineRow(
                        index: rowStart,
                        range: $fitRanges[rowStart],
                        rangeCount: fitRanges.count,
                        showAddButton: fitRanges.count == 1
                    )
                    if rowStart + 1 < fitRanges.count {
                        fitRangeInlineRow(
                            index: rowStart + 1,
                            range: $fitRanges[rowStart + 1],
                            rangeCount: fitRanges.count,
                            showAddButton: false
                        )
                    }
                }
            }

            if fitRanges.count > 1 {
                HStack {
                    Button {
                        onAdd()
                    } label: {
                        Label("Add fit range", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .labelStyle(.titleAndIcon)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func fitRangeInlineRow(
        index: Int,
        range: Binding<ThreeOmegaFitRange>,
        rangeCount: Int,
        showAddButton: Bool
    ) -> some View {
        ThreeOmegaFieldRow(
            label: rangeCount == 1 ? "Fit" : "Fit \(index + 1)",
            labelWidth: threeOmegaFitLabelWidth
        ) {
            FitRangeBoundField(placeholder: "T_lo (K)", value: range.tLo, onCommit: onCommit)
            Text("to")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(.secondary)
                .fixedSize()
            FitRangeBoundField(placeholder: "T_hi (K)", value: range.tHi, onCommit: onCommit)
            Button {
                onRemove(range.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .accessibilityLabel("Remove fit range")
            .disabled(rangeCount <= 1)

            if showAddButton {
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .accessibilityLabel("Add fit range")
            }
        }
    }
}

extension ThreeOmegaFitRangeEditor: Equatable {
    static func == (lhs: ThreeOmegaFitRangeEditor, rhs: ThreeOmegaFitRangeEditor) -> Bool {
        lhs.fitRanges == rhs.fitRanges
    }
}

/// Takes the status value directly (rather than reading through the store)
/// so `Equatable` reflects exactly what this panel renders — a tab switch or
/// style/font edit elsewhere in the workspace does not change `status` and so
/// does not force a rebuild via `.equatable()`.
private struct ThreeOmegaTransportStatusPanel: View {
    let status: ThreeOmegaTransportDerivedStatus

    var body: some View {
        let _ = { if WorkbenchPerformanceDiagnostics.isEnabled { print("[PERF][scaling] build statusPanel") } }()

        GroupBox("Scaling Status") {
            VStack(alignment: .leading, spacing: 6) {
                switch status {
                case .idle:
                    Text("Scaling Law waits for Analyze.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .refreshing:
                    Text("Updating Scaling Law…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .missing(let requirements):
                    Text("Scaling Law unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Missing: \(requirements.map(\.rawValue).joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.orange)
                case .ready:
                    Text("Scaling Law is up to date.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .unavailable(let message):
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

extension ThreeOmegaTransportStatusPanel: Equatable {}

/// Text field for an optional Double temperature bound.
private struct FitRangeBoundField: View {
    let placeholder: String
    @Binding var value: Double?
    let onCommit: () -> Void

    @State private var text: String = ""
    @State private var didAppear = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 68)
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                text = Self.format(value)
            }
            .onChange(of: value) { _, newValue in
                let formatted = Self.format(newValue)
                if text != formatted { text = formatted }
            }
            .onSubmit {
                commit()
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard value != nil else { return }
            value = nil
            onCommit()
        } else if let parsed = Double(trimmed) {
            guard parsed != value else { return }
            value = parsed
            onCommit()
        } else {
            text = Self.format(value)
        }
    }

    private static func format(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? ""
    }
}

// MARK: - Scaling result panel

private struct ThreeOmegaScalingResultPanel: View {
    let result: ThreeOmegaScalingResult

    var body: some View {
        let _ = { if WorkbenchPerformanceDiagnostics.isEnabled { print("[PERF][scaling] build resultPanel") } }()
        GroupBox("Scaling Law Fit Results") {
            VStack(alignment: .leading, spacing: 6) {
                if result.isSingleFullRange(), let seg = result.segments.first {
                    Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "R² = %.4f", seg.rSquared))
                        .font(.system(.body, design: .monospaced))
                    Text("\(result.points.count) data point(s)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(result.segments.enumerated()), id: \.element.id) { idx, seg in
                        if idx > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(seg.tLo.rounded())) K – \(Int(seg.tHi.rounded())) K  (n=\(seg.pointCount))")
                                .font(.callout.bold())
                                .foregroundStyle(.secondary)
                            Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                                .font(.system(.callout, design: .monospaced))
                            Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                                .font(.system(.callout, design: .monospaced))
                            Text(String(format: "R² = %.4f", seg.rSquared))
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                ForEach(result.warnings, id: \.self) { w in
                    Text("⚠ \(w)")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

extension ThreeOmegaScalingResultPanel: Equatable {}

// MARK: - RT search field with popover

private struct ThreeOmegaRTSearchField: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("RT file…", text: Binding(
                    get: { store.rtQuery },
                    set: { store.updateRTQuery($0) }
                ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit {
                        store.clearRTSelection()
                        appState.workbench.runThreeOmegaRTSearch(
                            libraryRootPath: libraryRoot,
                            librarySettings: appState.library.librarySettings
                        )
                    }
                    .popover(isPresented: $store.showRTPopover, arrowEdge: .bottom) {
                        ThreeOmegaRTPopover()
                            .environment(appState)
                    }

                Button {
                    store.clearRTSelection()
                    appState.workbench.runThreeOmegaRTSearch(
                        libraryRootPath: libraryRoot,
                        librarySettings: appState.library.librarySettings
                    )
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Search RT files")
                .disabled(store.rtQuery.trimmingCharacters(in: .whitespaces).isEmpty || store.isRTSearching || libraryRoot == nil)
            }

            if let hit = store.selectedRTHit {
                let fullName = hit.measurementFilePath.components(separatedBy: "/").last ?? hit.id
                Text("✓ \(fullName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fullName)
            }
        }
        .frame(width: 170, alignment: .leading)
    }
}

private struct ThreeOmegaRTPopover: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

        VStack(alignment: .leading, spacing: 6) {
            if store.isRTSearching {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Searching…").font(.caption)
                }
            } else if store.rtSearchResults.isEmpty {
                Text(store.rtSearchMessage ?? "No results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(store.rtSearchMessage ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.rtSearchResults) { hit in
                            Button {
                                store.selectRTHit(hit)
                                appState.scheduleInteractionSnapshotFlush(source: "threeOmegaRTHitSelect")
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.measurementFilePath.components(separatedBy: "/").last ?? hit.id)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(hit.conditionSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 360)
            }
        }
        .padding(8)
        .frame(width: 320)
    }
}
