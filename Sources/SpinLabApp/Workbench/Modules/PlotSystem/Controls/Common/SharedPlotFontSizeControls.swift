import SwiftUI

// MARK: - SharedPlotFontSizeControls

/// Shared font-size pickers for title, axis-title, and tick labels.
struct SharedPlotFontSizeControls: View {
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: (() -> Void)?

    var body: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        HStack(spacing: 10) {
            Text("Font Size")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            SharedPlotFontSizePicker(
                label: "Title",
                current: style.titleFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "titleFontSize"),
                onStyleChange: onStyleChange
            )
            SharedPlotFontSizePicker(
                label: "Axis",
                current: style.axisTitleFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "axisTitleFontSize"),
                onStyleChange: onStyleChange
            )
            SharedPlotFontSizePicker(
                label: "Ticks",
                current: style.tickLabelFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "tickLabelFontSize"),
                onStyleChange: onStyleChange
            )
        }
    }
}
