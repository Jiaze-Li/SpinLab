import SwiftUI

/// Heatmap Z/colorbar label override control.
struct HeatmapZLabelControl: View {
    let renderedDefault: String
    let currentValue: String
    let sourceResetToken: String
    let onCommit: (String) -> Void

    var body: some View {
        LabelOverrideField(
            label: "Z",
            renderedDefault: renderedDefault,
            currentValue: currentValue,
            sourceResetToken: sourceResetToken,
            onCommit: onCommit,
            fieldMaxWidth: .infinity
        )
        .frame(maxWidth: .infinity)
    }
}
