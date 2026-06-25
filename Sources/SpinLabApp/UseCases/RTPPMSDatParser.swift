import Foundation

// MARK: - RTPPMSDatParser
//
// Parses PPMS MultiVu .dat files for the RT workflow.
//
// File format:
//   Section headers: [Header], [Data], etc.
//   [Data] section contains a CSV header row followed by numeric data rows.
//
// Column resolution (by header name, not position):
//   x: "Temperature (K)"
//   y: "Bridge N Resistance (Ohms)"  (preferred)
//      "Bridge N Resistivity (Ohm)"  (fallback)
//   where N = bridgeIndex derived from sidecar channel metadata (ch1→1, ch2→2, ch3→3).

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
                return "Bridge \(idx) resistance/resistivity column not found in header of \(name)"
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
    static func bridgeIndex(forChannel channel: String) -> Int? {
        switch channel.lowercased() {
        case "ch1": return 1
        case "ch2": return 2
        case "ch3": return 3
        default: return nil
        }
    }

    func parse(fileURL: URL, bridgeIndex: Int) throws -> ParseResult {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let name = fileURL.lastPathComponent

        // Locate [Data] section marker
        guard let dataIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "[Data]"
        }) else {
            throw ParseError.dataSectionNotFound(name)
        }

        // Next non-empty line after [Data] is the CSV header row
        let afterData = lines[(dataIdx + 1)...]
        guard let headerIdx = afterData.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            throw ParseError.temperatureColumnNotFound(name)
        }

        let headers = lines[headerIdx]
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Resolve x column by header name
        guard let tempColIdx = headers.firstIndex(of: "Temperature (K)") else {
            throw ParseError.temperatureColumnNotFound(name)
        }

        // Resolve y column: prefer Resistance, fallback Resistivity
        let resistanceName = "Bridge \(bridgeIndex) Resistance (Ohms)"
        let resistivityName = "Bridge \(bridgeIndex) Resistivity (Ohm)"
        guard let rxxColIdx = headers.firstIndex(of: resistanceName)
                ?? headers.firstIndex(of: resistivityName) else {
            throw ParseError.bridgeColumnNotFound(bridgeIndex, name)
        }

        // Parse data rows
        var temperatureK: [Double] = []
        var rxx: [Double] = []
        var warnings: [String] = []
        let minimumColCount = max(tempColIdx, rxxColIdx) + 1

        for (offset, line) in lines[(headerIdx + 1)...].enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let cols = trimmed.components(separatedBy: ",")
            guard cols.count >= minimumColCount,
                  let t = Double(cols[tempColIdx].trimmingCharacters(in: .whitespaces)),
                  let r = Double(cols[rxxColIdx].trimmingCharacters(in: .whitespaces)) else {
                warnings.append("Skipped malformed row \(offset + 1) in \(name)")
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
