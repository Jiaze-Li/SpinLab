import SwiftUI

/// Heatmap display-interpolation control row. Nearest is the scientifically safer default;
/// Bilinear 2x is an opt-in for smoother publication/export renders. Display-only — never
/// applied to any workflow's stored scientific data.
struct HeatmapInterpolationControls: View {
    let interpolationMode: HeatmapInterpolationMode
    let onInterpolationModeChange: (HeatmapInterpolationMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Interpolation")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            Picker("", selection: Binding<HeatmapInterpolationMode>(
                get: { interpolationMode },
                set: { onInterpolationModeChange($0) }
            )) {
                Text("Nearest").tag(HeatmapInterpolationMode.nearest)
                Text("Bilinear 2x").tag(HeatmapInterpolationMode.bilinear)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
        }
    }
}
