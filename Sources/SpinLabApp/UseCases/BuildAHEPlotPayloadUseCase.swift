import Foundation

struct BuildAHEPlotPayloadUseCase {

    func execute(
        ingestion: AHEIngestionResult,
        workflowID: String = "AHE",
        workflowDisplayName: String = "AHE",
        title: String,
        axisMappingOverride: WorkbenchAxisMapping? = nil,
        styleParams: [String: String] = [:]
    ) -> WorkbenchPlotPayload {
        let axisMapping = axisMappingOverride ?? ingestion.defaultAxisMapping
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: axisMapping,
            series: ingestion.series,
            styleParams: styleParams
        )
    }
}
