import Foundation
import SwiftUI

/// Preset values for `DualAxisPlotControlsPanel`'s line-width / point-radius pickers.
/// Lives outside the generic panel type since generic types cannot declare static
/// stored properties.
private enum DualAxisPlotControlsPresets {
    static let lineWidth: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5]
    static let pointRadius: [Double] = [1.5, 2, 2.5, 3, 4, 5, 6]
}

/// Generic DualAxis controls surface.
/// This panel edits display state only; workflow adapters still own scientific payload construction.
struct DualAxisPlotControlsPanel<TitleRowTrailing: View>: View {
    @Binding var displayState: DualAxisDisplayState
    @Binding var titleTemplate: String
    @Binding var globalPlotDefaults: [String: String]
    @Binding var chartStyleOverrides: [String: String]
    var numericDisplayCache: [String: [String: String]] = [:]
    var activeLayout: DualAxisPlotLayout? = nil
    var sourceResetToken: String = ""
    /// Rendered default title from the active payload (shown as placeholder when no override is set).
    var renderedTitle: String = ""
    var renderedXLabel: String = ""
    var renderedLeftYLabel: String = ""
    var renderedRightYLabel: String = ""
    var onDisplayStateChange: (() -> Void)? = nil
    /// Capability to clear every manual axis-range override (X/L-Y/R-Y) in one
    /// atomic action. Non-nil shows the shared `PlotRangeResetControl` below the
    /// axis-range row; nil omits it. The caller owns the atomic state write (see
    /// `ThreeOmegaTemperatureDependencePlotControlsPanel`), mirroring how Cartesian
    /// XY workflows own their own `resetAxisRanges()` store method — this panel
    /// never mutates `displayState` itself for reset, same as every other field.
    /// The per-field clear (`xmark.circle`) buttons on each range field are
    /// unaffected by this capability — they always remain available.
    var onResetRanges: (() -> Void)? = nil
    /// Rendered at the trailing edge of the title template row. Defaults to `EmptyView` via
    /// the convenience init below, so existing callers are unaffected.
    @ViewBuilder var titleRowTrailingContent: () -> TitleRowTrailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            dualAxisTitleTemplate
            Divider()
            dualAxisLabelOverrides
            Divider()
            dualAxisAxisRanges
            Divider()
            dualAxisTickControls
            Divider()
            dualAxisTypography
            Divider()
            dualAxisSeriesStyle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var dualAxisTitleTemplate: some View {
        HStack(alignment: .top, spacing: 12) {
            WorkbenchTitleTemplateField(
                titleTemplate: $titleTemplate,
                numericDisplayCache: numericDisplayCache,
                onChange: onDisplayStateChange
            )
            if TitleRowTrailing.self != EmptyView.self {
                Spacer(minLength: 0)
            }
            titleRowTrailingContent()
        }
    }

    private var mergedStyleForPlaceholders: WorkbenchChartStyle {
        WorkbenchChartStyle.from(styleParams: globalPlotDefaults.merging(chartStyleOverrides) { _, new in new })
    }

