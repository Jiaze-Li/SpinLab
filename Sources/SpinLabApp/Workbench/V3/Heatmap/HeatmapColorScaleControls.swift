import SwiftUI

/// Heatmap color-scale control row.
struct HeatmapColorScaleControls: View {
    let colorScaleMode: PlotScaleTransform
    let onColorScaleModeChange: (PlotScaleTransform) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Color Scale")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            Picker("", selection: Binding<PlotScaleTransform>(
                get: { colorScaleMode },
                set: { onColorScaleModeChange($0) }
            )) {
                Text("Linear").tag(PlotScaleTransform.linear)
                Text("Log").tag(PlotScaleTransform.log10)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
        }
    }
}
