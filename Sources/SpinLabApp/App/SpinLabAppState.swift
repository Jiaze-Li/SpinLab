import Foundation
import SwiftUI

enum AppArea: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case workbench = "Workbench"
    case library = "Library"

    var id: String { rawValue }
}

struct PendingImportConfirmationDraft: Equatable {
    static let noProjectOption = "None"

    var batchName: String
    var sampleName: String
    var measurementName: String
    var deviceName: String
    var temperature: String
    var selectedExistingProjectName: String
    var newProjectName: String

    var isValid: Bool {
        !sampleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !measurementName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedProjectName: String? {
        let newName = Self.normalized(newProjectName)
        if let newName {
            return newName
        }

        guard selectedExistingProjectName != Self.noProjectOption else {
            return nil
        }
        return Self.normalized(selectedExistingProjectName)
    }

    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class SpinLabAppState: ObservableObject {
    private struct SubstrateConstraints {
        var treatments: Set<String> = []
        var materials: Set<String> = []
        var orientations: Set<String> = []

        var isEmpty: Bool {
            treatments.isEmpty && materials.isEmpty && orientations.isEmpty
        }
    }

    private struct SubstrateCandidate {
        var raw: String
        var treatment: String?
        var material: String?
        var orientation: String?
    }

    private struct SubstrateResolution {
        var resolvedSubstrate: String?
        var warning: String?
    }

    @Published var selectedArea: AppArea = .inbox
    @Published var pendingImports: [SpinLabDomain.PendingImport] = []
    @Published var archivedRecords: [SpinLabDomain.ArchivedRecord] = []
    @Published var projectCatalog: [SpinLabDomain.Project] = []
    @Published var selectedPendingImportID: UUID?
    @Published var selectedArchivedRecordID: UUID?
    @Published var workbenchResultDraft: String = ""
    @Published private(set) var registryFileName: String?
    @Published private(set) var registrySourceFilePath: String?
    @Published private(set) var registryPrefixEntries: [RegistryPrefixEntry] = []
    @Published var librarySettings: LibrarySettings
    @Published private(set) var libraryRootVerificationPath: String?
    @Published private(set) var libraryRootVerificationMessage: String?
    @Published private(set) var libraryPreview: LibraryPreview?
    @Published private(set) var libraryPreviewMessage: String?
    @Published private(set) var libraryPreviewWarnings: [LibraryWarning] = []
    @Published private(set) var libraryPreviewGroups: [String: [LibraryPreviewBatchGroup]] = [:]
    @Published private(set) var libraryDrawerMessage: String?
    @Published private(set) var libraryDrawerError: String?

    let workflow: SpinLabDomain.WorkflowKind = .amrPhe

    private let persistence: SpinLabPersistence
    private let importPipeline: SpinLabImportPipeline
    private let analysisModule: AnalysisModuleExtension
    private let viewExtension: ViewExtension
    private let managedStorage: SpinLabManagedStorage
    private var sampleRegistry: SampleRegistryIndexing
    private let librarySettingsStore = LibrarySettingsStore()
    private let libraryStore = LibraryStore()
    private let libraryLogger = LibraryLogger()

    init(
        persistence: SpinLabPersistence = LocalJSONPersistence(),
        importPipeline: SpinLabImportPipeline = .amrPhe,
        analysisModule: AnalysisModuleExtension = AMRPHEAnalysisModuleExtension(),
        viewExtension: ViewExtension = AMRPHEViewExtension(),
        managedStorage: SpinLabManagedStorage = SpinLabManagedStorage(),
        sampleRegistry: SampleRegistryIndexing = XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10)
    ) {
        self.persistence = persistence
        self.importPipeline = importPipeline
        self.analysisModule = analysisModule
        self.viewExtension = viewExtension
        self.managedStorage = managedStorage
        self.sampleRegistry = sampleRegistry
        self.librarySettings = librarySettingsStore.load()

        if !self.sampleRegistry.isLoaded, let currentRegistryURL = managedStorage.currentSampleRegistryFileURL() {
            self.sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(currentRegistryURL, previewRowCount: 10)
        }

        load()
        updateRegistryPresentation()
    }

    var selectedPendingImport: SpinLabDomain.PendingImport? {
        pendingImports.first { $0.id == selectedPendingImportID }
    }

    var selectedArchivedRecord: SpinLabDomain.ArchivedRecord? {
        archivedRecords.first { $0.id == selectedArchivedRecordID }
    }

    var workbenchTitle: String {
        if let archived = selectedArchivedRecord {
            return archived.measurement.name
        }

        if let pending = selectedPendingImport {
            return pending.fileName
        }

        return "No measurement selected"
    }

    var defaultViewDisplayName: String {
        viewExtension.displayName
    }

    var knownProjectNames: [String] {
        let archivedNames = archivedRecords.compactMap { $0.project?.name }
        let catalogNames = projectCatalog.map(\.name)
        return Array(Set(archivedNames + catalogNames)).sorted()
    }

    var registryPrefixMap: [String: String] {
        sampleRegistry.prefixToSheet
    }

    var measurementsStoragePath: String {
        managedStorage.measurementsDirectoryURL.path
    }

    private func load() {
        pendingImports = persistence.loadPendingImports()
        archivedRecords = persistence.loadArchivedRecords()
        projectCatalog = persistence.loadProjects()
        selectedPendingImportID = pendingImports.first?.id
        selectedArchivedRecordID = archivedRecords.first?.id
        workbenchResultDraft = selectedArchivedRecord?.latestResult?.summary ?? ""
    }

    func importFiles(from urls: [URL]) {
        let existingOriginalPaths = existingImportedOriginalPaths()
        let managedFiles = managedStorage.importMeasurementFiles(
            from: urls,
            allowedFileExtensions: importPipeline.supportedFileExtensions,
            excludedOriginalFilePaths: existingOriginalPaths
        )
        let imported = importPipeline.importFiles(managedFiles)
        guard !imported.isEmpty else {
            return
        }

        pendingImports.insert(contentsOf: imported, at: 0)
        persistence.savePendingImports(pendingImports)
        selectedPendingImportID = imported.first?.id
        selectedArea = .inbox
    }

    func clearPendingImports() {
        pendingImports = []
        selectedPendingImportID = nil
        persistence.savePendingImports(pendingImports)
    }

    func recomputeAllPendingParsedHints() {
        let fileManager = FileManager.default
        var updated: [SpinLabDomain.PendingImport] = []
        updated.reserveCapacity(pendingImports.count)

        for pending in pendingImports {
            var next = pending
            let parseURL: URL

            if let original = pending.originalFilePath,
               fileManager.fileExists(atPath: original) {
                parseURL = URL(fileURLWithPath: original)
            } else {
                parseURL = URL(fileURLWithPath: pending.fileName)
            }

            next.parsedHints = importPipeline.metadataExtension.parseFilename(from: parseURL)
            updated.append(next)
        }

        pendingImports = updated
        persistence.savePendingImports(pendingImports)
    }

    func loadSampleRegistry(from url: URL) {
        guard let installedURL = managedStorage.installSampleRegistry(from: url) else {
            return
        }

        sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(installedURL, previewRowCount: 10)
        updateLibraryRegistryPaths(installedURL: installedURL, sourceURL: url)
        libraryPreview = nil
        libraryPreviewWarnings = []
        libraryPreviewMessage = nil
        updateRegistryPresentation()
    }

    func loadLibraryPreview() {
        guard let registryPath = librarySettings.registryInternalPath
            ?? managedStorage.currentSampleRegistryFileURL()?.path else {
            libraryPreviewMessage = "No registry available. Load it from Inbox first."
            return
        }
        let parser = LibraryRegistryParser()
        let result = parser.parse(xlsxURL: URL(fileURLWithPath: registryPath), settings: librarySettings)
        let preview = LibraryPreview(index: result.index, warnings: result.warnings)
        libraryPreview = preview
        libraryPreviewWarnings = result.warnings
        libraryPreviewGroups = buildPreviewGroups(from: preview)
        libraryPreviewMessage = "Preview loaded: \(result.index.samples.count) samples"
        libraryLogger.write(result.warnings)
    }

    func createDrawersFromPreview() {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        guard let preview = libraryPreview else {
            libraryDrawerError = "Load the registry preview first."
            return
        }
        guard let rootPath = librarySettings.rootPath else {
            libraryDrawerError = "Select a Library Root first."
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)

        let batchesById = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })
        var created = 0
        for sample in preview.index.samples {
            guard let batch = batchesById[sample.batchId] else {
                continue
            }
            libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
            created += 1
        }

