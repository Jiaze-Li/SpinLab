import Foundation

// MARK: - RTPPMSDatParser
//
// RT workflow interpretation layer over the shared `PPMSDATLoader` (Phase 3g PPMS DAT
// consolidation, mirrors AHE's Phase 3f migration). All raw PPMS file I/O and [Header]/[Data]
// grammar detection now live exclusively in `PPMSDATLoader.loadRawTable`; this type performs no
// file reading of its own. What remains here is RT-specific interpretation only:
//
//   - resolving "Temperature (K)" and "Bridge N Resistance (Ohms)" columns by exact header-name
//     match (N = bridgeIndex, derived from sidecar channel metadata via `bridgeIndex(forChannel:)`)
//   - Resistance-only (Phase 4a): Resistance and Resistivity are distinct physical quantities, so
//     RT does not fall back to "Bridge N Resistivity (...)" — SpinLab must not assume a PPMS file's
//     geometry setting makes them numerically equal. Column resolution is a pure existence-in-header
//     check (unlike AHE's `AHEAxisDetector.yColumnName`, which additionally requires the column to
//     have at least one non-NaN value) — a deliberate compatibility choice: RT's pre-migration
//     behavior never checked column activity, and this migration preserves that behavior exactly
//     rather than silently adopting AHE's stricter rule.
//   - per-row validation: a row is dropped (with a warning) rather than kept as NaN, matching RT's
//     pre-migration parser exactly. `PPMSDATLoader` itself never drops rows (it pads/truncates and
//     emits diagnostics); the drop-with-warning behavior is RT interpretation applied on top of the
//     loader's padded/truncated row table.
//
// Temperature/bridge pairing and ascending-temperature sorting remain the caller's responsibility
// (`AnalyzeRTWorkflowUseCase`), unchanged from before this migration.

struct RTPPMSDatParser {

    enum ParseError: Error, LocalizedError {
        case dataSectionNotFound(String)
        case temperatureColumnNotFound(String)
        case bridgeColumnNotFound(Int, String)
        case noValidDataRows(String)

        var errorDescription: String? {
            switch self {
            case .dataSectionNotFound(let name):
                return "[Data] section not found in \(name)"
            case .temperatureColumnNotFound(let name):
                return "Column 'Temperature (K)' not found in header of \(name)"
            case .bridgeColumnNotFound(let idx, let name):
                return "Bridge \(idx) Resistance (Ohms) column not found in header of \(name)"
            case .noValidDataRows(let name):
                return "No valid data rows parsed from \(name)"
            }
        }
    }

    struct ParseResult {
        var temperatureK: [Double]
        var rxx: [Double]
        var warnings: [String]
    }

    /// Maps sidecar channel string to PPMS bridge index.
    /// ch1 → 1, ch2 → 2, ch3 → 3. Returns nil for unrecognized values.
    /// Delegates to the shared mapping (Phase 4a; was a byte-for-byte duplicate of `AHEChannel.bridgeIndex`).
    static func bridgeIndex(forChannel channel: String) -> Int? {
        PPMSBridgeChannelMapping.bridgeIndex(forChannel: channel)
    }

    func parse(fileURL: URL, bridgeIndex: Int) throws -> ParseResult {
        let name = fileURL.lastPathComponent

        let table: PPMSDATLoader.RawTable
        do {
            table = try PPMSDATLoader().loadRawTable(fileURL: fileURL)
        } catch let error as PPMSDATLoader.LoadError {
            switch error {
            case .unreadableFile, .missingDataSection, .unrecognizedFormat:
                throw ParseError.dataSectionNotFound(name)
            case .missingColumnHeader:
                throw ParseError.temperatureColumnNotFound(name)
            }
        }

        // Resolve x column by header name
        guard let tempColIdx = table.columnNames.firstIndex(of: "Temperature (K)") else {
            throw ParseError.temperatureColumnNotFound(name)
        }

        // Resolve y column: Resistance only (Phase 4a, no Resistivity fallback) — exact header-name
        // match only, no active-column check (see file-level doc comment for why this differs from AHE).
        let resistanceName = "Bridge \(bridgeIndex) Resistance (Ohms)"
        guard let rxxColIdx = table.columnNames.firstIndex(of: resistanceName) else {
            throw ParseError.bridgeColumnNotFound(bridgeIndex, name)
        }

        // Parse data rows. `table.rows` are already padded/truncated to columnNames.count by the
        // loader, so both indices are always in bounds; a row is dropped with a warning if either
        // field fails to parse as a Double (blank/non-numeric), matching the pre-migration parser.
        var temperatureK: [Double] = []
        var rxx: [Double] = []
        // Seed with loader-observed diagnostics (e.g. a padded/truncated malformed row) — computed
        // by PPMSDATLoader.loadRawTable but previously discarded (Phase 4a diagnostics wiring).
        var warnings: [String] = table.diagnostics.map { $0.asWorkflowWarning(fileName: name) }

        for (rowIndex, row) in table.rows.enumerated() {
            guard tempColIdx < row.count, rxxColIdx < row.count,
                  let t = Double(row[tempColIdx]),
                  let r = Double(row[rxxColIdx]) else {
                warnings.append("Skipped malformed row \(rowIndex + 1) in \(name)")
                continue
            }
            temperatureK.append(t)
            rxx.append(r)
        }

        guard !temperatureK.isEmpty else {
            throw ParseError.noValidDataRows(name)
        }

        return ParseResult(temperatureK: temperatureK, rxx: rxx, warnings: warnings)
    }
}
