import Foundation

struct AHEAxisDetector {

    static let semanticXField = WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .manifestPlainText)
    static let semanticYField = WorkbenchPlotDisplayVocabulary.label(for: .hallResistance, context: .manifestPlainText)
    static let rawMagneticFieldColumn = "Magnetic Field (Oe)"

    // MARK: - Default axis mapping

    func defaultAxisMapping() -> WorkbenchAxisMapping {
        let xField = Self.semanticXField
        let yField = Self.semanticYField
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
