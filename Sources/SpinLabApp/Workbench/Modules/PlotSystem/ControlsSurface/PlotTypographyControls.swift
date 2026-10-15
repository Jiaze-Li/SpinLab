import SwiftUI

/// Axis / Ticks / Legend / Point font sizes — shared by `cartesianXY` and `dualAxis`
/// (the title size belongs to Common, CS-13). Keeps the same style keys and callbacks the
/// legacy typography row used.
struct PlotTypographyControls: View {
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: () -> Void
    let idPrefix: String

    var body: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        WorkbenchControlGroup(id: "\(idPrefix).typography") {
            WorkbenchControlRow(id: "\(idPrefix).typography.row", label: "Font") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    picker("Axis", current: style.axisTitleFontSize, key: "axisTitleFontSize")
                    picker("Ticks", current: style.tickLabelFontSize, key: "tickLabelFontSize")
                    picker("Legend", current: style.legendFontSize, key: "legendFontSize")
                    picker("Point", current: style.pointLabelFontSize, key: "pointLabelFontSize")
                }
            }
        }
    }

    private func picker(_ label: String, current: CGFloat, key: String) -> some View {
        SharedPlotFontSizePicker(
            label: label,
            current: current,
            rawValue: $globalPlotDefaults.valueBinding(forKey: key),
            onStyleChange: onStyleChange,
            pickerWidth: 50
        )
        .accessibilityLabel("\(label) font size")
        .accessibilityIdentifier("\(idPrefix).typography.\(label.lowercased())")
    }
}
