import Foundation

private enum RegistryMetadataField: String {
    case batch
    case sample
    case measurement
    case device
    case temperature
    case project
}

private enum RegistryMetadataAliasBook {
    private static let ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared

    private static let fallbackAliases: [RegistryMetadataField: [String]] = [
        .batch: ["Batch", "BatchID", "Batch Name", "编号"],
        .sample: ["Sample", "SampleID", "Sample Name", "样品"],
        .measurement: ["Measurement", "MeasurementName", "Measurement Name"],
        .device: ["Device", "DeviceName", "Device Name"],
        .temperature: ["Temperature", "Temp", "T"],
        .project: ["Project", "ProjectName", "Project Name"]
    ]

    static func aliases(for field: RegistryMetadataField) -> [String] {
        if let configured = ruleProvider.ruleSet().registry?.metadataLookupAliases[field.rawValue],
           !configured.isEmpty {
            return configured
        }
        return fallbackAliases[field] ?? []
    }
}

protocol SpinLabDomainContext {
    func normalizedValue(_ value: String?) -> String?
    func metadataValue(in lookup: SampleRegistryLookupResult?, keys: [String]) -> String?
    func canonicalProject(named name: String) -> SpinLabDomain.Project?
    func createProject(named name: String) -> String?
    func canonicalBatch(named name: String) -> SpinLabDomain.Batch?
    func canonicalSample(named name: String) -> SpinLabDomain.Sample?
    func canonicalDevice(named name: String, sampleID: UUID) -> SpinLabDomain.Device?
    func canonicalMeasurement(forSourcePath path: String) -> SpinLabDomain.Measurement?
    func canonicalDataset(forSourcePath path: String) -> SpinLabDomain.Dataset?
    func measurementNotes(
        for pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> String
    func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String
}

struct ArchivedRecordBuildContext {
    let pending: SpinLabDomain.PendingImport
    let draft: PendingImportConfirmationDraft
    let registryLookup: SampleRegistryLookupResult?
    let domainContext: SpinLabDomainContext
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
    private let ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared

