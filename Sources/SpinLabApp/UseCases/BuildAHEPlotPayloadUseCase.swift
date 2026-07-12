import Foundation

struct AHEPlotPayloads: Sendable {
    let manifestPayload: WorkbenchPlotPayload
    let displayPayload: WorkbenchPlotPayload
    let warnings: [String]
}

struct BuildAHEPlotPayloadUseCase {

    /// `ingestion.series.x` is always canonical Tesla (see `IngestAHESelectionsUseCase`) — this
    /// is the invariant that keeps pack restore safe across this migration: old and new packs'
    /// persisted `AHEIngestionResult` both store Tesla-scale x values, so the magnitude-based
    /// display unit can always be freshly recomputed here without ambiguity.
    ///
    /// Ordinary-Hall linear background correction (`AHEBackgroundCorrectionUseCase`) runs first,
    /// before unit conversion and stacking/gap — both of the latter remain purely display-only
    /// re-scalings of the corrected series. Extraction (`ExtractAHEMetricsUseCase`, called by
    /// `AHEWorkspaceStore` with the same corrected series built here) reads the corrected,
    /// non-stacked series, so the persisted "Hc"/"R_AHE" metrics are derived from the
    /// background-corrected signal and are unaffected by unit choice or stack/gap offsets.
    func execute(
        ingestion: AHEIngestionResult,
        workflowID: String = "AHE",
        workflowDisplayName: String = "AHE",
        title: String,
        styleParams: [String: String] = [:]
    ) -> WorkbenchPlotPayload {
        executePayloads(
            ingestion: ingestion,
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            styleParams: styleParams
        ).manifestPayload
    }

    func executePayloads(
        ingestion: AHEIngestionResult,
        workflowID: String = "AHE",
        workflowDisplayName: String = "AHE",
        title: String,
        styleParams: [String: String] = [:],
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = [],
        stackOffsetMultiplier: Double = 0.0,
        minGapFraction: Double = 0.15
    ) -> AHEPlotPayloads {
        let fieldUnit = WorkbenchMagneticFieldDisplayPolicy.preferredUnit(
            canonicalTeslaValues: ingestion.series.flatMap(\.x)
        )

        // Ordinary-Hall linear background correction must run before any display-only
        // transform (unit conversion, stacking/gap) — see AHEBackgroundCorrectionUseCase.
        let correctedSeries = AHEBackgroundCorrectionUseCase().correctedSeries(ingestion.series)

        let displaySeries: [WorkbenchPlotSeries] = fieldUnit == .tesla
            ? correctedSeries
            : correctedSeries.map { series in
                var converted = series
                converted.x = series.x.map {
                    WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: fieldUnit)
                }
                return converted
            }

        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: displaySeries,
                visualSeriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys,
                stackingPolicy: .orderEnforcingVertical(
                    multiplier: stackOffsetMultiplier,
                    minGapFraction: minGapFraction
                )
            )
        )

        // Post-correction, the plotted quantity is the anomalous Hall signal R_AHE, not raw
        // R_H — same physical-quantity family as 3ω's R_AHE^{1ω}/R_AHE^{3ω}
        // (WorkbenchPlotDisplayVocabulary.raheCombined). Manifest gets plain text; the
        // rendered chart axis gets the math-markup label so it renders with a subscript,
        // mirroring the 3ω RAHE-vs-Device tab.
        let manifestAxisMapping = WorkbenchAxisMapping(
            xField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .externalMagneticField, unit: fieldUnit),
            yField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .raheCombined)
        )
        let displayAxisMapping = WorkbenchAxisMapping(
            xField: WorkbenchPlotDisplayVocabulary.plotLabel(for: .externalMagneticField, unit: fieldUnit),
            yField: WorkbenchPlotDisplayVocabulary.plotLabel(for: .raheCombined)
        )

        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: manifestAxisMapping,
            series: plan.visualSeries,
            styleParams: styleParams,
            seriesReorderable: true
        )

        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: displayAxisMapping,
            series: plan.displaySeries,
            styleParams: styleParams,
            seriesReorderable: true
        )

        return AHEPlotPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: plan.warnings
        )
    }
}
