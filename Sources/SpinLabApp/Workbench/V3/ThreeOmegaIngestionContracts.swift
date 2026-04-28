import Foundation

// MARK: - File classification

enum ThreeOmegaFileKind: String, Codable, Hashable, Sendable {
    /// Field-sweep measurement at fixed temperature (filename contains "_3w_")
    case fieldSweep
    /// Resistance vs. temperature sweep (filename contains "_RT_")
    case rtSweep
}

// MARK: - Raw parsed LVM file

/// Raw data extracted from one Zurich Instruments LVM file.
/// Column layout (0-indexed, positional — LVM files have no column header row):
///   0  H (Oe)          — magnetic field
///   1  V¹ω_X (V)       — 1st harmonic in-phase voltage
///   2  V¹ω_Y (V)
///   3  V¹ω_R (V)       — 1st harmonic magnitude
///   4  V¹ω_θ           — 1st harmonic phase
///   5  V³ω_X (V)       — 3rd harmonic in-phase voltage  ← AHE signal
///   6  V³ω_Y (V)
///   7  V³ω_R (V)
///   8  V³ω_θ
///   9  R_H (Ω)         — pre-calculated: V¹ω_X / I_rms  (verified ~1e-11 precision)
///  10  f_ref (Hz)      — ~317.3 Hz = 3ω reference frequency
///
/// For RT files: Col 0 = Temperature (K), Col 9 = Rxx (Ω) pre-calculated.
struct ThreeOmegaLVMFile: Sendable {
    // Formula: I_rms = mean( Col[1][i] / Col[9][i] ) for first N rows
    // Verified: consistent across all rows to ~1e-11; equals I_amp / √2
    var iRms: Double

    /// Nominal AC current amplitude parsed from filename "Iac_X A" (backup only)
    var iAmpFromFilename: Double?

    /// Temperature in Kelvin parsed from filename "T_(value) K".
    /// NaN for RT files.
    var temperatureK: Double

    /// Device label from sidecar conditions (e.g. "0deg", "30deg").
    /// Fallback: parser derives from parent folder name.
    var device: String

    var fileKind: ThreeOmegaFileKind

    /// Original filename (stem only, no extension).
    var stem: String

    // Raw column data (parallel arrays, same length)
    var col0: [Double]   // H (Oe) for fieldSweep; T (K) for rtSweep
    var col1: [Double]   // V¹ω_X (V)
    var col5: [Double]   // V³ω_X (V)
    var col9: [Double]   // R_H (Ω) pre-calculated
}

// MARK: - Processed field-sweep result

/// One temperature's worth of processed field-sweep data.
struct ThreeOmegaFieldSweepResult: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(device)_\(String(format: "%.1f", temperatureK))K" }

    var temperatureK: Double
    var device: String

    /// Sample metadata carried from search hit for legend resolution (v5.3.4).
    /// Optional so legacy packs without this field decode safely.
    var sampleMetadata: [String: String]?

    /// Stable series identity injected from WorkflowMeasurementSearchHit.sampleKey (v5.3.6).
    /// nil in packs created before 5.3.6; used for drag-reorder and label remapping.
    var sampleID: String? = nil

    // Formula: R¹ω(H) = V¹ω_X(H) / I_rms   (Col[1] / I_rms)
    // Then centered: R¹ω_c(H) = R¹ω(H) - (max(R¹ω) + min(R¹ω)) / 2
    var hField: [Double]    // Oe
    var r1omega: [Double]   // Ω, centered
    var r3omega: [Double]   // Ω, centered

    // I_rms — carried from LVM file for RAHE(3ω) derivation.
    var iRms: Double

    // Formula: R¹ω_AHE = (b⁺ - b⁻) / 2  (HFE on col9)
    //   b⁺ = linear fit intercept at H=0 for H > 0.7×Hmax
    //   b⁻ = linear fit intercept at H=0 for H < -0.7×Hmax
    var rahe1omega: Double?     // Ω, HFE on col9
    var rahe1omegaWA: Double?   // Ω, WA on col9

    // Formula: R_mid = (max(R) + min(R)) / 2
    // Hc = average of |crossing field| on positive and negative branches
    var hc1omega: Double?    // Oe
    var hc3omega: Double?    // Oe

    // V^(3ω)_AHE — primary: window average of (ascending − descending) near H=0.
    // Formula: V3w_AHE = mean(col5 | ascending, |H|<Hwin) − mean(col5 | descending, |H|<Hwin)
    var v3omegaWindow: Double       // V  (primary result)

    // V^(3ω)_AHE — cross-check: high-field linear extrapolation (b⁺ − b⁻) / 2.
    // nil when high-field point count is insufficient for a stable fit.
    var v3omegaFit: Double?         // V  (cross-check; nil = fit failed)

    /// Unified RAHE accessor — hides 1ω/3ω data-source asymmetry.
    /// 1ω: directly from col9 (instrument R). 3ω: derived from V_AHE / iRms.
    /// HFE fallback for 3ω: v3omegaFit ?? v3omegaWindow (aligned with Scaling Law).
    func rahe(harmonic: Int, method: ThreeOmegaV3Method) -> Double? {
        switch (harmonic, method) {
        case (1, .highField): return rahe1omega
        case (1, .window):    return rahe1omegaWA
        case (3, .highField):
            guard abs(iRms) > 1e-30 else { return nil }
            let v = v3omegaFit ?? (v3omegaWindow.isNaN ? nil : v3omegaWindow)
            return v.map { $0 / iRms }
        case (3, .window):
            guard abs(iRms) > 1e-30, !v3omegaWindow.isNaN else { return nil }
            return v3omegaWindow / iRms
        default: return nil
        }
    }
}

