import Foundation

// MARK: - ThreeOmegaLVMParser
//
// 3ω-specific workflow adapter over the shared `ZurichLVMLoader` (Phase 3d, following IV's
// Phase 3c migration). Raw file I/O, Tableau-marker detection, and positional 11-column
// extraction all live in `ZurichLVMLoader` — this type owns only 3ω-specific interpretation the
// shared, format-agnostic loader cannot know on its own (see the 2026-08-08 MeasurementData/
// Signal architecture audit §4/§9):
//   - fileKind classification (fieldSweep vs rtSweep) from filename/sidecar override
//   - col0 physical meaning: magnetic field (Oe) for fieldSweep, temperature (K) for rtSweep
//   - col1/col5/col9 positional-to-named mapping (1ω/3ω voltage, pre-calculated R_H)
//   - I_rms derivation from data (Col[1]/Col[9])
//   - filename metadata (temperature, I_amp, device fallback)
//
// Column layout (0-indexed, positional) — same container as IV/XY Rotation, different column
// semantics; this mapping is 3ω workflow interpretation, not raw file grammar:
//   0  H (Oe) or T (K) for RT files
//   1  V¹ω_X (V)       — 1st harmonic in-phase voltage
//   2  V¹ω_Y (V)
//   3  V¹ω_R (V)       — 1st harmonic magnitude
//   4  V¹ω_θ           — 1st harmonic phase
//   5  V³ω_X (V)       — 3rd harmonic in-phase voltage  ← AHE signal
//   6  V³ω_Y (V)
//   7  V³ω_R (V)
//   8  V³ω_θ
//   9  R_H (Ω)         — pre-calculated: V¹ω_X / I_rms  (verified ~1e-11 precision)
//  10  f_ref (Hz)      — ~317.3 Hz = 3ω reference frequency
//
// For RT files: Col 0 = Temperature (K), Col 9 = Rxx (Ω) pre-calculated.

struct ThreeOmegaLVMParser {

    enum ParseError: Error, LocalizedError {
        case markerNotFound(String)
        case noDataRows(URL)
        case iRmsDerivationFailed(URL)
        case temperatureNotFound(String)

        var errorDescription: String? {
            switch self {
            case .markerNotFound(let path):
                return "LVM marker 'Tableau:' not found in \(path)"
            case .noDataRows(let url):
                return "No data rows found in \(url.lastPathComponent)"
            case .iRmsDerivationFailed(let url):
                return "Cannot derive I_rms from Col[1]/Col[9] in \(url.lastPathComponent)"
            case .temperatureNotFound(let stem):
                return "Cannot parse temperature from filename: \(stem)"
            }
        }
    }

    /// Number of leading rows used to compute I_rms (from data, not filename).
    var iRmsAveragingRows: Int = 20

    /// Tableau marker string threaded through to `ZurichLVMLoader` (API compatibility —
    /// configuration, not a second detection implementation).
    var marker: String = "Tableau:"

    func parse(fileURL: URL, temperatureOverride: Double? = nil, kindOverride: ThreeOmegaFileKind? = nil) throws -> ThreeOmegaLVMFile {
        let stem = fileURL.deletingPathExtension().lastPathComponent

        // Classify file kind: sidecar override takes priority over filename heuristic.
        // This is the one filename-derived fact that is 3ω-workflow-owned per the Phase 3d
        // audit (§7) — it stays here, not in the shared loader.
        let kind: ThreeOmegaFileKind
        if let k = kindOverride {
            kind = k
        } else if stem.contains("_RT_") || stem.uppercased().hasPrefix("RT_") {
            kind = .rtSweep
        } else {
            kind = .fieldSweep
        }

        // Parse device label from parent folder name (fallback only)
        let device = _device(from: fileURL)

        // Resolve temperature: prefer override (from sidecar conditions), fall back to filename.
        let temperatureK: Double
        if kind == .fieldSweep {
            if let t = temperatureOverride {
                temperatureK = t
            } else {
                guard let t = _parseTemperature(stem: stem) else {
                    throw ParseError.temperatureNotFound(stem)
                }
                temperatureK = t
            }
        } else {
            temperatureK = .nan  // RT files have no single temperature
        }

        // Parse optional I_amp from filename (backup/validation only)
        let iAmpFromFilename = _parseIAmp(stem: stem)

        // Raw file I/O, Tableau-marker detection, and positional 11-column extraction all live
        // in ZurichLVMLoader — this adapter never opens the file itself.
        let loaded: LoadedMeasurement
        do {
            loaded = try ZurichLVMLoader(marker: marker).load(fileURL: fileURL)
        } catch let error as ZurichLVMLoader.LoadError {
            throw Self._mapLoadError(error)
        }

        let interpreted = Self._applyThreeOmegaUnitInterpretation(to: loaded, kind: kind)
        return try Self._buildThreeOmegaLVMFile(
            from: interpreted,
            stem: stem,
            temperatureK: temperatureK,
            device: device,
            kind: kind,
            iAmpFromFilename: iAmpFromFilename,
            iRmsAveragingRows: iRmsAveragingRows,
            fileURL: fileURL
        )
    }

    // MARK: - 3ω-specific interpretation (workflow-owned; the shared loader cannot know this)

