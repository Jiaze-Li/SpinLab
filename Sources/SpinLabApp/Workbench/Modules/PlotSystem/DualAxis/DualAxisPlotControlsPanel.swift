import Foundation
import SwiftUI

/// Generic DualAxis controls surface.
/// This panel edits display state only; workflow adapters still own scientific payload construction.
struct DualAxisPlotControlsPanel: View {
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
        WorkbenchTitleTemplateField(
            titleTemplate: $titleTemplate,
            numericDisplayCache: numericDisplayCache,
            onChange: onDisplayStateChange
        )
    }

    private var mergedStyleForPlaceholders: WorkbenchChartStyle {
        WorkbenchChartStyle.from(styleParams: globalPlotDefaults.merging(chartStyleOverrides) { _, new in new })
    }

    @ViewBuilder
    private var dualAxisTickControls: some View {
        HStack(spacing: 18) {
            Text("Ticks")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            tickStepper(label: "X", count: xTickCount) { updateTickCount(key: "tickTargetX", value: $0) }
            tickStepper(label: "Left Y", count: leftYTickCount) { updateTickCount(key: "tickTargetLeftY", value: $0) }
            tickStepper(label: "Right Y", count: rightYTickCount) { updateTickCount(key: "tickTargetRightY", value: $0) }
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
        CompactTypographyRow(globalPlotDefaults: $globalPlotDefaults, onStyleChange: onDisplayStateChange)
    }

    private func updateRange(_ bound: DualAxisAxisRangeBound, value: Double?) {
        let next = dualAxisRangeOverrideByUpdating(displayState.axisRangeOverride, bound: bound, value: value)
        guard next != displayState.axisRangeOverride else { return }
        displayState.axisRangeOverride = next
        onDisplayStateChange?()
    }

    private func formatAuto(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == 0 { return "0" }
        let absValue = Swift.abs(value)
        if absValue >= 0.001 && absValue < 100_000 {
            return String(format: "%g", value)
        }
        return String(format: "%.3e", value)
    }

    @ViewBuilder
    private var dualAxisLabelOverrides: some View {
        ViewThatFits(in: .horizontal) {
            DualAxisControlWeightedRowLayout(spacing: 12) {
                labelOverrideField(
                    label: "Plot title",
                    renderedDefault: renderedTitle,
                    currentValue: displayState.titleOverride,
                    onCommit: { updateLabel(\.titleOverride, value: $0) }
                )
                .dualAxisControlWeight(3)

                labelOverrideField(
                    label: "X",
                    renderedDefault: renderedXLabel,
                    currentValue: displayState.xLabelOverride,
                    onCommit: { updateLabel(\.xLabelOverride, value: $0) }
                )
                .dualAxisControlWeight(1)

                labelOverrideField(
                    label: "Left Y",
                    renderedDefault: renderedLeftYLabel,
                    currentValue: displayState.leftYLabelOverride,
                    onCommit: { updateLabel(\.leftYLabelOverride, value: $0) }
                )
                .dualAxisControlWeight(1)

                labelOverrideField(
                    label: "Right Y",
                    renderedDefault: renderedRightYLabel,
                    currentValue: displayState.rightYLabelOverride,
                    onCommit: { updateLabel(\.rightYLabelOverride, value: $0) }
                )
                .dualAxisControlWeight(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                DualAxisControlWeightedRowLayout(spacing: 12) {
                    labelOverrideField(
                        label: "Plot title",
                        renderedDefault: renderedTitle,
                        currentValue: displayState.titleOverride,
                        onCommit: { updateLabel(\.titleOverride, value: $0) }
                    )
                    .dualAxisControlWeight(3)

                    labelOverrideField(
                        label: "X",
                        renderedDefault: renderedXLabel,
                        currentValue: displayState.xLabelOverride,
                        onCommit: { updateLabel(\.xLabelOverride, value: $0) }
                    )
                    .dualAxisControlWeight(1)
                }

                DualAxisControlWeightedRowLayout(spacing: 12) {
                    labelOverrideField(
                        label: "Left Y",
                        renderedDefault: renderedLeftYLabel,
                        currentValue: displayState.leftYLabelOverride,
                        onCommit: { updateLabel(\.leftYLabelOverride, value: $0) }
                    )
                    .dualAxisControlWeight(1)

                    labelOverrideField(
                        label: "Right Y",
                        renderedDefault: renderedRightYLabel,
                        currentValue: displayState.rightYLabelOverride,
                        onCommit: { updateLabel(\.rightYLabelOverride, value: $0) }
                    )
                    .dualAxisControlWeight(1)
                }
            }
        }
    }

    @ViewBuilder
    private var dualAxisAxisRanges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                RangeControlRow(
                    label: "X",
                    minPlaceholder: formatAuto(activeLayout?.axisXMin),
                    maxPlaceholder: formatAuto(activeLayout?.axisXMax),
                    minValue: displayState.axisRangeOverride?.xMin,
                    maxValue: displayState.axisRangeOverride?.xMax,
                    sourceResetToken: sourceResetToken,
                    fieldWidth: 66,
                    onMinCommit: { updateRange(.xMin, value: $0) },
                    onMaxCommit: { updateRange(.xMax, value: $0) }
                )
                RangeControlRow(
                    label: "Left Y",
                    minPlaceholder: formatAuto(activeLayout?.axisLeftYMin),
                    maxPlaceholder: formatAuto(activeLayout?.axisLeftYMax),
                    minValue: displayState.axisRangeOverride?.leftYMin,
                    maxValue: displayState.axisRangeOverride?.leftYMax,
                    sourceResetToken: sourceResetToken,
                    fieldWidth: 66,
                    onMinCommit: { updateRange(.leftYMin, value: $0) },
                    onMaxCommit: { updateRange(.leftYMax, value: $0) }
                )
                RangeControlRow(
                    label: "Right Y",
                    minPlaceholder: formatAuto(activeLayout?.axisRightYMin),
                    maxPlaceholder: formatAuto(activeLayout?.axisRightYMax),
                    minValue: displayState.axisRangeOverride?.rightYMin,
                    maxValue: displayState.axisRangeOverride?.rightYMax,
                    sourceResetToken: sourceResetToken,
                    fieldWidth: 66,
                    onMinCommit: { updateRange(.rightYMin, value: $0) },
                    onMaxCommit: { updateRange(.rightYMax, value: $0) }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                RangeControlRow(
                    label: "X",
                    minPlaceholder: formatAuto(activeLayout?.axisXMin),
                    maxPlaceholder: formatAuto(activeLayout?.axisXMax),
                    minValue: displayState.axisRangeOverride?.xMin,
                    maxValue: displayState.axisRangeOverride?.xMax,
                    sourceResetToken: sourceResetToken,
                    fieldWidth: 66,
                    onMinCommit: { updateRange(.xMin, value: $0) },
                    onMaxCommit: { updateRange(.xMax, value: $0) }
                )
                RangeControlRow(
                    label: "Left Y",
                    minPlaceholder: formatAuto(activeLayout?.axisLeftYMin),
                    maxPlaceholder: formatAuto(activeLayout?.axisLeftYMax),
                    minValue: displayState.axisRangeOverride?.leftYMin,
                    maxValue: displayState.axisRangeOverride?.leftYMax,
                    sourceResetToken: sourceResetToken,
                    fieldWidth: 66,
                    onMinCommit: { updateRange(.leftYMin, value: $0) },
                    onMaxCommit: { updateRange(.leftYMax, value: $0) }
                )
                RangeControlRow(
                    label: "Right Y",
                    minPlaceholder: formatAuto(activeLayout?.axisRightYMin),
                    maxPlaceholder: formatAuto(activeLayout?.axisRightYMax),
                    minValue: displayState.axisRangeOverride?.rightYMin,
                    maxValue: displayState.axisRangeOverride?.rightYMax,
                    sourceResetToken: sourceResetToken,
                    fieldWidth: 66,
                    onMinCommit: { updateRange(.rightYMin, value: $0) },
                    onMaxCommit: { updateRange(.rightYMax, value: $0) }
                )
            }
        }
        if displayState.axisRangeOverride != nil {
            Button("Reset ranges") {
                displayState.axisRangeOverride = nil
                onDisplayStateChange?()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var dualAxisSeriesStyle: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
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
                axisColorPolicyRow
            }

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
                HStack(alignment: .top, spacing: 12) {
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
                    axisColorPolicyRow
                }
            }
        }
    }

    @ViewBuilder
    private var axisColorPolicyRow: some View {
        menuPickerRow(
            label: "Axis colors",
            labelWidth: 92,
            selection: axisColorPolicyBinding,
            pickerWidth: 180
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
        ControlRow(label: label, labelWidth: 40, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    menuPickerRow(label: "Line", labelWidth: 52, selection: linePatternBinding, pickerWidth: 96) {
                        Text("Solid").tag(DualAxisLinePattern.solid)
                        Text("Dashed").tag(DualAxisLinePattern.dashed)
                    }
                    numericFieldRow(
                        label: "Width",
                        value: lineWidth,
                        placeholder: widthPlaceholder,
                        onCommit: onLineWidthCommit
                    )
                }
                HStack(spacing: 10) {
                    menuPickerRow(label: "Marker", labelWidth: 52, selection: markerShapeBinding, pickerWidth: 96) {
                        Text("Circle").tag(DualAxisMarkerShape.circle)
                        Text("Square").tag(DualAxisMarkerShape.square)
                    }
                    numericFieldRow(
                        label: "Size",
                        value: pointRadius,
                        placeholder: sizePlaceholder,
                        onCommit: onPointRadiusCommit
                    )
                }
                menuPickerRow(label: "Fill", labelWidth: 52, selection: markerFillBinding, pickerWidth: 110) {
                    Text("Filled").tag(DualAxisMarkerFill.filled)
                    Text("Open").tag(DualAxisMarkerFill.open)
                }
            }
        }
    }

    @ViewBuilder
    private func numericFieldRow(
        label: String,
        value: Double?,
        placeholder: String,
        onCommit: @escaping (Double?) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            CompactNumericField(
                placeholder: placeholder,
                currentValue: value,
                sourceResetToken: sourceResetToken,
                width: 48,
                onCommit: onCommit
            )
        }
    }

    private var widthPlaceholder: String {
        if let v = mergedStyleForPlaceholders.lineWidth { return formatAuto(v) }
        return "2"
    }

    private var sizePlaceholder: String {
        if let v = mergedStyleForPlaceholders.pointRadius { return formatAuto(v) }
        return "2.5"
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
        pickerWidth: CGFloat,
        @ViewBuilder options: @escaping () -> Options
    ) -> some View {
        ControlRow(label: label, labelWidth: labelWidth, spacing: 6) {
            Picker("", selection: selection) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: pickerWidth, alignment: .leading)
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

private struct DualAxisControlWeightKey: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

private struct DualAxisControlWeightedRowLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let weights = subviews.map { max($0[DualAxisControlWeightKey.self], 0.0001) }
        let totalWeight = weights.reduce(0, +)
        let proposedWidth = proposal.width ?? idealWidth(subviews: subviews, totalSpacing: totalSpacing)
        let contentWidth = max(proposedWidth - totalSpacing, 0)

        var maxHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let width = contentWidth * weights[index] / totalWeight
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
            maxHeight = max(maxHeight, size.height)
        }

        return CGSize(width: proposedWidth, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }

        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let weights = subviews.map { max($0[DualAxisControlWeightKey.self], 0.0001) }
        let totalWeight = weights.reduce(0, +)
        let contentWidth = max(bounds.width - totalSpacing, 0)
        var x = bounds.minX

        for (index, subview) in subviews.enumerated() {
            let width = contentWidth * weights[index] / totalWeight
            let subBounds = CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
            subview.place(at: subBounds.origin, proposal: ProposedViewSize(subBounds.size))
            x += width + spacing
        }
    }

    private func idealWidth(subviews: Subviews, totalSpacing: CGFloat) -> CGFloat {
        let ideal = subviews.reduce(CGFloat.zero) { partialResult, subview in
            partialResult + subview.sizeThatFits(.unspecified).width
        }
        return ideal + totalSpacing
    }
}

private extension View {
    func dualAxisControlWeight(_ weight: CGFloat) -> some View {
        layoutValue(key: DualAxisControlWeightKey.self, value: weight)
    }
}
