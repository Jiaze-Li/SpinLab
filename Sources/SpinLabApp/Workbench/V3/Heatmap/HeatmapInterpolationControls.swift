import SwiftUI

/// Heatmap display-interpolation control row. Nearest is the scientifically safer default;
/// Log-Space Gaussian 1.5x is an opt-in for smoother publication/export renders that stays
/// well-behaved around sharp diffraction peaks. Display-only — never applied to any
/// workflow's stored scientific data.
struct HeatmapInterpolationControls: View {
    let interpolationMode: HeatmapInterpolationMode
    let onInterpolationModeChange: (HeatmapInterpolationMode) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("Interpolation")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            Picker("", selection: Binding<HeatmapInterpolationMode>(
                get: { interpolationMode },
                set: { onInterpolationModeChange($0) }
            )) {
                Text("Nearest").tag(HeatmapInterpolationMode.nearest)
                Text("Log-Space Gaussian 1.5×").tag(HeatmapInterpolationMode.logSpaceGaussian1p5x)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
    }
}
