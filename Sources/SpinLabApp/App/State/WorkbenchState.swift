import Foundation

struct WorkbenchState {
    func resolvedSummary(
        for measurement: SpinLabDomain.Measurement,
        draftSummary: String,
        analysisModule: AnalysisModuleExtension
    ) -> String {
        draftSummary.isEmpty ? analysisModule.defaultResultSummary(for: measurement) : draftSummary
    }
}
