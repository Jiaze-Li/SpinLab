import Foundation

// MARK: - IVLVMParser
//
// Parses Zurich Instruments LVM files for the IV workflow.
//
// File format (same container as XY Rotation, different column semantics):
//   Line 0:  double-header line (ignored)
//   Line 1:  blank (ignored)
//   Line 2:  "Tableau:" marker
//   Line 3+: tab-separated numeric data rows
//
// Column layout (0-indexed, positional):
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

        var errorDescription: String? {
            switch self {
            case .markerNotFound(let path):
                return "LVM marker 'Tableau:' not found in \(path)"
            case .noDataRows(let url):
                return "No data rows found in \(url.lastPathComponent)"
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

        let temperatureK = temperatureOverride ?? _parseTemperature(stem: stem) ?? 0.0
        let fieldT = fieldOverride ?? 0.0

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
            throw ParseError.markerNotFound(fileURL.path)
        }

        let dataLines = lines[start...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !dataLines.isEmpty else {
            throw ParseError.noDataRows(fileURL)
        }

        var current: [Double] = []
        var ch1X:    [Double] = []
        var ch1Y:    [Double] = []
        var ch2X:    [Double] = []
        var ch2Y:    [Double] = []
        var firstR: [Double] = []
        var firstTheta: [Double] = []
        var secondR: [Double] = []
        var secondTheta: [Double] = []
        var firstRH: [Double] = []
        var frequencyAfter: [Double] = []

        for line in dataLines {
            let parts = line.components(separatedBy: "\t")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 11 else { continue }
            guard
                let v0 = Double(parts[0]),
                let v1 = Double(parts[1]),
                let v2 = Double(parts[2]),
                let v3 = Double(parts[3]),
                let v4 = Double(parts[4]),
                let v5 = Double(parts[5]),
                let v6 = Double(parts[6]),
                let v7 = Double(parts[7]),
                let v8 = Double(parts[8]),
                let v9 = Double(parts[9]),
                let v10 = Double(parts[10])
            else { continue }

            current.append(v0)
            ch1X.append(v1)
            ch1Y.append(v2)
            firstR.append(v3)
            firstTheta.append(v4)
            ch2X.append(v5)
            ch2Y.append(v6)
            secondR.append(v7)
            secondTheta.append(v8)
            firstRH.append(v9)
            frequencyAfter.append(v10)
        }

        guard !current.isEmpty else {
            throw ParseError.noDataRows(fileURL)
        }

        return IVSweep(
            stem: stem,
            temperatureK: temperatureK,
            fieldT: fieldT,
            current: current,
            ch1X: ch1X,
            ch1Y: ch1Y,
            ch2X: ch2X,
            ch2Y: ch2Y,
            firstR: firstR,
            firstTheta: firstTheta,
            secondR: secondR,
            secondTheta: secondTheta,
            firstRH: firstRH,
            frequencyAfter: frequencyAfter,
            measurementFilePath: fileURL.path,
            sampleMetadata: nil
        )
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
