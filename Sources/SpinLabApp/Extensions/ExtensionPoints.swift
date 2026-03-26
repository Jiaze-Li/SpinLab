import Foundation

struct ArchivedRecordBuildContext {
    let pending: SpinLabDomain.PendingImport
    let draft: PendingImportConfirmationDraft
    let registryLookup: SampleRegistryLookupResult?
    let normalized: (String?) -> String?
    let metadataValue: (SampleRegistryLookupResult?, [String]) -> String?
    let canonicalProject: (String) -> SpinLabDomain.Project?
    let createProject: (String) -> String?
    let canonicalBatch: (String) -> SpinLabDomain.Batch?
    let canonicalSample: (String) -> SpinLabDomain.Sample?
    let canonicalDevice: (String, UUID) -> SpinLabDomain.Device?
    let canonicalMeasurement: (String) -> SpinLabDomain.Measurement?
    let canonicalDataset: (String) -> SpinLabDomain.Dataset?
    let measurementNotes: (SpinLabDomain.PendingImport, PendingImportConfirmationDraft, SampleRegistryLookupResult?) -> String?
    let defaultResultSummary: (SpinLabDomain.Measurement) -> String
}

protocol WorkflowExtension {
    var workflow: SpinLabDomain.WorkflowKind { get }
    var supportedMeasurementTypes: [SpinLabDomain.MeasurementType] { get }
    func createArchivedRecord(context: ArchivedRecordBuildContext) -> SpinLabDomain.ArchivedRecord
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

    func createArchivedRecord(context: ArchivedRecordBuildContext) -> SpinLabDomain.ArchivedRecord {
        buildArchivedRecord(context: context, measurementType: .amrPhe, rawSeriesName: "Raw AMR/PHE")
    }
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

    func createArchivedRecord(context: ArchivedRecordBuildContext) -> SpinLabDomain.ArchivedRecord {
        buildArchivedRecord(context: context, measurementType: .dummy, rawSeriesName: "Raw Dummy")
    }
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

private func buildArchivedRecord(
    context: ArchivedRecordBuildContext,
    measurementType: SpinLabDomain.MeasurementType,
    rawSeriesName: String
) -> SpinLabDomain.ArchivedRecord {
    let pending = context.pending
    let draft = context.draft
    let registryLookup = context.registryLookup

    let sampleIDFromFilename = pending.parsedHints.sampleIDs.first
    let batchName = context.normalized(draft.batchName)
        ?? sampleIDFromFilename
        ?? context.metadataValue(registryLookup, ["Batch", "BatchID", "Batch Name", "编号"])
    let sampleName = context.normalized(draft.sampleName)
        ?? pending.parsedHints.sampleName
        ?? batchName
        ?? "Unassigned Sample"
    let measurementName = context.normalized(draft.measurementName)
        ?? context.metadataValue(registryLookup, ["Measurement", "MeasurementName", "Measurement Name"])
        ?? pending.parsedHints.measurementName
        ?? pending.fileName
    let deviceName = context.normalized(draft.deviceName)
        ?? context.metadataValue(registryLookup, ["Device", "DeviceName", "Device Name"])
    let projectName = draft.resolvedProjectName
        ?? context.metadataValue(registryLookup, ["Project", "ProjectName", "Project Name"])

    var project = projectName.flatMap { context.canonicalProject($0) }
    if project == nil, let projectName {
        let createdName = context.createProject(projectName) ?? projectName
        project = context.canonicalProject(createdName)
    }
    var sample = context.canonicalSample(sampleName) ?? SpinLabDomain.Sample(name: sampleName)
    let batch = batchName.flatMap { context.canonicalBatch($0) } ?? batchName.map { SpinLabDomain.Batch(name: $0) }

    if let projectID = project?.id {
        if !sample.projectIDs.contains(projectID) {
            sample.projectIDs.append(projectID)
        }
        if project?.sampleIDs.contains(sample.id) == false {
            project?.sampleIDs.append(sample.id)
        }
    }

    let device = deviceName.flatMap { name in
        context.canonicalDevice(name, sample.id)
            ?? SpinLabDomain.Device(sampleID: sample.id, name: name)
    }

    let measurement = context.canonicalMeasurement(pending.sourceFilePath).map { existing in
        var linked = existing
        linked.name = measurementName
        linked.measurementType = measurementType
        linked.sampleID = sample.id
        linked.batchID = batch?.id
        linked.deviceID = device?.id
        linked.sourceFilePath = pending.sourceFilePath
        linked.originalFilePath = pending.originalFilePath
        linked.notes = context.measurementNotes(pending, draft, registryLookup) ?? ""
        if linked.acquiredAt == nil {
            linked.acquiredAt = pending.importedAt
        }
        return linked
    } ?? SpinLabDomain.Measurement(
        name: measurementName,
        measurementType: measurementType,
        sampleID: sample.id,
        batchID: batch?.id,
        deviceID: device?.id,
        sourceFilePath: pending.sourceFilePath,
        originalFilePath: pending.originalFilePath,
        acquiredAt: pending.importedAt,
        notes: context.measurementNotes(pending, draft, registryLookup) ?? ""
    )

    let dataset = context.canonicalDataset(pending.sourceFilePath).map { existing in
        var linked = existing
        linked.measurementID = measurement.id
        linked.sourceFilePath = pending.sourceFilePath
        linked.originalFilePath = pending.originalFilePath
        return linked
    } ?? SpinLabDomain.Dataset(
        measurementID: measurement.id,
        sourceFilePath: pending.sourceFilePath,
        originalFilePath: pending.originalFilePath,
        columns: ["Field", "Rxx", "Rxy"],
        series: [
            SpinLabDomain.PlotSeries(
                name: rawSeriesName,
                points: [
                    SpinLabDomain.PlotPoint(x: -1.0, y: 1.0),
                    SpinLabDomain.PlotPoint(x: 0.0, y: 1.2),
                    SpinLabDomain.PlotPoint(x: 1.0, y: 1.1)
                ]
            )
        ]
    )

    let result = SpinLabDomain.Result(
        measurementID: measurement.id,
        summary: context.defaultResultSummary(measurement),
        rating: nil
    )

    return SpinLabDomain.ArchivedRecord(
        project: project,
        batch: batch,
        sample: sample,
        device: device,
        measurement: measurement,
        dataset: dataset,
        latestResult: result
    )
}
