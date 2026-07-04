import SwiftUI

// MARK: - CompactTypographyRow

/// Compact shared typography row for Cartesian XY plot controls.
///
/// Uses the existing shared font-size picker semantics while allowing the row
/// to wrap on narrow widths.
struct CompactTypographyRow: View {
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: (() -> Void)?

    var body: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        ViewThatFits(in: .horizontal) {
            horizontalRow(style: style)
            verticalRow(style: style)
        }
    }

    private func horizontalRow(style: WorkbenchChartStyle) -> some View {
        HStack(spacing: 8) {
            Text("Font")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            SharedPlotFontSizePicker(
                label: "Title",
                key: "titleFontSize",
                current: style.titleFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Axis",
                key: "axisTitleFontSize",
                current: style.axisTitleFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Ticks",
                key: "tickLabelFontSize",
                current: style.tickLabelFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Legend",
                key: "legendFontSize",
                current: style.legendFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
            SharedPlotFontSizePicker(
                label: "Point",
                key: "pointLabelFontSize",
                current: style.pointLabelFontSize,
                globalPlotDefaults: $globalPlotDefaults,
                onStyleChange: onStyleChange,
                pickerWidth: 50
            )
        }
    }

    private func verticalRow(style: WorkbenchChartStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Font")
                    .font(WorkbenchUIStyle.controlLabelFont)
                    .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                    .fixedSize()
                SharedPlotFontSizePicker(
                    label: "Title",
                    key: "titleFontSize",
                    current: style.titleFontSize,
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange,
                    pickerWidth: 50
                )
                SharedPlotFontSizePicker(
                    label: "Axis",
                    key: "axisTitleFontSize",
                    current: style.axisTitleFontSize,
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange,
                    pickerWidth: 50
                )
                SharedPlotFontSizePicker(
                    label: "Ticks",
                    key: "tickLabelFontSize",
                    current: style.tickLabelFontSize,
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange,
                    pickerWidth: 50
                )
            }
            HStack(spacing: 8) {
                SharedPlotFontSizePicker(
                    label: "Legend",
                    key: "legendFontSize",
                    current: style.legendFontSize,
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange,
                    pickerWidth: 50
                )
                SharedPlotFontSizePicker(
                    label: "Point",
                    key: "pointLabelFontSize",
                    current: style.pointLabelFontSize,
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange,
                    pickerWidth: 50
                )
            }
        }
    }
}
