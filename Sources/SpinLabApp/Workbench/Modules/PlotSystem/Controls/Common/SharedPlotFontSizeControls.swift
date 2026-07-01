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
                key: "titleFontSize",
                current: style.titleFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange
            )
            SharedPlotFontSizePicker(
                label: "Axis",
                key: "axisTitleFontSize",
                current: style.axisTitleFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange
            )
            SharedPlotFontSizePicker(
                label: "Ticks",
                key: "tickLabelFontSize",
                current: style.tickLabelFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange
            )
        }
    }
}
