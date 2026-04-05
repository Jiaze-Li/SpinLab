import Foundation

// MARK: - ThreeOmegaStackOffsetUseCase
//
// Computes a vertical stacking offset for each field-sweep curve so that
// curves at different temperatures are separated and do not overlap.
//
// Algorithm:
//   1. Find the maximum peak-to-peak amplitude across all input curves.
//   2. step = maxPeakToPeak × multiplier
//   3. offset[i] = i × step  (index 0 = lowest temperature = bottom)
//
// The multiplier controls spacing: 1.0 = curves just touch, >1.0 = gap between curves.
// Caller is responsible for sorting sweeps before passing yValues.

struct ThreeOmegaStackOffsetUseCase {

    /// - Parameters:
    ///   - yValues: Y data arrays for each sweep, index-aligned with the sweep array.
    ///              Must be pre-sorted (e.g. temperature ascending = bottom to top).
    ///   - multiplier: Spacing multiplier. Default 1.2 leaves ~20% gap between curves.
    /// - Returns: One offset value per sweep, index-aligned with yValues.
    func execute(yValues: [[Double]], multiplier: Double = 1.2) -> [Double] {
        guard !yValues.isEmpty else { return [] }

        let maxPeakToPeak = yValues.compactMap { ys -> Double? in
            guard let mn = ys.min(), let mx = ys.max(), mx > mn else { return nil }
            return mx - mn
        }.max() ?? 0.0

        let step = maxPeakToPeak * multiplier

        return yValues.indices.map { Double($0) * step }
    }
}
