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
//   Line 3+: tab-separated numeric data rows, 11 positional columns, NO header row — there is
//            nothing in the file itself that names a column, so this loader never assigns
//            rawLabel or physicalQuantityID. What each column *means* (current vs voltage vs
//            harmonic) is workflow-specific interpretation, not something this loader can know.
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

    /// Fixed column count for this shared container format across IV/3ω/XY Rotation.
    static let columnCount = 11

    var marker: String = "Tableau:"

    /// Reads `fileURL` and returns a `LoadedMeasurement` with `Self.columnCount` raw,
    /// uninterpreted `MeasurementColumn`s. A data row is kept only when all `columnCount` fields
    /// parse as `Double`; otherwise the row is silently skipped (matches the malformed-row
    /// tolerance every pre-migration LVM parser already had).
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

        var columnValues = Array(repeating: [Double](), count: Self.columnCount)

        for line in dataLines {
            let parts = line.components(separatedBy: "\t")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= Self.columnCount else { continue }

            var rowValues: [Double] = []
            rowValues.reserveCapacity(Self.columnCount)
            var rowIsValid = true
            for i in 0..<Self.columnCount {
                guard let v = Double(parts[i]) else { rowIsValid = false; break }
                rowValues.append(v)
            }
            guard rowIsValid else { continue }

            for i in 0..<Self.columnCount {
                columnValues[i].append(rowValues[i])
            }
        }

        guard let rowCount = columnValues.first?.count, rowCount > 0 else {
            throw LoadError.noDataRows(fileURL)
        }

        let signals = (0..<Self.columnCount).map { index in
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
