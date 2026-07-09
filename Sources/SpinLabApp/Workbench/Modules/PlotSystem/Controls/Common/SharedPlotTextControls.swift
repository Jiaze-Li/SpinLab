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
        PlotControlWeightedRowLayout(spacing: 12) {
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

// MARK: - PlotControlWeightedRowLayout

private struct PlotControlWeightKey: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

private struct PlotControlWeightedRowLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let weights = subviews.map { max($0[PlotControlWeightKey.self], 0.0001) }
        let totalWeight = weights.reduce(0, +)
        let proposedWidth = proposal.width ?? idealWidth(subviews: subviews, totalSpacing: totalSpacing)
        let contentWidth = max(proposedWidth - totalSpacing, 0)

        var maxHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let width = contentWidth * weights[index] / totalWeight
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
            maxHeight = max(maxHeight, size.height)
        }

        return CGSize(width: proposedWidth, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }

        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let weights = subviews.map { max($0[PlotControlWeightKey.self], 0.0001) }
        let totalWeight = weights.reduce(0, +)
        let contentWidth = max(bounds.width - totalSpacing, 0)
        var x = bounds.minX

        for (index, subview) in subviews.enumerated() {
            let width = contentWidth * weights[index] / totalWeight
            let subBounds = CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
            subview.place(at: subBounds.origin, proposal: ProposedViewSize(subBounds.size))
            x += width + spacing
        }
    }

    private func idealWidth(subviews: Subviews, totalSpacing: CGFloat) -> CGFloat {
        let ideal = subviews.reduce(CGFloat.zero) { partialResult, subview in
            partialResult + subview.sizeThatFits(.unspecified).width
        }
        return ideal + totalSpacing
    }
}

private extension View {
    func plotControlWeight(_ weight: CGFloat) -> some View {
        layoutValue(key: PlotControlWeightKey.self, value: weight)
    }
}
