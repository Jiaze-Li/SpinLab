import Foundation

// MARK: - IVPlotRenderer
//
// Builds WorkbenchPlotPayload for IV workflow tabs.
//
// Tab "1st / I":  1st harmonic selected component vs Current (mA, peak/RMS)
// Tab "2nd / I":  2nd harmonic selected component vs Current (mA, peak/RMS)

// MARK: - Angle resolution (IV-workflow-owned; see IV_ANGLE_DEPENDENCE.md)
//
// Reuses the existing free-text "device" token convention already produced by
// IngestIVSelectionsUseCase (e.g. "45deg") and the shared ThreeOmegaDeviceAngleParser
// — no ingestion/parser change. IVAngleDependence itself never touches sampleMetadata.
extension IVSweep {
    var angleDeg: Double? {
        ThreeOmegaDeviceAngleParser.parseDegrees(sampleMetadata?["device"] ?? "")
    }
}

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

    /// Angle-dependence module state (IV-owned; see IVAngleDependence). When true,
    /// replaces the current tab's V-vs-I^n payload with a_n(Ψ) — see IV_ANGLE_DEPENDENCE.md.
    var angularPlotEnabled: Bool = false

    /// Angular harmonic fit overlay state (IV-owned; see IVAngularFitAdapter). Only
    /// consulted when angularPlotEnabled is true.
    var angularFitMode: AngularFitMode = .none
    var angularFitFold: Int = 1

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
        if angularPlotEnabled {
            return makeAngleDependencePayloads(
                sweeps: sweeps,
                device: device,
                titleSuffix: "1st / I",
                component: ch1Component,
                yValueForSweep: { ch1Component == .x ? $0.ch1X : $0.ch1Y }
            )
        }
        return makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.ivFirstHarmonicVsCurrent,
            titleSuffix: "1st / I",
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
        if angularPlotEnabled {
            return makeAngleDependencePayloads(
                sweeps: sweeps,
                device: device,
                titleSuffix: "2nd / I",
                component: ch2Component,
                yValueForSweep: { ch2Component == .x ? $0.ch2X : $0.ch2Y }
            )
        }
        return makeStackedPayloads(
            sweeps: sweeps,
            device: device,
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.ivSecondHarmonicVsCurrent,
            titleSuffix: "2nd / I",
            component: ch2Component,
            yValueForSweep: { ch2Component == .x ? $0.ch2X : $0.ch2Y }
        )
    }

    // MARK: - Angular plot (IVAngleDependence)

    private func makeAngleDependencePayloads(
        sweeps: [IVSweep],
        device: String,
        titleSuffix: String,
        component: IVSignalComponent,
        yValueForSweep: (IVSweep) -> [Double]
    ) -> StackedIVPayloads? {
        guard !sweeps.isEmpty else { return nil }

        let inputs: [IVAngleDependenceSweepInput] = sweeps.map { sweep in
            IVAngleDependenceSweepInput(
                angleDeg: sweep.angleDeg,
                currentMA: _adjustedCurrent(sweep.current),
                voltageMV: yValueForSweep(sweep).map { $0 * 1000.0 },
                label: sweep.stem
            )
        }
        let result = IVAngleDependenceUseCase().execute(sweeps: inputs, fitMode: fitMode)
        let title = _defaultTitle("\(titleSuffix) \(IVAngleDependenceProjection.titleSuffix)", device: device)

        let manifestSeries = IVAngleDependenceProjection.makeSeries(
            from: result,
            legendLabel: IVAngleDependenceProjection.legendLabel(mode: fitMode, component: component, context: .manifestPlainText)
        )
        let displaySeries = IVAngleDependenceProjection.makeSeries(
            from: result,
            legendLabel: IVAngleDependenceProjection.legendLabel(mode: fitMode, component: component, context: .plotAxis)
        )

        // Additive-only: appends a fit-line overlay anchored to the scatter series above
        // when angularFitMode is .harmonic; leaves manifestSeries/displaySeries, sort
        // order, and legend label untouched. No overlay is appended (byte-for-byte
        // unchanged payload) when angularFitMode is .none or the fit does not succeed.
        let fitOverlay = IVAngularFitAdapter.makeOverlay(
            from: result,
            fitMode: angularFitMode,
            fold: angularFitFold
        )
        let overlays = fitOverlay.map { [$0] } ?? []

        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "IV",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: IVAngleDependenceProjection.xAxisLabel(context: .manifestPlainText),
                yField: IVAngleDependenceProjection.yAxisLabel(mode: fitMode, component: component, context: .manifestPlainText)
            ),
            series: [manifestSeries],
            seriesOverlays: overlays
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "IV",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: IVAngleDependenceProjection.xAxisLabel(context: .plotAxis),
                yField: IVAngleDependenceProjection.yAxisLabel(mode: fitMode, component: component, context: .plotAxis)
            ),
            series: [displaySeries],
            seriesOverlays: overlays
        )
        return StackedIVPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: result.warnings
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
        component: IVSignalComponent,
        yValueForSweep: (IVSweep) -> [Double]
    ) -> StackedIVPayloads? {
        guard !sweeps.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        var projectionsByIdentityKey: [String: IVPowerLawFitAdapter.SeriesProjection] = [:]
        for sweep in sweeps {
            let tempLabel = _tempLabel(sweep.temperatureK)
            let ref = (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? "")
            let stableSemanticID = WorkbenchSeriesIdentityMetadata.stableSemanticID(
                sourceRef: sweep.measurementFilePath,
                sampleID: sweep.id,
                fallback: sweep.stem
            ) ?? sweep.stem
            let projection = IVPowerLawFitAdapter.project(
                currentMA: _adjustedCurrent(sweep.current),
                voltageV: yValueForSweep(sweep),
                fitMode: fitMode,
                zeroAtCurrentOrigin: zeroAtCurrentOrigin,
                component: component
            )
            let metadata = _seriesMetadata(
                base: sweep.sampleMetadata ?? [:],
                tabKey: tabKey,
                seriesRole: "sweep",
                stableSemanticID: stableSemanticID
            )
            series.append(WorkbenchPlotSeries(
                label: tempLabel,
                x: projection.currentTransformed,
                y: projection.voltageMV,
                sourceRef: ref,
                sampleID: sweep.id,
                metadata: metadata
            ))
            if let identityKey = metadata[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey] {
                projectionsByIdentityKey[identityKey] = projection
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

        func makeOverlays(displayOffsets: [String: Double]) -> [WorkbenchPlotSeriesOverlay] {
            plan.visualSeries.compactMap { s in
                guard let key = s.metadata[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey],
                      let projection = projectionsByIdentityKey[key] else { return nil }
                return IVPowerLawFitAdapter.makeOverlay(
                    identityKey: key,
                    projection: projection,
                    displayOffset: displayOffsets[key] ?? 0
                )
            }
        }
        let manifestOverlays = makeOverlays(displayOffsets: [:])
        let displayOverlays = makeOverlays(displayOffsets: plan.displayOffsetsByIdentityKey)

        let title = _defaultTitle(titleSuffix, device: device)
        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "IV",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: IVPowerLawFitAdapter.xAxisLabel(mode: fitMode, basis: xCurrentBasis, context: .manifestPlainText),
                yField: IVPowerLawFitAdapter.yAxisLabel(mode: fitMode, component: component, context: .manifestPlainText)
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
                xField: IVPowerLawFitAdapter.xAxisLabel(mode: fitMode, basis: xCurrentBasis, context: .plotAxis),
                yField: IVPowerLawFitAdapter.yAxisLabel(mode: fitMode, component: component, context: .plotAxis)
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
