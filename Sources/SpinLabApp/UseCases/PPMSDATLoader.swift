import Foundation

// MARK: - PPMSDATLoader
//
// Shared raw-file loader for the PPMS .dat container format, Phase 3f (2026-08-08 PPMS DAT
// consolidation). Mirrors ZurichLVMLoader's role for the Zurich LVM grammar: this type owns file
// I/O, [Header]/[Data] structure detection, comma-separated row parsing, column-index
// construction, and numeric conversion — nothing else.
//
// Unlike LVM's headerless positional grammar, PPMS .dat files declare a named column header
// (the "Comment,..." line), so this loader — unlike ZurichLVMLoader — does populate `rawLabel`
// per column. It still must not know AHE/RT/XY Rotation, bridge wiring meaning, Rxx/Rxy, axis
// roles, or series labels; those stay workflow interpretation, assigned after the column leaves
// this loader (see MeasurementColumn's ownership doc comment).
//
// Two header variants are supported (both already required by AHE before this migration):
//   Variant A: "[Header]" ... "[Data]" \n "Comment,<names>" \n data rows
//   Variant B: no "[Header]" block — file starts directly with "Comment,<names>"
//
// A data row with the wrong field count is padded (short) or truncated (long) to the declared
// column count, matching the pre-migration AHE tolerance exactly; each such row also produces a
// `MeasurementDiagnostic` instead of being silently normalized. A field that does not parse as a
// `Double` (e.g. the "Comment" text column, or a blank field) becomes `Double.nan` in that column's
// `values`, preserving row alignment across columns for name-based paired lookups downstream.

struct PPMSDATLoader {

    enum LoadError: Error, LocalizedError {
        case unreadableFile(URL)
        case missingDataSection(URL)
        case missingColumnHeader(URL)
        case unrecognizedFormat(URL)

        var errorDescription: String? {
            switch self {
            case .unreadableFile(let url):
                return "Cannot read file: \(url.lastPathComponent)"
            case .missingDataSection(let url):
                return "Missing [Data] section: \(url.lastPathComponent)"
            case .missingColumnHeader(let url):
                return "Missing column header after [Data]: \(url.lastPathComponent)"
            case .unrecognizedFormat(let url):
                return "Unrecognized .dat format: \(url.lastPathComponent)"
            }
        }
    }

    /// The raw string-table shape of a parsed PPMS .dat file — column names exactly as declared
    /// in the header, and one row of trimmed string fields per data line, padded/truncated to the
    /// column count. Exists so callers that still need literal (non-Double-round-tripped) field
    /// text (a legacy string-table compatibility adapter) can be built without re-parsing the file.
    struct RawTable {
        var columnNames: [String]
        var rows: [[String]]
        var diagnostics: [MeasurementDiagnostic]
    }

    /// Reads and parses `fileURL`'s PPMS .dat container grammar only — no numeric conversion, no
    /// unit/PhysicalQuantity interpretation. This is the single place raw PPMS file I/O and
    /// [Header]/[Data] structure detection happen.
    func loadRawTable(fileURL: URL) throws -> RawTable {
        let raw: String
        do {
            raw = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            guard let latin1 = try? String(contentsOf: fileURL, encoding: .isoLatin1) else {
                throw LoadError.unreadableFile(fileURL)
            }
            raw = latin1
        }

        let allLines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let columnLine: String
        let dataStartIndex: Int

        // The historical parser searched for [Data] anywhere in the file, tolerating leading
        // blank lines and instrument preamble before [Header]/[Data]. Restore that: locate
        // [Data] wherever it appears, rather than requiring it to be the very first line.
        if let dataIdx = allLines.firstIndex(of: "[Data]") {
            // The historical RT grammar allows one or more blank lines between [Data] and the
            // Comment,... column header; skip them, but a genuinely missing header still fails.
            var colIdx = dataIdx + 1
            while colIdx < allLines.count, allLines[colIdx].isEmpty {
                colIdx += 1
            }
            guard colIdx < allLines.count, allLines[colIdx].hasPrefix("Comment,") else {
                throw LoadError.missingColumnHeader(fileURL)
            }
            columnLine = allLines[colIdx]
            dataStartIndex = colIdx + 1
        } else if let commentIdx = allLines.firstIndex(where: { $0.hasPrefix("Comment,") }) {
            columnLine = allLines[commentIdx]
            dataStartIndex = commentIdx + 1
        } else {
            throw LoadError.unrecognizedFormat(fileURL)
        }

        let columnNames = columnLine
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let colCount = columnNames.count
        var diagnostics: [MeasurementDiagnostic] = []
        let dataLines = allLines[dataStartIndex...].filter { !$0.isEmpty }

        let rows: [[String]] = dataLines.enumerated().map { rowIndex, line -> [String] in
            var fields = line
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if fields.count < colCount {
                diagnostics.append(MeasurementDiagnostic(
                    code: "malformedRow.tooFewFields",
                    message: "Row \(rowIndex) had \(fields.count) fields, expected \(colCount); padded with empty values.",
                    columnKey: nil,
                    rowIndex: rowIndex
                ))
                fields += Array(repeating: "", count: colCount - fields.count)
            } else if fields.count > colCount {
                diagnostics.append(MeasurementDiagnostic(
                    code: "malformedRow.tooManyFields",
                    message: "Row \(rowIndex) had \(fields.count) fields, expected \(colCount); truncated extra values.",
                    columnKey: nil,
                    rowIndex: rowIndex
                ))
                fields = Array(fields.prefix(colCount))
            }
            return fields
        }

        return RawTable(columnNames: columnNames, rows: rows, diagnostics: diagnostics)
    }

