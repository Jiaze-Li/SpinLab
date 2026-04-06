import Foundation

// MARK: - ThreeOmegaScalingUseCase
//
// Computes the Fig 5b Berry curvature quadrupole scaling analysis.
// All formulas are annotated for auditability.
//
// Reference: Y = E^(3ω)_AHE / (E_xx³ × σ_xx) = α·σ²_xx + β
//   β → Berry curvature quadrupole Q_xxz (intrinsic, main physical result)
//   α → extrinsic skew-scattering contribution
//   NOTE: E_xx³ is E_xx raised to the POWER of 3 — not "third harmonic".

struct ThreeOmegaScalingUseCase {

    /// Primary entry point: takes a mapping from temperatureK → iRms (A).
    /// fitRanges controls which temperature sub-ranges are fitted independently.
    /// A single default ThreeOmegaFitRange() (both bounds nil) = full-range fit.
    func executeWithIRms(
        fieldSweeps: [ThreeOmegaFieldSweepResult],
        rtResult: ThreeOmegaRTResult,
        geometry: ThreeOmegaGeometry,
        iRmsValues: [Double: Double],   // temperatureK → iRms (A)
        fitRanges: [ThreeOmegaFitRange] = [ThreeOmegaFitRange()]
    ) -> ThreeOmegaScalingResult {
        guard geometry.isComplete else {
            return ThreeOmegaScalingResult(
                points: [],
                segments: [],
                warnings: ["Geometry incomplete — L_xx, L_xy, d required (all > 0)."]
            )
        }

        // Unit conversions
        // Formula: d_m    = d_nm  × 1e-9    (nm → m)
        // Formula: L_xx_m = L_xx  × 1e-6   (μm → m)
        // Formula: L_xy_m = L_xy  × 1e-6   (μm → m)
        let d_m    = geometry.dNm  * 1e-9
        let lxx_m  = geometry.lxx  * 1e-6
        let lxy_m  = geometry.lxy  * 1e-6

        var points: [ThreeOmegaScalingPoint] = []
        var warnings: [String] = []

        for sweep in fieldSweeps {
            // Look up Rxx at this temperature via nearest-neighbour interpolation
            guard let rxx = _interpolateRxx(temperatureK: sweep.temperatureK, rtResult: rtResult) else {
                warnings.append("No RT data near T=\(Int(sweep.temperatureK))K — skipping.")
                continue
            }

            guard let iRms = iRmsValues[sweep.temperatureK] else {
                warnings.append("No I_rms for T=\(Int(sweep.temperatureK))K — skipping.")
                continue
            }
            // Formula: ρ_xx = Rxx(T) × (d_m × L_xy_m / L_xx_m)
            let rho_xx = rxx * (d_m * lxy_m / lxx_m)
            guard rho_xx > 0 else {
                warnings.append("ρ_xx ≤ 0 at T=\(Int(sweep.temperatureK))K — skipping.")
                continue
            }

            // Formula: σ_xx = 1 / ρ_xx   (S/m)
            let sigma_xx = 1.0 / rho_xx

            // Formula: E_xx = Ixx × Rxx(T) / L_xx_m   (V/m)
            // Ixx = iRms (rms value, per docs/specs/three_omega_physics.md §2.2)
            let E_xx = iRms * rxx / lxx_m
            guard E_xx > 0 else {
                warnings.append("E_xx ≤ 0 at T=\(Int(sweep.temperatureK))K — skipping.")
                continue
            }

            // Formula: E^(3ω)_AHE = V^(3ω)_AHE / L_xy_m   (V/m)
            // v3omegaWindow: window-average primary result (ascending − descending near H=0)
            let E3w_AHE = sweep.v3omegaWindow / lxy_m

            // X-axis: σ²_xx(T)   (S/m)²
            let sigma2xx = sigma_xx * sigma_xx

            // Y-axis: E^(3ω)_AHE / ( E_xx³ × σ_xx )
            // NOTE: E_xx³ = E_xx^3 (to the power 3, NOT "3rd harmonic")
            let E_xx3 = E_xx * E_xx * E_xx
            let scalingY = E3w_AHE / (E_xx3 * sigma_xx)

            guard scalingY.isFinite && sigma2xx.isFinite else {
                warnings.append("Non-finite scaling value at T=\(Int(sweep.temperatureK))K — skipping.")
                continue
            }

            points.append(ThreeOmegaScalingPoint(
                temperatureK: sweep.temperatureK,
                sigma2xx: sigma2xx,
                scalingY: scalingY
            ))
        }

        guard points.count >= 2 else {
            warnings.append("Fewer than 2 scaling points — linear fit not possible.")
            return ThreeOmegaScalingResult(points: points, segments: [], warnings: warnings)
        }

        // Normalize fit ranges against actual data temperature bounds
        let dataTMin = points.map { $0.temperatureK }.min()!
        let dataTMax = points.map { $0.temperatureK }.max()!
        let (normalizedRanges, rangeWarnings) = _normalizeFitRanges(
            fitRanges,
            dataTMin: dataTMin,
            dataTMax: dataTMax
        )
        warnings.append(contentsOf: rangeWarnings)

        // Fit each segment independently
        var segments: [ThreeOmegaScalingSegment] = []
        for (segIdx, range) in normalizedRanges.enumerated() {
            let segNum = segIdx + 1
            let segLabel = "Segment \(segNum) (\(Int(range.lo.rounded()))K–\(Int(range.hi.rounded()))K)"

            let segPoints = points.filter {
                $0.temperatureK >= range.lo && $0.temperatureK <= range.hi
            }

            guard segPoints.count >= 2 else {
                warnings.append("\(segLabel): fewer than 2 valid points, skipped.")
                continue
            }

            let xs = segPoints.map { $0.sigma2xx }
            let ys = segPoints.map { $0.scalingY }

            guard let (alpha, beta, r2) = _linearFit(x: xs, y: ys) else {
                warnings.append("\(segLabel): fit failed (degenerate data), skipped.")
                continue
            }

            segments.append(ThreeOmegaScalingSegment(
                id: UUID(),
                tLo: range.lo,
                tHi: range.hi,
                alpha: alpha,
                beta: beta,
                rSquared: r2,
                pointCount: segPoints.count,
                participatingXValues: xs
            ))
        }

        return ThreeOmegaScalingResult(points: points, segments: segments, warnings: warnings)
    }

