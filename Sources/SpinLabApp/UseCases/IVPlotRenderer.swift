import Foundation

// MARK: - IVPlotRenderer
//
// Builds WorkbenchPlotPayload for IV workflow tabs.
//
// Tab "1st / I":  1st harmonic selected component vs Current (mA, peak/RMS)
// Tab "2nd / I":  2nd harmonic selected component vs Current (mA, peak/RMS)

struct IVPlotRenderer {

    var workflowID: String = ""
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

    private struct StackedIVPayloads {
        let manifestPayload: WorkbenchPlotPayload
        let displayPayload: WorkbenchPlotPayload
        let warnings: [String]
    }

    // MARK: - 1st / I

    mutating func makeFirstHarmonicPayload(
        sweeps: [IVSweep],
        device: String
    ) -> WorkbenchPlotPayload? {
        makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: [],
            titleSuffix: "1st / I",
            yLabel: "V (V)",
            yValueForSweep: { ch1Component == .x ? $0.ch1X : $0.ch1Y }
        )?.manifestPayload
    }

    mutating func renderFirstHarmonicVsCurrent(
        sweeps: [IVSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payloads = makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: hiddenSeriesKeys,
            titleSuffix: "1st / I",
            yLabel: "V (V)",
            yValueForSweep: { ch1Component == .x ? $0.ch1X : $0.ch1Y }
        ) else {
            return (nil, nil, nil, [])
        }
        return (nil, nil, payloads.displayPayload, payloads.warnings)
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
        makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: [],
            titleSuffix: "2nd / I",
            yLabel: "V (V)",
            yValueForSweep: { ch2Component == .x ? $0.ch2X : $0.ch2Y }
        )?.manifestPayload
    }

    mutating func renderSecondHarmonicVsCurrent(
        sweeps: [IVSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payloads = makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: hiddenSeriesKeys,
            titleSuffix: "2nd / I",
            yLabel: "V (V)",
            yValueForSweep: { ch2Component == .x ? $0.ch2X : $0.ch2Y }
        ) else {
            return (nil, nil, nil, [])
        }
        return (nil, nil, payloads.displayPayload, payloads.warnings)
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
        return zip(series, offsets).map { pair in
            let (s, offset) = pair
            guard offset != 0 else { return s }
            var shifted = s
            shifted.y = s.y.map { $0 + offset }
            return shifted
        }
    }

    private func makeStackedPayloads(
        sweeps: [IVSweep],
        device: String,
        hiddenSeriesKeys: [String],
        titleSuffix: String,
        yLabel: String,
        yValueForSweep: (IVSweep) -> [Double]
    ) -> StackedIVPayloads? {
        guard !sweeps.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        for sweep in sweeps {
            let tempLabel = _tempLabel(sweep.temperatureK)
            let ref = (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? "")
            series.append(WorkbenchPlotSeries(
                label: tempLabel,
                x: _adjustedCurrent(sweep.current),
                y: yValueForSweep(sweep),
                sourceRef: ref,
                sampleID: sweep.id,
                metadata: sweep.sampleMetadata ?? [:]
            ))
        }
        series = _applySeriesOrder(series, currentSeriesOrder: seriesOrder)

        let visibility = filterHiddenStackSeries(series, hiddenSeriesKeys: hiddenSeriesKeys)
        let visibleSeries = visibility.series
        let stackInputSeries = visibility.ignoredAllHidden ? series : visibleSeries
        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: stackInputSeries.map(\.y),
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        let displaySeries = zip(stackInputSeries, offsets).map { pair in
            let (series, offset) = pair
            guard offset != 0 else { return series }
            var shifted = series
            shifted.y = series.y.map { $0 + offset }
            return shifted
        }
        let warning = visibility.ignoredAllHidden ? ["series visibility ignored: all series were hidden"] : []

        let title = _defaultTitle(titleSuffix, device: device)
        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "IV",
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: xCurrentBasis.axisLabel, yField: yLabel),
            series: series,
            seriesReorderable: true
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "IV",
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: xCurrentBasis.axisLabel, yField: yLabel),
            series: displaySeries,
            seriesReorderable: true
        )
        return StackedIVPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: warning
        )
    }

    private func _applySeriesOrder(
        _ series: [WorkbenchPlotSeries],
        currentSeriesOrder: [String]?
    ) -> [WorkbenchPlotSeries] {
        let orderedKeys = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(currentSeriesOrder, series: series)
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series)
        guard orderedKeys != identities.map(\.identityKey) else {
            return series
        }

        let keyedSeries = zip(identities, series).map { identity, series in
            (
                key: identity.identityKey,
                series: series
            )
        }
        let lookup = Dictionary(uniqueKeysWithValues: keyedSeries.map { ($0.key, $0.series) })
        return orderedKeys.compactMap { lookup[$0] }
    }
}
