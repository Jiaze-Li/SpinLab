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

    /// - Parameters:
    ///   - yValues: Y data arrays for each sweep, index-aligned with the sweep array.
    ///              Must be pre-sorted (e.g. temperature ascending = bottom to top).
    ///   - multiplier: Spacing multiplier (>= 0). Default 1.2 leaves ~20% gap between curves.
    ///   - minGapFraction: Minimum gap as a fraction of max peak-to-peak (>= 0). Default 0.15.
    /// - Returns: One offset value per sweep, index-aligned with yValues.
    func execute(yValues: [[Double]], multiplier: Double = 1.2, minGapFraction: Double = 0.15) -> [Double] {
        guard !yValues.isEmpty else { return [] }

        let pp = yValues.map { ys -> Double in
            guard let mn = ys.min(), let mx = ys.max() else { return 0.0 }
            return max(mx - mn, 0.0)
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
