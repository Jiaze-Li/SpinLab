import Foundation

struct AHEAxisDetector {

    private static let xPriority = [
        "Magnetic Field (Oe)",
        "Temperature (K)",
        "Sample Position (deg)",
    ]

    private static let bridgeRange = 1...3

    // MARK: - Candidate axis fields (union across files, fixed priority order)

    func candidateAxisFields(from files: [PPMSParsedFile]) -> [String] {
        guard !files.isEmpty else { return [] }

        var eligibleNames = Set<String>()
        for file in files {
            for (idx, name) in file.columnNames.enumerated() where !name.isEmpty {
                if file.rows.contains(where: { Double(safeField($0, idx)) != nil }) {
                    eligibleNames.insert(name)
                }
            }
        }

        var result: [String] = []
        var seen = Set<String>()

        func add(_ name: String) {
            guard eligibleNames.contains(name), seen.insert(name).inserted else { return }
            result.append(name)
        }

        for field in Self.xPriority { add(field) }

        let rhLabel = "R_H (\u{03A9})"
        result.append(rhLabel)
        seen.insert(rhLabel)
        for n in Self.bridgeRange {
            add("Bridge \(n) Resistance (Ohms)")
        }
        for n in Self.bridgeRange {
            // Match whichever Resistivity variant the file uses (Ohm or Ohm-m)
            for file in files {
                if let name = file.columnNames.first(where: { $0.hasPrefix("Bridge \(n) Resistivity") }) {
                    add(name)
                }
            }
        }

        return result
    }

    // MARK: - Default axis mapping

    func defaultAxisMapping(from files: [PPMSParsedFile]) -> WorkbenchAxisMapping {
        let xField = "Magnetic Field (T)"
        let yField = "R_H (\u{03A9})"
        return WorkbenchAxisMapping(xField: xField, yField: yField)
    }

    // MARK: - Per-bridge y column resolution

    /// Returns the best available y column name for a given bridge in a file.
    /// Prefers Resistance (Ohms); falls back to Resistivity if present and active.
    func yColumnName(from file: PPMSParsedFile, bridgeIndex: Int) -> String? {
        let resistance = "Bridge \(bridgeIndex) Resistance (Ohms)"
        if hasActiveColumn(resistance, in: file) { return resistance }
        if let resistivity = file.columnNames.first(where: { $0.hasPrefix("Bridge \(bridgeIndex) Resistivity") }),
           hasActiveColumn(resistivity, in: file) {
            return resistivity
        }
        return nil
    }

    // MARK: - Paired value extraction (x and y aligned by row)

    func pairedValues(
        from file: PPMSParsedFile,
        xColumn: String,
        yColumn: String
    ) -> (x: [Double], y: [Double]) {
        guard let xIdx = file.columnNames.firstIndex(of: xColumn),
              let yIdx = file.columnNames.firstIndex(of: yColumn) else {
            return ([], [])
        }
        var xs: [Double] = []
        var ys: [Double] = []
        for row in file.rows {
            let xStr = safeField(row, xIdx)
            let yStr = safeField(row, yIdx)
            if let x = Double(xStr), let y = Double(yStr) {
                xs.append(x)
                ys.append(y)
            }
        }
        return (xs, ys)
    }

    // MARK: - Private helpers

    private func hasActiveColumn(_ name: String, in file: PPMSParsedFile) -> Bool {
        guard let idx = file.columnNames.firstIndex(of: name) else { return false }
        return file.rows.contains { Double(safeField($0, idx)) != nil }
    }

    private func safeField(_ row: [String], _ idx: Int) -> String {
        idx < row.count ? row[idx] : ""
    }
}
