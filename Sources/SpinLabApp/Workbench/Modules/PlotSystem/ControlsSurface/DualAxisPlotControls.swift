import SwiftUI

/// State and callbacks of the `dualAxis` Plot section (CS-28). The section edits display
/// state only; payload construction stays with the workflow adapter.
struct DualAxisControlsModel {
    var displayState: Binding<DualAxisDisplayState>
    var globalPlotDefaults: Binding<[String: String]>
    var chartStyleOverrides: Binding<[String: String]>
    var activeLayout: DualAxisPlotLayout?
    var sourceResetToken: String
    var renderedXLabel: String
    var renderedLeftYLabel: String
    var renderedRightYLabel: String
    /// Persisted change (title template, tick counts, typography).
    var onDisplayStateChange: () -> Void
    /// Session-only change (ranges, labels, series style, axis colors).
    var onTransientChange: () -> Void
    var onResetRanges: () -> Void
}

private enum DualAxisPresets {
    static let lineWidth: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5]
    static let pointRadius: [Double] = [1.5, 2, 2.5, 3, 4, 5, 6]
}

/// The single `dualAxis` Plot section (CS-11).
struct DualAxisPlotControls: View {
    let model: DualAxisControlsModel
    private let id = "controls.plot"

    private var state: DualAxisDisplayState { model.displayState.wrappedValue }

    var body: some View {
        WorkbenchControlFlow(justified: true) {
            PlotAxesControls(model: axesModel, idPrefix: id)
            axisColorsGroup
            PlotTypographyControls(
                globalPlotDefaults: model.globalPlotDefaults,
                roles: [.title, .axis, .ticks, .legend],
                onStyleChange: model.onDisplayStateChange,
                idPrefix: id
            )
            seriesGroup.workbenchFlowFill()
        }
    }

    // MARK: Shared Axes (X, L-Y, R-Y)

    private var axesModel: PlotAxesModel {
        let layout = model.activeLayout
        let override = state.axisRangeOverride
        return PlotAxesModel(
            sourceResetToken: model.sourceResetToken,
            labels: [
                labelModel(.x, rendered: model.renderedXLabel, current: state.xLabelOverride, key: \.xLabelOverride),
                labelModel(.leftY, rendered: model.renderedLeftYLabel, current: state.leftYLabelOverride, key: \.leftYLabelOverride),
                labelModel(.rightY, rendered: model.renderedRightYLabel, current: state.rightYLabelOverride, key: \.rightYLabelOverride),
            ],
            ranges: [
                rangeModel(.x, "dualAxisXMin", "dualAxisXMax", .xMin, .xMax,
                           layout?.axisXMin, layout?.axisXMax, override?.xMin, override?.xMax),
                rangeModel(.leftY, "dualAxisLeftYMin", "dualAxisLeftYMax", .leftYMin, .leftYMax,
                           layout?.axisLeftYMin, layout?.axisLeftYMax, override?.leftYMin, override?.leftYMax),
                rangeModel(.rightY, "dualAxisRightYMin", "dualAxisRightYMax", .rightYMin, .rightYMax,
                           layout?.axisRightYMin, layout?.axisRightYMax, override?.rightYMin, override?.rightYMax),
            ],
            hasRangeOverride: override != nil,
            onResetRanges: model.onResetRanges,
            ticks: [
                PlotAxisTickModel(role: .x, count: tickCount("tickTargetX", fallback: 6)) { updateTick("tickTargetX", $0) },
                PlotAxisTickModel(role: .leftY, count: tickCount("tickTargetLeftY", fallback: sharedY)) { updateTick("tickTargetLeftY", $0) },
                PlotAxisTickModel(role: .rightY, count: tickCount("tickTargetRightY", fallback: sharedY)) { updateTick("tickTargetRightY", $0) },
            ])
    }

    private func labelModel(
        _ role: PlotAxisRole, rendered: String, current: String,
        key path: WritableKeyPath<DualAxisDisplayState, String>
    ) -> PlotAxisLabelModel {
        PlotAxisLabelModel(role: role, rendered: rendered, override: current) { value in
            guard model.displayState.wrappedValue[keyPath: path] != value else { return }
            model.displayState.wrappedValue[keyPath: path] = value
            model.onTransientChange()
        }
    }

    private func rangeModel(
        _ role: PlotAxisRole, _ minName: String, _ maxName: String,
        _ lower: DualAxisAxisRangeBound, _ upper: DualAxisAxisRangeBound,
        _ layoutMin: Double?, _ layoutMax: Double?, _ overrideMin: Double?, _ overrideMax: Double?
    ) -> PlotAxisRangeModel {
        PlotAxisRangeModel(
            role: role, minDebugName: minName, maxDebugName: maxName,
            layoutMin: layoutMin, layoutMax: layoutMax, overrideMin: overrideMin, overrideMax: overrideMax,
            onCommitMin: { updateRange(lower, $0) }, onCommitMax: { updateRange(upper, $0) })
    }

