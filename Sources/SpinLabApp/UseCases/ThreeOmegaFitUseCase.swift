import Foundation
import Accelerate

// MARK: - ThreeOmegaFitUseCase
//
// Processes one LVM field-sweep file into a ThreeOmegaFieldSweepResult.
// All formulas are annotated for auditability.
//
// Physics reference: docs/specs/three_omega_physics.md

struct ThreeOmegaFitUseCase {

    /// High-field fraction for linear extrapolation (V1w background subtraction, RAHE, Hc).
    /// Points with |H| > highFrac × Hmax are used for the linear fit.
    var highFrac: Double = 0.70

    /// Minimum points required in high-field region for fit.
    var minHighFieldPoints: Int = 3

    /// Number of closest-to-zero field points averaged on each branch for WA extraction.
    var zeroBranchAveragePoints: Int = 3

    func process(file: ThreeOmegaLVMFile, deviceOverride: String? = nil) -> ThreeOmegaFieldSweepResult {
        let H = file.col0   // Oe
        let iRms = file.iRms

        // ── Step 2: Raw voltage → Resistance ─────────────────────────────────
        // Formula: R1w(H) = Vw_xy(H)  / Ixx   [col1 / iRms]
        // Formula: R3w(H) = V3w_xy(H) / Ixx   [col5 / iRms]
        let r1raw = file.col1.map { $0 / iRms }
        let r3raw = file.col5.map { $0 / iRms }

        // ── Step 3: Centering (remove DC offset) ─────────────────────────────
        // Formula: R_centered(H) = R(H) - (max(R) + min(R)) / 2
        let r1centered = _center(r1raw)
        let r3centered = _center(r3raw)

        // ── Step 4: Linear background subtraction (§1.3) ─────────────────────
        // k = average slope of positive and negative high-field fits.
        // Stored arrays are used for plotting (square hysteresis loop).
        // Formula: R_plot(H) = R_centered(H) - k·H
        let r1 = _subtractLinearBackground(H: H, R: r1centered)
        let r3 = _subtractLinearBackground(H: H, R: r3centered)

        // The V3w_AHE extraction should use the same centering + linear-background
        // correction path as the plotted R3w loop, but kept in voltage units for
        // the scaling-law electric field E3w_AHE = V3w_AHE / Lxy.
        let v3CorrectedVoltage = _subtractLinearBackground(H: H, R: _center(file.col5))

        // ── Step 5: V3w_AHE extraction ───────────────────────────────────────
        // Primary: near-zero branch average, polarity-aligned with HFE.
        // Formula: V3w_AHE = (mean(V3w_corr | +M branch near H=0) − mean(V3w_corr | −M branch near H=0)) / 2
        // Cross-check: high-field extrapolation (b⁺ − b⁻) / 2 on corrected V3w.
        let v3Window = _windowV3w(H: H, V: v3CorrectedVoltage) ?? .nan
        let v3Fit    = _fitAHEFromVoltage(H: H, V: v3CorrectedVoltage)

        // ── Step 6: RAHE and Hc ──────────────────────────────────────────────
        // RAHE(1ω): extracted directly from col9 (instrument R), not from derived col1/iRms.
        let rahe1    = _fitRAHE(H: H, R: file.col9)
        let rahe1WA  = _windowV3w(H: H, V: file.col9)
        // RAHE(3ω): derived as V3w_AHE / iRms at use site — no separate extraction.
        let hc1 = _fitHc(H: H, R: r1)
        let hc3 = _fitHc(H: H, R: r3)

        return ThreeOmegaFieldSweepResult(
            temperatureK: file.temperatureK,
            device: deviceOverride ?? file.device,
            hField: H,
            r1omega: r1,
            r3omega: r3,
            iRms: iRms,
            rahe1omega: rahe1,
            rahe1omegaWA: rahe1WA,
            hc1omega: hc1,
            hc3omega: hc3,
            v3omegaWindow: v3Window,
            v3omegaFit: v3Fit
        )
    }

    // MARK: - Centering

    // Formula: R_centered = R - (max(R) + min(R)) / 2
    private func _center(_ r: [Double]) -> [Double] {
        guard !r.isEmpty else { return r }
        let lo = r.min()!
        let hi = r.max()!
        let mid = 0.5 * (hi + lo)
        return r.map { $0 - mid }
    }

