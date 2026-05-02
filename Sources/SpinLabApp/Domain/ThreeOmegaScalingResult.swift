import Foundation

struct ThreeOmegaScalingPoint: Codable, Hashable, Sendable {
    var temperatureK: Double
    // X-axis: σ²_xx(T)  (S/m)²
    // Formula: σ_xx = 1 / ρ_xx
    // Formula: ρ_xx = Rxx(T) × (d_m × L_xy_m / L_xx_m)
    var sigma2xx: Double
    // Y-axis: E^(3ω)_AHE / ( E_xx(T)³ × σ_xx(T) )
    // Formula: E^(3ω)_AHE = V^(3ω)_AHE / L_xy_m
    // Formula: E_xx = I_rms × Rxx(T) / L_xx_m
    // NOTE: denominator uses E_xx to the POWER of 3, not "third harmonic"
    var scalingY: Double
}

/// One independent temperature range submitted for linear fitting.
/// tLo/tHi are session-only; nil means "use data boundary".
struct ThreeOmegaFitRange: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var tLo: Double?   // nil = data T_min
    var tHi: Double?   // nil = data T_max
}

/// Result of one independent linear fit Y = α·σ²_xx + β on a temperature sub-range.
struct ThreeOmegaScalingSegment: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let tLo: Double
    let tHi: Double
    // Formula: Y = α × σ²_xx + β
    // β → Berry curvature quadrupole Q_xxz (intrinsic, main physical result)
    // α → extrinsic skew-scattering contribution
    let alpha: Double
    let beta: Double
    let rSquared: Double
    let pointCount: Int
    /// σ²_xx values (S/m)² for points that participated in this fit.
    /// Used by the renderer to determine the x-range of the fit line.
    let participatingXValues: [Double]
}

struct ThreeOmegaScalingResult: Codable, Hashable, Sendable {
    var points: [ThreeOmegaScalingPoint]
    var segments: [ThreeOmegaScalingSegment]
    var warnings: [String] = []

    /// True when there is exactly one segment and it covers every computed point.
    /// Drives the compact (legacy) display format in the results panel.
    func isSingleFullRange() -> Bool {
        segments.count == 1 && segments[0].pointCount == points.count
    }
}