    private func updateRange(_ bound: DualAxisAxisRangeBound, _ value: Double?) {
        let next = dualAxisRangeOverrideByUpdating(state.axisRangeOverride, bound: bound, value: value, layout: model.activeLayout)
        guard next != state.axisRangeOverride else { return }
        model.displayState.wrappedValue.axisRangeOverride = next
        model.onTransientChange()
    }

    // MARK: Axis colour policy (Plot-Specific)

    private var overrides: [String: String] { model.chartStyleOverrides.wrappedValue }
    private var sharedY: Int { overrides["tickTargetY"].flatMap(Int.init) ?? 5 }

    private func tickCount(_ key: String, fallback: Int) -> Int {
        overrides[key].flatMap(Int.init) ?? fallback
    }

    private var axisColorsGroup: some View {
        WorkbenchControlGroup(id: "\(id).axisColors") {
            WorkbenchControlRow(id: "\(id).axisColors.row", label: "Axis colors") {
                Picker("", selection: Binding(
                    get: { state.axisColorPolicy },
                    set: { model.displayState.wrappedValue.axisColorPolicy = $0; model.onTransientChange() }
                )) {
                    Text("Template paired").tag(DualAxisAxisColorPolicy.templatePaired)
                    Text("Monochrome").tag(DualAxisAxisColorPolicy.monochrome)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 120, idealWidth: 140, maxWidth: 156, alignment: .leading)
                .workbenchControl(.menu)
            }
        }
    }

    private func updateTick(_ key: String, _ value: Int) {
        let clamped = max(PlotTickConfiguration.validRange.lowerBound, min(PlotTickConfiguration.validRange.upperBound, value))
        guard model.chartStyleOverrides.wrappedValue[key] != "\(clamped)" else { return }
        model.chartStyleOverrides.wrappedValue[key] = "\(clamped)"
        model.onDisplayStateChange()
    }

    // MARK: Left / Right series appearance

    private var styleDefaults: WorkbenchChartStyle {
        WorkbenchChartStyle.from(styleParams: model.globalPlotDefaults.wrappedValue.merging(overrides) { _, new in new })
    }

    private var seriesGroup: some View {
        WorkbenchControlGroup(id: "\(id).seriesAppearance") {
            seriesRow("left", "Left", \.leftSeriesStyle)
            seriesRow("right", "Right", \.rightSeriesStyle)
        }
    }

    private func seriesRow(_ key: String, _ label: String, _ path: WritableKeyPath<DualAxisDisplayState, DualAxisSeriesVisualStyle>) -> some View {
        WorkbenchControlRow(id: "\(id).seriesAppearance.\(key)", label: label) {
            WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                menu("Line", state[keyPath: path].linePattern, [("Solid", DualAxisLinePattern.solid), ("Dashed", .dashed)]) {
                    model.displayState.wrappedValue[keyPath: path].linePattern = $0; model.onTransientChange()
                }
                preset("W", DualAxisPresets.lineWidth, state[keyPath: path].lineWidth, styleDefaults.lineWidth ?? 2) {
                    model.displayState.wrappedValue[keyPath: path].lineWidth = $0; model.onTransientChange()
                }
                menu("Marker", state[keyPath: path].markerShape, [("Circle", DualAxisMarkerShape.circle), ("Square", .square)]) {
                    model.displayState.wrappedValue[keyPath: path].markerShape = $0; model.onTransientChange()
                }
                preset("Size", DualAxisPresets.pointRadius, state[keyPath: path].pointRadius, styleDefaults.pointRadius ?? 2.5) {
                    model.displayState.wrappedValue[keyPath: path].pointRadius = $0; model.onTransientChange()
                }
                menu("Fill", state[keyPath: path].markerFill, [("Filled", DualAxisMarkerFill.filled), ("Open", .open)]) {
                    model.displayState.wrappedValue[keyPath: path].markerFill = $0; model.onTransientChange()
                }
            }
        }
    }

    private func menu<V: Hashable>(_ label: String, _ current: V, _ options: [(String, V)], set: @escaping (V) -> Void) -> some View {
        PlotLabeledMenu(
            label: label, selection: Binding(get: { current }, set: set),
            options: options.map { .init(label: $0.0, value: $0.1) })
    }

    private func preset(_ label: String, _ presets: [Double], _ current: Double?, _ defaultValue: Double, commit: @escaping (Double?) -> Void) -> some View {
        func nearest(_ v: Double) -> Double { presets.min(by: { abs($0 - v) < abs($1 - v) }) ?? v }
        return PlotLabeledMenu(
            label: label,
            selection: Binding<Double>(
                get: { nearest(current ?? defaultValue) },
                set: { commit($0 == nearest(defaultValue) ? nil : $0) }),
            options: presets.map { .init(label: $0.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", $0) : String(format: "%.1f", $0), value: $0) },
            width: (54, 60, 64))
    }
}
