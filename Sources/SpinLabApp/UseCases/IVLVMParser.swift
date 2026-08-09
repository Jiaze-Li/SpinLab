import Foundation

// MARK: - IVLVMParser
//
// IV-specific workflow adapter over the shared `ZurichLVMLoader` (Phase 3c). Raw file I/O,
// Tableau-marker detection, and positional 11-column extraction all live in `ZurichLVMLoader` —
// this type owns only the IV-specific positional-to-named column mapping and the current-unit
// interpretation the shared, format-agnostic loader cannot know on its own (see the 2026-08-08
// MeasurementData/Signal architecture audit §4/§9).
//
// Column layout (0-indexed, positional) — same container as XY Rotation/3ω, different column
// semantics; this mapping is IV workflow interpretation, not raw file grammar:
//   0  Current (A, peak)
//   1  1st X (V)        ← ch1 in-phase voltage
//   2  1st Y (V)        ← ch1 quadrature voltage
//   3  1st R (V)        ← ch1 amplitude (raw audit/reference)
//   4  1st Theta        ← ch1 phase (raw audit/reference)
//   5  2nd X (V)        ← ch2 in-phase voltage
//   6  2nd Y (V)        ← ch2 quadrature voltage
//   7  2nd R (V)        ← ch2 amplitude (raw audit/reference)
//   8  2nd Theta        ← ch2 phase (raw audit/reference)
//   9  1st R_H (Ω)      ← raw audit/reference for the ch1 relation
//  10  Frequency_after  ← raw audit/reference

struct IVLVMParser {

    enum ParseError: Error, LocalizedError {
        case markerNotFound(String)
        case noDataRows(URL)
        case temperatureNotFound(URL)

        var errorDescription: String? {
            switch self {
            case .markerNotFound(let path):
                return "LVM marker 'Tableau:' not found in \(path)"
            case .noDataRows(let url):
                return "No data rows found in \(url.lastPathComponent)"
            case .temperatureNotFound(let url):
                return "Cannot determine temperature for \(url.lastPathComponent) — no sidecar temperature and no T_<n>K in filename"
            }
        }
    }

    var marker: String = "Tableau:"

    /// Parses `fileURL` and returns an `IVSweep` with raw channel data.
    ///
    /// - Parameters:
    ///   - temperatureOverride: When provided, bypasses filename-based temperature extraction.
    ///   - fieldOverride: When provided, sets fieldT directly instead of defaulting to 0.
    func parse(fileURL: URL,
               temperatureOverride: Double? = nil,
               fieldOverride: Double? = nil) throws -> IVSweep {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        // Phase 4a: never fabricate a 0 K sweep. If neither the sidecar override nor the filename
        // fallback can resolve a temperature, reject the file rather than silently defaulting.
        guard let temperatureK = temperatureOverride ?? _parseTemperature(stem: stem) else {
            throw ParseError.temperatureNotFound(fileURL)
        }
        let fieldT = fieldOverride ?? 0.0

        let loaded: LoadedMeasurement
        do {
            loaded = try ZurichLVMLoader(marker: marker).load(fileURL: fileURL)
        } catch let error as ZurichLVMLoader.LoadError {
            throw Self._mapLoadError(error)
        }

        let interpreted = Self._applyIVUnitInterpretation(to: loaded)
        return try Self._buildIVSweep(
            from: interpreted,
            stem: stem,
            temperatureK: temperatureK,
            fieldT: fieldT,
            fileURL: fileURL
        )
    }

    // MARK: - IV-specific interpretation (workflow-owned; the shared loader cannot know this)

    /// col0 is peak current in Amperes by IV's own file grammar — a fact about how THIS
    /// workflow's files are wired, not something the shared, format-agnostic loader could ever
    /// assert (per the audit's §4 assignment rule). Tags it here, once, at the IV boundary.
    private static func _applyIVUnitInterpretation(to loaded: LoadedMeasurement) -> LoadedMeasurement {
        var loaded = loaded
        guard loaded.signals.indices.contains(0) else { return loaded }
        loaded.signals[0].physicalQuantityID = .current
        loaded.signals[0].sourceUnit = .current(.ampere)
        return loaded
    }

