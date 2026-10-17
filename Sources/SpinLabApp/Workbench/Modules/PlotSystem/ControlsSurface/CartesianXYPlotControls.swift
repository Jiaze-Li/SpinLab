import SwiftUI

/// Series-panel inputs of the Cartesian XY section.
struct CartesianXYSeriesControls {
    var payload: WorkbenchPlotPayload?
    var controlModel: SeriesControlModel?
    var currentOrder: [String]?
    var hiddenKeys: [String]
    var labelOverrides: [String: String]
    var canReorder: Bool
    var onOrderCommit: ([String]) -> Void
    var onVisibilityChange: (String, Bool) -> Void
    var onRenameLabel: (String, String) -> Void
}

/// All state and callbacks the `cartesianXY` Plot section needs (CS-28). Required callbacks
/// are non-optional so a workflow cannot remove a standard control by passing nil (CS-12).
struct CartesianXYControlsModel {
    var capabilities: CartesianXYCapabilities = []
    var titleTemplate: Binding<String>
    var numericDisplayCache: [String: [String: String]]
    var pointTags: Binding<Bool> = .constant(false)
    var stackOffset: Binding<Double>
    var stackRange: ClosedRange<Double> = 0...1.6
    var minGapFraction: Binding<Double>
    var showGrid: Binding<Bool>
    var seriesRenderMode: Binding<SeriesRenderMode>
    var globalPlotDefaults: Binding<[String: String]>
    var chartStyleOverrides: Binding<[String: String]>
    var series: CartesianXYSeriesControls
    var xLabelOverride: String
    var yLabelOverride: String
    var renderedXLabel: String
    var renderedYLabel: String
    var sourceResetToken: String
    var onXLabelOverride: (String) -> Void
    var onYLabelOverride: (String) -> Void
    var activeLayout: WorkbenchPlotLayout?
    var axisRangeOverride: AxisRangeOverride?
    var onAxisBoundUpdate: (AxisRangeBound, Double?) -> Void
    var onResetRanges: () -> Void
    var tickOverride: PlotTickOverride?
    var onTickCountUpdate: (PlotTickAxis, Int) -> Void
    /// Persisted style change (re-render + snapshot flush).
    var onChange: () -> Void
    /// Session-only change (re-render only).
    var onTransientChange: () -> Void
}

/// The single `cartesianXY` Plot section (CS-11).
struct CartesianXYPlotControls: View {
    let model: CartesianXYControlsModel
    private let id = "controls.plot"

    private var resolvedXTickCount: Int {
        model.tickOverride?.x ?? model.chartStyleOverridesValue["tickTargetX"].flatMap(Int.init) ?? 6
    }
    private var resolvedYTickCount: Int {
        model.tickOverride?.y ?? model.chartStyleOverridesValue["tickTargetY"].flatMap(Int.init) ?? 5
    }

    var body: some View {
        WorkbenchControlFlow {
            titleTemplateGroup.workbenchFlowFill()
            spacingGroup
            drawGroup
            appearanceGroup
            axisLabelsGroup.workbenchFlowFill()
            rangeGroup
            tickGroup
            PlotTypographyControls(
                globalPlotDefaults: model.globalPlotDefaults,
                onStyleChange: model.onChange,
                idPrefix: id
            )
            if model.series.payload != nil { seriesGroup.workbenchFlowFill() }
        }
    }

    private var titleTemplateGroup: some View {
        WorkbenchControlGroup(id: "\(id).titleTemplate") {
            WorkbenchControlRow(id: "\(id).titleTemplate.field", label: "Title template") {
                SharedPlotTextFieldRow(
                    label: "",
                    placeholder: "#tab #device #sample",
                    text: model.titleTemplate,
                    fieldMinWidth: WorkbenchInputWidth.compact,
                    fieldIdealWidth: WorkbenchInputWidth.wide,
                    fieldMaxWidth: .infinity,
                    onTextChange: model.onChange
                )
            }
            if model.capabilities.contains(.pointTags) {
                WorkbenchCheckbox(title: "Point Tags", isOn: model.pointTags)
            }
            WorkbenchAvailableTokensHint(numericDisplayCache: model.numericDisplayCache)
        }
    }

    private var spacingGroup: some View {
        WorkbenchControlGroup(id: "\(id).spacing") {
            WorkbenchControlRow(id: "\(id).spacing.row", label: "Stack") {
                WorkbenchPlotSpacingInlineControls(
                    stackOffset: model.stackOffset,
                    stackRange: model.stackRange,
                    minGapFraction: model.minGapFraction,
                    onStackChange: model.onChange,
                    onGapSubmit: model.onChange,
                    sliderWidth: WorkbenchInputWidth.sliderIdeal
                )
            }
        }
    }

