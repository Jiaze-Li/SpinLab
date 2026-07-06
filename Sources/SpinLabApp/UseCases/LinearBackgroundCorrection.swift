import Foundation

/// Shared high-field linear background subtraction, used to remove the ordinary-Hall
/// (linear-in-H) background from a raw Hall-type signal, isolating the anomalous component.
/// Formula: R_corrected(H) = R(H) - k_avg·H, where k_avg is the average of the positive- and
/// negative-branch high-field slopes (OLS fit over |H| > highFrac × max|H|).
///
/// Extracted from `ThreeOmegaFitUseCase` (which pioneered this correction for 3ω's 1ω/3ω
/// channels) so AHE's ordinary Hall background correction uses the exact same formula.
enum LinearBackgroundCorrection {
    static func subtractLinearBackground(
        H: [Double],
        R: [Double],
        highFrac: Double,
        minHighFieldPoints: Int
    ) -> [Double] {
        guard H.count == R.count, !H.isEmpty else { return R }
        let Hmax = H.map { abs($0) }.max()!
        let Hcut = highFrac * Hmax

        var Hpos: [Double] = [], Rpos: [Double] = []
        var Hneg: [Double] = [], Rneg: [Double] = []
        for (h, r) in zip(H, R) {
            if h > Hcut  { Hpos.append(h); Rpos.append(r) }
            if h < -Hcut { Hneg.append(h); Rneg.append(r) }
        }

        var k = 0.0
        var count = 0
        if Hpos.count >= minHighFieldPoints,
           let (kPos, _) = linearSlopeAndIntercept(x: Hpos, y: Rpos) {
            k += kPos; count += 1
        }
        if Hneg.count >= minHighFieldPoints,
           let (kNeg, _) = linearSlopeAndIntercept(x: Hneg, y: Rneg) {
            k += kNeg; count += 1
        }
        guard count > 0 else { return R }
        k /= Double(count)

        return zip(R, H).map { $0.0 - k * $0.1 }
    }

    /// OLS linear fit y = k·x + b. Returns (slope k, intercept b) or nil.
    static func linearSlopeAndIntercept(x: [Double], y: [Double]) -> (Double, Double)? {
        let n = Double(x.count)
        guard x.count == y.count, x.count >= 2 else { return nil }

        let sx  = x.reduce(0, +)
        let sy  = y.reduce(0, +)
        let sxx = x.map { $0 * $0 }.reduce(0, +)
        let sxy = zip(x, y).map { $0 * $1 }.reduce(0, +)

        let denom = n * sxx - sx * sx
        guard abs(denom) > 1e-30 else { return nil }

        let k = (n * sxy - sx * sy) / denom
        let b = (sy - k * sx) / n
        return (k, b)
    }
}
