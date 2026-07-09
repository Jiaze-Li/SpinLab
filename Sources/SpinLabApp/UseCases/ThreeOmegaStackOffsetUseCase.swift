import Foundation

// MARK: - ThreeOmegaStackOffsetUseCase
//
// Computes a vertical stacking offset for each field-sweep curve so that
// curves at different temperatures are separated and do not overlap.
//
// Algorithm (adaptive adjacent spacing with minimum gap):
//   1. pp[i] = peak-to-peak amplitude of curve i (0 for empty or flat curves).
//   2. minGap = max(all pp) × minGapFraction
//   3. offset[0] = 0
//   4. offset[i+1] = offset[i] + max(minGap, (pp[i]/2 + pp[i+1]/2) × multiplier)
//
// Order-enforcing field-sweep placement:
//   1. curves are provided bottom-to-top in the desired physical stack order
//   2. each next curve is shifted just far enough to sit above the previous curve
//      by the configured gap
//   3. offsets may be positive or negative; only the order is fixed by input order
//
// Each pair of adjacent curves gets spacing proportional to their own amplitudes,
// so small-amplitude curves sit closer together while large-amplitude curves
// spread further apart. The minGap floor prevents tiny-amplitude curves from
// collapsing on top of each other.
//
// The multiplier controls spacing: 1.0 = curves just touch, >1.0 = gap between curves.
// multiplier must be >= 0. 0 = no stacking (all offsets zero).
// minGapFraction must be >= 0. 0 = no minimum gap floor.
// Caller is responsible for sorting sweeps before passing yValues.

struct ThreeOmegaStackOffsetUseCase {

    enum PlacementMode: Sendable {
        case adaptiveAdjacent
        case orderEnforcingBottomToTop
    }

    /// - Parameters:
    ///   - yValues: Y data arrays for each sweep, index-aligned with the sweep array.
    ///              Must be pre-sorted (e.g. temperature ascending = bottom to top).
    ///   - multiplier: Spacing multiplier (>= 0). Default 1.2 leaves ~20% gap between curves.
    ///   - minGapFraction: Minimum gap as a fraction of max peak-to-peak (>= 0). Default 0.15.
    ///   - placementMode: `adaptiveAdjacent` preserves the legacy adjacent-spacing behavior.
    ///                    `orderEnforcingBottomToTop` keeps the provided order fixed and
    ///                    shifts each curve just enough to remain above the previous one.
    /// - Returns: One offset value per sweep, index-aligned with yValues.
    func execute(
        yValues: [[Double]],
        multiplier: Double = 1.2,
        minGapFraction: Double = 0.15,
        placementMode: PlacementMode = .adaptiveAdjacent
    ) -> [Double] {
        guard !yValues.isEmpty else { return [] }

        switch placementMode {
        case .adaptiveAdjacent:
            return _adaptiveAdjacentOffsets(yValues: yValues, multiplier: multiplier, minGapFraction: minGapFraction)
        case .orderEnforcingBottomToTop:
            return _orderEnforcingOffsets(yValues: yValues, multiplier: multiplier, minGapFraction: minGapFraction)
        }
    }

    private func _peakToPeak(_ ys: [Double]) -> Double {
        guard let mn = ys.min(), let mx = ys.max() else { return 0.0 }
        return max(mx - mn, 0.0)
    }

    private func _bounds(_ ys: [Double]) -> (min: Double, max: Double, pp: Double) {
        guard let mn = ys.min(), let mx = ys.max() else { return (0.0, 0.0, 0.0) }
        return (min: mn, max: mx, pp: max(mx - mn, 0.0))
    }

    private func _adaptiveAdjacentOffsets(
        yValues: [[Double]],
        multiplier: Double,
        minGapFraction: Double
    ) -> [Double] {
        let pp = yValues.map { ys -> Double in
            _peakToPeak(ys)
        }

        // multiplier == 0 means stacking disabled; skip minGap floor entirely.
        let maxPP = pp.max() ?? 0.0
        let minGap = multiplier > 0 ? maxPP * minGapFraction : 0.0

        var offsets = [Double](repeating: 0.0, count: pp.count)
        for i in 0 ..< pp.count - 1 {
            let adaptiveGap = (pp[i] / 2.0 + pp[i + 1] / 2.0) * multiplier
            offsets[i + 1] = offsets[i] + max(minGap, adaptiveGap)
        }
        return offsets
    }

    private func _orderEnforcingOffsets(
        yValues: [[Double]],
        multiplier: Double,
        minGapFraction: Double
    ) -> [Double] {
        guard yValues.count > 1 else { return [0.0] }
        guard multiplier != 0 else { return [Double](repeating: 0.0, count: yValues.count) }

        let bounds = yValues.map { _bounds($0) }
        let maxPP = bounds.map(\.pp).max() ?? 0.0
        let minGap = maxPP * minGapFraction

        var offsets = [Double](repeating: 0.0, count: bounds.count)
        for i in 0 ..< bounds.count - 1 {
            let adaptiveGap = ((bounds[i].pp / 2.0) + (bounds[i + 1].pp / 2.0)) * multiplier
            let gap = max(minGap, adaptiveGap)
            let nextOffset = offsets[i] + bounds[i].max - bounds[i + 1].min + gap
            offsets[i + 1] = nextOffset
        }
        return offsets
    }
}

// MARK: - Stack series visibility

/// Filters hidden series from a stacked render set using stable identity keys.
///
/// The caller is responsible for applying any offsets after filtering. If every
/// series would be hidden, the original series set is returned and the caller
/// should surface the standard visibility warning.
func filterHiddenStackSeries(
    _ series: [WorkbenchPlotSeries],
    hiddenSeriesKeys: [String]
) -> (series: [WorkbenchPlotSeries], ignoredAllHidden: Bool) {
    guard !hiddenSeriesKeys.isEmpty, !series.isEmpty else {
        return (series, false)
    }

    let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series)
    let hidden = Set(hiddenSeriesKeys)
    let visible = zip(identities, series).compactMap { identity, series in
        hidden.contains(identity.identityKey) ? nil : series
    }
    if visible.isEmpty {
        return (series, true)
    }
    return (visible, false)
}
