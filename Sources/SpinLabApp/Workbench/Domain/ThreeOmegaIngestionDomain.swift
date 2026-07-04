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
    /// Explicit storage-unit marker for this result's magnetic-field values
    /// (`ThreeOmegaFieldSweepResult.hField`/`.hc1omega`/`.hc3omega`).
    ///
    /// Added v5.5.6+ (docs/architecture/workbench/MAGNETIC_FIELD_STORAGE_AUDIT.md) to make 3ω's
    /// storage unit an explicit data field instead of an implicit assumption. Packs saved before
    /// this field existed have no marker at all and MUST be treated as `"Oe"` on decode — that is
    /// the only unit 3ω ever wrote to disk before the canonical-Tesla save migration below.
    static let oerstedStorageUnit = "Oe"

    /// Canonical storage unit for new 3ω pack saves as of the Oe→T migration
    /// (`ThreeOmegaWorkspaceStore+Pack.swift._buildPackResult()`, via `normalizedToStorageTesla()`
    /// below). Never used as a default for freshly-ingested in-memory results — the internal
    /// runtime/analysis representation remains Oe; only the pack-save boundary converts to this.
    static let teslaStorageUnit = "T"

    var fieldSweeps: [ThreeOmegaFieldSweepResult]   // sorted by temperatureK ascending
    var rtResult: ThreeOmegaRTResult?
    var device: String
    var deviceMode: String
    var devices: [String]
    /// I_rms (A) keyed by temperatureK — required for scaling use case.
    var iRmsValues: [Double: Double]
    var warnings: [String]
    /// See `oerstedStorageUnit`/`teslaStorageUnit` doc comments above. Freshly-ingested in-memory
    /// results are always `"Oe"` (the internal runtime representation) — the pack-save boundary
    /// is what converts this to `"T"` for what actually reaches disk.
    var magneticFieldStorageUnit: String

    init(
        fieldSweeps: [ThreeOmegaFieldSweepResult] = [],
        rtResult: ThreeOmegaRTResult? = nil,
        device: String,
        deviceMode: String = "single",
        devices: [String] = [],
        iRmsValues: [Double: Double] = [:],
        warnings: [String] = [],
        magneticFieldStorageUnit: String = ThreeOmegaIngestionResult.oerstedStorageUnit
    ) {
        self.fieldSweeps = fieldSweeps
        self.rtResult = rtResult
        self.device = device
        self.deviceMode = deviceMode
        self.devices = devices
        self.iRmsValues = iRmsValues
        self.warnings = warnings
        self.magneticFieldStorageUnit = magneticFieldStorageUnit
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fieldSweeps = try c.decode([ThreeOmegaFieldSweepResult].self, forKey: .fieldSweeps)
        rtResult    = try c.decodeIfPresent(ThreeOmegaRTResult.self, forKey: .rtResult)
        device      = try c.decode(String.self, forKey: .device)
        deviceMode  = try c.decodeIfPresent(String.self, forKey: .deviceMode) ?? "single"
        devices     = try c.decodeIfPresent([String].self, forKey: .devices) ?? []
        iRmsValues  = try c.decodeIfPresent([Double: Double].self, forKey: .iRmsValues) ?? [:]
        warnings    = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        // Missing key = legacy pack saved before this marker existed = always Oe.
        magneticFieldStorageUnit = try c.decodeIfPresent(String.self, forKey: .magneticFieldStorageUnit)
            ?? ThreeOmegaIngestionResult.oerstedStorageUnit
    }
}

// MARK: - Restore-time storage-unit compatibility boundary

extension ThreeOmegaIngestionResult {
    /// The single restore-time boundary for 3ω magnetic-field storage-unit compatibility.
    ///
    /// Reads `magneticFieldStorageUnit` — a data field decoded from the pack, never inferred from
    /// a display label — and normalizes `fieldSweeps[].hField`/`.hc1omega`/`.hc3omega` to Oe, the
    /// unit every existing 3ω analysis/manifest/display path assumes. Every pack-restore call site
    /// (main restore, overlay ingestion) must route decoded results through this before the values
    /// are used anywhere else, so a future Tesla-storage pack is interpreted correctly instead of
    /// silently mis-scaled by 10000x.
    ///
    /// - `magneticFieldStorageUnit == "Oe"` (explicit, or defaulted from a missing/legacy key):
    ///   values pass through completely unchanged — this is a no-op, not a reinterpretation.
    /// - `magneticFieldStorageUnit == "T"`: values are converted T→Oe once, and the marker is
    ///   updated to `"Oe"` to reflect that the in-memory representation is now canonical Oe.
    /// - Any other value is treated defensively the same as `"Oe"` (pass-through) rather than
    ///   guessed at — an unrecognized marker is more likely a hand-edited or corrupt file than a
    ///   real future format worth guessing about.
    func normalizedToStorageOersted() -> ThreeOmegaIngestionResult {
        guard magneticFieldStorageUnit == "T" else { return self }
        var copy = self
        copy.fieldSweeps = fieldSweeps.map { sweep in
            var s = sweep
            s.hField = sweep.hField.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: .oersted) }
            s.hc1omega = sweep.hc1omega.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: .oersted) }
            s.hc3omega = sweep.hc3omega.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: .oersted) }
            return s
        }
        copy.magneticFieldStorageUnit = ThreeOmegaIngestionResult.oerstedStorageUnit
        return copy
    }
}

// MARK: - Save-time canonical-Tesla storage boundary

extension ThreeOmegaIngestionResult {
    /// The single save-time boundary that converts 3ω magnetic-field values to canonical Tesla
    /// storage. Called only from `ThreeOmegaWorkspaceStore+Pack.swift._buildPackResult()` — the
    /// one place a `ThreeOmegaPackResult` is constructed for writing to a pack.
    ///
    /// The internal runtime/analysis representation stays Oe (unchanged by this method's caller;
    /// this returns a converted copy, it does not mutate the store's `ingestionResult`). Only what
    /// actually reaches disk is Tesla from here on:
    /// - `hField`/`hc1omega`/`hc3omega` are converted Oe→T (`×1e-4`), same conversion for both.
    /// - `magneticFieldStorageUnit` is written as `"T"`.
    ///
    /// Guards on `magneticFieldStorageUnit == "Oe"` because that is the only unit the in-memory
    /// runtime ever produces (fresh ingestion defaults to Oe; `normalizedToStorageOersted()`
    /// always leaves a restored result marked `"Oe"` too) — so this is a straight-line conversion,
    /// not a branch on some other possible input state. A result already marked `"T"` (there is no
    /// code path that produces one today, but defensively) or any unrecognized marker passes
    /// through unchanged rather than being converted twice.
    func normalizedToStorageTesla() -> ThreeOmegaIngestionResult {
        guard magneticFieldStorageUnit == ThreeOmegaIngestionResult.oerstedStorageUnit else { return self }
        var copy = self
        copy.fieldSweeps = fieldSweeps.map { sweep in
            var s = sweep
            s.hField = sweep.hField.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .oersted, to: .tesla) }
            s.hc1omega = sweep.hc1omega.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .oersted, to: .tesla) }
            s.hc3omega = sweep.hc3omega.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .oersted, to: .tesla) }
            return s
        }
        copy.magneticFieldStorageUnit = ThreeOmegaIngestionResult.teslaStorageUnit
        return copy
    }
}
