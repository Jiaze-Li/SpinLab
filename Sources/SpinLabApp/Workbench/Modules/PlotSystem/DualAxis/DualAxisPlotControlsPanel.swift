import Foundation
import SwiftUI

/// Generic DualAxis controls surface.
/// This panel edits display state only; workflow adapters still own scientific payload construction.
struct DualAxisPlotControlsPanel: View {
    @Binding var displayState: DualAxisDisplayState
    var activeLayout: DualAxisPlotLayout? = nil
    var sourceResetToken: String = ""
    var onDisplayStateChange: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            dualAxisLabelOverrides
            Divider()
            dualAxisAxisRanges
            Divider()
            dualAxisSeriesStyle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    renderedDefault: "",
                    currentValue: displayState.titleOverride,
                    onCommit: { updateLabel(\.titleOverride, value: $0) }
                )
                .dualAxisControlWeight(3)

                labelOverrideField(
                    label: "X",
                    renderedDefault: "",
                    currentValue: displayState.xLabelOverride,
                    onCommit: { updateLabel(\.xLabelOverride, value: $0) }
                )
                .dualAxisControlWeight(1)

                labelOverrideField(
                    label: "Left Y",
                    renderedDefault: "",
                    currentValue: displayState.leftYLabelOverride,
                    onCommit: { updateLabel(\.leftYLabelOverride, value: $0) }
                )
                .dualAxisControlWeight(1)

                labelOverrideField(
                    label: "Right Y",
                    renderedDefault: "",
                    currentValue: displayState.rightYLabelOverride,
                    onCommit: { updateLabel(\.rightYLabelOverride, value: $0) }
                )
                .dualAxisControlWeight(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                DualAxisControlWeightedRowLayout(spacing: 12) {
                    labelOverrideField(
                        label: "Plot title",
                        renderedDefault: "",
                        currentValue: displayState.titleOverride,
                        onCommit: { updateLabel(\.titleOverride, value: $0) }
                    )
                    .dualAxisControlWeight(3)

                    labelOverrideField(
                        label: "X",
                        renderedDefault: "",
                        currentValue: displayState.xLabelOverride,
                        onCommit: { updateLabel(\.xLabelOverride, value: $0) }
                    )
                    .dualAxisControlWeight(1)
                }

                DualAxisControlWeightedRowLayout(spacing: 12) {
                    labelOverrideField(
                        label: "Left Y",
                        renderedDefault: "",
                        currentValue: displayState.leftYLabelOverride,
                        onCommit: { updateLabel(\.leftYLabelOverride, value: $0) }
                    )
                    .dualAxisControlWeight(1)

                    labelOverrideField(
                        label: "Right Y",
                        renderedDefault: "",
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
                    markerFillBinding: leftMarkerFillBinding
                )
                dualAxisSeriesStyleRow(
                    label: "Right",
                    linePatternBinding: rightLinePatternBinding,
                    markerShapeBinding: rightMarkerShapeBinding,
                    markerFillBinding: rightMarkerFillBinding
                )
                axisColorPolicyRow
            }

            VStack(alignment: .leading, spacing: 6) {
                dualAxisSeriesStyleRow(
                    label: "Left",
                    linePatternBinding: leftLinePatternBinding,
                    markerShapeBinding: leftMarkerShapeBinding,
                    markerFillBinding: leftMarkerFillBinding
                )
                HStack(alignment: .top, spacing: 12) {
                    dualAxisSeriesStyleRow(
                        label: "Right",
                        linePatternBinding: rightLinePatternBinding,
                        markerShapeBinding: rightMarkerShapeBinding,
                        markerFillBinding: rightMarkerFillBinding
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
        markerFillBinding: Binding<DualAxisMarkerFill>
    ) -> some View {
        ControlRow(label: label, labelWidth: 40, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                menuPickerRow(label: "Line", labelWidth: 52, selection: linePatternBinding, pickerWidth: 110) {
                    Text("Solid").tag(DualAxisLinePattern.solid)
                    Text("Dashed").tag(DualAxisLinePattern.dashed)
                }
                menuPickerRow(label: "Marker", labelWidth: 52, selection: markerShapeBinding, pickerWidth: 110) {
                    Text("Circle").tag(DualAxisMarkerShape.circle)
                    Text("Square").tag(DualAxisMarkerShape.square)
                }
                menuPickerRow(label: "Fill", labelWidth: 52, selection: markerFillBinding, pickerWidth: 110) {
                    Text("Filled").tag(DualAxisMarkerFill.filled)
                    Text("Open").tag(DualAxisMarkerFill.open)
                }
            }
        }
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
