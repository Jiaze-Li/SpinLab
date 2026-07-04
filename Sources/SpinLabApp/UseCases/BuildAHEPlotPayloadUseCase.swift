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
    /// display unit can always be freshly recomputed here without ambiguity. Extraction
    /// (`ExtractAHEMetricsUseCase`, persisted "Hc"/"R_AHE" metrics) reads the *ingestion* series
    /// directly and is untouched by this display-only re-scaling.
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
        hiddenSeriesKeys: [String] = []
    ) -> AHEPlotPayloads {
        let fieldUnit = WorkbenchMagneticFieldDisplayPolicy.preferredUnit(
            canonicalTeslaValues: ingestion.series.flatMap(\.x)
        )

        let displaySeries: [WorkbenchPlotSeries] = fieldUnit == .tesla
            ? ingestion.series
            : ingestion.series.map { series in
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
                stackingPolicy: .none
            )
        )

        let axisMapping = WorkbenchAxisMapping(
            xField: WorkbenchPlotDisplayVocabulary.magneticFieldLabel(
                for: .externalMagneticField,
                context: .manifestPlainText,
                unit: fieldUnit
            ),
            yField: AHEAxisDetector.displayYField
        )

        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: axisMapping,
            series: plan.visualSeries,
            styleParams: styleParams,
            seriesReorderable: true
        )

        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: axisMapping,
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
