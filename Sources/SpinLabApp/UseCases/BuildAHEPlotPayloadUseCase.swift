import Foundation

struct BuildAHEPlotPayloadUseCase {

    func execute(
        ingestion: AHEIngestionResult,
        workflowID: String = "AHE",
        workflowDisplayName: String = "AHE",
        title: String,
        styleParams: [String: String] = [:]
    ) -> WorkbenchPlotPayload {
        return WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: AHEAxisDetector.displayXField,
                yField: AHEAxisDetector.displayYField
            ),
            series: ingestion.series,
            styleParams: styleParams
        )
    }
}