/// Which V^(3ω)_AHE extraction method to use in Scaling Law.
enum ThreeOmegaV3Method: String, CaseIterable, Identifiable {
    case highField = "High-field extrapolation"
    case window    = "Window average"

    var id: String { rawValue }

    /// Pick the appropriate value from a field-sweep result.
    func v3ahe(from sweep: ThreeOmegaFieldSweepResult) -> Double {
        switch self {
        case .highField:
            return sweep.v3omegaFit ?? sweep.v3omegaWindow
        case .window:
            return sweep.v3omegaWindow
        }
    }
}

// MARK: - RT result

/// Resistance vs. temperature from RT sweep files.
struct ThreeOmegaRTResult: Codable, Hashable, Sendable, Identifiable {
    var id: String { device }

    var device: String

    // Formula: Rxx(T) = Col[9](T)  (pre-calculated R_H in RT file = longitudinal Rxx)
    var temperatureK: [Double]
    var rxx: [Double]   // Ω
}

// MARK: - Geometry parameters (session-only, not persisted)

struct ThreeOmegaGeometry: Codable, Hashable, Sendable {
    /// Channel length along current direction (μm)
    var lxx: Double = 0
    /// Channel length along Hall direction (μm)
    var lxy: Double = 0
    /// Film thickness (nm)
    var dNm: Double = 0

    var isComplete: Bool { lxx > 0 && lxy > 0 && dNm > 0 }
}

// MARK: - Fig 5b scaling

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

// MARK: - Top-level ingestion result

struct ThreeOmegaIngestionResult: Codable, Hashable, Sendable {
    var fieldSweeps: [ThreeOmegaFieldSweepResult]   // sorted by temperatureK ascending
    var rtResult: ThreeOmegaRTResult?
    var device: String
    /// I_rms (A) keyed by temperatureK — required for scaling use case.
    var iRmsValues: [Double: Double] = [:]
    var warnings: [String] = []
}

// MARK: - UI tab enum

enum ThreeOmegaWorkbenchTab: String, CaseIterable, Identifiable {
    case fieldSweep1omega = "AHE (1ω)"
    case fieldSweep3omega = "AHE (3ω)"
    case rahe1omegaVsT    = "RAHE (1ω)"
    case rahe3omegaVsT    = "RAHE (3ω)"
    case hcVsT            = "Hc"
    case rtCurve          = "RT"
    case scaling          = "Scaling Law"

    var id: String { rawValue }

    /// Stable identity key for persistence. Hand-written, never derived via reflection.
    var stableKey: String {
        switch self {
        case .fieldSweep1omega: return "fieldSweep1omega"
        case .fieldSweep3omega: return "fieldSweep3omega"
        case .rahe1omegaVsT:    return "rahe1omegaVsT"
        case .rahe3omegaVsT:    return "rahe3omegaVsT"
        case .hcVsT:            return "hcVsT"
        case .rtCurve:          return "rtCurve"
        case .scaling:          return "scaling"
        }
    }

    /// Index in `allCases` order, used for sort rank.
    static let stableKeyRank: [String: Int] = {
        Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1.stableKey, $0) })
    }()
}