    // MARK: - Linear background subtraction

    // Returns R with linear background subtracted.
    // k_avg = (k_pos + k_neg) / 2 from high-field fits.
    // Formula: R_plot(H) = R(H) - k_avg·H
    private func _subtractLinearBackground(H: [Double], R: [Double]) -> [Double] {
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
           let (kPos, _) = _linearSlopeAndIntercept(x: Hpos, y: Rpos) {
            k += kPos; count += 1
        }
        if Hneg.count >= minHighFieldPoints,
           let (kNeg, _) = _linearSlopeAndIntercept(x: Hneg, y: Rneg) {
            k += kNeg; count += 1
        }
        guard count > 0 else { return R }
        k /= Double(count)

        return zip(R, H).map { $0.0 - k * $0.1 }
    }

    // MARK: - V3w_AHE extraction

    // WA (Window Approximation) method.
    // Splits the scan into the two near-zero branches. Each branch is averaged over
    // the closest zeroBranchAveragePoints points to H=0, not a single point.
    // Polarity convention matches HFE: (positive-state branch − negative-state branch) / 2.
    // For standard +H → −H → +H scans, this reduces to (first branch − second branch) / 2.
    // For standard −H → +H → −H scans, the order is reversed.
    private func _windowV3w(H: [Double], V: [Double]) -> Double? {
        guard H.count == V.count, H.count >= 4 else { return nil }
        let N = H.count

        // Locate zero crossings in scan order (do not sort H).
        var crossings: [Int] = []
        for i in 0..<(N - 1) {
            if (H[i] >= 0) != (H[i + 1] >= 0) { crossings.append(i) }
        }
        guard crossings.count >= 2 else { return nil }
        let iFirst = crossings[0]   // first near-zero branch endpoint
        let iSecond = crossings[1]  // second near-zero branch start

        guard let firstBranchMean = _meanClosestToZero(
            H: H,
            V: V,
            range: 0...(iFirst + 1),
            count: zeroBranchAveragePoints
        ), let secondBranchMean = _meanClosestToZero(
            H: H,
            V: V,
            range: iSecond...(N - 1),
            count: zeroBranchAveragePoints
        ), let initialSign = _firstNonZeroSign(H) else {
            return nil
        }

        // HFE defines polarity as b+ − b−. The first near-zero branch carries the
        // magnetization state set by the initial high-field saturation. Therefore:
        //   initial +H: first branch is +M, second branch is −M.
        //   initial −H: first branch is −M, second branch is +M.
        if initialSign > 0 {
            return 0.5 * (firstBranchMean - secondBranchMean)
        } else {
            return 0.5 * (secondBranchMean - firstBranchMean)
        }
    }

    // Cross-check: high-field linear extrapolation (b⁺ − b⁻) / 2.
    //   b+ = H=0 intercept from linear fit of V3w_xy for H > highFrac·Hmax
    //   b- = H=0 intercept from linear fit of V3w_xy for H < -highFrac·Hmax
    // Operates on the same corrected voltage used by WA, not raw col5.
    private func _fitAHEFromVoltage(H: [Double], V: [Double]) -> Double? {
        guard H.count == V.count, !H.isEmpty else { return nil }
        let Hmax = H.map { abs($0) }.max()!
        let Hcut = highFrac * Hmax

        var Hpos: [Double] = [], Vpos: [Double] = []
        var Hneg: [Double] = [], Vneg: [Double] = []
        for (h, v) in zip(H, V) {
            if h > Hcut  { Hpos.append(h); Vpos.append(v) }
            if h < -Hcut { Hneg.append(h); Vneg.append(v) }
        }

        guard Hpos.count >= minHighFieldPoints, Hneg.count >= minHighFieldPoints else { return nil }
        guard let (_, bPos) = _linearSlopeAndIntercept(x: Hpos, y: Vpos),
              let (_, bNeg) = _linearSlopeAndIntercept(x: Hneg, y: Vneg) else { return nil }

        return 0.5 * (bPos - bNeg)
    }

    // MARK: - RAHE fitting

