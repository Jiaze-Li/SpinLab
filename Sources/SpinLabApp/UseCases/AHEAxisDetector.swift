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

    /// Returns the y column name for a given bridge in a measurement.
    ///
    /// Resistance-only (Phase 4a): Resistance and Resistivity are distinct physical quantities;
    /// SpinLab must not assume a PPMS file's geometry setting makes them numerically equal. Only
    /// "Bridge N Resistance (Ohms)" is accepted — no Resistivity fallback. If the bridge is absent
    /// or inactive, the caller surfaces the existing "no data" warning/failure path.
    func yColumnName(from measurement: LoadedMeasurement, bridgeIndex: Int) -> String? {
        let resistance = "Bridge \(bridgeIndex) Resistance (Ohms)"
        if hasActiveColumn(resistance, in: measurement) { return resistance }
        return nil
    }

    // MARK: - Paired value extraction (x and y aligned by row)

    func pairedValues(
        from measurement: LoadedMeasurement,
        xColumn: String,
        yColumn: String
    ) -> (x: [Double], y: [Double]) {
        guard let xCol = measurement.signals.first(where: { $0.rawLabel == xColumn }),
              let yCol = measurement.signals.first(where: { $0.rawLabel == yColumn }) else {
            return ([], [])
        }
        var xs: [Double] = []
        var ys: [Double] = []
        let count = min(xCol.values.count, yCol.values.count)
        for i in 0..<count {
            let x = xCol.values[i]
            let y = yCol.values[i]
            if !x.isNaN, !y.isNaN {
                xs.append(x)
                ys.append(y)
            }
        }
        return (xs, ys)
    }

    // MARK: - Private helpers

    private func hasActiveColumn(_ name: String, in measurement: LoadedMeasurement) -> Bool {
        guard let col = measurement.signals.first(where: { $0.rawLabel == name }) else { return false }
        return col.values.contains { !$0.isNaN }
    }
}
