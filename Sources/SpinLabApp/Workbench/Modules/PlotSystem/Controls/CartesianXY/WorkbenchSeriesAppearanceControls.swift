import SwiftUI

// MARK: - WorkbenchSeriesAppearanceControls

/// Shell-level line width and scatter radius controls shared by all Cartesian XY workflows.
///
/// Both settings persist via `globalPlotDefaults` (same mechanism as font sizes).
/// "Auto" leaves the renderer to use its built-in defaults (series.lineWidth ≈ 2.0, dot radius 3.5).
struct WorkbenchSeriesAppearanceControls: View {
    @Binding var globalPlotDefaults: [String: String]
    var onStyleChange: (() -> Void)?

    private static let lineWidthOptions: [(label: String, raw: String?)] = [
        ("Auto", nil),
        ("0.5", "0.5"), ("1", "1"), ("1.5", "1.5"), ("2", "2"),
        ("2.5", "2.5"), ("3", "3"), ("4", "4"), ("5", "5"),
    ]

    private static let pointRadiusOptions: [(label: String, raw: String?)] = [
        ("Auto", nil),
        ("1", "1"), ("2", "2"), ("3", "3"), ("3.5", "3.5"),
        ("4", "4"), ("5", "5"), ("6", "6"), ("8", "8"), ("10", "10"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            Text("Line")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            appearancePicker(
                key: "lineWidth",
                options: Self.lineWidthOptions
            )
            .frame(width: 68)

            Text("Scatter")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            appearancePicker(
                key: "pointRadius",
                options: Self.pointRadiusOptions
            )
            .frame(width: 68)
        }
    }

    @ViewBuilder
    private func appearancePicker(key: String, options: [(label: String, raw: String?)]) -> some View {
        let currentRaw = globalPlotDefaults[key]
        Picker("", selection: Binding<String?>(
            get: { currentRaw },
            set: { newVal in
                if let v = newVal {
                    globalPlotDefaults[key] = v
                } else {
                    globalPlotDefaults.removeValue(forKey: key)
                }
                onStyleChange?()
            }
        )) {
            ForEach(options, id: \.raw) { opt in
                Text(opt.label).tag(opt.raw)
            }
        }
        .labelsHidden()
    }
}