    // MARK: - Private helpers

    /// Resolved temperature range after normalization.
    private struct _ResolvedRange {
        let lo: Double
        let hi: Double
    }

    /// Normalises fit ranges:
    ///   1. Resolve nil bounds to data T_min / T_max.
    ///   2. Swap reversed bounds (tLo > tHi).
    ///   3. Clip to [dataTMin, dataTMax].
    ///   4. Sort by lo ascending.
    ///   5. Detect closed-interval overlaps and emit warnings.
    private func _normalizeFitRanges(
        _ ranges: [ThreeOmegaFitRange],
        dataTMin: Double,
        dataTMax: Double
    ) -> ([_ResolvedRange], [String]) {
        var warnings: [String] = []

        // Steps 1–3
        var resolved: [_ResolvedRange] = ranges.map { range in
            var lo = range.tLo ?? dataTMin
            var hi = range.tHi ?? dataTMax
            if lo > hi { swap(&lo, &hi) }
            lo = max(lo, dataTMin)
            hi = min(hi, dataTMax)
            return _ResolvedRange(lo: lo, hi: hi)
        }

        // Step 4: sort by lo
        resolved.sort { $0.lo < $1.lo }

        // Step 5: overlap detection on sorted list (check adjacent pairs)
        // Closed-interval overlap: max(lo1, lo2) <= min(hi1, hi2)
        guard resolved.count >= 2 else { return (resolved, warnings) }
        for i in 0..<(resolved.count - 1) {
            let a = resolved[i]
            let b = resolved[i + 1]
            if max(a.lo, b.lo) <= min(a.hi, b.hi) {
                warnings.append(
                    "Segment \(i + 1) (\(Int(a.lo.rounded()))K–\(Int(a.hi.rounded()))K) and " +
                    "Segment \(i + 2) (\(Int(b.lo.rounded()))K–\(Int(b.hi.rounded()))K) overlap."
                )
            }
        }

        return (resolved, warnings)
    }

    /// Linear interpolation of Rxx at a given temperature from the RT curve.
    /// Uses nearest-neighbour within ±2K tolerance, then linear interpolation.
    private func _interpolateRxx(temperatureK: Double, rtResult: ThreeOmegaRTResult) -> Double? {
        let Ts = rtResult.temperatureK
        let Rs = rtResult.rxx
        guard !Ts.isEmpty, Ts.count == Rs.count else { return nil }

        // Find the two bracketing points
        var below: (T: Double, R: Double)? = nil
        var above: (T: Double, R: Double)? = nil

        for (t, r) in zip(Ts, Rs) {
            if t <= temperatureK {
                if below == nil || t > below!.T { below = (t, r) }
            } else {
                if above == nil || t < above!.T { above = (t, r) }
            }
        }

        switch (below, above) {
        case let (b?, a?):
            // Linear interpolation between bracketing points
            let span = a.T - b.T
            guard span > 0 else { return b.R }
            let frac = (temperatureK - b.T) / span
            return b.R + frac * (a.R - b.R)
        case let (b?, nil):
            // Extrapolation guard: only if within 5K
            return abs(temperatureK - b.T) < 5.0 ? b.R : nil
        case let (nil, a?):
            return abs(temperatureK - a.T) < 5.0 ? a.R : nil
        default:
            return nil
        }
    }

    /// OLS linear fit y = α·x + β. Returns (α, β, R²) or nil.
    private func _linearFit(x: [Double], y: [Double]) -> (Double, Double, Double)? {
        let n = Double(x.count)
        guard x.count == y.count, x.count >= 2 else { return nil }

        let sx  = x.reduce(0, +)
        let sy  = y.reduce(0, +)
        let sxx = x.map { $0 * $0 }.reduce(0, +)
        let sxy = zip(x, y).map { $0 * $1 }.reduce(0, +)

        let denom = n * sxx - sx * sx
        guard abs(denom) > 1e-60 else { return nil }

        let alpha = (n * sxy - sx * sy) / denom
        let beta  = (sy - alpha * sx) / n

        // R² = 1 - SS_res / SS_tot
        let yMean = sy / n
        let ssTot = y.map { ($0 - yMean) * ($0 - yMean) }.reduce(0, +)
        let ssRes: Double = zip(x, y).reduce(0.0) { acc, pair in
            let pred = alpha * pair.0 + beta
            let diff = pair.1 - pred
            return acc + diff * diff
        }

        let r2 = ssTot > 0 ? 1.0 - ssRes / ssTot : 1.0

        return (alpha, beta, r2)
    }
}