    @ViewBuilder
    private var dualAxisTickControls: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("Ticks")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            tickStepper(label: "X", count: xTickCount) { updateTickCount(key: "tickTargetX", value: $0) }
            tickStepper(label: "L-Y", count: leftYTickCount) { updateTickCount(key: "tickTargetLeftY", value: $0) }
            tickStepper(label: "R-Y", count: rightYTickCount) { updateTickCount(key: "tickTargetRightY", value: $0) }
            axisColorPolicyRow
        }
    }

    private var xTickCount: Int { chartStyleOverrides["tickTargetX"].flatMap(Int.init) ?? 6 }
    private var sharedYTickCount: Int { chartStyleOverrides["tickTargetY"].flatMap(Int.init) ?? 5 }
    private var leftYTickCount: Int { chartStyleOverrides["tickTargetLeftY"].flatMap(Int.init) ?? sharedYTickCount }
    private var rightYTickCount: Int { chartStyleOverrides["tickTargetRightY"].flatMap(Int.init) ?? sharedYTickCount }

    private func updateTickCount(key: String, value: Int) {
        let clamped = max(PlotTickConfiguration.validRange.lowerBound, min(PlotTickConfiguration.validRange.upperBound, value))
        guard chartStyleOverrides[key] != "\(clamped)" else { return }
        chartStyleOverrides[key] = "\(clamped)"
        onDisplayStateChange?()
    }

    @ViewBuilder
    private func tickStepper(label: String, count: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            Stepper(
                value: Binding(
                    get: { count },
                    set: { onChange($0) }
                ),
                in: PlotTickConfiguration.validRange
            ) {
                Text("\(count)")
                    .font(WorkbenchUIStyle.controlValueFont)
                    .frame(width: 16)
            }
            .frame(width: 64)
        }
    }

    @ViewBuilder
    private var dualAxisTypography: some View {
        CompactTypographyRow(
            globalPlotDefaults: $globalPlotDefaults,
            onStyleChange: onDisplayStateChange,
            showTitle: $displayState.showTitle
        )
    }

    private func updateRange(_ bound: DualAxisAxisRangeBound, value: Double?) {
        let next = dualAxisRangeOverrideByUpdating(displayState.axisRangeOverride, bound: bound, value: value, layout: activeLayout)
        guard next != displayState.axisRangeOverride else { return }
        displayState.axisRangeOverride = next
        onDisplayStateChange?()
    }

    @ViewBuilder
    private var dualAxisLabelOverrides: some View {
        WeightedRowLayout<DualAxisControlWeightKey>(spacing: 12) {
            labelOverrideField(
                label: "Plot title",
                renderedDefault: renderedTitle,
                currentValue: displayState.titleOverride,
                onCommit: { updateLabel(\.titleOverride, value: $0) }
            )
            .dualAxisControlWeight(2.2)

            labelOverrideField(
                label: "X",
                renderedDefault: renderedXLabel,
                currentValue: displayState.xLabelOverride,
                onCommit: { updateLabel(\.xLabelOverride, value: $0) }
            )
            .dualAxisControlWeight(1.0)

            labelOverrideField(
                label: "L-Y",
                renderedDefault: renderedLeftYLabel,
                currentValue: displayState.leftYLabelOverride,
                onCommit: { updateLabel(\.leftYLabelOverride, value: $0) }
            )
            .dualAxisControlWeight(1.1)

            labelOverrideField(
                label: "R-Y",
                renderedDefault: renderedRightYLabel,
                currentValue: displayState.rightYLabelOverride,
                onCommit: { updateLabel(\.rightYLabelOverride, value: $0) }
            )
            .dualAxisControlWeight(1.1)
        }
    }

    @ViewBuilder
    private var dualAxisAxisRanges: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Range")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            dualAxisRangeGroup(
                label: "X",
                minDebugName: "dualAxisXMin",
                maxDebugName: "dualAxisXMax",
                minPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisXMin),
                maxPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisXMax),
                minValue: displayState.axisRangeOverride?.xMin,
                maxValue: displayState.axisRangeOverride?.xMax,
                effectiveMinBound: displayState.axisRangeOverride?.xMin ?? activeLayout?.axisXMin,
                effectiveMaxBound: displayState.axisRangeOverride?.xMax ?? activeLayout?.axisXMax,
                onMinCommit: { updateRange(.xMin, value: $0) },
                onMaxCommit: { updateRange(.xMax, value: $0) }
            )
            dualAxisRangeGroup(
                label: "L-Y",
                minDebugName: "dualAxisLeftYMin",
                maxDebugName: "dualAxisLeftYMax",
                minPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisLeftYMin),
                maxPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisLeftYMax),
                minValue: displayState.axisRangeOverride?.leftYMin,
                maxValue: displayState.axisRangeOverride?.leftYMax,
                effectiveMinBound: displayState.axisRangeOverride?.leftYMin ?? activeLayout?.axisLeftYMin,
                effectiveMaxBound: displayState.axisRangeOverride?.leftYMax ?? activeLayout?.axisLeftYMax,
                onMinCommit: { updateRange(.leftYMin, value: $0) },
                onMaxCommit: { updateRange(.leftYMax, value: $0) }
            )
            dualAxisRangeGroup(
                label: "R-Y",
                minDebugName: "dualAxisRightYMin",
                maxDebugName: "dualAxisRightYMax",
                minPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisRightYMin),
                maxPlaceholder: formatPlotAxisRangeValue(activeLayout?.axisRightYMax),
                minValue: displayState.axisRangeOverride?.rightYMin,
                maxValue: displayState.axisRangeOverride?.rightYMax,
                effectiveMinBound: displayState.axisRangeOverride?.rightYMin ?? activeLayout?.axisRightYMin,
                effectiveMaxBound: displayState.axisRangeOverride?.rightYMax ?? activeLayout?.axisRightYMax,
                onMinCommit: { updateRange(.rightYMin, value: $0) },
                onMaxCommit: { updateRange(.rightYMax, value: $0) }
            )
        }
        if let onResetRanges {
            PlotRangeResetControl(
                hasActiveOverride: displayState.axisRangeOverride != nil,
                onReset: onResetRanges
            )
        }
    }

    @ViewBuilder
    private func dualAxisRangeGroup(
        label: String,
        minDebugName: String,
        maxDebugName: String,
        minPlaceholder: String,
        maxPlaceholder: String,
        minValue: Double?,
        maxValue: Double?,
        effectiveMinBound: Double?,
        effectiveMaxBound: Double?,
        onMinCommit: @escaping (Double?) -> Void,
        onMaxCommit: @escaping (Double?) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
                .layoutPriority(1)
            PlotAxisBoundField(
                identity: PlotAxisBoundIdentity(debugName: minDebugName, role: .lower),
                placeholder: minPlaceholder,
                currentValue: minValue,
                effectiveOppositeBound: effectiveMaxBound,
                sourceResetToken: sourceResetToken,
                width: .flexible(min: 44, ideal: 54, max: 54),
                onCommit: onMinCommit
            )
            Text("–")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            PlotAxisBoundField(
                identity: PlotAxisBoundIdentity(debugName: maxDebugName, role: .upper),
                placeholder: maxPlaceholder,
                currentValue: maxValue,
                effectiveOppositeBound: effectiveMinBound,
                sourceResetToken: sourceResetToken,
                width: .flexible(min: 44, ideal: 54, max: 54),
                onCommit: onMaxCommit
            )
        }
    }

    @ViewBuilder
    private var dualAxisSeriesStyle: some View {
        VStack(alignment: .leading, spacing: 6) {
            dualAxisSeriesStyleRow(
                label: "Left",
                linePatternBinding: leftLinePatternBinding,
                markerShapeBinding: leftMarkerShapeBinding,
                markerFillBinding: leftMarkerFillBinding,
                lineWidth: displayState.leftSeriesStyle.lineWidth,
                onLineWidthCommit: { updateLeftLineWidth($0) },
                pointRadius: displayState.leftSeriesStyle.pointRadius,
                onPointRadiusCommit: { updateLeftPointRadius($0) }
            )
            dualAxisSeriesStyleRow(
                label: "Right",
                linePatternBinding: rightLinePatternBinding,
                markerShapeBinding: rightMarkerShapeBinding,
                markerFillBinding: rightMarkerFillBinding,
                lineWidth: displayState.rightSeriesStyle.lineWidth,
                onLineWidthCommit: { updateRightLineWidth($0) },
                pointRadius: displayState.rightSeriesStyle.pointRadius,
                onPointRadiusCommit: { updateRightPointRadius($0) }
            )
        }
    }

    @ViewBuilder
    private var axisColorPolicyRow: some View {
        menuPickerRow(
            label: "Axis colors",
            labelWidth: 80,
            selection: axisColorPolicyBinding,
            pickerMinWidth: 120,
            pickerIdealWidth: 140,
            pickerMaxWidth: 156
        ) {
            Text("Template paired").tag(DualAxisAxisColorPolicy.templatePaired)
            Text("Monochrome").tag(DualAxisAxisColorPolicy.monochrome)
        }
    }

    @ViewBuilder
    private func dualAxisSeriesStyleRow(
        label: String,
        linePatternBinding: Binding<DualAxisLinePattern>,
        markerShapeBinding: Binding<DualAxisMarkerShape>,
        markerFillBinding: Binding<DualAxisMarkerFill>,
        lineWidth: Double?,
        onLineWidthCommit: @escaping (Double?) -> Void,
        pointRadius: Double?,
        onPointRadiusCommit: @escaping (Double?) -> Void
    ) -> some View {
        DualAxisAlignedControlRow(label: label, labelWidth: 42, spacing: 8) {
            menuPickerRow(label: "Line", labelWidth: 38, selection: linePatternBinding, pickerMinWidth: 64, pickerIdealWidth: 76, pickerMaxWidth: 84) {
                Text("Solid").tag(DualAxisLinePattern.solid)
                Text("Dashed").tag(DualAxisLinePattern.dashed)
            }
            presetPickerRow(
                label: "W",
                selection: presetBinding(
                    presets: DualAxisPlotControlsPresets.lineWidth,
                    current: lineWidth,
                    defaultValue: widthDefaultValue,
                    onCommit: onLineWidthCommit
                ),
                presets: DualAxisPlotControlsPresets.lineWidth,
                minWidth: 54,
                idealWidth: 57,
                maxWidth: 60
            )
            menuPickerRow(label: "Marker", labelWidth: 54, selection: markerShapeBinding, pickerMinWidth: 88, pickerIdealWidth: 98, pickerMaxWidth: 104) {
                Text("Circle").tag(DualAxisMarkerShape.circle)
                Text("Square").tag(DualAxisMarkerShape.square)
            }
            presetPickerRow(
                label: "Size",
                selection: presetBinding(
                    presets: DualAxisPlotControlsPresets.pointRadius,
                    current: pointRadius,
                    defaultValue: sizeDefaultValue,
                    onCommit: onPointRadiusCommit
                ),
                presets: DualAxisPlotControlsPresets.pointRadius,
                minWidth: 58,
                idealWidth: 61,
                maxWidth: 64
            )
            markerFillPickerRow(selection: markerFillBinding)
        }
    }

    @ViewBuilder
    private func markerFillPickerRow(selection: Binding<DualAxisMarkerFill>) -> some View {
        Picker("", selection: selection) {
            Text("Filled").tag(DualAxisMarkerFill.filled)
            Text("Open").tag(DualAxisMarkerFill.open)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 72, idealWidth: 84, maxWidth: 92, alignment: .leading)
        .accessibilityLabel("Marker fill")
        .help("Marker fill")
    }

    private var widthDefaultValue: Double { mergedStyleForPlaceholders.lineWidth ?? 2 }
    private var sizeDefaultValue: Double { mergedStyleForPlaceholders.pointRadius ?? 2.5 }

    private func nearestPreset(_ presets: [Double], to value: Double) -> Double {
        presets.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    /// Selection snaps display to the nearest preset (covers legacy/custom stored
    /// values not in the preset list). Picking the preset that matches the
    /// current effective default writes `nil` instead of an explicit override,
    /// so choosing the already-in-effect value doesn't manufacture state that
    /// diverges from "unset" for no reason.
    private func presetBinding(
        presets: [Double],
        current: Double?,
        defaultValue: Double,
        onCommit: @escaping (Double?) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { nearestPreset(presets, to: current ?? defaultValue) },
            set: { newValue in
                if newValue == nearestPreset(presets, to: defaultValue) {
                    onCommit(nil)
                } else {
                    onCommit(newValue)
                }
            }
        )
    }

    @ViewBuilder
    private func presetPickerRow(
        label: String,
        selection: Binding<Double>,
        presets: [Double],
        minWidth: CGFloat,
        idealWidth: CGFloat,
        maxWidth: CGFloat
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
                .layoutPriority(1)
            Picker("", selection: selection) {
                ForEach(presets, id: \.self) { preset in
                    Text(formatPreset(preset)).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth, alignment: .leading)
        }
    }

    private func formatPreset(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func updateLeftLineWidth(_ value: Double?) {
        guard displayState.leftSeriesStyle.lineWidth != value else { return }
        displayState.leftSeriesStyle.lineWidth = value
        onDisplayStateChange?()
    }

    private func updateRightLineWidth(_ value: Double?) {
        guard displayState.rightSeriesStyle.lineWidth != value else { return }
        displayState.rightSeriesStyle.lineWidth = value
        onDisplayStateChange?()
    }

    private func updateLeftPointRadius(_ value: Double?) {
        guard displayState.leftSeriesStyle.pointRadius != value else { return }
        displayState.leftSeriesStyle.pointRadius = value
        onDisplayStateChange?()
    }

    private func updateRightPointRadius(_ value: Double?) {
        guard displayState.rightSeriesStyle.pointRadius != value else { return }
        displayState.rightSeriesStyle.pointRadius = value
        onDisplayStateChange?()
    }

    @ViewBuilder
    private func labelOverrideField(
        label: String,
        renderedDefault: String,
        currentValue: String,
        onCommit: @escaping (String) -> Void
    ) -> some View {
        LabelOverrideField(
            label: label,
            renderedDefault: renderedDefault,
            currentValue: currentValue,
            sourceResetToken: sourceResetToken,
            onCommit: onCommit,
            fieldMaxWidth: .infinity
        )
    }

    @ViewBuilder
    private func menuPickerRow<Selection: Hashable, Options: View>(
        label: String,
        labelWidth: CGFloat,
        selection: Binding<Selection>,
        pickerMinWidth: CGFloat,
        pickerIdealWidth: CGFloat,
        pickerMaxWidth: CGFloat,
        @ViewBuilder options: @escaping () -> Options
    ) -> some View {
        ControlRow(label: label, labelWidth: labelWidth, spacing: 6) {
            Picker("", selection: selection) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: pickerMinWidth, idealWidth: pickerIdealWidth, maxWidth: pickerMaxWidth, alignment: .leading)
        }
    }

    private func updateLabel(_ keyPath: WritableKeyPath<DualAxisDisplayState, String>, value: String) {
        let current = displayState[keyPath: keyPath]
        guard current != value else { return }
        displayState[keyPath: keyPath] = value
        onDisplayStateChange?()
    }

    private var leftLinePatternBinding: Binding<DualAxisLinePattern> {
        Binding(
            get: { displayState.leftSeriesStyle.linePattern },
            set: { value in displayState.leftSeriesStyle.linePattern = value; onDisplayStateChange?() }
        )
    }

    private var rightLinePatternBinding: Binding<DualAxisLinePattern> {
        Binding(
            get: { displayState.rightSeriesStyle.linePattern },
            set: { value in displayState.rightSeriesStyle.linePattern = value; onDisplayStateChange?() }
        )
    }

    private var leftMarkerShapeBinding: Binding<DualAxisMarkerShape> {
        Binding(
            get: { displayState.leftSeriesStyle.markerShape },
            set: { value in displayState.leftSeriesStyle.markerShape = value; onDisplayStateChange?() }
        )
    }

    private var rightMarkerShapeBinding: Binding<DualAxisMarkerShape> {
        Binding(
            get: { displayState.rightSeriesStyle.markerShape },
            set: { value in displayState.rightSeriesStyle.markerShape = value; onDisplayStateChange?() }
        )
    }

    private var leftMarkerFillBinding: Binding<DualAxisMarkerFill> {
        Binding(
            get: { displayState.leftSeriesStyle.markerFill },
            set: { value in displayState.leftSeriesStyle.markerFill = value; onDisplayStateChange?() }
        )
    }

    private var rightMarkerFillBinding: Binding<DualAxisMarkerFill> {
        Binding(
            get: { displayState.rightSeriesStyle.markerFill },
            set: { value in displayState.rightSeriesStyle.markerFill = value; onDisplayStateChange?() }
        )
    }

    private var axisColorPolicyBinding: Binding<DualAxisAxisColorPolicy> {
        Binding(
            get: { displayState.axisColorPolicy },
            set: { value in displayState.axisColorPolicy = value; onDisplayStateChange?() }
        )
    }
}

