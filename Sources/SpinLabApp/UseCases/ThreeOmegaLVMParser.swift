import Foundation

// MARK: - ThreeOmegaLVMParser
//
// Parses Zurich Instruments LVM files for the 3ω AHE workflow.
//
// File format:
//   Line 0:  double-header line (ignored)
//   Line 1:  second header line (ignored)
//   Line 2:  blank (ignored)
//   Line 3:  "Tableau:" marker
//   Line 4+: tab-separated numeric data rows, NO column-header row
//
// Column layout (0-indexed, positional):
//   0  H (Oe) or T (K) for RT files
//   1  V¹ω_X (V)
//   2  V¹ω_Y (V)
//   3  V¹ω_R (V)
//   4  V¹ω_θ
//   5  V³ω_X (V)   ← 3rd harmonic in-phase
//   6  V³ω_Y (V)
//   7  V³ω_R (V)
//   8  V³ω_θ
//   9  R_H (Ω)     pre-calculated: V¹ω_X / I_rms
//  10  f_ref (Hz)

struct ThreeOmegaLVMParser {

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

    /// Number of leading rows used to compute I_rms (from data, not filename).
    var iRmsAveragingRows: Int = 20

    /// Tableau marker string used in LVM headers.
    var marker: String = "Tableau:"

    func parse(fileURL: URL, temperatureOverride: Double? = nil) throws -> ThreeOmegaLVMFile {
        let stem = fileURL.deletingPathExtension().lastPathComponent

        // Classify file kind
        let kind: ThreeOmegaFileKind
        if stem.contains("_RT_") || stem.uppercased().hasPrefix("RT_") {
            kind = .rtSweep
        } else {
            kind = .fieldSweep
        }

        // Parse angle label from parent folder name
        let angleLabel = _angleLabel(from: fileURL)

        // Resolve temperature: prefer override (from sidecar conditions), fall back to filename.
        let temperatureK: Double
        if kind == .fieldSweep {
            if let t = temperatureOverride {
                temperatureK = t
            } else {
                guard let t = _parseTemperature(stem: stem) else {
                    throw ParseError.temperatureNotFound(stem)
                }
                temperatureK = t
            }
        } else {
            temperatureK = .nan  // RT files have no single temperature
        }

        // Parse optional I_amp from filename (backup/validation only)
        let iAmpFromFilename = _parseIAmp(stem: stem)

        // Read file content and locate Tableau: marker
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        // Locate data start: prefer explicit "Tableau:" marker (field-sweep files).
        // Fallback: find first line whose first tab-separated token parses as Double.
        // RT files from this instrument omit the Tableau: marker entirely.
        var dataStart: Int?
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                dataStart = i + 1   // data begins on the line after "Tableau:"
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

        // Parse numeric rows
        var col0: [Double] = []
        var col1: [Double] = []
        var col5: [Double] = []
        var col9: [Double] = []

        for line in dataLines {
            let parts = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 10 else {
                // Tolerate short trailing lines (e.g. footer)
                continue
            }
            guard
                let v0 = Double(parts[0]),
                let v1 = Double(parts[1]),
                let v5 = Double(parts[5]),
                let v9 = Double(parts[9])
            else { continue }

            col0.append(v0)
            col1.append(v1)
            col5.append(v5)
            col9.append(v9)
        }

        guard !col0.isEmpty else {
            throw ParseError.noDataRows(fileURL)
        }

        // Derive I_rms from data: I_rms = mean( Col[1][i] / Col[9][i] )
        // Formula: I_rms = V¹ω_X / R_H
        // This is primary — more reliable than filename parsing.
        // Verified: consistent across all rows to ~1e-11 precision.
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

        return ThreeOmegaLVMFile(
            iRms: iRms,
            iAmpFromFilename: iAmpFromFilename,
            temperatureK: temperatureK,
            angleLabel: angleLabel,
            fileKind: kind,
            stem: stem,
            col0: col0,
            col1: col1,
            col5: col5,
            col9: col9
        )
    }

    // MARK: - Private helpers

    /// Extract temperature in Kelvin from filename, e.g. "T_5 K" or "T_160.5 K".
    private func _parseTemperature(stem: String) -> Double? {
        // Pattern: T_<value>[ ]K  (case-insensitive)
        let pattern = #"T_([0-9]+(?:\.[0-9]+)?)\s*K"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(stem.startIndex..., in: stem)
        guard let match = regex.firstMatch(in: stem, range: range),
              let tRange = Range(match.range(at: 1), in: stem) else { return nil }
        return Double(stem[tRange])
    }

    /// Extract I_amp in Amperes from filename, e.g. "Iac_1 A" or "Iac_0.5 A".
    private func _parseIAmp(stem: String) -> Double? {
        let pattern = #"Iac_([0-9]+(?:\.[0-9]+)?)\s*A"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(stem.startIndex..., in: stem)
        guard let match = regex.firstMatch(in: stem, range: range),
              let iRange = Range(match.range(at: 1), in: stem) else { return nil }
        return Double(stem[iRange])
    }

    /// Derive angle label from the file's parent folder name.
    /// E.g. path ".../0deg/file.lvm" → "0deg"
    private func _angleLabel(from url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent
    }
}