    // Formula: RAHE = (b⁺ - b⁻) / 2
    //   b⁺ = intercept at H=0 from linear fit R = k×H + b for H > highFrac × Hmax
    //   b⁻ = intercept at H=0 from linear fit R = k×H + b for H < -highFrac × Hmax
    // Returns nil if insufficient points in either high-field region.
    private func _fitRAHE(H: [Double], R: [Double]) -> Double? {
        guard H.count == R.count, !H.isEmpty else { return nil }
        let Hmax = H.map { abs($0) }.max()!
        let Hcut = highFrac * Hmax

        var Hpos: [Double] = [], Rpos: [Double] = []
        var Hneg: [Double] = [], Rneg: [Double] = []

        for (h, r) in zip(H, R) {
            if h > Hcut  { Hpos.append(h); Rpos.append(r) }
            if h < -Hcut { Hneg.append(h); Rneg.append(r) }
        }

        guard Hpos.count >= minHighFieldPoints, Hneg.count >= minHighFieldPoints else { return nil }

        guard let (_, bPos) = _linearSlopeAndIntercept(x: Hpos, y: Rpos),
              let (_, bNeg) = _linearSlopeAndIntercept(x: Hneg, y: Rneg) else { return nil }

        return 0.5 * (bPos - bNeg)
    }

    // MARK: - Hc fitting

    // Formula: R_mid = (max(R) + min(R)) / 2
    // Hc⁺ = field where R(H>0) crosses R_mid
    // Hc⁻ = field where R(H<0) crosses R_mid
    // Hc = (|Hc⁺| + |Hc⁻|) / 2
    private func _fitHc(H: [Double], R: [Double]) -> Double? {
        guard H.count == R.count, H.count >= 4 else { return nil }
        let Rmid = 0.5 * ((R.max() ?? 0) + (R.min() ?? 0))

        var Hpos: [Double] = [], Rpos: [Double] = []
        var Hneg: [Double] = [], Rneg: [Double] = []
        for (h, r) in zip(H, R) {
            if h > 0 { Hpos.append(h); Rpos.append(r) }
            if h < 0 { Hneg.append(h); Rneg.append(r) }
        }

        guard let HcP = _crossingField(H: Hpos, R: Rpos, target: Rmid),
              let HcN = _crossingField(H: Hneg, R: Rneg, target: Rmid) else { return nil }

        return 0.5 * (abs(HcP) + abs(HcN))
    }

    // MARK: - Private math helpers

    private func _meanClosestToZero(
        H: [Double],
        V: [Double],
        range: ClosedRange<Int>,
        count: Int
    ) -> Double? {
        let targetCount = max(1, count)
        let candidates: [(absH: Double, value: Double)] = range.compactMap { i in
            guard H.indices.contains(i), V.indices.contains(i), H[i].isFinite, V[i].isFinite else {
                return nil
            }
            return (abs(H[i]), V[i])
        }

        let selected = candidates.sorted { $0.absH < $1.absH }.prefix(targetCount)
        guard !selected.isEmpty else { return nil }
        let sum = selected.reduce(0.0) { $0 + $1.value }
        return sum / Double(selected.count)
    }

    private func _firstNonZeroSign(_ H: [Double]) -> Int? {
        for h in H where h.isFinite && abs(h) > 1e-12 {
            return h > 0 ? 1 : -1
        }
        return nil
    }

    // OLS linear fit y = k·x + b. Returns (slope k, intercept b) or nil.
    private func _linearSlopeAndIntercept(x: [Double], y: [Double]) -> (Double, Double)? {
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

    // Linear interpolation to find field H where R(H) crosses `target`.
    // Returns the crossing closest to H=0 (smallest |H|).
    private func _crossingField(H: [Double], R: [Double], target: Double) -> Double? {
        guard H.count == R.count, H.count >= 2 else { return nil }

        var candidates: [Double] = []
        for i in 0..<(H.count - 1) {
            let s1 = R[i] - target
            let s2 = R[i + 1] - target
            guard s1 * s2 <= 0 else { continue }

            let x1 = H[i], x2 = H[i + 1]
            let xc: Double
            if abs(s2 - s1) < 1e-30 {
                xc = 0.5 * (x1 + x2)
            } else {
                xc = x1 + (-s1) * (x2 - x1) / (s2 - s1)
            }
            candidates.append(xc)
        }

        guard !candidates.isEmpty else { return nil }
        return candidates.min(by: { abs($0) < abs($1) })
    }
}
