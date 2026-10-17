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
            drawGroup
            if model.capabilities.contains(.pointTags) { pointTagsGroup }
            appearanceGroup
            spacingGroup
            PlotAxesControls(model: axesModel, idPrefix: id)
            PlotTypographyControls(
                globalPlotDefaults: model.globalPlotDefaults,
                roles: [.title, .axis, .ticks, .legend, .point],
                onStyleChange: model.onChange,
                idPrefix: id
            )
            if model.series.payload != nil { seriesGroup.workbenchFlowFill() }
        }
    }

    private var pointTagsGroup: some View {
        WorkbenchControlGroup(id: "\(id).pointTags") {
            WorkbenchCheckbox(title: "Point Tags", isOn: model.pointTags)
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

    /// Shared Axes configuration for the X / Y roles (CS-38a).
    private var axesModel: PlotAxesModel {
        let override = model.axisRangeOverride
        let layout = model.activeLayout
        return PlotAxesModel(
            sourceResetToken: model.sourceResetToken,
            labels: [
                PlotAxisLabelModel(role: .x, rendered: model.renderedXLabel, override: model.xLabelOverride, onCommit: model.onXLabelOverride),
                PlotAxisLabelModel(role: .y, rendered: model.renderedYLabel, override: model.yLabelOverride, onCommit: model.onYLabelOverride),
            ],
            ranges: [
                PlotAxisRangeModel(
                    role: .x, minDebugName: "xMin", maxDebugName: "xMax",
                    layoutMin: layout?.axisXMin, layoutMax: layout?.axisXMax,
                    overrideMin: override?.xMin, overrideMax: override?.xMax,
                    onCommitMin: { model.onAxisBoundUpdate(.xMin, $0) },
                    onCommitMax: { model.onAxisBoundUpdate(.xMax, $0) },
                    debugLog: { AxisRangeDebug.log($0) }),
                PlotAxisRangeModel(
                    role: .y, minDebugName: "yMin", maxDebugName: "yMax",
                    layoutMin: layout?.axisYMin, layoutMax: layout?.axisYMax,
                    overrideMin: override?.yMin, overrideMax: override?.yMax,
                    onCommitMin: { model.onAxisBoundUpdate(.yMin, $0) },
                    onCommitMax: { model.onAxisBoundUpdate(.yMax, $0) },
                    debugLog: { AxisRangeDebug.log($0) }),
            ],
            hasRangeOverride: override != nil,
            onResetRanges: model.onResetRanges,
            ticks: [
                PlotAxisTickModel(role: .x, count: resolvedXTickCount) { model.onTickCountUpdate(.x, PlotTickConfiguration.clamp($0)) },
                PlotAxisTickModel(role: .y, count: resolvedYTickCount) { model.onTickCountUpdate(.y, PlotTickConfiguration.clamp($0)) },
            ],
            onLabelCommitted: model.onTransientChange)
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
