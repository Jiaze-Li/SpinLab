import Foundation

protocol WorkflowExtension {
    var workflow: SpinLabDomain.WorkflowKind { get }
    var supportedMeasurementTypes: [SpinLabDomain.MeasurementType] { get }
}

protocol MetadataExtension {
    var workflow: SpinLabDomain.WorkflowKind { get }
    func parseFilename(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints
    func defaultConfirmationDraft(
        pending: SpinLabDomain.PendingImport,
        suggestedProjectName: String?,
        registryLookup: SampleRegistryLookupResult?,
        fallbackSampleID: String?
    ) -> PendingImportConfirmationDraft
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

    func defaultConfirmationDraft(
        pending: SpinLabDomain.PendingImport,
        suggestedProjectName: String?,
        registryLookup: SampleRegistryLookupResult?,
        fallbackSampleID: String?
    ) -> PendingImportConfirmationDraft {
        var draft = PendingImportConfirmationDraft(
            batchName: pending.parsedHints.batchName ?? fallbackSampleID ?? "",
            sampleName: pending.parsedHints.sampleName ?? "",
            measurementName: pending.parsedHints.measurementName ?? pending.fileName,
            workflowTag: pending.parsedHints.workflowName ?? "",
            deviceName: pending.parsedHints.deviceName ?? "",
            temperature: pending.parsedHints.temperature ?? "",
            selectedExistingProjectName: suggestedProjectName ?? PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        if let registryLookup {
            applyRegistryMetadata(registryLookup, to: &draft)
        }

        if let sampleID = fallbackSampleID,
           draft.sampleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.sampleName = sampleID
        }

        return draft
    }

    private func applyRegistryMetadata(_ lookup: SampleRegistryLookupResult, to draft: inout PendingImportConfirmationDraft) {
        draft.batchName = firstNonEmpty(
            draft.batchName,
            metadataValue(in: lookup, keys: ["Batch", "BatchID", "Batch Name", "编号"])
        )
        draft.sampleName = firstNonEmpty(
            draft.sampleName,
            metadataValue(in: lookup, keys: ["Sample", "SampleID", "Sample Name", "样品"])
        )
        draft.measurementName = firstNonEmpty(
            draft.measurementName,
            metadataValue(in: lookup, keys: ["Measurement", "MeasurementName", "Measurement Name"])
        )
        draft.deviceName = firstNonEmpty(
            draft.deviceName,
            metadataValue(in: lookup, keys: ["Device", "DeviceName", "Device Name"])
        )
        draft.temperature = firstNonEmpty(
            draft.temperature,
            metadataValue(in: lookup, keys: ["Temperature", "Temp", "T"])
        )
    }

    private func firstNonEmpty(_ candidates: String?...) -> String {
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private func metadataValue(in lookup: SampleRegistryLookupResult, keys: [String]) -> String? {
        for key in keys {
            for (existingKey, value) in lookup.metadata where existingKey.caseInsensitiveCompare(key) == .orderedSame {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
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

struct DummyWorkflowExtension: WorkflowExtension {
    let workflow: SpinLabDomain.WorkflowKind = .dummy
    let supportedMeasurementTypes: [SpinLabDomain.MeasurementType] = [.dummy]
}

struct DummyMetadataExtension: MetadataExtension {
    let workflow: SpinLabDomain.WorkflowKind = .dummy

    func parseFilename(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints {
        SpinLabDomain.ParsedFilenameHints(
            measurementName: "Dummy: \(fileURL.deletingPathExtension().lastPathComponent)",
            workflowName: "Dummy",
            warnings: ["Dummy workflow parser active."]
        )
    }

    func defaultConfirmationDraft(
        pending: SpinLabDomain.PendingImport,
        suggestedProjectName: String?,
        registryLookup: SampleRegistryLookupResult?,
        fallbackSampleID: String?
    ) -> PendingImportConfirmationDraft {
        PendingImportConfirmationDraft(
            batchName: pending.parsedHints.batchName ?? fallbackSampleID ?? "DUMMY-BATCH",
            sampleName: pending.parsedHints.sampleName ?? fallbackSampleID ?? "DUMMY-SAMPLE",
            measurementName: pending.parsedHints.measurementName ?? "Dummy: \(pending.fileName)",
            workflowTag: "Dummy",
            deviceName: pending.parsedHints.deviceName ?? "Dummy Device",
            temperature: pending.parsedHints.temperature ?? "N/A",
            selectedExistingProjectName: suggestedProjectName ?? PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )
    }
}

struct DummyAnalysisModuleExtension: AnalysisModuleExtension {
    let workflow: SpinLabDomain.WorkflowKind = .dummy

    func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String {
        "Dummy workflow result for \(measurement.name)"
    }
}

struct DummyViewExtension: ViewExtension {
    let workflow: SpinLabDomain.WorkflowKind = .dummy
    let displayName: String = "Dummy Workflow Preview View"
}
