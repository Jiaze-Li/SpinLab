import SwiftUI

/// Heatmap Z/colorbar visibility and label override control.
///
/// The checkbox controls the entire colorbar block (gradient, tick labels, Z title).
struct HeatmapZLabelControl: View {
    let showColorbar: Bool
    let onShowColorbarChange: (Bool) -> Void
    let renderedDefault: String
    let currentValue: String
    let sourceResetToken: String
    let onCommit: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("Z", isOn: Binding(
                get: { showColorbar },
                set: { onShowColorbarChange($0) }
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