    /// Reads `fileURL` and returns a `LoadedMeasurement` with one `MeasurementColumn` per declared
    /// header column. `rawLabel` is the literal header text; `values` are the row-aligned `Double`
    /// conversions (`Double.nan` where a field is blank or non-numeric, e.g. the "Comment" column).
    func load(fileURL: URL) throws -> LoadedMeasurement {
        let table = try loadRawTable(fileURL: fileURL)

        let signals = table.columnNames.enumerated().map { index, rawLabel -> MeasurementColumn in
            let values = table.rows.map { row -> Double in
                let field = index < row.count ? row[index] : ""
                return Double(field) ?? Double.nan
            }
            let (unit, quantityID) = Self.classify(rawLabel: rawLabel)
            return MeasurementColumn(
                stableSourceKey: "col\(index)",
                rawLabel: rawLabel,
                sourceColumnIndex: index,
                values: values,
                sourceUnit: unit,
                physicalQuantityID: quantityID,
                instrumentChannelLabel: nil
            )
        }

        return LoadedMeasurement(
            sourceFilePath: fileURL.path,
            format: .ppmsDAT,
            signals: signals,
            rowCount: table.rows.count,
            diagnostics: table.diagnostics
        )
    }

    // MARK: - Unit/PhysicalQuantity classification (Phase 3c rule, applied strictly)
    //
    // Only assigns a typed unit + PhysicalQuantityID where the header text is unambiguous on its
    // own, without any external/workflow context: "Temperature (K)" and "Magnetic Field (Oe)".
    // Every other parenthesized-unit column (Resistance, Resistivity, Sample Position, ...)
    // preserves the literal unit text via `.raw(...)` but is never assigned a PhysicalQuantityID —
    // bridge-number-to-Rxx/Rxy meaning and Sample Position's cross-workflow ambiguity are workflow
    // interpretation, not loader-owned. Columns with no parenthesized unit (e.g. "Comment") are
    // `.undeclared`.
    private static func classify(rawLabel: String) -> (PhysicalQuantityUnitTag, PhysicalQuantityID?) {
        guard rawLabel.hasSuffix(")"), let openParen = rawLabel.lastIndex(of: "(") else {
            return (.undeclared, nil)
        }
        let base = rawLabel[rawLabel.startIndex..<openParen].trimmingCharacters(in: .whitespaces)
        let unitStart = rawLabel.index(after: openParen)
        let unitEnd = rawLabel.index(before: rawLabel.endIndex)
        guard unitStart < unitEnd else { return (.undeclared, nil) }
        let unitText = String(rawLabel[unitStart..<unitEnd])

        switch base {
        case "Temperature" where unitText == "K":
            return (.temperature(.kelvin), .temperature)
        case "Magnetic Field" where unitText == "Oe":
            return (.magneticField(.oersted), .externalMagneticField)
        default:
            return (.raw(unitText), nil)
        }
    }
}
