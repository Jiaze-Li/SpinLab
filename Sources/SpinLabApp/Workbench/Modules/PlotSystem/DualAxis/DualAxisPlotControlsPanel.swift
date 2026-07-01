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
            GroupBox("Labels") {
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

            GroupBox("Ranges") {
                VStack(alignment: .leading, spacing: 8) {
                    rangeRow(
                        label: "X",
                        minBound: .xMin,
                        maxBound: .xMax,
                        minPlaceholder: formatAuto(activeLayout?.axisXMin),
                        maxPlaceholder: formatAuto(activeLayout?.axisXMax),
                        minValue: displayState.axisRangeOverride?.xMin,
                        maxValue: displayState.axisRangeOverride?.xMax
                    )
                    rangeRow(
                        label: "Left Y",
                        minBound: .leftYMin,
                        maxBound: .leftYMax,
                        minPlaceholder: formatAuto(activeLayout?.axisLeftYMin),
                        maxPlaceholder: formatAuto(activeLayout?.axisLeftYMax),
                        minValue: displayState.axisRangeOverride?.leftYMin,
                        maxValue: displayState.axisRangeOverride?.leftYMax
                    )
                    rangeRow(
                        label: "Right Y",
                        minBound: .rightYMin,
                        maxBound: .rightYMax,
                        minPlaceholder: formatAuto(activeLayout?.axisRightYMin),
                        maxPlaceholder: formatAuto(activeLayout?.axisRightYMax),
                        minValue: displayState.axisRangeOverride?.rightYMin,
                        maxValue: displayState.axisRangeOverride?.rightYMax
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

            GroupBox("Left Series") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Line", selection: leftLinePatternBinding) {
                        Text("Solid").tag(DualAxisLinePattern.solid)
                        Text("Dashed").tag(DualAxisLinePattern.dashed)
                    }
                    .pickerStyle(.segmented)
                    Picker("Marker", selection: leftMarkerShapeBinding) {
                        Text("Circle").tag(DualAxisMarkerShape.circle)
                        Text("Square").tag(DualAxisMarkerShape.square)
                    }
                    .pickerStyle(.segmented)
                    Picker("Fill", selection: leftMarkerFillBinding) {
                        Text("Filled").tag(DualAxisMarkerFill.filled)
                        Text("Open").tag(DualAxisMarkerFill.open)
                    }
                    .pickerStyle(.segmented)
                }
            }

            GroupBox("Right Series") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Line", selection: rightLinePatternBinding) {
                        Text("Solid").tag(DualAxisLinePattern.solid)
                        Text("Dashed").tag(DualAxisLinePattern.dashed)
                    }
                    .pickerStyle(.segmented)
                    Picker("Marker", selection: rightMarkerShapeBinding) {
                        Text("Circle").tag(DualAxisMarkerShape.circle)
                        Text("Square").tag(DualAxisMarkerShape.square)
                    }
                    .pickerStyle(.segmented)
                    Picker("Fill", selection: rightMarkerFillBinding) {
                        Text("Filled").tag(DualAxisMarkerFill.filled)
                        Text("Open").tag(DualAxisMarkerFill.open)
                    }
                    .pickerStyle(.segmented)
                }
            }

            GroupBox("Axis Colors") {
                Picker("Axis colors", selection: axisColorPolicyBinding) {
                    Text("Template paired").tag(DualAxisAxisColorPolicy.templatePaired)
                    Text("Monochrome").tag(DualAxisAxisColorPolicy.monochrome)
                }
                .pickerStyle(.segmented)
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

    @ViewBuilder
    private func rangeRow(
        label: String,
        minBound: DualAxisAxisRangeBound,
        maxBound: DualAxisAxisRangeBound,
        minPlaceholder: String,
        maxPlaceholder: String,
        minValue: Double?,
        maxValue: Double?
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .frame(width: 52, alignment: .trailing)
            DualAxisRangeBoundField(
                debugName: "\(label)-min",
                placeholder: minPlaceholder,
                currentValue: minValue,
                sourceResetToken: sourceResetToken,
                onCommit: { updateRange(minBound, value: $0) }
            )
            Text("–")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            DualAxisRangeBoundField(
                debugName: "\(label)-max",
                placeholder: maxPlaceholder,
                currentValue: maxValue,
                sourceResetToken: sourceResetToken,
                onCommit: { updateRange(maxBound, value: $0) }
            )
        }
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

private struct DualAxisRangeBoundField: View {
    let debugName: String
    let placeholder: String
    let currentValue: Double?
    let sourceResetToken: String
    let onCommit: (Double?) -> Void

    @State private var editText: String = ""
    @State private var isDirty: Bool = false
    @FocusState private var focused: Bool

    private var hasOverride: Bool { currentValue != nil }
    private var displayText: String {
        if let currentValue { return formatBound(currentValue) }
        return placeholder
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: dirtyBinding)
                .textFieldStyle(.roundedBorder)
                .font(WorkbenchUIStyle.controlValueFont)
                .foregroundStyle(hasOverride ? Color.primary : Color.secondary)
                .frame(width: 64)
                .focused($focused)
                .onSubmit { commitIfDirty() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commitIfDirty() }
                }
            if hasOverride {
                Button {
                    onCommit(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }
        }
        .task(id: displayText) {
            guard !focused else { return }
            editText = displayText
            isDirty = false
        }
        .task(id: sourceResetToken) {
            editText = displayText
            isDirty = false
            focused = false
        }
    }

    private var dirtyBinding: Binding<String> {
        Binding(
            get: { editText },
            set: { newValue in
                editText = newValue
                isDirty = true
            }
        )
    }

    private func commitIfDirty() {
        guard isDirty else { return }
        isDirty = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onCommit(nil)
            return
        }
        guard let parsed = Double(trimmed) else { return }
        if parsed == currentValue { return }
        onCommit(parsed)
    }

    private func formatBound(_ value: Double) -> String {
        if value == 0 { return "0" }
        let absValue = Swift.abs(value)
        if absValue >= 0.001 && absValue < 100_000 { return String(format: "%g", value) }
        return String(format: "%.3e", value)
    }
}
