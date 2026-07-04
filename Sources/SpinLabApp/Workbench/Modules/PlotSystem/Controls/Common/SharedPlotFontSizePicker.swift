import SwiftUI

// MARK: - SharedPlotFontSizePicker

/// Shared font-size picker row used by plot controls that expose global chart
/// style overrides.
struct SharedPlotFontSizePicker: View {
    let label: String
    let key: String
    let current: CGFloat
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: (() -> Void)?
    var labelFont: Font = WorkbenchUIStyle.controlLabelFont
    var pickerWidth: CGFloat = 58

    private static let options: [CGFloat] = [12, 14, 16, 18, 19, 20, 22, 24, 25, 28, 32]

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(labelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                .fixedSize()
            Picker("", selection: Binding<CGFloat>(
                get: { globalPlotDefaults[key].flatMap { Double($0).map { CGFloat($0) } } ?? current },
                set: { newValue in
                    globalPlotDefaults[key] = "\(Int(newValue))"
                    onStyleChange?()
                }
            )) {
                ForEach(Self.options, id: \.self) { value in
                    Text("\(Int(value))").tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: pickerWidth)
        }
    }
}
