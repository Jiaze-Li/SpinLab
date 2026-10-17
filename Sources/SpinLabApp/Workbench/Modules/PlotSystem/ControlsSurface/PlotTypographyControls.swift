import SwiftUI

/// Font role a Plot Mode can expose. Each role maps to one shared style key and is shown only
/// when the mode's capability list declares it (CS-38).
enum PlotFontRole: CaseIterable {
    case title, axis, ticks, legend, point

    var label: String {
        switch self {
        case .title: return "Title"
        case .axis: return "Axis"
        case .ticks: return "Ticks"
        case .legend: return "Legend"
        case .point: return "Point"
        }
    }

    var styleKey: String {
        switch self {
        case .title: return "titleFontSize"
        case .axis: return "axisTitleFontSize"
        case .ticks: return "tickLabelFontSize"
        case .legend: return "legendFontSize"
        case .point: return "pointLabelFontSize"
        }
    }

    func size(in style: WorkbenchChartStyle) -> CGFloat {
        switch self {
        case .title: return style.titleFontSize
        case .axis: return style.axisTitleFontSize
        case .ticks: return style.tickLabelFontSize
        case .legend: return style.legendFontSize
        case .point: return style.pointLabelFontSize
        }
    }
}

/// The single Font row of the Plot region (Shared Typography, CS-38): one picker per declared
/// role, written to the shared chart style keys. Roles are a capability parameter; this view
/// knows nothing about workflows.
struct PlotTypographyControls: View {
    @Binding var globalPlotDefaults: [String: String]
    let roles: [PlotFontRole]
    let onStyleChange: () -> Void
    let idPrefix: String

    var body: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        WorkbenchControlGroup(id: "\(idPrefix).typography") {
            WorkbenchControlRow(id: "\(idPrefix).typography.row", label: "Font") {
                WorkbenchControlFlow(spacing: WorkbenchControlMetrics.groupSpacing, lineSpacing: AppSpacing.sm) {
                    ForEach(roles, id: \.self) { role in
                        picker(role, current: role.size(in: style))
                    }
                }
            }
        }
    }

    private func picker(_ role: PlotFontRole, current: CGFloat) -> some View {
        SharedPlotFontSizePicker(
            label: role.label,
            current: current,
            rawValue: $globalPlotDefaults.valueBinding(forKey: role.styleKey),
            onStyleChange: onStyleChange,
            pickerWidth: 50
        )
        .accessibilityLabel("\(role.label) font size")
        .accessibilityIdentifier("\(idPrefix).typography.\(role.label.lowercased())")
    }
}
