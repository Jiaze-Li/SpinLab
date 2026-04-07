import Foundation

// MARK: - XYRotationLVMParser
//
// Parses Zurich Instruments LVM files for the XY Rotation workflow.
//
// File format (same container as 3ω, different column semantics):
//   Line 0:  double-header line (ignored)
//   Line 1:  blank (ignored)
//   Line 2:  "Tableau:" marker
//   Line 3+: tab-separated numeric data rows
//
// Column layout (0-indexed, positional):
//   0  Position (angle in degrees)
//   1  1st X (V)        ← V¹ω in-phase
//   2  1st Y (V)
//   3  1st R (V)
//   4  1st Theta
//   5  2nd X (V)        ← V²ω in-phase (for Rxy)
//   6  2nd Y (V)
//   7  2nd R (V)
//   8  2nd Theta
//   9  1st R_H (Ω)      ← Rxx = V¹ω_X / I_rms
//  10  f_ref (Hz)
//
// Derivations:
//   I_rms = mean( col[1] / col[9] )   (first N rows)
//   Rxx   = col[9]                     (1st R_H)
//   Rxy   = col[5] / I_rms            (2nd X / I_rms)

struct XYRotationLVMParser {

    enum ParseError: Error, LocalizedError {
        case markerNotFound(String)
        case insufficientColumns(Int, URL)
        case noDataRows(URL)
        case iRmsDerivationFailed(URL)
        case temperatureNotFound(String)

        var errorDescription: String? {
            switch self {
            case .markerNotFound(let path):
                return "LVM marker 'Tableau:' not found in \(path)"
            case .insufficientColumns(let n, let url):
                return "Expected ≥10 columns, got \(n) in \(url.lastPathComponent)"
            case .noDataRows(let url):
                return "No data rows found in \(url.lastPathComponent)"
            case .iRmsDerivationFailed(let url):
                return "Cannot derive I_rms from Col[1]/Col[9] in \(url.lastPathComponent)"
            case .temperatureNotFound(let stem):
                return "Cannot parse temperature from filename: \(stem)"
            }
        }
    }

    var iRmsAveragingRows: Int = 20
    var marker: String = "Tableau:"

    func parse(fileURL: URL, temperatureOverride: Double? = nil) throws -> XYRotationAngleSweep {
        let stem = fileURL.deletingPathExtension().lastPathComponent

        // Resolve temperature: prefer override (from sidecar), fall back to filename.
        let temperatureK: Double
        if let t = temperatureOverride {
            temperatureK = t
        } else {
            guard let t = _parseTemperature(stem: stem) else {
                throw ParseError.temperatureNotFound(stem)
            }
            temperatureK = t
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        // Locate data start: "Tableau:" marker, or first numeric line as fallback.
        var dataStart: Int?
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                dataStart = i + 1
                break
            }
        }
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

        // Parse numeric rows: col0=angle, col1=1stX, col5=2ndX, col9=R_H
        var angleDeg: [Double] = []
        var col1: [Double] = []
        var col5: [Double] = []
        var col9: [Double] = []

        for line in dataLines {
            let parts = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 10 else { continue }
            guard
                let v0 = Double(parts[0]),
                let v1 = Double(parts[1]),
                let v5 = Double(parts[5]),
                let v9 = Double(parts[9])
            else { continue }

            angleDeg.append(v0)
            col1.append(v1)
            col5.append(v5)
            col9.append(v9)
        }

        guard !angleDeg.isEmpty else {
            throw ParseError.noDataRows(fileURL)
        }

        // Derive I_rms = mean( col[1] / col[9] )
        let nRows = min(iRmsAveragingRows, col1.count)
        var iRmsSum = 0.0
        var iRmsCount = 0
        for i in 0..<nRows {
            guard col9[i] != 0, col1[i].isFinite, col9[i].isFinite else { continue }
            iRmsSum += col1[i] / col9[i]
            iRmsCount += 1
        }
        guard iRmsCount > 0 else {
            throw ParseError.iRmsDerivationFailed(fileURL)
        }
        let iRms = iRmsSum / Double(iRmsCount)

        // Rxx = col[9] (1st R_H), Rxy = col[5] / I_rms (2nd X / I_rms)
        let rxx = col9
        let rxy = col5.map { $0 / iRms }

        return XYRotationAngleSweep(
            temperatureK: temperatureK,
            stem: stem,
            sourceKind: .lvm,
            angleDeg: angleDeg,
            resistance: rxx,
            resistanceXY: rxy,
            defaultPhiOffset: 0
        )
    }

    // MARK: - Private

    private func _parseTemperature(stem: String) -> Double? {
        // Match patterns like "80K", "170K", "4.999K"
        let pattern = #"(?:^|[_\s])(\d+(?:\.\d+)?)\s*K(?:[_\s]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range(at: 1), in: stem),
              let value = Double(stem[range])
        else { return nil }
        return value
    }
}
