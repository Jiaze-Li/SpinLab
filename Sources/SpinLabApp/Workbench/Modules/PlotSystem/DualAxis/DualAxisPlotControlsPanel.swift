import SwiftUI

/// Generic DualAxis controls surface.
/// This panel edits display state only; workflow adapters still own scientific payload construction.
struct DualAxisPlotControlsPanel: View {
    @Binding var displayState: DualAxisDisplayState
    var onDisplayStateChange: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Labels") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title override", text: stringBinding(get: { displayState.titleOverride }, set: { displayState.titleOverride = $0 }))
                    TextField("X label override", text: stringBinding(get: { displayState.xLabelOverride }, set: { displayState.xLabelOverride = $0 }))
                    TextField("Left Y label override", text: stringBinding(get: { displayState.leftYLabelOverride }, set: { displayState.leftYLabelOverride = $0 }))
                    TextField("Right Y label override", text: stringBinding(get: { displayState.rightYLabelOverride }, set: { displayState.rightYLabelOverride = $0 }))
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
