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
struct ThreeOmegaLVMFile: Codable, Hashable, Sendable {
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

/// Which V^(3ω)_AHE extraction method to use in Scaling Law.
enum ThreeOmegaV3Method: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
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

// MARK: - Top-level ingestion result

struct ThreeOmegaIngestionResult: Codable, Hashable, Sendable {
    var fieldSweeps: [ThreeOmegaFieldSweepResult]   // sorted by temperatureK ascending
    var rtResult: ThreeOmegaRTResult?
    var device: String
    /// I_rms (A) keyed by temperatureK — required for scaling use case.
    var iRmsValues: [Double: Double] = [:]
    var warnings: [String] = []
}
