import Foundation

protocol WorkflowExtension {
    var workflow: SpinLabDomain.WorkflowKind { get }
    var supportedMeasurementTypes: [SpinLabDomain.MeasurementType] { get }
}

protocol MetadataExtension {
    var workflow: SpinLabDomain.WorkflowKind { get }
    func parseFilename(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints
}

protocol AnalysisModuleExtension {
    var workflow: SpinLabDomain.WorkflowKind { get }
    func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String
}

protocol ViewExtension {
    var workflow: SpinLabDomain.WorkflowKind { get }
    var displayName: String { get }
}

struct AMRPHEWorkflowExtension: WorkflowExtension {
    let workflow: SpinLabDomain.WorkflowKind = .amrPhe
    let supportedMeasurementTypes: [SpinLabDomain.MeasurementType] = [.amrPhe]
}

struct AMRPHEMetadataExtension: MetadataExtension {
    let workflow: SpinLabDomain.WorkflowKind = .amrPhe

    func parseFilename(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints {
        let loadResult = RuleLoader.shared.loadCached()
        let parser = FilenameRuleParser(ruleSet: loadResult.ruleSet)
        return parser.parse(from: fileURL)
    }
}

struct AMRPHEAnalysisModuleExtension: AnalysisModuleExtension {
    let workflow: SpinLabDomain.WorkflowKind = .amrPhe

    func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String {
        "AMR/PHE result placeholder for \(measurement.name)"
    }
}

struct AMRPHEViewExtension: ViewExtension {
    let workflow: SpinLabDomain.WorkflowKind = .amrPhe
    let displayName: String = "Default AMR/PHE Plot View"
}
