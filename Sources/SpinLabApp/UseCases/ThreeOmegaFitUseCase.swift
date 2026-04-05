import Foundation
import Accelerate

// MARK: - ThreeOmegaFitUseCase
//
// Processes one LVM field-sweep file into a ThreeOmegaFieldSweepResult.
// All formulas are annotated for auditability.

struct ThreeOmegaFitUseCase {

    /// High-field fraction for RAHE linear extrapolation.
    /// Points with |H| > highFrac × Hmax are used for the linear fit.
    var highFrac: Double = 0.70

    /// Minimum points required in high-field region for RAHE fit.
    var minHighFieldPoints: Int = 3

    func process(file: ThreeOmegaLVMFile) -> ThreeOmegaFieldSweepResult {
        let H = file.col0   // Oe
        let iRms = file.iRms

        // ── Step 2: Raw voltage → Resistance ─────────────────────────────────
        // Formula: R¹ω(H) = V¹ω_X(H) / I_rms   [Col[1] / I_rms]
        // Formula: R³ω(H) = V³ω_X(H) / I_rms   [Col[5] / I_rms]
        let r1raw = file.col1.map { $0 / iRms }
        let r3raw = file.col5.map { $0 / iRms }

        // ── Step 3: Centering (remove DC offset) ─────────────────────────────
        // Formula: R_centered(H) = R(H) - (max(R) + min(R)) / 2
        let r1 = _center(r1raw)
        let r3 = _center(r3raw)

        // ── Step 4: V^(3ω)_AHE at H≈0 ───────────────────────────────────────
        // Direct read at H closest to zero (method TBD after first plot).
        // Formula: V^(3ω)_AHE ≈ V³ω_X(H≈0) = R³ω(H≈0) × I_rms  (pre-centering)
        let v3AtZero = _v3omegaAtZeroField(H: H, v3omega: file.col5)

        // ── Step 5: RAHE and Hc fitting ──────────────────────────────────────
        let rahe1 = _fitRAHE(H: H, R: r1)
        let rahe3 = _fitRAHE(H: H, R: r3)
        let hc1 = _fitHc(H: H, R: r1)
        let hc3 = _fitHc(H: H, R: r3)

        return ThreeOmegaFieldSweepResult(
            temperatureK: file.temperatureK,
            angleLabel: file.angleLabel,
            hField: H,
            r1omega: r1,
            r3omega: r3,
            rahe1omega: rahe1,
            rahe3omega: rahe3,
            hc1omega: hc1,
            hc3omega: hc3,
            v3omegaAtZeroField: v3AtZero
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

    // MARK: - V³ω at H≈0

    // Direct read: find the row with |H| closest to zero.
    // Formula: V^(3ω)_AHE ≈ V³ω_X(H≈0)
    // Note: uses raw V³ω_X (col5), not the I_rms-divided value, to preserve voltage units.
    private func _v3omegaAtZeroField(H: [Double], v3omega: [Double]) -> Double {
        guard !H.isEmpty else { return .nan }
        var bestIdx = 0
        var bestDist = abs(H[0])
        for i in 1..<H.count {
            let d = abs(H[i])
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        return v3omega[bestIdx]
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

        guard let bPos = _linearIntercept(x: Hpos, y: Rpos),
              let bNeg = _linearIntercept(x: Hneg, y: Rneg) else { return nil }

        // Formula: RAHE = (b⁺ - b⁻) / 2
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

        // Formula: Hc = (|Hc⁺| + |Hc⁻|) / 2
        return 0.5 * (abs(HcP) + abs(HcN))
    }

    // MARK: - Private math helpers

    // Ordinary least-squares linear fit: y = k×x + b. Returns b (intercept at x=0).
    // Uses exact closed-form OLS to avoid Accelerate dependency for simple 1D case.
    private func _linearIntercept(x: [Double], y: [Double]) -> Double? {
        let n = Double(x.count)
        guard x.count == y.count, x.count >= 2 else { return nil }

        let sx  = x.reduce(0, +)
        let sy  = y.reduce(0, +)
        let sxx = x.map { $0 * $0 }.reduce(0, +)
        let sxy = zip(x, y).map { $0 * $1 }.reduce(0, +)

        let denom = n * sxx - sx * sx
        guard abs(denom) > 1e-30 else { return nil }

        // k = (n·Σxy - Σx·Σy) / (n·Σx² - (Σx)²)
        let k = (n * sxy - sx * sy) / denom
        // b = (Σy - k·Σx) / n
        let b = (sy - k * sx) / n
        return b
    }

    // Linear interpolation to find field H where R(H) crosses `target`.
    // Returns the crossing closest to H=0 (smallest |H|).
    private func _crossingField(H: [Double], R: [Double], target: Double) -> Double? {
        guard H.count == R.count, H.count >= 2 else { return nil }

        var candidates: [Double] = []
        for i in 0..<(H.count - 1) {
            let s1 = R[i] - target
            let s2 = R[i + 1] - target
            guard s1 * s2 <= 0 else { continue }  // sign change

            let x1 = H[i], x2 = H[i + 1]
            let xc: Double
            if abs(s2 - s1) < 1e-30 {
                xc = 0.5 * (x1 + x2)
            } else {
                // Linear interpolation: xc = x1 + (0 - s1) × (x2-x1)/(s2-s1)
                xc = x1 + (-s1) * (x2 - x1) / (s2 - s1)
            }
            candidates.append(xc)
        }

        guard !candidates.isEmpty else { return nil }
        // Return the crossing closest to H=0
        return candidates.min(by: { abs($0) < abs($1) })
    }
}
