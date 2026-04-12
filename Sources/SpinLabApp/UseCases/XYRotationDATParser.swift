import Foundation

// MARK: - XYRotationDATParser
//
// Parses PPMS .dat files for the XY Rotation workflow.
// Internally delegates to AHEDataParser for low-level CSV parsing,
// then maps columns by name to extract angle, Rxx, Rxy, and temperature.
//
// Column mapping (by header name):
//   "Sample Position (deg)"    → angle
//   "Bridge 2 Resistivity (Ohm)" or "Bridge 2 Resistance (Ohms)" → Rxx
//   "Bridge 3 Resistivity (Ohm)" or "Bridge 3 Resistance (Ohms)" → Rxy
//   "Temperature (K)"          → temperature

struct XYRotationDATParser {

    enum ParseError: Error, LocalizedError {
        case columnNotFound(String, URL)
        case noDataRows(URL)
        case temperatureNotFound(URL)

        var errorDescription: String? {
            switch self {
            case .columnNotFound(let col, let url):
                return "Column '\(col)' not found in \(url.lastPathComponent)"
            case .noDataRows(let url):
                return "No valid data rows in \(url.lastPathComponent)"
            case .temperatureNotFound(let url):
                return "Cannot determine temperature for \(url.lastPathComponent)"
            }
        }
    }

    func parse(fileURL: URL, temperatureOverride: Double? = nil) throws -> XYRotationAngleSweep {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let parsed = try AHEDataParser().parse(fileURL: fileURL)

        // Find column indices by name
        let angleIdx = _findColumn(parsed.columnNames, candidates: [
            "Sample Position (deg)"
        ])
        guard let ai = angleIdx else {
            throw ParseError.columnNotFound("Sample Position (deg)", fileURL)
        }

        let rxxIdx = _findColumn(parsed.columnNames, candidates: [
            "Bridge 2 Resistivity (Ohm)",
            "Bridge 2 Resistance (Ohms)"
        ])
        guard let ri = rxxIdx else {
            throw ParseError.columnNotFound("Bridge 2 Resistivity/Resistance", fileURL)
        }

        let rxyIdx = _findColumn(parsed.columnNames, candidates: [
            "Bridge 3 Resistivity (Ohm)",
            "Bridge 3 Resistance (Ohms)"
        ])

        let tempIdx = _findColumn(parsed.columnNames, candidates: [
            "Temperature (K)"
        ])

        // Parse rows
        var angleDeg: [Double] = []
        var rxx: [Double] = []
        var rxy: [Double] = []
        var temperatures: [Double] = []

        for row in parsed.rows {
            guard ai < row.count, ri < row.count else { continue }
            guard let angle = Double(row[ai]), let resistance = Double(row[ri]) else { continue }
            // When Bridge 3 column exists, require parseable value to keep row aligned
            if let xi = rxyIdx {
                guard xi < row.count, Double(row[xi]) != nil else { continue }
            }
            angleDeg.append(angle)
            rxx.append(resistance)
            if let xi = rxyIdx, xi < row.count, let v = Double(row[xi]) {
                rxy.append(v)
            }
            if let ti = tempIdx, ti < row.count, let t = Double(row[ti]) {
                temperatures.append(t)
            }
        }

        guard !angleDeg.isEmpty else {
            throw ParseError.noDataRows(fileURL)
        }

        // Determine temperature: prefer override, then data column mean, then filename.
        let temperatureK: Double
        if let t = temperatureOverride {
            temperatureK = t
        } else if !temperatures.isEmpty {
            temperatureK = temperatures.reduce(0, +) / Double(temperatures.count)
        } else if let t = _parseTemperatureFromFilename(stem: stem) {
            temperatureK = t
        } else {
            throw ParseError.temperatureNotFound(fileURL)
        }

        return XYRotationAngleSweep(
            temperatureK: temperatureK,
            stem: stem,
            sourceKind: .dat,
            angleDeg: angleDeg,
            resistanceXX: rxx,
            resistanceXY: rxy.isEmpty ? nil : rxy,
            defaultPhiOffset: 0
        )
    }

    // MARK: - Private

    private func _findColumn(_ names: [String], candidates: [String]) -> Int? {
        for candidate in candidates {
            if let idx = names.firstIndex(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return idx
            }
        }
        return nil
    }

    private func _parseTemperatureFromFilename(stem: String) -> Double? {
        let pattern = #"(?:^|[_\s])(\d+(?:\.\d+)?)\s*K(?:[_\s]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range(at: 1), in: stem),
              let value = Double(stem[range])
        else { return nil }
        return value
    }
}
