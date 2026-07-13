import SwiftUI

// MARK: - SharedPlotTextControls

/// Shared text override controls for plot title, X label, and Y label.
///
/// The row uses a weighted layout so the Title field occupies roughly 60% of
/// the available width while X and Y each take roughly 20%.
struct SharedPlotTextControls: View {
    let titleOverride: String
    let xLabelOverride: String
    let yLabelOverride: String
    let renderedTitle: String
    let renderedXLabel: String
    let renderedYLabel: String
    let sourceResetToken: String
    let onTitleOverride: (String) -> Void
    let onXLabelOverride: (String) -> Void
    let onYLabelOverride: (String) -> Void

    var body: some View {
        WeightedRowLayout<PlotControlWeightKey>(spacing: 12) {
            LabelOverrideField(
                label: "Plot title",
                renderedDefault: renderedTitle,
                currentValue: titleOverride,
                sourceResetToken: sourceResetToken,
                onCommit: onTitleOverride,
                fieldMaxWidth: .infinity
            )
            .plotControlWeight(3)

            LabelOverrideField(
                label: "X",
                renderedDefault: renderedXLabel,
                currentValue: xLabelOverride,
                sourceResetToken: sourceResetToken,
                onCommit: onXLabelOverride,
                fieldMaxWidth: .infinity
            )
            .plotControlWeight(1)

            LabelOverrideField(
                label: "Y",
                renderedDefault: renderedYLabel,
                currentValue: yLabelOverride,
                sourceResetToken: sourceResetToken,
                onCommit: onYLabelOverride,
                fieldMaxWidth: .infinity
            )
            .plotControlWeight(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - PlotControlWeightKey

private struct PlotControlWeightKey: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

private extension View {
    func plotControlWeight(_ weight: CGFloat) -> some View {
        layoutValue(key: PlotControlWeightKey.self, value: weight)
    }
}
