import Foundation

/// Persisted per-sample metric-identity keys for AHE (`WorkbenchMetricIdentity`, sample-library
/// metric ledger). These are data keys, not display text — they must never be derived from or
/// coupled to `WorkbenchPlotDisplayVocabulary` output. See AHE_LABEL_KEY_AUDIT.md.
enum AHEDataFieldKey: String {
    case hc = "Hc"
    case rAHE = "R_AHE"
}

struct AHEAxisDetector {

    /// Display-only axis text for the AHE plot (`WorkbenchAxisMapping.xField`/`.yField`).
    /// Sourced from the display vocabulary; must never be used as a data lookup or persisted
    /// key. Raw-file column lookups use `rawMagneticFieldColumn`/`yColumnName` instead, which
    /// are independent of this text. See AHE_LABEL_KEY_AUDIT.md.
    static let displayXField = WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .externalMagneticField)
    static let displayYField = WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .hallResistance)
    static let rawMagneticFieldColumn = "Magnetic Field (Oe)"

    // MARK: - Default axis mapping

    func defaultAxisMapping() -> WorkbenchAxisMapping {
        let xField = Self.displayXField
        let yField = Self.displayYField
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