extension DualAxisPlotControlsPanel where TitleRowTrailing == EmptyView {
    init(
        displayState: Binding<DualAxisDisplayState>,
        titleTemplate: Binding<String>,
        globalPlotDefaults: Binding<[String: String]>,
        chartStyleOverrides: Binding<[String: String]>,
        numericDisplayCache: [String: [String: String]] = [:],
        activeLayout: DualAxisPlotLayout? = nil,
        sourceResetToken: String = "",
        renderedTitle: String = "",
        renderedXLabel: String = "",
        renderedLeftYLabel: String = "",
        renderedRightYLabel: String = "",
        onDisplayStateChange: (() -> Void)? = nil,
        onResetRanges: (() -> Void)? = nil
    ) {
        self._displayState = displayState
        self._titleTemplate = titleTemplate
        self._globalPlotDefaults = globalPlotDefaults
        self._chartStyleOverrides = chartStyleOverrides
        self.numericDisplayCache = numericDisplayCache
        self.activeLayout = activeLayout
        self.sourceResetToken = sourceResetToken
        self.renderedTitle = renderedTitle
        self.renderedXLabel = renderedXLabel
        self.renderedLeftYLabel = renderedLeftYLabel
        self.renderedRightYLabel = renderedRightYLabel
        self.onDisplayStateChange = onDisplayStateChange
        self.onResetRanges = onResetRanges
        self.titleRowTrailingContent = { EmptyView() }
    }
}

/// DualAxis-local row chrome with a fixed, leading-aligned row label — used only by
/// the Left/Right series-style rows so those two rows' columns (Line/W/Marker/Size/Fill)
/// line up with each other. Not shared with Range/Ticks, which align only within
/// themselves. Label uses leading alignment (not `ControlRow`'s trailing alignment)
/// plus `fixedSize()` + `layoutPriority(1)` so it can never be compressed/clipped by
/// the row's more flexible trailing content.
private struct DualAxisAlignedControlRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 48
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
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

private struct DualAxisControlWeightKey: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

private extension View {
    func dualAxisControlWeight(_ weight: CGFloat) -> some View {
        layoutValue(key: DualAxisControlWeightKey.self, value: weight)
    }
}
