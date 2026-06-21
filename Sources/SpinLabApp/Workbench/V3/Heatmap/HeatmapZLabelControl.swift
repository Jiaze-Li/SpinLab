import SwiftUI

/// Heatmap Z/colorbar label override control.
struct HeatmapZLabelControl: View {
    let showZLabel: Bool
    let onShowZLabelChange: (Bool) -> Void
    let renderedDefault: String
    let currentValue: String
    let sourceResetToken: String
    let onCommit: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("Z", isOn: Binding(
                get: { showZLabel },
                set: { onShowZLabelChange($0) }
            ))
            .toggleStyle(.checkbox)
            .fixedSize()

            LabelOverrideField(
                label: "",
                renderedDefault: renderedDefault,
                currentValue: currentValue,
                sourceResetToken: sourceResetToken,
                onCommit: onCommit,
                fieldMaxWidth: .infinity
            )
        }
        .frame(maxWidth: .infinity)
    }
}