    func parseFilename(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints {
        let parser = FilenameRuleParser(ruleSet: ruleProvider.ruleSet())
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
            workflowID: pending.parsedHints.workflowID ?? "",
            conditionValues: seedConditionValues(from: pending.parsedHints),
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
            metadataValue(in: lookup, keys: RegistryMetadataAliasBook.aliases(for: .batch))
        )
        draft.sampleName = firstNonEmpty(
            draft.sampleName,
            metadataValue(in: lookup, keys: RegistryMetadataAliasBook.aliases(for: .sample))
        )
        draft.measurementName = firstNonEmpty(
            draft.measurementName,
            metadataValue(in: lookup, keys: RegistryMetadataAliasBook.aliases(for: .measurement))
        )
        let tempKey = ConditionFieldCatalog.temperatureID
        if draft.conditionValues[tempKey, default: ""].isEmpty,
           let v = metadataValue(in: lookup, keys: RegistryMetadataAliasBook.aliases(for: .temperature)) {
            draft.conditionValues[tempKey] = v
        }
        let deviceKey = ConditionFieldCatalog.deviceID
        if draft.conditionValues[deviceKey, default: ""].isEmpty,
           let v = metadataValue(in: lookup, keys: RegistryMetadataAliasBook.aliases(for: .device)) {
            draft.conditionValues[deviceKey] = v
        }
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

// MARK: - 3ω AHE Extension Bundle

struct ThreeOmegaAHEWorkflowExtension: WorkflowExtension {
    let workflow: SpinLabDomain.WorkflowKind = .threeOmegaAHE
    let supportedMeasurementTypes: [SpinLabDomain.MeasurementType] = [.threeOmegaAHE]

    func createArchivedRecord(context: ArchivedRecordBuildContext) -> SpinLabDomain.ArchivedRecord {
        buildArchivedRecord(context: context, measurementType: .threeOmegaAHE, rawSeriesName: "Raw 3w")
    }
}

struct ThreeOmegaAHEMetadataExtension: MetadataExtension {
    let workflow: SpinLabDomain.WorkflowKind = .threeOmegaAHE
    private let ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared

    func parseFilename(from fileURL: URL) -> SpinLabDomain.ParsedFilenameHints {
        // Delegate to the generic filename rule parser (handles .lvm, temperature, current).
        // Workflow ID is injected as "3w" to match WorkflowWorkspaceRegistry routing.
        let parser = FilenameRuleParser(ruleSet: ruleProvider.ruleSet())
        var hints = parser.parse(from: fileURL)
        if hints.workflowID == nil || hints.workflowID?.isEmpty == true {
            hints.workflowID = "3w"
        }
        return hints
    }

    func defaultConfirmationDraft(
        pending: SpinLabDomain.PendingImport,
        suggestedProjectName: String?,
        registryLookup: SampleRegistryLookupResult?,
        fallbackSampleID: String?
    ) -> PendingImportConfirmationDraft {
        PendingImportConfirmationDraft(
            batchName: pending.parsedHints.batchName ?? fallbackSampleID ?? "",
            sampleName: pending.parsedHints.sampleName ?? fallbackSampleID ?? "",
            measurementName: pending.parsedHints.measurementName ?? pending.fileName,
            workflowID: "3w",
            conditionValues: seedConditionValues(from: pending.parsedHints),
            selectedExistingProjectName: suggestedProjectName ?? PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )
    }
}

struct ThreeOmegaAHEAnalysisModuleExtension: AnalysisModuleExtension {
    let workflow: SpinLabDomain.WorkflowKind = .threeOmegaAHE

    func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String {
        "3w result for \(measurement.name)"
    }
}

struct ThreeOmegaAHEViewExtension: ViewExtension {
    let workflow: SpinLabDomain.WorkflowKind = .threeOmegaAHE
    let displayName: String = "3w Workspace"
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
            workflowID: "Dummy",
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
            workflowID: "Dummy",
            conditionValues: seedConditionValues(from: pending.parsedHints),
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

/// Seeds conditionValues from parsed filename hints using well-known field keys.
/// This is a best-effort mapping; the UI filters displayed fields by workflow definition.
private func seedConditionValues(from hints: SpinLabDomain.ParsedFilenameHints) -> [String: String] {
    ConditionFieldCatalog.conditionValues(from: hints)
}

private func buildArchivedRecord(
    context: ArchivedRecordBuildContext,
    measurementType: SpinLabDomain.MeasurementType,
    rawSeriesName: String
) -> SpinLabDomain.ArchivedRecord {
    let pending = context.pending
    let draft = context.draft
    let registryLookup = context.registryLookup
    let domainContext = context.domainContext

    let sampleIDFromFilename = pending.parsedHints.sampleIDs.first
    let batchName = domainContext.normalizedValue(draft.batchName)
        ?? sampleIDFromFilename
        ?? domainContext.metadataValue(in: registryLookup, keys: RegistryMetadataAliasBook.aliases(for: .batch))
    let sampleName = domainContext.normalizedValue(draft.sampleName)
        ?? pending.parsedHints.sampleName
        ?? batchName
        ?? "Unassigned Sample"
    let measurementName = domainContext.normalizedValue(draft.measurementName)
        ?? domainContext.metadataValue(in: registryLookup, keys: RegistryMetadataAliasBook.aliases(for: .measurement))
        ?? pending.parsedHints.measurementName
        ?? pending.fileName
    let deviceName = domainContext.normalizedValue(draft.conditionValues[ConditionFieldCatalog.deviceID])
        ?? domainContext.metadataValue(in: registryLookup, keys: RegistryMetadataAliasBook.aliases(for: .device))
    let projectName = draft.resolvedProjectName
        ?? domainContext.metadataValue(in: registryLookup, keys: RegistryMetadataAliasBook.aliases(for: .project))

    var project = projectName.flatMap { domainContext.canonicalProject(named: $0) }
    var sample = domainContext.canonicalSample(named: sampleName) ?? SpinLabDomain.Sample(name: sampleName)
    let batch = batchName.flatMap { domainContext.canonicalBatch(named: $0) } ?? batchName.map { SpinLabDomain.Batch(name: $0) }

    if let projectID = project?.id {
        if !sample.projectIDs.contains(projectID) {
            sample.projectIDs.append(projectID)
        }
        if project?.sampleIDs.contains(sample.id) == false {
            project?.sampleIDs.append(sample.id)
        }
    }

    let device = deviceName.flatMap { name in
        domainContext.canonicalDevice(named: name, sampleID: sample.id)
            ?? SpinLabDomain.Device(sampleID: sample.id, name: name)
    }

    let measurement = domainContext.canonicalMeasurement(forSourcePath: pending.sourceFilePath).map { existing in
        var linked = existing
        linked.name = measurementName
        linked.measurementType = measurementType
        linked.sampleID = sample.id
        linked.batchID = batch?.id
        linked.deviceID = device?.id
        linked.sourceFilePath = pending.sourceFilePath
        linked.originalFilePath = pending.originalFilePath
        linked.notes = domainContext.measurementNotes(for: pending, draft: draft, registryLookup: registryLookup)
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
        notes: domainContext.measurementNotes(for: pending, draft: draft, registryLookup: registryLookup)
    )

    let dataset = domainContext.canonicalDataset(forSourcePath: pending.sourceFilePath).map { existing in
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
        summary: domainContext.defaultResultSummary(for: measurement),
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