        var index = preview.index
        index.updatedAt = .now
        index.registryInternalPath = librarySettings.registryInternalPath
        index.registrySourcePath = librarySettings.registrySourcePath
        libraryStore.saveIndex(index, to: rootURL)

        libraryDrawerMessage = "Created \(created) sample drawers."
    }

    func createDrawersForSelection(batchId: String?, sampleId: String?) {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        guard let preview = libraryPreview else {
            libraryDrawerError = "Load the registry preview first."
            return
        }
        guard let rootPath = librarySettings.rootPath else {
            libraryDrawerError = "Select a Library Root first."
            return
        }
        guard let batchId else {
            libraryDrawerError = "Select a batch or sample."
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)

        let batchesById = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })
        guard let batch = batchesById[batchId] else {
            libraryDrawerError = "Selected batch not found."
            return
        }

        let samples = preview.index.samples.filter { $0.batchId == batchId }
        let targetSamples: [LibrarySample]
        if let sampleId, let sample = samples.first(where: { $0.id == sampleId }) {
            targetSamples = [sample]
        } else {
            targetSamples = samples
        }

        guard !targetSamples.isEmpty else {
            libraryDrawerError = "No samples found for selection."
            return
        }

        for sample in targetSamples {
            libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
        }

        var index = preview.index
        index.updatedAt = .now
        index.registryInternalPath = librarySettings.registryInternalPath
        index.registrySourcePath = librarySettings.registrySourcePath
        libraryStore.saveIndex(index, to: rootURL)

        libraryDrawerMessage = "Created \(targetSamples.count) sample drawers."
    }

    func updateLibraryRoot(to url: URL) {
        librarySettings.rootPath = url.path
        librarySettingsStore.save(librarySettings)
        libraryRootVerificationPath = nil
        libraryRootVerificationMessage = nil
    }

    func updateAllowedBatchPrefixes(from rawValue: String) {
        let prefixes = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        librarySettings.allowedBatchPrefixes = prefixes
        librarySettingsStore.save(librarySettings)
    }

    func verifyLibraryRoot() {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard let verifyURL = libraryStore.verifyRoot(at: rootURL) else {
            libraryRootVerificationMessage = "Failed to verify Library Root."
            return
        }
        libraryRootVerificationPath = verifyURL.path
        libraryRootVerificationMessage = "Library Root verified."
    }

    func openPendingImportInWorkbench() {
        guard selectedPendingImport != nil else {
            return
        }

        selectedArea = .workbench
    }

    func openArchivedRecordInWorkbench(_ recordID: UUID) {
        guard let record = archivedRecords.first(where: { $0.id == recordID }) else {
            return
        }

        selectedArchivedRecordID = record.id
        workbenchResultDraft = record.latestResult?.summary ?? analysisModule.defaultResultSummary(for: record.measurement)
        selectedArea = .workbench
    }

    func defaultConfirmationDraft(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        let resolvedSampleID = pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)
        var draft = PendingImportConfirmationDraft(
            batchName: pending.parsedHints.batchName ?? resolvedSampleID ?? "",
            sampleName: pending.parsedHints.sampleName ?? "",
            measurementName: pending.parsedHints.measurementName ?? pending.fileName,
            deviceName: pending.parsedHints.deviceName ?? "",
            temperature: pending.parsedHints.temperature ?? "",
            selectedExistingProjectName: suggestedProject(for: pending)?.name ?? PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        if let lookup = registryLookup(for: pending) {
            applyRegistryMetadata(lookup, to: &draft)
        }

        let lookup = registryLookup(for: pending)
        if let sampleID = resolvedSampleID,
           let resolved = resolvedPhysicalSampleName(for: pending, registryLookup: lookup, sampleID: sampleID) {
            draft.sampleName = resolved
        } else if let sampleID = resolvedSampleID,
                  draft.sampleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.sampleName = sampleID
        }

        return draft
    }

    func pendingDisplayDraft(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        defaultConfirmationDraft(for: pending)
    }

    func pendingDisplayWarnings(for pending: SpinLabDomain.PendingImport) -> [String] {
        var warnings = pending.parsedHints.warnings
        if let warning = substrateWarning(for: pending, registryLookup: registryLookup(for: pending)),
           !warnings.contains(warning) {
            warnings.append(warning)
        }
        return warnings
    }

    func pendingDisplayInfoTags(for pending: SpinLabDomain.PendingImport) -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: pending.parsedHints.measurementTags.compactMap { normalized($0) })
        tags.append(contentsOf: pending.parsedHints.substrateTags.compactMap { normalized($0) })

        if let rotation = normalized(pending.parsedHints.rotationHint) {
            tags.append("rotation: \(rotation)")
        }

        var seen: Set<String> = []
        return tags.filter { tag in
            let key = tag.lowercased()
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    func pendingDisplayAutoValues(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        let resolvedSampleID = pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)
        let lookup = registryLookup(for: pending)
        let resolvedSample = resolvedSampleID.flatMap { sampleID in
            resolvedPhysicalSampleName(for: pending, registryLookup: lookup, sampleID: sampleID)
        }

        return PendingImportConfirmationDraft(
            batchName: pending.parsedHints.batchName ?? resolvedSampleID ?? "",
            sampleName: resolvedSample ?? pending.parsedHints.sampleName ?? "",
            measurementName: pending.parsedHints.measurementName ?? pending.fileName,
            deviceName: pending.parsedHints.deviceName ?? "",
            temperature: pending.parsedHints.temperature ?? "",
            selectedExistingProjectName: suggestedProject(for: pending)?.name ?? PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )
    }

    func confirmSelectedPendingImport(with draft: PendingImportConfirmationDraft) {
        confirmSelectedPendingImport(with: draft, editedFileContents: nil)
    }

    func confirmSelectedPendingImport(with draft: PendingImportConfirmationDraft, editedFileContents: String?) {
        guard let pending = selectedPendingImport else {
            return
        }

        if let editedFileContents {
            savePendingImportContents(editedFileContents, for: pending)
        }

        let registryLookup = registryLookup(for: pending)
        let record = makeArchivedRecord(from: pending, draft: draft, registryLookup: registryLookup)
        archivedRecords.insert(record, at: 0)
        pendingImports.removeAll { $0.id == pending.id }

        persistence.saveArchivedRecords(archivedRecords)
        persistence.savePendingImports(pendingImports)

        selectedArchivedRecordID = record.id
        selectedPendingImportID = pendingImports.first?.id
        workbenchResultDraft = record.latestResult?.summary ?? analysisModule.defaultResultSummary(for: record.measurement)
        selectedArea = .library
    }

    func createProject(named name: String) -> String? {
        guard let normalizedName = normalized(name) else {
            return nil
        }

        if let existing = canonicalProject(named: normalizedName) {
            return existing.name
        }

        let project = SpinLabDomain.Project(name: normalizedName)
        projectCatalog.append(project)
        persistence.saveProjects(projectCatalog)
        return project.name
    }

    func pendingImportEditableContents(for pending: SpinLabDomain.PendingImport) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pending.sourceFilePath)) else {
            return nil
        }

        for encoding in [String.Encoding.utf8, .ascii, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        return nil
    }

    func saveWorkbenchResult() {
        guard let selectedArchivedRecordID else {
            return
        }

        guard let recordIndex = archivedRecords.firstIndex(where: { $0.id == selectedArchivedRecordID }) else {
            return
        }

        var record = archivedRecords[recordIndex]
        let existingResultID = record.latestResult?.id ?? UUID()
        record.latestResult = SpinLabDomain.Result(
            id: existingResultID,
            measurementID: record.measurement.id,
            summary: workbenchResultDraft.isEmpty ? analysisModule.defaultResultSummary(for: record.measurement) : workbenchResultDraft,
            rating: record.latestResult?.rating,
            updatedAt: .now
        )

        archivedRecords[recordIndex] = record
        persistence.saveArchivedRecords(archivedRecords)
    }

    func registryLookup(for pending: SpinLabDomain.PendingImport) -> SampleRegistryLookupResult? {
        if let sampleID = pending.parsedHints.sampleIDs.first {
            return sampleRegistry.lookup(sampleID: sampleID)
        }
        return sampleRegistry.lookup(from: pending.fileName)
    }

    func parsedSampleIDFromFilename(for pending: SpinLabDomain.PendingImport) -> String? {
        pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)
    }

    func parsedPrefixFromFilename(for pending: SpinLabDomain.PendingImport) -> String? {
        guard let sampleID = parsedSampleIDFromFilename(for: pending) else {
            return nil
        }
        return SampleIDParser.extractPrefix(fromSampleID: sampleID)
    }

    func resolvedSampleDisplayName(for pending: SpinLabDomain.PendingImport) -> String? {
        let sampleID = pending.parsedHints.batchName
            ?? pending.parsedHints.sampleIDs.first
            ?? sampleRegistry.sampleID(from: pending.fileName)

        return resolvedPhysicalSampleName(
            for: pending,
            registryLookup: registryLookup(for: pending),
            sampleID: sampleID
        ) ?? pending.parsedHints.sampleName
    }

    private func makeArchivedRecord(
        from pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> SpinLabDomain.ArchivedRecord {
        let sampleIDFromFilename = pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)
        let batchName = normalized(draft.batchName)
            ?? sampleIDFromFilename
            ?? metadataValue(in: registryLookup, keys: ["Batch", "BatchID", "Batch Name", "编号"])
        let sampleName = normalized(draft.sampleName)
            ?? resolvedPhysicalSampleName(for: pending, registryLookup: registryLookup, sampleID: batchName ?? sampleIDFromFilename)
            ?? pending.parsedHints.sampleName
            ?? batchName
            ?? "Unassigned Sample"
        let measurementName = normalized(draft.measurementName)
            ?? metadataValue(in: registryLookup, keys: ["Measurement", "MeasurementName", "Measurement Name"])
            ?? pending.parsedHints.measurementName
            ?? pending.fileName
        let deviceName = normalized(draft.deviceName) ?? metadataValue(in: registryLookup, keys: ["Device", "DeviceName", "Device Name"])
        let projectName = draft.resolvedProjectName ?? metadataValue(in: registryLookup, keys: ["Project", "ProjectName", "Project Name"])

        var project = projectName.flatMap { canonicalProject(named: $0) }
        if project == nil, let projectName {
            let createdName = createProject(named: projectName) ?? projectName
            project = canonicalProject(named: createdName)
        }
        var sample = canonicalSample(named: sampleName) ?? SpinLabDomain.Sample(name: sampleName)
        let batch = batchName.flatMap { canonicalBatch(named: $0) } ?? batchName.map { SpinLabDomain.Batch(name: $0) }

        if let projectID = project?.id {
            if !sample.projectIDs.contains(projectID) {
                sample.projectIDs.append(projectID)
            }
            if project?.sampleIDs.contains(sample.id) == false {
                project?.sampleIDs.append(sample.id)
            }
        }

        let device = deviceName.flatMap { name in
            canonicalDevice(named: name, sampleID: sample.id)
                ?? SpinLabDomain.Device(sampleID: sample.id, name: name)
        }

        let measurement = canonicalMeasurement(forSourcePath: pending.sourceFilePath).map { existing in
            var linked = existing
            linked.name = measurementName
            linked.measurementType = .amrPhe
            linked.sampleID = sample.id
            linked.batchID = batch?.id
            linked.deviceID = device?.id
            linked.sourceFilePath = pending.sourceFilePath
            linked.originalFilePath = pending.originalFilePath
            linked.notes = measurementNotes(for: pending, draft: draft, registryLookup: registryLookup)
            if linked.acquiredAt == nil {
                linked.acquiredAt = pending.importedAt
            }
            return linked
        } ?? SpinLabDomain.Measurement(
            name: measurementName,
            measurementType: .amrPhe,
            sampleID: sample.id,
            batchID: batch?.id,
            deviceID: device?.id,
            sourceFilePath: pending.sourceFilePath,
            originalFilePath: pending.originalFilePath,
            acquiredAt: pending.importedAt,
            notes: measurementNotes(for: pending, draft: draft, registryLookup: registryLookup)
        )

        let dataset = canonicalDataset(forSourcePath: pending.sourceFilePath).map { existing in
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
                    name: "Raw AMR/PHE",
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
            summary: analysisModule.defaultResultSummary(for: measurement),
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

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateRegistryPresentation() {
        registrySourceFilePath = sampleRegistry.sourceFilePath
        registryFileName = sampleRegistry.sourceFilePath.map { URL(fileURLWithPath: $0).lastPathComponent }
        registryPrefixEntries = sampleRegistry.prefixToSheet
            .map { RegistryPrefixEntry(prefix: $0.key, sheetName: $0.value) }
            .sorted { $0.prefix < $1.prefix }
    }

    private func updateLibraryRegistryPaths(installedURL: URL, sourceURL: URL?) {
        librarySettings.registryInternalPath = installedURL.path
        librarySettings.registrySourcePath = sourceURL?.path
        librarySettingsStore.save(librarySettings)
    }

    private func buildPreviewGroups(from preview: LibraryPreview) -> [String: [LibraryPreviewBatchGroup]] {
        var groups: [String: [LibraryPreviewBatchGroup]] = [:]
        let samplesByBatch = Dictionary(grouping: preview.index.samples) { $0.batchId }
        for (batchId, samples) in samplesByBatch {
            let prefix = LibrarySort.batchSortKey(batchId).prefix
            let sortedSamples = samples.sorted { $0.substrateDisplay < $1.substrateDisplay }
            let group = LibraryPreviewBatchGroup(batchId: batchId, samples: sortedSamples)
            groups[prefix, default: []].append(group)
        }
        for prefix in groups.keys {
            groups[prefix] = groups[prefix]?.sorted { LibrarySort.compareBatch($0.batchId, $1.batchId) }
        }
        return groups
    }

    private func savePendingImportContents(_ contents: String, for pending: SpinLabDomain.PendingImport) {
        try? contents.write(to: URL(fileURLWithPath: pending.sourceFilePath), atomically: true, encoding: .utf8)
    }

    private func existingImportedOriginalPaths() -> Set<String> {
        var paths: Set<String> = []

        for pending in pendingImports {
            if let original = pending.originalFilePath {
                paths.insert(normalizedPath(original))
            }
        }

        for record in archivedRecords {
            if let original = record.measurement.originalFilePath {
                paths.insert(normalizedPath(original))
            }
        }

        return paths
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func metadataValue(in lookup: SampleRegistryLookupResult?, keys: [String]) -> String? {
        guard let lookup else {
            return nil
        }

        let normalizedKeys = keys.map { normalizeKey($0) }
        for (key, value) in lookup.metadata {
            if normalizedKeys.contains(normalizeKey(key)),
               let cleaned = normalized(value) {
                return cleaned
            }
        }
        return nil
    }

    private func normalizeKey(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func resolvedPhysicalSampleName(
        for pending: SpinLabDomain.PendingImport,
        registryLookup: SampleRegistryLookupResult?,
        sampleID: String?
    ) -> String? {
        let allowsOriginToken = hasStandaloneOriginToken(for: pending)
        if let lookup = registryLookup,
           let resolved = resolvedPhysicalSampleName(
            from: lookup,
            substrateTags: pending.parsedHints.substrateTags,
            allowsOriginToken: allowsOriginToken
           ) {
            return resolved
        }
        return nil
    }

    private func resolvedPhysicalSampleName(
        from lookup: SampleRegistryLookupResult,
        substrateTags: [String],
        allowsOriginToken: Bool = true
    ) -> String? {
        let sampleID = metadataValue(in: lookup, keys: ["Sample", "SampleID", "Sample Id", "sample_id", "编号"]) ?? lookup.sampleID

        let resolution = resolvedSubstrate(
            from: lookup,
            substrateTags: substrateTags,
            allowsOriginToken: allowsOriginToken
        )
        guard let substrate = resolution.resolvedSubstrate else {
            return nil
        }

        return formatPhysicalSampleName(sampleID: sampleID, substrate: substrate)
    }

    private func resolvedSubstrate(
        from lookup: SampleRegistryLookupResult,
        substrateTags: [String],
        allowsOriginToken: Bool
    ) -> SubstrateResolution {
        let normalizedTags = substrateTags.compactMap { normalized($0) }
        guard let substrateValue = metadataValue(in: lookup, keys: ["substrate", "Substrate", "衬底"]) else {
            return SubstrateResolution(
                resolvedSubstrate: nil,
                warning: "Registry substrate is missing for \(lookup.sampleID)."
            )
        }

        let variants = substrateValue
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !variants.isEmpty else {
            return SubstrateResolution(
                resolvedSubstrate: nil,
                warning: "Registry substrate is empty for \(lookup.sampleID)."
            )
        }

        if normalizedTags.isEmpty {
            if variants.count == 1 {
                return SubstrateResolution(resolvedSubstrate: variants[0], warning: nil)
            }
            return SubstrateResolution(resolvedSubstrate: nil, warning: nil)
        }

        let constraints = substrateConstraints(from: normalizedTags, allowsOriginToken: allowsOriginToken)
        let candidates = variants.map(parseSubstrateCandidate)
        let matches = candidates.filter { candidate in
            substrateCandidate(candidate, satisfies: constraints)
        }

        if matches.count == 1 {
            return SubstrateResolution(resolvedSubstrate: matches[0].raw, warning: nil)
        }

        let info = substrateConstraintDescription(constraints)
        if matches.isEmpty {
            return SubstrateResolution(
                resolvedSubstrate: nil,
                warning: "No substrate candidate matches parsed tags for \(lookup.sampleID) (\(info))."
            )
        }

        return SubstrateResolution(
            resolvedSubstrate: nil,
            warning: "Multiple substrate candidates match parsed tags for \(lookup.sampleID) (\(info))."
        )
    }

    private func normalizeSubstrateTag(_ value: String) -> String {
        let normalized = value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
        if normalized == "o" {
            return "origin"
        }
        return normalized
    }

    private func substrateConstraints(from substrateTags: [String], allowsOriginToken: Bool) -> SubstrateConstraints {
        var constraints = SubstrateConstraints()

        for tag in substrateTags {
            let normalized = normalizeSubstrateTag(tag)
            if normalized == "hf" {
                constraints.treatments.insert("hf")
                continue
            }
            if normalized.contains("bake") {
                constraints.treatments.insert("baked")
                continue
            }
            if allowsOriginToken && (normalized == "o" || normalized.contains("origin") || normalized.contains("original")) {
                constraints.treatments.insert("o")
                continue
            }

            if let orientation = extractOrientation(from: normalized) {
                constraints.orientations.insert(orientation)
            }

            if let material = conservativeMaterial(from: normalized) {
                constraints.materials.insert(material.lowercased())
            }
        }

        // If specific processing tags exist, ignore origin to avoid false positives.
        if constraints.treatments.contains("hf") || constraints.treatments.contains("baked") {
            constraints.treatments.remove("o")
        }

        return constraints
    }

    private func parseSubstrateCandidate(_ substrate: String) -> SubstrateCandidate {
        let normalized = normalizeSubstrateTag(substrate)
        var candidate = SubstrateCandidate(raw: substrate, treatment: nil, material: nil, orientation: nil)

        if normalized.contains("hf") {
            candidate.treatment = "hf"
        } else if normalized.contains("bake") {
            candidate.treatment = "baked"
        } else if normalized.contains("origin") || normalized.contains("original") || normalized == "o" {
            candidate.treatment = "o"
        }

        candidate.orientation = extractOrientation(from: normalized)
        candidate.material = conservativeMaterial(from: substrate)?.lowercased()
        return candidate
    }

    private func substrateCandidate(_ candidate: SubstrateCandidate, satisfies constraints: SubstrateConstraints) -> Bool {
        if !constraints.treatments.isEmpty {
            guard let treatment = candidate.treatment, constraints.treatments.contains(treatment) else {
                return false
            }
        }

        if !constraints.materials.isEmpty {
            guard let material = candidate.material, constraints.materials.contains(material) else {
                return false
            }
        }

        if !constraints.orientations.isEmpty {
            guard let orientation = candidate.orientation, constraints.orientations.contains(orientation) else {
                return false
            }
        }

        return true
    }

    private func extractOrientation(from normalized: String) -> String? {
        guard let match = normalized.range(of: #"\d{3}"#, options: .regularExpression) else {
            return nil
        }
        return String(normalized[match])
    }

    private func conservativeMaterial(from source: String) -> String? {
        let cleaned = source.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawTokens = cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        let materialCandidates = rawTokens.compactMap { token -> String? in
            if token == "hf" || token == "baked" || token == "bake" || token == "origin" || token == "original" || token == "o" {
                return nil
            }
            if token.range(of: #"^\d+$"#, options: .regularExpression) != nil {
                return nil
            }
            if token.range(of: #"^[a-z]{2,}\d{3}$"#, options: .regularExpression) != nil {
                let letters = token.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
                return letters.count >= 2 ? letters : nil
            }
            if token.range(of: #"^[a-z]{2,}$"#, options: .regularExpression) != nil {
                return token
            }
            return nil
        }

        let unique = Array(Set(materialCandidates))
        guard unique.count == 1, let material = unique.first else {
            return nil
        }

        return material.uppercased()
    }

    private func substrateConstraintDescription(_ constraints: SubstrateConstraints) -> String {
        var parts: [String] = []
        if !constraints.treatments.isEmpty {
            parts.append("treatment=\(constraints.treatments.sorted().joined(separator: "/"))")
        }
        if !constraints.materials.isEmpty {
            parts.append("material=\(constraints.materials.sorted().joined(separator: "/"))")
        }
        if !constraints.orientations.isEmpty {
            parts.append("orientation=\(constraints.orientations.sorted().joined(separator: "/"))")
        }
        return parts.isEmpty ? "no substrate constraints" : parts.joined(separator: ", ")
    }

    private func formatPhysicalSampleName(sampleID: String, substrate: String) -> String {
        let normalized = normalizeSubstrateTag(substrate)

        let modifier: String? = {
            if normalized.contains("hf") {
                return "HF"
            }
            if normalized.contains("bake") || normalized.contains("baked") {
                return "baked"
            }
            if normalized.contains("origin") || normalized.contains("original") {
                return "o"
            }
            return nil
        }()

        let orientation = formattedSubstrateOrientation(from: substrate)

        return ([sampleID, modifier, orientation].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .joined(separator: " ")
    }

    private func formattedSubstrateOrientation(from substrate: String) -> String? {
        let upper = substrate.uppercased()
        let patterns: [(String, String)] = [
            (#"(STO)[^0-9]*(111)"#, "STO"),
            (#"(STO)[^0-9]*(001)"#, "STO"),
            (#"(NGO)[^0-9]*(110)"#, "NGO"),
            (#"(MAO)[^0-9]*(100)"#, "MAO")
        ]

        for (pattern, label) in patterns {
            if let match = upper.range(of: pattern, options: .regularExpression) {
                let fragment = String(upper[match])
                if let orientation = fragment.range(of: #"(111|001|110|100)"#, options: .regularExpression) {
                    return "\(label)(\(fragment[orientation]))"
                }
            }
        }

        if upper.contains("STO") {
            return "STO"
        }
        if upper.contains("NGO") {
            return "NGO"
        }
        if upper.contains("MAO") {
            return "MAO"
        }

        return substrate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func measurementNotes(
        for pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> String {
        var lines: [String] = []

        let temp = draft.temperature.trimmingCharacters(in: .whitespacesAndNewlines)
        if !temp.isEmpty {
            lines.append("Measurement temperature: \(temp)")
        }

        let growthTemperature = pending.parsedHints.growthTemperature
            ?? metadataValue(in: registryLookup, keys: ["生长温度", "Growth Temperature", "growthtemperature"])
        if let growthTemperature {
            lines.append("Growth temperature: \(growthTemperature)")
        }

        if let rotationHint = pending.parsedHints.rotationHint {
            lines.append("Rotation hint: \(rotationHint)")
        }

        if let warning = substrateWarning(for: pending, registryLookup: registryLookup) {
            lines.append("Substrate warning: \(warning)")
        }

        return lines.joined(separator: "\n")
    }

    private func substrateWarning(
        for pending: SpinLabDomain.PendingImport,
        registryLookup: SampleRegistryLookupResult?
    ) -> String? {
        guard let lookup = registryLookup else {
            return nil
        }
        let resolution = resolvedSubstrate(
            from: lookup,
            substrateTags: pending.parsedHints.substrateTags,
            allowsOriginToken: hasStandaloneOriginToken(for: pending)
        )
        return resolution.warning
    }

    private func hasStandaloneOriginToken(for pending: SpinLabDomain.PendingImport) -> Bool {
        let separators = CharacterSet(charactersIn: "_- ()")
        var texts: [String] = [pending.fileName]

        if let originalPath = pending.originalFilePath {
            let url = URL(fileURLWithPath: originalPath)
            texts.append(url.deletingPathExtension().lastPathComponent)
            texts.append(url.deletingLastPathComponent().lastPathComponent)
            texts.append(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)
        }

        for text in texts {
            let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
            if tokens.contains(where: { token in
                let lower = token.lowercased()
                return lower == "o" || lower.contains("origin") || lower.contains("original")
            }) {
                return true
            }
        }

        return false
    }

    private func applyRegistryMetadata(_ lookup: SampleRegistryLookupResult, to draft: inout PendingImportConfirmationDraft) {
        if draft.batchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let batch = metadataValue(in: lookup, keys: ["Batch", "BatchID", "Batch Name", "编号"]) {
            draft.batchName = batch
        }
        if draft.measurementName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let measurement = metadataValue(in: lookup, keys: ["Measurement", "MeasurementName", "Measurement Name"]) {
            draft.measurementName = measurement
        }
        if draft.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let device = metadataValue(in: lookup, keys: ["Device", "DeviceName", "Device Name"]) {
            draft.deviceName = device
        }

        guard
            draft.resolvedProjectName == nil,
            let projectName = metadataValue(in: lookup, keys: ["Project", "ProjectName", "Project Name"])
        else {
            return
        }

        if knownProjectNames.contains(where: { namesEqual($0, projectName) }) {
            draft.selectedExistingProjectName = knownProjectNames.first(where: { namesEqual($0, projectName) }) ?? PendingImportConfirmationDraft.noProjectOption
            draft.newProjectName = ""
        } else {
            draft.selectedExistingProjectName = PendingImportConfirmationDraft.noProjectOption
            draft.newProjectName = projectName
        }
    }

    private func namesEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func canonicalProject(named name: String) -> SpinLabDomain.Project? {
        archivedRecords.compactMap { $0.project }.first { namesEqual($0.name, name) }
            ?? projectCatalog.first { namesEqual($0.name, name) }
    }

    private func canonicalBatch(named name: String) -> SpinLabDomain.Batch? {
        archivedRecords.compactMap { $0.batch }.first { namesEqual($0.name, name) }
    }

    private func canonicalSample(named name: String) -> SpinLabDomain.Sample? {
        archivedRecords.map(\.sample).first { namesEqual($0.name, name) }
    }

    private func canonicalDevice(named name: String, sampleID: UUID) -> SpinLabDomain.Device? {
        archivedRecords.compactMap(\.device).first {
            $0.sampleID == sampleID && namesEqual($0.name, name)
        }
    }

    private func canonicalMeasurement(forSourcePath path: String) -> SpinLabDomain.Measurement? {
        archivedRecords.map(\.measurement).first {
            $0.sourceFilePath == path
        }
    }

    private func canonicalDataset(forSourcePath path: String) -> SpinLabDomain.Dataset? {
        archivedRecords.map(\.dataset).first {
            $0.sourceFilePath == path
        }
    }

    private func suggestedProject(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.Project? {
        guard let sampleName = pending.parsedHints.sampleName else {
            return nil
        }

        return archivedRecords.first { $0.sample.name == sampleName }?.project
    }
}