    /// col0 → current, col1/col2 → ch1X/ch1Y, col5/col6 → ch2X/ch2Y, col3/col4/col7/col8/col9/
    /// col10 → raw audit/reference arrays. This positional-to-named mapping is IV workflow
    /// interpretation (audit §9), not something `ZurichLVMLoader` performs.
    private static func _buildIVSweep(from loaded: LoadedMeasurement,
                                       stem: String,
                                       temperatureK: Double,
                                       fieldT: Double,
                                       fileURL: URL) throws -> IVSweep {
        // IV's own requirement: it reads column 10 (Frequency_after), one column beyond what
        // the shared loader guarantees (ZurichLVMLoader.minimumColumnCount == 10). 3ω and XY
        // Rotation files legitimately stop at 10 columns and must not be rejected by this check
        // — only IV needs it, so IV enforces it here rather than in the shared loader.
        let requiredColumnCount = ZurichLVMLoader.minimumColumnCount + 1
        guard loaded.signals.count >= requiredColumnCount else {
            throw ParseError.noDataRows(fileURL)
        }
        let columns = loaded.signals
        let current = columns[0].values
        let ch1X = columns[1].values
        let ch1Y = columns[2].values
        let ch2X = columns[5].values
        let ch2Y = columns[6].values
        let firstR = columns[3].values
        let firstTheta = columns[4].values
        let secondR = columns[7].values
        let secondTheta = columns[8].values
        let firstRH = columns[9].values
        let frequencyAfter = columns[10].values
        guard !current.isEmpty else { throw ParseError.noDataRows(fileURL) }

        // The shared loader now preserves malformed rows with non-finite values instead of
        // dropping them; IV owns the requirement that its channel-classification and fitting
        // inputs (current, ch1X/Y, ch2X/Y — see the column-layout doc above) are the fields that
        // matter, so a malformed required-column row must be skipped here, matching historical
        // behavior, before it can reach channel-state classification or fitting. All arrays are
        // filtered by the same retained-row indices to keep alignment.
        let validIndices = (0..<current.count).filter {
            current[$0].isFinite && ch1X[$0].isFinite && ch1Y[$0].isFinite
                && ch2X[$0].isFinite && ch2Y[$0].isFinite
        }
        guard !validIndices.isEmpty else { throw ParseError.noDataRows(fileURL) }

        func retain(_ values: [Double]) -> [Double] { validIndices.map { values[$0] } }

        return IVSweep(
            stem: stem,
            temperatureK: temperatureK,
            fieldT: fieldT,
            current: retain(current),
            ch1X: retain(ch1X),
            ch1Y: retain(ch1Y),
            ch2X: retain(ch2X),
            ch2Y: retain(ch2Y),
            firstR: retain(firstR),
            firstTheta: retain(firstTheta),
            secondR: retain(secondR),
            secondTheta: retain(secondTheta),
            firstRH: retain(firstRH),
            frequencyAfter: retain(frequencyAfter),
            measurementFilePath: fileURL.path,
            sampleMetadata: nil
        )
    }

    private static func _mapLoadError(_ error: ZurichLVMLoader.LoadError) -> ParseError {
        switch error {
        case .markerNotFound(let path): return .markerNotFound(path)
        case .noDataRows(let url): return .noDataRows(url)
        }
    }

    // MARK: - Private

    private func _parseTemperature(stem: String) -> Double? {
        let pattern = #"(?:^|[_\s])(\d+(?:\.\d+)?)\s*K(?:[_\s]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range(at: 1), in: stem),
              let value = Double(stem[range])
        else { return nil }
        return value
    }
}
