import Foundation

// MARK: - XYRotationDATParser
//
// XY Rotation workflow interpretation layer over the shared `PPMSDATLoader` (Phase 3h PPMS DAT
// consolidation, mirrors AHE's Phase 3f and RT's Phase 3g migrations). All raw PPMS file I/O and
// [Header]/[Data] grammar detection now live exclusively in `PPMSDATLoader.loadRawTable`; this
// type performs no file reading of its own. The former `AHEDataParser` -> `PPMSParsedFile`
// indirection has been removed — both types were deleted once this was their last consumer.
//
// What remains here is XY Rotation-specific interpretation only:
//   - angle column: "Sample Position (deg)" only, no fallback name
//   - Rxx (Bridge 2) / Rxy (Bridge 3): Resistance-only (Phase 4a) — "Bridge N Resistance (Ohms)"
//     only, no Resistivity fallback. Resistance and Resistivity are distinct physical quantities;
//     SpinLab must not assume a PPMS file's geometry setting makes them numerically equal. This
//     replaces the pre-4a Resistivity-preferred/Resistance-fallback precedence, which was the
//     OPPOSITE of AHE's/RT's own (already Resistance-only) rule.
//   - Rxx is mandatory; Rxy is optional (sweep proceeds without it if absent from the header)
//   - row alignment: when a Bridge 3 column exists in the header, a row is only kept if Bridge 3
//     also parses on that row, even though Rxy itself is optional overall
//   - temperature resolution: override param -> mean of "Temperature (K)" column -> filename regex
//   - `defaultPhiOffset` stays hardcoded to 0 here; shift/phi application remains
//     `IngestXYRotationSelectionsUseCase`'s responsibility, applied identically to `.dat`/`.lvm`
//   - `sourceKind: .dat` is set here, distinguishing this direct-from-file resistance path from
//     the Zurich-LVM-derived `.lvm` path (`XYRotationLVMParser`)
//
// Column mapping (by header name):
//   "Sample Position (deg)"    → angle
//   "Bridge 2 Resistance (Ohms)" → Rxx
//   "Bridge 3 Resistance (Ohms)" → Rxy (optional)
//   "Temperature (K)"          → temperature

struct XYRotationDATParser {

    enum ParseError: Error, LocalizedError {
        case columnNotFound(String, URL)
        case noDataRows(URL)
        case temperatureNotFound(URL)

        var errorDescription: String? {
            switch self {
            case .columnNotFound(let col, let url):
                return "Column '\(col)' not found in \(url.lastPathComponent)"
            case .noDataRows(let url):
                return "No valid data rows in \(url.lastPathComponent)"
            case .temperatureNotFound(let url):
                return "Cannot determine temperature for \(url.lastPathComponent)"
            }
        }
    }

    func parse(fileURL: URL, temperatureOverride: Double? = nil) throws -> XYRotationAngleSweep {
        try parseWithDiagnostics(fileURL: fileURL, temperatureOverride: temperatureOverride).sweep
    }

    /// Same as `parse`, but also returns the loader's row-level `MeasurementDiagnostic`s (Phase 4a
    /// diagnostics wiring) so the caller can surface them as workflow warnings without re-parsing
    /// the file. `parse` above stays the primary/back-compat entry point for callers that don't
    /// need diagnostics.
    func parseWithDiagnostics(
        fileURL: URL,
        temperatureOverride: Double? = nil
    ) throws -> (sweep: XYRotationAngleSweep, diagnostics: [MeasurementDiagnostic]) {
        let stem = fileURL.deletingPathExtension().lastPathComponent

        let table: PPMSDATLoader.RawTable
        do {
            table = try PPMSDATLoader().loadRawTable(fileURL: fileURL)
        } catch let error as PPMSDATLoader.LoadError {
            // Preserves the exact error type/text AHEDataParser used to surface for these
            // LoadError cases (this file previously reached PPMSDATLoader indirectly through it).
            switch error {
            case .unreadableFile:
                throw AppError.io(error.errorDescription ?? "Cannot read file")
            case .missingDataSection, .missingColumnHeader, .unrecognizedFormat:
                throw AppError.validation(error.errorDescription ?? "Unrecognized .dat format")
            }
        }

        // Find column indices by name
        let angleIdx = _findColumn(table.columnNames, candidates: [
            "Sample Position (deg)"
        ])
        guard let ai = angleIdx else {
            throw ParseError.columnNotFound("Sample Position (deg)", fileURL)
        }

        let rxxIdx = _findColumn(table.columnNames, candidates: [
            "Bridge 2 Resistance (Ohms)"
        ])
        guard let ri = rxxIdx else {
            throw ParseError.columnNotFound("Bridge 2 Resistance (Ohms)", fileURL)
        }

        let rxyIdx = _findColumn(table.columnNames, candidates: [
            "Bridge 3 Resistance (Ohms)"
        ])

        let tempIdx = _findColumn(table.columnNames, candidates: [
            "Temperature (K)"
        ])

        // Parse rows
        var angleDeg: [Double] = []
        var rxx: [Double] = []
        var rxy: [Double] = []
        var temperatures: [Double] = []

        for row in table.rows {
            guard ai < row.count, ri < row.count else { continue }
            guard let angle = Double(row[ai]), let resistance = Double(row[ri]) else { continue }
            // When Bridge 3 column exists, require parseable value to keep row aligned
            if let xi = rxyIdx {
                guard xi < row.count, Double(row[xi]) != nil else { continue }
            }
            angleDeg.append(angle)
            rxx.append(resistance)
            if let xi = rxyIdx, xi < row.count, let v = Double(row[xi]) {
                rxy.append(v)
            }
            if let ti = tempIdx, ti < row.count, let t = Double(row[ti]) {
                temperatures.append(t)
            }
        }

        guard !angleDeg.isEmpty else {
            throw ParseError.noDataRows(fileURL)
        }

        // Determine temperature: prefer override, then data column mean, then filename.
        let temperatureK: Double
        if let t = temperatureOverride {
            temperatureK = t
        } else if !temperatures.isEmpty {
            temperatureK = temperatures.reduce(0, +) / Double(temperatures.count)
        } else if let t = _parseTemperatureFromFilename(stem: stem) {
            temperatureK = t
        } else {
            throw ParseError.temperatureNotFound(fileURL)
        }

        let sweep = XYRotationAngleSweep(
            temperatureK: temperatureK,
            stem: stem,
            sourceKind: .dat,
            angleDeg: angleDeg,
            resistanceXX: rxx,
            resistanceXY: rxy.isEmpty ? nil : rxy,
            defaultPhiOffset: 0
        )
        return (sweep, table.diagnostics)
    }

    // MARK: - Private

    private func _findColumn(_ names: [String], candidates: [String]) -> Int? {
        for candidate in candidates {
            if let idx = names.firstIndex(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return idx
            }
        }
        return nil
    }

    private func _parseTemperatureFromFilename(stem: String) -> Double? {
        let pattern = #"(?:^|[_\s])(\d+(?:\.\d+)?)\s*K(?:[_\s]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range(at: 1), in: stem),
              let value = Double(stem[range])
        else { return nil }
        return value
    }
}
