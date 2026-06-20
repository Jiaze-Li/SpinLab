import Foundation

/// Parses whitespace-delimited RSM text files with H K L and one intensity column.
///
/// Accepted intensity column names (case-insensitive): Detector, Intensity, Counts, I.
/// Lines starting with '#' or ';' are treated as comments and skipped.
/// The header row is the first non-comment line that contains tokens H, K, and L.
enum RSMDataParser {

    enum ParseError: Error, Sendable, LocalizedError, Equatable {
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

    static func parse(
        text: String,
        title: String = "",
        sourceRef: String = ""
    ) throws -> CanonicalRSMDataset {
        let lines = normalizedLines(text)
        guard !lines.isEmpty else { throw ParseError.empty }

        // First non-comment line that has H, K, L tokens is the header.
        guard let headerIdx = lines.indices.first(where: { isHeaderLine(lines[$0]) }) else {
            throw ParseError.missingRequiredColumns(found: tokens(of: lines[0]))
        }

        let header = tokens(of: lines[headerIdx])
        guard
            let hCol = header.firstIndex(where: { $0.uppercased() == "H" }),
            let kCol = header.firstIndex(where: { $0.uppercased() == "K" }),
            let lCol = header.firstIndex(where: { $0.uppercased() == "L" }),
            let dCol = header.firstIndex(where: { isIntensityToken($0) })
        else {
            throw ParseError.missingRequiredColumns(found: header)
        }

        let needed = max(hCol, kCol, lCol, dCol)
        var points: [CanonicalRSMPoint] = []

        for offset in (headerIdx + 1) ..< lines.count {
            let line = lines[offset]
            let t = tokens(of: line)
            let lineNumber = offset + 1   // 1-based for error messages
            guard t.count > needed else {
                throw ParseError.malformedRow(lineNumber: lineNumber, content: line)
            }
            guard
                let h = Double(t[hCol]),
                let k = Double(t[kCol]),
                let l = Double(t[lCol]),
                let d = Double(t[dCol])
            else {
                throw ParseError.malformedRow(lineNumber: lineNumber, content: line)
            }
            points.append(CanonicalRSMPoint(h: h, k: k, l: l, detector: d))
        }

        let detectorColumnName = header[dCol].capitalized

        return CanonicalRSMDataset(
            points: points,
            title: title,
            sourceRef: sourceRef,
            detectorColumnName: detectorColumnName
        )
    }

    // MARK: - Helpers

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
