import SwiftUI

/// State and callbacks of the `dualAxis` Plot section (CS-28). The section edits display
/// state only; payload construction stays with the workflow adapter.
struct DualAxisControlsModel {
    var displayState: Binding<DualAxisDisplayState>
    var titleTemplate: Binding<String>
    var numericDisplayCache: [String: [String: String]]
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
        WorkbenchControlFlow {
            titleTemplateGroup.workbenchFlowFill()
            axisLabelsGroup.workbenchFlowFill()
            rangeGroup
            tickGroup
            PlotTypographyControls(
                globalPlotDefaults: model.globalPlotDefaults,
                onStyleChange: model.onDisplayStateChange,
                idPrefix: id
            )
            seriesGroup.workbenchFlowFill()
        }
    }

    // MARK: Title template / labels

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
                    onTextChange: model.onDisplayStateChange
                )
            }
            WorkbenchAvailableTokensHint(numericDisplayCache: model.numericDisplayCache)
        }
    }

    private var axisLabelsGroup: some View {
        WorkbenchControlGroup(id: "\(id).axisLabels") {
            labelField("x", "X label", rendered: model.renderedXLabel, current: state.xLabelOverride, key: \.xLabelOverride)
            labelField("leftY", "L-Y label", rendered: model.renderedLeftYLabel, current: state.leftYLabelOverride, key: \.leftYLabelOverride)
            labelField("rightY", "R-Y label", rendered: model.renderedRightYLabel, current: state.rightYLabelOverride, key: \.rightYLabelOverride)
        }
    }

    private func labelField(
        _ key: String, _ label: String, rendered: String, current: String,
        key path: WritableKeyPath<DualAxisDisplayState, String>
    ) -> some View {
        WorkbenchControlRow(id: "\(id).axisLabels.\(key)", label: label) {
            LabelOverrideField(
                label: "", renderedDefault: rendered, currentValue: current,
                sourceResetToken: model.sourceResetToken,
                onCommit: { value in
                    guard model.displayState.wrappedValue[keyPath: path] != value else { return }
                    model.displayState.wrappedValue[keyPath: path] = value
                    model.onTransientChange()
                },
                fieldMaxWidth: .infinity)
        }
    }

    // MARK: Ranges

    private var rangeGroup: some View {
        WorkbenchControlGroup(id: "\(id).ranges") {
            WorkbenchControlRow(id: "\(id).ranges.row", label: "Range") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    rangePair("X", "dualAxisXMin", "dualAxisXMax", .xMin, .xMax,
                              model.activeLayout?.axisXMin, model.activeLayout?.axisXMax,
                              state.axisRangeOverride?.xMin, state.axisRangeOverride?.xMax)
                    rangePair("L-Y", "dualAxisLeftYMin", "dualAxisLeftYMax", .leftYMin, .leftYMax,
                              model.activeLayout?.axisLeftYMin, model.activeLayout?.axisLeftYMax,
                              state.axisRangeOverride?.leftYMin, state.axisRangeOverride?.leftYMax)
                    rangePair("R-Y", "dualAxisRightYMin", "dualAxisRightYMax", .rightYMin, .rightYMax,
                              model.activeLayout?.axisRightYMin, model.activeLayout?.axisRightYMax,
                              state.axisRangeOverride?.rightYMin, state.axisRangeOverride?.rightYMax)
                    PlotRangeResetControl(hasActiveOverride: state.axisRangeOverride != nil, onReset: model.onResetRanges, alwaysPresent: true)
                }
            }
        }
    }

    private func rangePair(
        _ label: String, _ minName: String, _ maxName: String,
        _ lower: DualAxisAxisRangeBound, _ upper: DualAxisAxisRangeBound,
        _ layoutMin: Double?, _ layoutMax: Double?, _ overrideMin: Double?, _ overrideMax: Double?
    ) -> some View {
        AxisRangeFieldRow(
            axisLabel: label,
            minDebugName: minName, maxDebugName: maxName,
            minPlaceholder: formatPlotAxisRangeValue(layoutMin),
            maxPlaceholder: formatPlotAxisRangeValue(layoutMax),
            minValue: overrideMin, maxValue: overrideMax,
            effectiveMinBound: overrideMin ?? layoutMin,
            effectiveMaxBound: overrideMax ?? layoutMax,
            sourceResetToken: model.sourceResetToken,
            onCommitMin: { updateRange(lower, $0) },
            onCommitMax: { updateRange(upper, $0) }
        )
    }

    private func updateRange(_ bound: DualAxisAxisRangeBound, _ value: Double?) {
        let next = dualAxisRangeOverrideByUpdating(state.axisRangeOverride, bound: bound, value: value, layout: model.activeLayout)
        guard next != state.axisRangeOverride else { return }
        model.displayState.wrappedValue.axisRangeOverride = next
        model.onTransientChange()
    }

    // MARK: Ticks + axis colors

    private var overrides: [String: String] { model.chartStyleOverrides.wrappedValue }
    private var sharedY: Int { overrides["tickTargetY"].flatMap(Int.init) ?? 5 }

    private var tickGroup: some View {
        WorkbenchControlGroup(id: "\(id).ticks") {
            WorkbenchControlRow(id: "\(id).ticks.row", label: "Ticks") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    stepper("X", overrides["tickTargetX"].flatMap(Int.init) ?? 6, "tickTargetX")
                    stepper("L-Y", overrides["tickTargetLeftY"].flatMap(Int.init) ?? sharedY, "tickTargetLeftY")
                    stepper("R-Y", overrides["tickTargetRightY"].flatMap(Int.init) ?? sharedY, "tickTargetRightY")
                }
            }
            WorkbenchControlRow(id: "\(id).ticks.axisColors", label: "Axis colors") {
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
            }
        }
    }

    private func stepper(_ label: String, _ count: Int, _ key: String) -> some View {
        HStack(spacing: 3) {
            Text(label).font(WorkbenchUIStyle.controlLabelFont).fixedSize()
            Stepper(value: Binding(get: { count }, set: { updateTick(key, $0) }), in: PlotTickConfiguration.validRange) {
                Text("\(count)").font(WorkbenchUIStyle.controlValueFont).frame(width: 16)
            }
            .frame(width: 64)
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
        HStack(spacing: 4) {
            Text(label).font(WorkbenchUIStyle.controlLabelFont).fixedSize()
            Picker("", selection: Binding(get: { current }, set: set)) {
                ForEach(options.indices, id: \.self) { Text(options[$0].0).tag(options[$0].1) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 72, idealWidth: 84, maxWidth: 96, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func preset(_ label: String, _ presets: [Double], _ current: Double?, _ defaultValue: Double, commit: @escaping (Double?) -> Void) -> some View {
        func nearest(_ v: Double) -> Double { presets.min(by: { abs($0 - v) < abs($1 - v) }) ?? v }
        return HStack(spacing: 4) {
            Text(label).font(WorkbenchUIStyle.controlLabelFont).fixedSize()
            Picker("", selection: Binding<Double>(
                get: { nearest(current ?? defaultValue) },
                set: { commit($0 == nearest(defaultValue) ? nil : $0) }
            )) {
                ForEach(presets, id: \.self) { value in
                    Text(value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 54, idealWidth: 60, maxWidth: 64, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
