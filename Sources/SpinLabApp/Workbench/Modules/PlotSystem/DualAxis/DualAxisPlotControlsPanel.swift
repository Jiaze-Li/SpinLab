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
        VStack(alignment: .leading, spacing: 10) {
            PlotControlSection(title: "Labels") {
                VStack(alignment: .leading, spacing: 8) {
                    SharedPlotTextFieldRow(
                        label: "Title override",
                        placeholder: "Title override",
                        text: stringBinding(get: { displayState.titleOverride }, set: { displayState.titleOverride = $0 }),
                        fieldMinWidth: nil,
                        fieldMaxWidth: .infinity
                    )
                    SharedPlotTextFieldRow(
                        label: "X label override",
                        placeholder: "X label override",
                        text: stringBinding(get: { displayState.xLabelOverride }, set: { displayState.xLabelOverride = $0 }),
                        fieldMinWidth: nil,
                        fieldMaxWidth: .infinity
                    )
                    SharedPlotTextFieldRow(
                        label: "Left Y label override",
                        placeholder: "Left Y label override",
                        text: stringBinding(get: { displayState.leftYLabelOverride }, set: { displayState.leftYLabelOverride = $0 }),
                        fieldMinWidth: nil,
                        fieldMaxWidth: .infinity
                    )
                    SharedPlotTextFieldRow(
                        label: "Right Y label override",
                        placeholder: "Right Y label override",
                        text: stringBinding(get: { displayState.rightYLabelOverride }, set: { displayState.rightYLabelOverride = $0 }),
                        fieldMinWidth: nil,
                        fieldMaxWidth: .infinity
                    )
                }
            }

            PlotControlSection(title: "Ranges") {
                VStack(alignment: .leading, spacing: 8) {
                    RangeControlRow(
                        label: "X",
                        minPlaceholder: formatAuto(activeLayout?.axisXMin),
                        maxPlaceholder: formatAuto(activeLayout?.axisXMax),
                        minValue: displayState.axisRangeOverride?.xMin,
                        maxValue: displayState.axisRangeOverride?.xMax,
                        sourceResetToken: sourceResetToken,
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
                        onMinCommit: { updateRange(.rightYMin, value: $0) },
                        onMaxCommit: { updateRange(.rightYMax, value: $0) }
                    )
                    if displayState.axisRangeOverride != nil {
                        Button("Reset ranges") {
                            displayState.axisRangeOverride = nil
                            onDisplayStateChange?()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }

            PlotControlSection(title: "Left Series") {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedControlRow(label: "Line", labelWidth: 52, selection: leftLinePatternBinding) {
                        Text("Solid").tag(DualAxisLinePattern.solid)
                        Text("Dashed").tag(DualAxisLinePattern.dashed)
                    }
                    SegmentedControlRow(label: "Marker", labelWidth: 52, selection: leftMarkerShapeBinding) {
                        Text("Circle").tag(DualAxisMarkerShape.circle)
                        Text("Square").tag(DualAxisMarkerShape.square)
                    }
                    SegmentedControlRow(label: "Fill", labelWidth: 52, selection: leftMarkerFillBinding) {
                        Text("Filled").tag(DualAxisMarkerFill.filled)
                        Text("Open").tag(DualAxisMarkerFill.open)
                    }
                }
            }

            PlotControlSection(title: "Right Series") {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedControlRow(label: "Line", labelWidth: 52, selection: rightLinePatternBinding) {
                        Text("Solid").tag(DualAxisLinePattern.solid)
                        Text("Dashed").tag(DualAxisLinePattern.dashed)
                    }
                    SegmentedControlRow(label: "Marker", labelWidth: 52, selection: rightMarkerShapeBinding) {
                        Text("Circle").tag(DualAxisMarkerShape.circle)
                        Text("Square").tag(DualAxisMarkerShape.square)
                    }
                    SegmentedControlRow(label: "Fill", labelWidth: 52, selection: rightMarkerFillBinding) {
                        Text("Filled").tag(DualAxisMarkerFill.filled)
                        Text("Open").tag(DualAxisMarkerFill.open)
                    }
                }
            }

            PlotControlSection(title: "Axis Colors") {
                SegmentedControlRow(label: "Axis colors", labelWidth: 92, selection: axisColorPolicyBinding) {
                    Text("Template paired").tag(DualAxisAxisColorPolicy.templatePaired)
                    Text("Monochrome").tag(DualAxisAxisColorPolicy.monochrome)
                }
            }
        }
    }

    private func stringBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<String> {
        Binding(
            get: get,
            set: { value in
                set(value)
                onDisplayStateChange?()
            }
        )
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
