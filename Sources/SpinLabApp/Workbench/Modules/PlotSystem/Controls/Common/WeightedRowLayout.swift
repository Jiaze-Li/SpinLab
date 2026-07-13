import SwiftUI

// MARK: - WeightedRowLayout

/// Lays out subviews in a single row, each sized proportionally to a
/// per-subview weight (attached via `Key`, a caller-supplied `LayoutValueKey`
/// whose `Value` is `CGFloat`). Weights below `0.0001` are clamped to that
/// floor so a zero/negative weight cannot collapse a column or divide by zero.
///
/// Callers each define their own `Key` type (and a `layoutValue(key:value:)`
/// convenience) so weight semantics stay scoped to the call site — this type
/// owns only the sizing/placement algorithm, which is identical regardless of
/// which key tags the weight.
struct WeightedRowLayout<Key: LayoutValueKey>: Layout where Key.Value == CGFloat {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let weights = subviews.map { max($0[Key.self], 0.0001) }
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
        let weights = subviews.map { max($0[Key.self], 0.0001) }
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
