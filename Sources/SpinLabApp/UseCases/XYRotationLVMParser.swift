import Foundation

// MARK: - XYRotationLVMParser
//
// XY Rotation-specific workflow adapter over the shared `ZurichLVMLoader` (Phase 3e, following
// IV's Phase 3c and 3ω's Phase 3d migrations). Raw file I/O, Tableau-marker detection, and
// positional 11-column extraction all live in `ZurichLVMLoader` — this type owns only the
// XY-specific positional-to-named column mapping and the derivation the shared, format-agnostic
// loader cannot know on its own (see the 2026-08-08 MeasurementData/Signal architecture audit
// §4/§9).
//
// Column layout (0-indexed, positional) — same container as IV/3ω, different column semantics;
// this mapping is XY Rotation workflow interpretation, not raw file grammar:
//   0  Position (angle in degrees)
//   1  1st X (V)        ← V¹ω in-phase
//   2  1st Y (V)
//   3  1st R (V)
//   4  1st Theta
//   5  2nd X (V)        ← V²ω in-phase (for Rxy)
//   6  2nd Y (V)
//   7  2nd R (V)
//   8  2nd Theta
//   9  1st R_H (Ω)      ← Rxx = V¹ω_X / I_rms
//  10  f_ref (Hz)
//
// Derivations (workflow-owned; ZurichLVMLoader performs none of these):
//   I_rms = mean( col[1] / col[9] )   (first N rows)
//   Rxx   = col[9]                     (1st R_H — already resistance in the raw file)
//   Rxy   = col[5] / I_rms            (2nd X raw voltage / I_rms — derived here, not the loader)

struct XYRotationLVMParser {

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

    var iRmsAveragingRows: Int = 20

    /// Tableau marker threaded through to `ZurichLVMLoader` (API compatibility — configuration,
    /// not a second detection implementation).
    var marker: String = "Tableau:"

    func parse(fileURL: URL, temperatureOverride: Double? = nil) throws -> XYRotationAngleSweep {
        let stem = fileURL.deletingPathExtension().lastPathComponent

        // Resolve temperature: prefer override (from sidecar), fall back to filename.
        let temperatureK: Double
        if let t = temperatureOverride {
            temperatureK = t
        } else {
            guard let t = _parseTemperature(stem: stem) else {
                throw ParseError.temperatureNotFound(stem)
            }
            temperatureK = t
        }

        // Raw file I/O, Tableau-marker detection, and positional 11-column extraction all live
        // in ZurichLVMLoader — this adapter never opens the file itself.
        let loaded: LoadedMeasurement
        do {
            loaded = try ZurichLVMLoader(marker: marker).load(fileURL: fileURL)
        } catch let error as ZurichLVMLoader.LoadError {
            throw Self._mapLoadError(error)
        }

        let interpreted = Self._applyXYRotationUnitInterpretation(to: loaded)
        return try Self._buildAngleSweep(
            from: interpreted,
            stem: stem,
            temperatureK: temperatureK,
            iRmsAveragingRows: iRmsAveragingRows,
            fileURL: fileURL
        )
    }

    // MARK: - XY-specific interpretation (workflow-owned; the shared loader cannot know this)

    /// col0 is the sweep angle in degrees by XY Rotation's own file grammar — the LVM positional
    /// grammar makes this unambiguous, per the audit's §4 assignment rule. col1/col5/col9 (raw
    /// harmonic voltages / pre-calculated R_H) are deliberately left untagged: they are not yet
    /// resistance (col5) or have no clean existing PhysicalQuantityID for a raw voltage's
    /// harmonic role (col1) — tagging them would either be premature (before Rxy derivation) or
    /// force an identity the model doesn't cleanly support.
    private static func _applyXYRotationUnitInterpretation(to loaded: LoadedMeasurement) -> LoadedMeasurement {
        var loaded = loaded
        guard loaded.signals.indices.contains(0) else { return loaded }
        loaded.signals[0].physicalQuantityID = .deviceAngle
        loaded.signals[0].sourceUnit = .raw("deg")
        return loaded
    }

    /// col0/col1/col5/col9 → angle/V1w_X/V2w_X/R_H, plus I_rms and Rxy derivation. This
    /// positional-to-named mapping and the physics derivation are XY Rotation workflow
    /// interpretation (audit §9), not something `ZurichLVMLoader` performs.
    private static func _buildAngleSweep(
        from loaded: LoadedMeasurement,
        stem: String,
        temperatureK: Double,
        iRmsAveragingRows: Int,
        fileURL: URL
    ) throws -> XYRotationAngleSweep {
        guard loaded.signals.count >= ZurichLVMLoader.columnCount else {
            throw ParseError.noDataRows(fileURL)
        }
        let columns = loaded.signals
        let angleDeg = columns[0].values
        let col1 = columns[1].values      // raw V1w_X — survives here, pre-derivation
        let col5 = columns[5].values      // raw V2w_X — survives here, pre-derivation (Rxy source)
        let col9 = columns[9].values      // pre-calculated R_H — already Rxx, no derivation needed
        guard !angleDeg.isEmpty else { throw ParseError.noDataRows(fileURL) }

        let iRms = try _deriveIRms(col1: col1, col9: col9, averagingRows: iRmsAveragingRows, fileURL: fileURL)

        // Rxx = col[9] (1st R_H, already resistance in the raw file — no division needed).
        // Rxy = col[5] / I_rms (2nd X raw voltage / I_rms) — this division is the workflow-owned
        // derivation the raw loader must never perform.
        let rxx = col9
        let rxy = col5.map { $0 / iRms }

        return XYRotationAngleSweep(
            temperatureK: temperatureK,
            stem: stem,
            sourceKind: .lvm,
            angleDeg: angleDeg,
            resistanceXX: rxx,
            resistanceXY: rxy,
            defaultPhiOffset: 0
        )
    }

    /// Derive I_rms from data: I_rms = mean( Col[1][i] / Col[9][i] ) for the first N rows.
    /// Moved unchanged from the raw-parser layer (Phase 3e) — same source columns, same row
    /// window, same fallback/error behavior, same numeric results.
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

    // MARK: - Private

    private func _parseTemperature(stem: String) -> Double? {
        // Match patterns like "80K", "170K", "4.999K"
        let pattern = #"(?:^|[_\s])(\d+(?:\.\d+)?)\s*K(?:[_\s]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range(at: 1), in: stem),
              let value = Double(stem[range])
        else { return nil }
        return value
    }
}
