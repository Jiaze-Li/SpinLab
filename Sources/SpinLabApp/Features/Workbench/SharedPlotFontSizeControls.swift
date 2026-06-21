import SwiftUI

// MARK: - SharedPlotFontSizeControls

/// Shared font-size pickers for title, axis-title, and tick labels.
struct SharedPlotFontSizeControls: View {
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: (() -> Void)?

    var body: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        HStack(spacing: 10) {
            Text("Size")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            fontSizePicker(label: "Title", key: "titleFontSize", current: style.titleFontSize)
            fontSizePicker(label: "Axis", key: "axisTitleFontSize", current: style.axisTitleFontSize)
            fontSizePicker(label: "Ticks", key: "tickLabelFontSize", current: style.tickLabelFontSize)
        }
    }

    @ViewBuilder
    private func fontSizePicker(label: String, key: String, current: CGFloat) -> some View {
        let options: [CGFloat] = [12, 14, 16, 18, 19, 20, 22, 24, 25, 28, 32]
        HStack(spacing: 2) {
            Text(label)
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            Picker("", selection: Binding<CGFloat>(
                get: { globalPlotDefaults[key].flatMap { Double($0).map { CGFloat($0) } } ?? current },
                set: { newValue in
                    globalPlotDefaults[key] = "\(Int(newValue))"
                    onStyleChange?()
                }
            )) {
                ForEach(options, id: \.self) { value in
                    Text("\(Int(value))").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 58)
        }
    }
}
