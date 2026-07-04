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
            compactMenuRow(label: "Line", key: "lineWidth", options: Self.lineWidthOptions)
            compactMenuRow(label: "Scatter", key: "pointRadius", options: Self.pointRadiusOptions)
        }
    }

    @ViewBuilder
    private func compactMenuRow(label: String, key: String, options: [(label: String, raw: String?)]) -> some View {
        let currentRaw = globalPlotDefaults[key]
        HStack(spacing: 6) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
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
            .pickerStyle(.menu)
            .frame(width: 74)
        }
    }
}
