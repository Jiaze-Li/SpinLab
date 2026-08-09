import Foundation

// MARK: - RSMTextLoader
//
// Shared raw-file loader for the whitespace-delimited RSM text grammar (Phase 3i RSM migration,
// 2026-08-08 MeasurementData/Signal architecture audit — final raw-format vertical slice). Mirrors
// ZurichLVMLoader/PPMSDATLoader's role: this type owns file I/O, comment skipping, header
// detection (first non-comment line whose tokens contain H, K, and L), detector/intensity column
// synonym resolution, whitespace-separated row parsing, numeric conversion, and row diagnostics —
// nothing else. It does not know view selection, `recommendedView`, `isViewCompatible`, plotting,
// slicing, or heatmap interpretation; those stay RSM workflow interpretation (CanonicalRSMDataset /
// RSMViewClassifier / RSMHeatmapPayloadBuilder), assigned after the data leaves this loader.
//
// H/K/L are tagged `physicalQuantityID: .reciprocalH/.reciprocalK/.reciprocalL` — the one
// exception to "loaders don't assign identity beyond an unambiguous header" — because the RSM
// grammar itself is defined as "the header line where H, K, and L co-occur"; recognizing that
// co-occurring set *is* this loader's grammar, not external context. `sourceUnit` stays
// `.undeclared` for H/K/L and the detector column: reciprocal-lattice-unit convention is domain
// knowledge, not something the raw file declares, and detector/intensity counts have no typed
// PhysicalQuantity in this codebase.
//
// Row-error policy: a row with too few fields, or a non-numeric H/K/L/detector field, aborts the
// whole load by throwing `LoadError.malformedRow` — matching the pre-migration RSMDataParser
// behavior exactly (no silent skip, no diagnostic-and-continue, unlike ZurichLVMLoader/
// PPMSDATLoader's per-row tolerance). This is a deliberate divergence from the other two loaders'
// tolerance policy, preserved because RSM's existing tests assert the abort behavior.

struct RSMTextLoader {

    enum LoadError: Error, Sendable, LocalizedError, Equatable {
        case empty
        case missingRequiredColumns(found: [String])
        case malformedRow(lineNumber: Int, content: String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "RSM file is empty."
            case let .missingRequiredColumns(found):
                let list = found.isEmpty ? "(none)" : found.joined(separator: ", ")
                return "RSM file missing required columns (H, K, L, Detector/Intensity/Counts/I). Found: \(list)."
            case let .malformedRow(n, content):
                return "RSM file: malformed data on line \(n): \"\(content)\"."
            }
        }
    }

    /// Reads `fileURL` and returns a `LoadedMeasurement` with four `MeasurementColumn`s: H, K, L,
    /// and detector/intensity. This is the only place raw RSM file I/O happens.
    func load(fileURL: URL) throws -> LoadedMeasurement {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try Self.parseMeasurement(text: text, sourceFilePath: fileURL.path)
    }

    /// Parses the RSM text grammar from an in-memory string. Exposed (not `private`) so
    /// `RSMDataParser` can adapt this loader's output into `CanonicalRSMDataset` without owning a
    /// second, duplicate implementation of the grammar.
    static func parseMeasurement(text: String, sourceFilePath: String) throws -> LoadedMeasurement {
        let lines = normalizedLines(text)
        guard !lines.isEmpty else { throw LoadError.empty }

        // First non-comment line that has H, K, L tokens is the header.
        guard let headerIdx = lines.indices.first(where: { isHeaderLine(lines[$0]) }) else {
            throw LoadError.missingRequiredColumns(found: tokens(of: lines[0]))
        }

        let header = tokens(of: lines[headerIdx])
        guard
            let hCol = header.firstIndex(where: { $0.uppercased() == "H" }),
            let kCol = header.firstIndex(where: { $0.uppercased() == "K" }),
            let lCol = header.firstIndex(where: { $0.uppercased() == "L" }),
            let dCol = header.firstIndex(where: { isIntensityToken($0) })
        else {
            throw LoadError.missingRequiredColumns(found: header)
        }

        let needed = max(hCol, kCol, lCol, dCol)
        var hValues: [Double] = []
        var kValues: [Double] = []
        var lValues: [Double] = []
        var dValues: [Double] = []

        for offset in (headerIdx + 1) ..< lines.count {
            let line = lines[offset]
            let t = tokens(of: line)
            let lineNumber = offset + 1   // 1-based for error messages
            guard t.count > needed else {
                throw LoadError.malformedRow(lineNumber: lineNumber, content: line)
            }
            guard
                let h = Double(t[hCol]),
                let k = Double(t[kCol]),
                let l = Double(t[lCol]),
                let d = Double(t[dCol])
            else {
                throw LoadError.malformedRow(lineNumber: lineNumber, content: line)
            }
            hValues.append(h)
            kValues.append(k)
            lValues.append(l)
            dValues.append(d)
        }

        let rowCount = hValues.count
        let signals = [
            MeasurementColumn(
                stableSourceKey: "H",
                rawLabel: header[hCol],
                sourceColumnIndex: hCol,
                values: hValues,
                sourceUnit: .undeclared,
                physicalQuantityID: .reciprocalH
            ),
            MeasurementColumn(
                stableSourceKey: "K",
                rawLabel: header[kCol],
                sourceColumnIndex: kCol,
                values: kValues,
                sourceUnit: .undeclared,
                physicalQuantityID: .reciprocalK
            ),
            MeasurementColumn(
                stableSourceKey: "L",
                rawLabel: header[lCol],
                sourceColumnIndex: lCol,
                values: lValues,
                sourceUnit: .undeclared,
                physicalQuantityID: .reciprocalL
            ),
            MeasurementColumn(
                stableSourceKey: "detector",
                rawLabel: header[dCol],
                sourceColumnIndex: dCol,
                values: dValues,
                sourceUnit: .undeclared,
                physicalQuantityID: nil
            )
        ]

        return LoadedMeasurement(
            sourceFilePath: sourceFilePath,
            format: .rsmText,
            signals: signals,
            rowCount: rowCount,
            diagnostics: []
        )
    }

    // MARK: - Grammar helpers (sole owner of RSM text-grammar detection in the codebase)

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .components(separatedBy: "\n")
            .map  { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") }
    }

    private static func tokens(of line: String) -> [String] {
        line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    private static func isHeaderLine(_ line: String) -> Bool {
        let t = Set(tokens(of: line).map { $0.uppercased() })
        return t.contains("H") && t.contains("K") && t.contains("L")
    }

    private static func isIntensityToken(_ token: String) -> Bool {
        ["DETECTOR", "INTENSITY", "COUNTS", "I"].contains(token.uppercased())
    }
}