    /// col0 means different physical quantities depending on fileKind — a fact about how THIS
    /// workflow's files are wired, not something the shared, format-agnostic loader could ever
    /// assert (per the audit's §4 assignment rule). Tags it here, once, at the 3ω boundary.
    /// col1/col5 (1ω/3ω harmonic voltages) are deliberately left untagged — the existing
    /// PhysicalQuantity model has no clean case for a raw voltage's harmonic role (per the
    /// Phase 3d handoff's explicit instruction not to force one).
    private static func _applyThreeOmegaUnitInterpretation(to loaded: LoadedMeasurement, kind: ThreeOmegaFileKind) -> LoadedMeasurement {
        var loaded = loaded
        guard loaded.signals.indices.contains(0) else { return loaded }
        switch kind {
        case .fieldSweep:
            loaded.signals[0].physicalQuantityID = .externalMagneticField
            loaded.signals[0].sourceUnit = .magneticField(.oersted)
        case .rtSweep:
            loaded.signals[0].physicalQuantityID = .temperature
            loaded.signals[0].sourceUnit = .temperature(.kelvin)
        }
        return loaded
    }

    /// col0/col1/col5/col9 → H-or-T/V¹ω_X/V³ω_X/R_H, plus I_rms derivation from col1/col9. This
    /// positional-to-named mapping and the physics derivation are 3ω workflow interpretation
    /// (audit §9), not something `ZurichLVMLoader` performs.
    private static func _buildThreeOmegaLVMFile(
        from loaded: LoadedMeasurement,
        stem: String,
        temperatureK: Double,
        device: String,
        kind: ThreeOmegaFileKind,
        iAmpFromFilename: Double?,
        iRmsAveragingRows: Int,
        fileURL: URL
    ) throws -> ThreeOmegaLVMFile {
        guard loaded.signals.count >= ZurichLVMLoader.minimumColumnCount else {
            throw ParseError.noDataRows(fileURL)
        }
        let columns = loaded.signals
        let col0 = columns[0].values
        let col1 = columns[1].values
        let col5 = columns[5].values
        let col9 = columns[9].values
        guard !col0.isEmpty else { throw ParseError.noDataRows(fileURL) }

        let iRms = try _deriveIRms(col1: col1, col9: col9, averagingRows: iRmsAveragingRows, fileURL: fileURL)

        return ThreeOmegaLVMFile(
            iRms: iRms,
            iAmpFromFilename: iAmpFromFilename,
            temperatureK: temperatureK,
            device: device,
            fileKind: kind,
            stem: stem,
            col0: col0,
            col1: col1,
            col5: col5,
            col9: col9
        )
    }

    /// Derive I_rms from data: I_rms = mean( Col[1][i] / Col[9][i] ) for the first N rows.
    /// Formula: I_rms = V¹ω_X / R_H. Verified: consistent across all rows to ~1e-11 precision —
    /// more reliable than filename parsing, which is kept only as a backup/validation value
    /// (`iAmpFromFilename`). Moved unchanged from the raw-parser layer (Phase 3d) — same source
    /// columns, same row window, same fallback/error behavior, same numeric results.
    private static func _deriveIRms(col1: [Double], col9: [Double], averagingRows: Int, fileURL: URL) throws -> Double {
        let nRows = min(averagingRows, col1.count)
        var iRmsSum = 0.0
        var iRmsCount = 0
        for i in 0..<nRows {
            guard col9[i] != 0, col1[i].isFinite, col9[i].isFinite else { continue }
            iRmsSum += col1[i] / col9[i]
            iRmsCount += 1
        }
        guard iRmsCount > 0 else {
            throw ParseError.iRmsDerivationFailed(fileURL)
        }
        return iRmsSum / Double(iRmsCount)
    }

    private static func _mapLoadError(_ error: ZurichLVMLoader.LoadError) -> ParseError {
        switch error {
        case .markerNotFound(let path): return .markerNotFound(path)
        case .noDataRows(let url): return .noDataRows(url)
        }
    }

    // MARK: - Private filename helpers

    /// Extract temperature in Kelvin from filename, e.g. "T_5 K" or "T_160.5 K".
    private func _parseTemperature(stem: String) -> Double? {
        // Pattern: T_<value>[ ]K  (case-insensitive)
        let pattern = #"T_([0-9]+(?:\.[0-9]+)?)\s*K"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(stem.startIndex..., in: stem)
        guard let match = regex.firstMatch(in: stem, range: range),
              let tRange = Range(match.range(at: 1), in: stem) else { return nil }
        return Double(stem[tRange])
    }

    /// Extract I_amp in Amperes from filename, e.g. "Iac_1 A" or "Iac_0.5 A".
    private func _parseIAmp(stem: String) -> Double? {
        let pattern = #"Iac_([0-9]+(?:\.[0-9]+)?)\s*A"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(stem.startIndex..., in: stem)
        guard let match = regex.firstMatch(in: stem, range: range),
              let iRange = Range(match.range(at: 1), in: stem) else { return nil }
        return Double(stem[iRange])
    }

    /// Derive device label from the file's parent folder name.
    /// E.g. path ".../0deg/file.lvm" → "0deg"
    /// NOTE: After library import, parent folder is "3w" not the original angle.
    /// Prefer sidecar conditions["device"] over this fallback.
    private func _device(from url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent
    }
}
