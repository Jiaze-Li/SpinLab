import Foundation

// MARK: - ThreeOmegaStackOffsetUseCase
//
// Vertical stacking offsets for stacked-curve workflows (AHE, IV, RT, XY Rotation, 3ω) — the
// single Gap rule:
//   1. curves are provided bottom-to-top in the desired physical stack order
//   2. the net gap between the vertical envelopes of adjacent curves is always
//      `max(all peak-to-peak) × gap` — no per-curve amplitude term, no Stack multiplier
//   3. gap = 0 (or NaN/∞/negative), a flat set (max peak-to-peak = 0) or a single curve
//      leaves every curve at its original position
// Offsets may be positive or negative; only the order is fixed by input order.
// Caller is responsible for sorting sweeps before passing yValues.

struct ThreeOmegaStackOffsetUseCase {

    /// - Parameters:
    ///   - yValues: Y data arrays for each sweep, bottom to top.
    ///   - minGapFraction: The Gap input — net gap as a fraction of max peak-to-peak (>= 0).
    /// - Returns: One offset value per sweep, index-aligned with yValues.
    func execute(yValues: [[Double]], minGapFraction: Double) -> [Double] {
        guard !yValues.isEmpty else { return [] }
        return _uniformGapOffsets(yValues: yValues, gapFraction: minGapFraction)
    }

    private func _bounds(_ ys: [Double]) -> (min: Double, max: Double, pp: Double) {
        guard let mn = ys.min(), let mx = ys.max() else { return (0.0, 0.0, 0.0) }
        return (min: mn, max: mx, pp: max(mx - mn, 0.0))
    }

    private func _uniformGapOffsets(yValues: [[Double]], gapFraction: Double) -> [Double] {
        let zeros = [Double](repeating: 0.0, count: yValues.count)
        guard yValues.count > 1, gapFraction.isFinite, gapFraction > 0 else { return zeros }
        let bounds = yValues.map { _bounds($0) }
        let gap = (bounds.map(\.pp).max() ?? 0.0) * gapFraction
        guard gap > 0, gap.isFinite else { return zeros }

        var offsets = zeros
        for i in 0 ..< bounds.count - 1 {
            offsets[i + 1] = offsets[i] + bounds[i].max - bounds[i + 1].min + gap
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
