import Foundation

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
        let fieldUnit = WorkbenchMagneticFieldDisplayPolicy.preferredUnit(
            canonicalTeslaValues: ingestion.series.flatMap(\.x)
        )
        let displaySeries: [WorkbenchPlotSeries] = fieldUnit == .tesla
            ? ingestion.series
            : ingestion.series.map { series in
                var converted = series
                converted.x = series.x.map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .tesla, to: fieldUnit) }
                return converted
            }
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .externalMagneticField, context: .manifestPlainText, unit: fieldUnit),
                yField: AHEAxisDetector.displayYField
            ),
            series: displaySeries,
            styleParams: styleParams
        )
    }
}
