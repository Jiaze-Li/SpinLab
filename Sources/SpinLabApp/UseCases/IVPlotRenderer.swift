import Foundation

// MARK: - IVPlotRenderer
//
// Builds WorkbenchPlotPayload for IV workflow tabs.
//
// Tab "1st / I":  1st harmonic selected component vs Current (mA, peak/RMS)
// Tab "2nd / I":  2nd harmonic selected component vs Current (mA, peak/RMS)

struct IVPlotRenderer {

    var titleTemplate: String = "#tab #device #sample"
    var titleTokens: [String: String] = [:]
    var seriesOrder: [String]? = nil
    var stackOffsetMultiplier: Double = 0.0
    var minGapFraction: Double = 0.15

    /// Which component of ch1 to use when building series.
    var ch1Component: IVSignalComponent = .x
    /// Which component of ch2 to use when building series.
    var ch2Component: IVSignalComponent = .x
    /// Whether the x-axis current is peak or RMS.
    var xCurrentBasis: IVCurrentBasis = .peak

    // MARK: - 1st / I

    mutating func makeFirstHarmonicPayload(
        sweeps: [IVSweep],
        device: String
    ) -> WorkbenchPlotPayload? {
        guard !sweeps.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        for sweep in sweeps {
            let tempLabel = _tempLabel(sweep.temperatureK)
            let ref = (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? "")
            let selected = ch1Component == .x ? sweep.ch1X : sweep.ch1Y
            series.append(WorkbenchPlotSeries(
                label: tempLabel,
                x: _adjustedCurrent(sweep.current),
                y: selected,
                sourceRef: ref,
                sampleID: sweep.id,
                metadata: sweep.sampleMetadata ?? [:]
            ))
        }
        series = _applySeriesOrder(series, currentSeriesOrder: seriesOrder)
        series = _applyStackOffsets(series, yExtractor: { $0.y })

        return WorkbenchPlotPayload(
            workflowID: "IV",
            workflowDisplayName: "IV",
            title: _defaultTitle("1st / I", device: device),
            axisMapping: WorkbenchAxisMapping(xField: xCurrentBasis.axisLabel, yField: "V (V)"),
            series: series,
            seriesReorderable: true
        )
    }

    mutating func renderFirstHarmonicVsCurrent(
        sweeps: [IVSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeFirstHarmonicPayload(sweeps: sweeps, device: device) else {
            return (nil, nil, nil, [])
        }
        return (nil, nil, payload, [])
    }

    // Backward-compatible wrapper for older call sites and tests.
    mutating func renderVoltageVsCurrent(
        sweeps: [IVSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        renderFirstHarmonicVsCurrent(sweeps: sweeps, device: device)
    }

    // MARK: - 2nd / I

    mutating func makeSecondHarmonicPayload(
        sweeps: [IVSweep],
        device: String
    ) -> WorkbenchPlotPayload? {
        guard !sweeps.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        for sweep in sweeps {
            let tempLabel = _tempLabel(sweep.temperatureK)
            let ref = (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? "")
            let selected = ch2Component == .x ? sweep.ch2X : sweep.ch2Y
            series.append(WorkbenchPlotSeries(
                label: tempLabel,
                x: _adjustedCurrent(sweep.current),
                y: selected,
                sourceRef: ref,
                sampleID: sweep.id,
                metadata: sweep.sampleMetadata ?? [:]
            ))
        }
        series = _applySeriesOrder(series, currentSeriesOrder: seriesOrder)
        series = _applyStackOffsets(series, yExtractor: { $0.y })

        return WorkbenchPlotPayload(
            workflowID: "IV",
            workflowDisplayName: "IV",
            title: _defaultTitle("2nd / I", device: device),
            axisMapping: WorkbenchAxisMapping(xField: xCurrentBasis.axisLabel, yField: "V (V)"),
            series: series,
            seriesReorderable: true
        )
    }

    mutating func renderSecondHarmonicVsCurrent(
        sweeps: [IVSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload = makeSecondHarmonicPayload(sweeps: sweeps, device: device) else {
            return (nil, nil, nil, [])
        }
        return (nil, nil, payload, [])
    }

    // Backward-compatible wrapper for older call sites and tests.
    mutating func renderResistanceVsCurrent(
        sweeps: [IVSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        renderSecondHarmonicVsCurrent(sweeps: sweeps, device: device)
    }

    private func _defaultTitle(_ tabName: String, device: String) -> String {
        var tokens = titleTokens
        tokens["tab"] = tabName
        tokens["device"] = device
        return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
    }

    private func _tempLabel(_ t: Double) -> String {
        t.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(t)) K"
            : String(format: "%.1f K", t)
    }

    private func _adjustedCurrent(_ values: [Double]) -> [Double] {
        return values.map { current_A in
            current_A * xCurrentBasis.scaleFactor
        }
    }

    private func _applyStackOffsets(
        _ series: [WorkbenchPlotSeries],
        yExtractor: (WorkbenchPlotSeries) -> [Double]
    ) -> [WorkbenchPlotSeries] {
        guard stackOffsetMultiplier != 0 || minGapFraction != 0 else { return series }
        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: series.map(yExtractor),
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        return zip(series, offsets).map { s, offset in
            guard offset != 0 else { return s }
            var shifted = s
            shifted.y = s.y.map { $0 + offset }
            return shifted
        }
    }

    private func _applySeriesOrder(
        _ series: [WorkbenchPlotSeries],
        currentSeriesOrder: [String]?
    ) -> [WorkbenchPlotSeries] {
        let orderedKeys = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(currentSeriesOrder, series: series)
        guard orderedKeys != series.enumerated().map({ index, series in
            WorkbenchSeriesOrderKeyResolver.resolve(for: series, originalIndex: index)
        }) else {
            return series
        }

        let keyedSeries = series.enumerated().map { index, series in
            (
                key: WorkbenchSeriesOrderKeyResolver.resolve(for: series, originalIndex: index),
                series: series
            )
        }
        let lookup = Dictionary(uniqueKeysWithValues: keyedSeries.map { ($0.key, $0.series) })
        return orderedKeys.compactMap { lookup[$0] }
    }
}
