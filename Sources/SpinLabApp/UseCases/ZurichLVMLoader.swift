import Foundation

// MARK: - ZurichLVMLoader
//
// Shared raw-file loader for the Zurich Instruments LVM container format used by IV, 3ω, and
// XY Rotation (Phase 3c migrated IV; Phase 3d migrated 3ω; Phase 3e migrated XY Rotation's LVM
// path — its PPMS .dat path is unrelated and untouched. See the 2026-08-08 MeasurementData/
// Signal architecture audit §8/§11).
//
// File grammar (all three workflows share this container):
//   Line 0:  double-header line (ignored)
//   Line 1:  blank (ignored)
//   Line 2:  "Tableau:" marker
//   Line 3+: tab-separated numeric data rows, 10 or 11 positional columns depending on the
//            source workflow (see minimumColumnCount/maximumColumnCount below), NO header row —
//            there is nothing in the file itself that names a column, so this loader never
//            assigns rawLabel or physicalQuantityID. What each column *means* (current vs
//            voltage vs harmonic) is workflow-specific interpretation, not something this
//            loader can know.
//
// This type knows file grammar only. It performs no physics derivation (no iRms, no Rxy, no
// harmonic/component/x-y assignment, no unit conversion) and does not import or reference any
// IV/ThreeOmega/XYRotation workflow type.

struct ZurichLVMLoader {

    enum LoadError: Error, LocalizedError {
        case markerNotFound(String)
        case noDataRows(URL)

        var errorDescription: String? {
            switch self {
            case .markerNotFound(let path):
                return "LVM marker 'Tableau:' not found in \(path)"
            case .noDataRows(let url):
                return "No data rows found in \(url.lastPathComponent)"
            }
        }
    }

    /// Minimum column width for this shared container across IV/3ω/XY Rotation. 3ω and XY
    /// Rotation only ever read columns 0–9 (10 columns); IV additionally needs an 11th
    /// (Frequency_after) and enforces that requirement itself, at its own interpretation
    /// boundary. The raw loader must not impose IV's stricter requirement on every workflow.
    static let minimumColumnCount = 10

    /// Known upper bound for this shared container's width (IV's 11-column layout). Column
    /// count is otherwise data-driven from the file itself; this only guards against a stray
    /// trailing tab inflating the detected width beyond the known grammar.
    static let maximumColumnCount = 11

    var marker: String = "Tableau:"

    /// Reads `fileURL` and returns a `LoadedMeasurement` with one raw, uninterpreted
    /// `MeasurementColumn` per detected column (10 for 3ω/XY Rotation files, 11 for IV files —
    /// see `minimumColumnCount`). A row is kept as long as it has at least `columnCount` tab
    /// fields; a field that doesn't parse as `Double` becomes `Double.nan` in that column rather
    /// than dropping the whole row — which columns are actually required is workflow
    /// interpretation (IV/3ω/XY), not something this shared loader decides.
    func load(fileURL: URL) throws -> LoadedMeasurement {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var dataStart: Int?
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                dataStart = i + 1
                break
            }
        }
        // Fallback: first line whose first tab-field parses as a Double.
        if dataStart == nil {
            for (i, line) in lines.enumerated() {
                let first = line.components(separatedBy: "\t").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if Double(first) != nil {
                    dataStart = i
                    break
                }
            }
        }
        guard let start = dataStart else {
            throw LoadError.markerNotFound(fileURL.path)
        }

        let dataLines = lines[start...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !dataLines.isEmpty else {
            throw LoadError.noDataRows(fileURL)
        }

        // Column width is data-driven, but a single malformed/short leading row must not
        // permanently pin the detected width: take the tab-field count that is most common
        // across the data rows (capped at maximumColumnCount to guard against a stray trailing
        // tab), not merely the count of the first row wide enough to be real data. This lets a
        // lone malformed 10-field row followed by genuinely 11-field rows still resolve to
        // width 11.
        var fieldCountFrequency: [Int: Int] = [:]
        for line in dataLines {
            let count = min(line.components(separatedBy: "\t").count, Self.maximumColumnCount)
            guard count >= Self.minimumColumnCount else { continue }
            fieldCountFrequency[count, default: 0] += 1
        }
        guard let columnCount = fieldCountFrequency
            .max(by: { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
            })?
            .key
        else {
            throw LoadError.noDataRows(fileURL)
        }

        var columnValues = Array(repeating: [Double](), count: columnCount)

        for line in dataLines {
            let parts = line.components(separatedBy: "\t")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= columnCount else { continue }

            for i in 0..<columnCount {
                columnValues[i].append(Double(parts[i]) ?? Double.nan)
            }
        }

        guard let rowCount = columnValues.first?.count, rowCount > 0 else {
            throw LoadError.noDataRows(fileURL)
        }

        let signals = (0..<columnCount).map { index in
            MeasurementColumn(
                stableSourceKey: "col\(index)",
                rawLabel: nil,
                sourceColumnIndex: index,
                values: columnValues[index],
                sourceUnit: .undeclared,
                physicalQuantityID: nil,
                instrumentChannelLabel: nil
            )
        }

        return LoadedMeasurement(
            sourceFilePath: fileURL.path,
            format: .zurichLVM,
            signals: signals,
            rowCount: rowCount,
            diagnostics: []
        )
    }
}
