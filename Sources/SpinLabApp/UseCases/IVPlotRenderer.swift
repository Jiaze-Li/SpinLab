import Foundation

// MARK: - IVPlotRenderer
//
// Builds WorkbenchPlotPayload for IV workflow tabs.
//
// Tab "1st / I":  1st harmonic selected component vs Current (mA, peak/RMS)
// Tab "2nd / I":  2nd harmonic selected component vs Current (mA, peak/RMS)

struct IVPlotRenderer {

    var workflowID: String = WorkflowKey.iv.rawValue
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

    /// Power-law fit module state (IV-owned; see IVPowerLawFitAdapter).
    var fitMode: PowerLawFitMode = .none
    var zeroAtCurrentOrigin: Bool = false

    struct StackedIVPayloads {
        let manifestPayload: WorkbenchPlotPayload
        let displayPayload: WorkbenchPlotPayload
        let warnings: [String]
    }

    // MARK: - 1st / I

    mutating func makeFirstHarmonicPayload(
        sweeps: [IVSweep],
        device: String
    ) -> WorkbenchPlotPayload? {
        makeFirstHarmonicPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: []
        )?.manifestPayload
    }

    mutating func makeFirstHarmonicPayloads(
        sweeps: [IVSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> StackedIVPayloads? {
        makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.ivFirstHarmonicVsCurrent,
            titleSuffix: "1st / I",
            yQuantity: .voltage,
            component: ch1Component,
            yValueForSweep: { ch1Component == .x ? $0.ch1X : $0.ch1Y }
        )
    }

    // MARK: - 2nd / I

    mutating func makeSecondHarmonicPayload(
        sweeps: [IVSweep],
        device: String
    ) -> WorkbenchPlotPayload? {
        makeSecondHarmonicPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: []
        )?.manifestPayload
    }

    mutating func makeSecondHarmonicPayloads(
        sweeps: [IVSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> StackedIVPayloads? {
        makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.ivSecondHarmonicVsCurrent,
            titleSuffix: "2nd / I",
            yQuantity: .voltage,
            component: ch2Component,
            yValueForSweep: { ch2Component == .x ? $0.ch2X : $0.ch2Y }
        )
    }

    private func _defaultTitle(_ tabName: String, device: String) -> String {
        var tokens = titleTokens
        tokens["tab"] = tabName
        tokens["device"] = device
        return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
    }

    private func _tempLabel(_ t: Double) -> String {
        WorkbenchPlotDisplayVocabulary.temperatureValueLabel(t)
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
        tabKey: String,
        titleSuffix: String,
        yQuantity: WorkbenchPhysicalQuantity,
        component: IVSignalComponent,
        yValueForSweep: (IVSweep) -> [Double]
    ) -> StackedIVPayloads? {
        guard !sweeps.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        var fitInputsByIdentityKey: [String: IVPowerLawFitAdapter.SeriesInput] = [:]
        for sweep in sweeps {
            let tempLabel = _tempLabel(sweep.temperatureK)
            let ref = (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? "")
            let stableSemanticID = WorkbenchSeriesIdentityMetadata.stableSemanticID(
                sourceRef: sweep.measurementFilePath,
                sampleID: sweep.id,
                fallback: sweep.stem
            ) ?? sweep.stem
            let currentMA = _adjustedCurrent(sweep.current)
            let voltageV = yValueForSweep(sweep)
            let metadata = _seriesMetadata(
                base: sweep.sampleMetadata ?? [:],
                tabKey: tabKey,
                seriesRole: "sweep",
                stableSemanticID: stableSemanticID
            )
            series.append(WorkbenchPlotSeries(
                label: tempLabel,
                x: currentMA,
                y: voltageV,
                sourceRef: ref,
                sampleID: sweep.id,
                metadata: metadata
            ))
            if let identityKey = metadata[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey] {
                fitInputsByIdentityKey[identityKey] = IVPowerLawFitAdapter.SeriesInput(
                    identityKey: identityKey,
                    currentMA: currentMA,
                    voltageV: voltageV
                )
            }
        }
        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: series,
                visualSeriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys,
                stackingPolicy: .orderEnforcingVertical(
                    multiplier: stackOffsetMultiplier,
                    minGapFraction: minGapFraction
                )
            )
        )

        let fitInputs = plan.visualSeries.compactMap { s in
            s.metadata[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey].flatMap { fitInputsByIdentityKey[$0] }
        }
        let manifestOverlays = IVPowerLawFitAdapter.makeOverlays(
            for: fitInputs,
            fitMode: fitMode,
            zeroAtCurrentOrigin: zeroAtCurrentOrigin,
            component: component
        )
        let displayOverlays = IVPowerLawFitAdapter.makeOverlays(
            for: fitInputs,
            fitMode: fitMode,
            zeroAtCurrentOrigin: zeroAtCurrentOrigin,
            component: component,
            displayOffsetsByIdentityKey: plan.displayOffsetsByIdentityKey
        )

        let title = _defaultTitle(titleSuffix, device: device)
        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "IV",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.plainTextLabel(
                    for: .current,
                    currentBasis: xCurrentBasis.workbenchCurrentBasis
                ),
                yField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: yQuantity)
            ),
            series: plan.visualSeries,
            seriesOverlays: manifestOverlays,
            seriesReorderable: true
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "IV",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.plotLabel(
                    for: .current,
                    currentBasis: xCurrentBasis.workbenchCurrentBasis
                ),
                yField: WorkbenchPlotDisplayVocabulary.plotLabel(for: yQuantity)
            ),
            series: plan.displaySeries,
            seriesOverlays: displayOverlays,
            seriesReorderable: true
        )
        return StackedIVPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: plan.warnings
        )
    }

    private func _seriesMetadata(
        base: [String: String] = [:],
        tabKey: String,
        seriesRole: String,
        stableSemanticID: String
    ) -> [String: String] {
        WorkbenchSeriesIdentityMetadata.metadata(
            base: base,
            seriesIdentityKey: WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
                workflowID: workflowID,
                tabKey: tabKey,
                seriesRole: seriesRole,
                stableSemanticID: stableSemanticID
            )
        )
    }

}