    private var drawGroup: some View {
        WorkbenchControlGroup(id: "\(id).draw") {
            WorkbenchControlRow(id: "\(id).draw.row", label: "Draw") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    Picker("", selection: Binding<SeriesRenderMode>(
                        get: { model.seriesRenderMode.wrappedValue },
                        set: { model.seriesRenderMode.wrappedValue = $0; model.onChange() }
                    )) {
                        Text("Line").tag(SeriesRenderMode.line)
                        Text("Scatter").tag(SeriesRenderMode.scatter)
                        Text("Line+Scatter").tag(SeriesRenderMode.lineAndScatter)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .workbenchControl(.menu)
                    WorkbenchCheckbox(title: "Grid", isOn: model.showGrid)
                        .onChange(of: model.showGrid.wrappedValue) { _, _ in model.onChange() }
                }
            }
        }
    }

    private var appearanceGroup: some View {
        WorkbenchControlGroup(id: "\(id).seriesAppearance") {
            WorkbenchSeriesAppearanceControls(
                globalPlotDefaults: model.globalPlotDefaults,
                onStyleChange: model.onChange
            )
        }
    }

    private var axisLabelsGroup: some View {
        WorkbenchControlGroup(id: "\(id).axisLabels") {
            WorkbenchControlRow(id: "\(id).axisLabels.x", label: "X label") {
                LabelOverrideField(
                    label: "", renderedDefault: model.renderedXLabel, currentValue: model.xLabelOverride,
                    sourceResetToken: model.sourceResetToken,
                    onCommit: { model.onXLabelOverride($0); model.onTransientChange() },
                    fieldMaxWidth: .infinity)
            }
            WorkbenchControlRow(id: "\(id).axisLabels.y", label: "Y label") {
                LabelOverrideField(
                    label: "", renderedDefault: model.renderedYLabel, currentValue: model.yLabelOverride,
                    sourceResetToken: model.sourceResetToken,
                    onCommit: { model.onYLabelOverride($0); model.onTransientChange() },
                    fieldMaxWidth: .infinity)
            }
        }
    }

    private var rangeGroup: some View {
        WorkbenchControlGroup(id: "\(id).ranges") {
            WorkbenchControlRow(id: "\(id).ranges.row", label: "Range") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    axisRange(label: "X", min: "xMin", max: "xMax", boundMin: .xMin, boundMax: .xMax,
                              layoutMin: model.activeLayout?.axisXMin, layoutMax: model.activeLayout?.axisXMax,
                              overrideMin: model.axisRangeOverride?.xMin, overrideMax: model.axisRangeOverride?.xMax)
                    axisRange(label: "Y", min: "yMin", max: "yMax", boundMin: .yMin, boundMax: .yMax,
                              layoutMin: model.activeLayout?.axisYMin, layoutMax: model.activeLayout?.axisYMax,
                              overrideMin: model.axisRangeOverride?.yMin, overrideMax: model.axisRangeOverride?.yMax)
                    PlotRangeResetControl(hasActiveOverride: model.axisRangeOverride != nil, onReset: model.onResetRanges, alwaysPresent: true)
                }
            }
        }
    }

    private func axisRange(
        label: String, min: String, max: String, boundMin: AxisRangeBound, boundMax: AxisRangeBound,
        layoutMin: Double?, layoutMax: Double?, overrideMin: Double?, overrideMax: Double?
    ) -> some View {
        AxisRangeFieldRow(
            axisLabel: label,
            minDebugName: min, maxDebugName: max,
            minPlaceholder: formatPlotAxisRangeValue(layoutMin),
            maxPlaceholder: formatPlotAxisRangeValue(layoutMax),
            minValue: overrideMin, maxValue: overrideMax,
            effectiveMinBound: overrideMin ?? layoutMin,
            effectiveMaxBound: overrideMax ?? layoutMax,
            sourceResetToken: model.sourceResetToken,
            onCommitMin: { model.onAxisBoundUpdate(boundMin, $0) },
            onCommitMax: { model.onAxisBoundUpdate(boundMax, $0) },
            debugLog: { AxisRangeDebug.log($0) }
        )
    }

    private var tickGroup: some View {
        WorkbenchControlGroup(id: "\(id).ticks") {
            CompactAxisTickCountRow(
                xTickCount: resolvedXTickCount,
                yTickCount: resolvedYTickCount,
                onTickCountUpdate: model.onTickCountUpdate
            )
        }
    }

    private var seriesGroup: some View {
        WorkbenchControlGroup(id: "\(id).series") {
            WorkbenchSeriesOrderPanel(
                seriesControlModel: model.series.controlModel,
                payload: model.series.payload,
                currentSeriesOrder: model.series.currentOrder,
                hiddenSeriesKeys: model.series.hiddenKeys,
                isVisible: true,
                onCommit: { order in
                    model.series.onOrderCommit(order)
                    model.onTransientChange()
                },
                allowsReordering: model.series.canReorder,
                seriesLabelOverrides: model.series.labelOverrides,
                onVisibilityChange: { key, visible in
                    model.series.onVisibilityChange(key, visible)
                    model.onTransientChange()
                },
                onRenameLabel: { key, label in
                    model.series.onRenameLabel(key, label)
                    model.onTransientChange()
                }
            )
        }
    }
}

private extension CartesianXYControlsModel {
    var chartStyleOverridesValue: [String: String] { chartStyleOverrides.wrappedValue }
}
