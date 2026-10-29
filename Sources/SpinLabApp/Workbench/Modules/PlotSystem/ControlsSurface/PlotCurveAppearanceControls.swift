import SwiftUI

/// Shared primitive of Curve Appearance (CS-38b): a "label [menu]" field used for line pattern,
/// width, marker shape/size/fill and the Cartesian Line/Scatter defaults alike. The mode
/// components decide which fields exist; this view only draws one of them.
struct PlotLabeledMenu<Value: Hashable>: View {
    struct Option {
        let label: String
        let value: Value
    }

    let label: String
    let selection: Binding<Value>
    let options: [Option]
    var width: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (72, 84, 96)
    /// Names the menu for the layout probe, and prefixes its accessibility label (e.g. "Left")
    /// when the same field repeats in several rows.
    var probeID: String? = nil
    var accessibilityContext: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(label).workbenchTextRole(.label).fixedSize()
            Picker("", selection: selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0].label).tag(options[$0].value) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: width.min, idealWidth: width.ideal, maxWidth: width.max, alignment: .leading)
            .workbenchControl(.menu)
            .workbenchProbed(ifNamed: probeID)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityContext.map { "\($0) \(label)" } ?? label)
    }
}
