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
    func executeWithIRms(
        fieldSweeps: [ThreeOmegaFieldSweepResult],
        rtResult: ThreeOmegaRTResult,
        geometry: ThreeOmegaGeometry,
        iRmsValues: [Double: Double]   // temperatureK → iRms (A)
    ) -> ThreeOmegaScalingResult {
        guard geometry.isComplete else {
            return ThreeOmegaScalingResult(
                points: [],
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
            // Formula: I_amp = I_rms × √2
            let iAmp = iRms * sqrt(2.0)

            // Formula: ρ_xx = Rxx(T) × (d_m × L_xy_m / L_xx_m)
            let rho_xx = rxx * (d_m * lxy_m / lxx_m)
            guard rho_xx > 0 else {
                warnings.append("ρ_xx ≤ 0 at T=\(Int(sweep.temperatureK))K — skipping.")
                continue
            }

            // Formula: σ_xx = 1 / ρ_xx   (S/m)
            let sigma_xx = 1.0 / rho_xx

            // Formula: E_xx = I_amp × Rxx(T) / L_xx_m   (V/m)
            let E_xx = iAmp * rxx / lxx_m
            guard E_xx > 0 else {
                warnings.append("E_xx ≤ 0 at T=\(Int(sweep.temperatureK))K — skipping.")
                continue
            }

            // Formula: E^(3ω)_AHE = V^(3ω)_AHE / L_xy_m   (V/m)
            // v3omegaAtZeroField is in Volts (raw V³ω_X at H≈0)
            let E3w_AHE = sweep.v3omegaAtZeroField / lxy_m

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

        // Linear fit: Y = α·σ²_xx + β
        var alpha: Double? = nil
        var beta: Double? = nil
        var rSquared: Double? = nil

        if points.count >= 2 {
            let xs = points.map { $0.sigma2xx }
            let ys = points.map { $0.scalingY }
            if let (a, b, r2) = _linearFit(x: xs, y: ys) {
                alpha = a
                beta = b
                rSquared = r2
            }
        } else if points.count < 2 {
            warnings.append("Fewer than 2 scaling points — linear fit not possible.")
        }

        return ThreeOmegaScalingResult(
            points: points,
            alpha: alpha,
            beta: beta,
            rSquared: rSquared,
            warnings: warnings
        )
    }

    // MARK: - Private helpers

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
