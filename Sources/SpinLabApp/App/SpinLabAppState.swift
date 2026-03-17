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

    let workflow: SpinLabDomain.WorkflowKind = .amrPhe

    private let persistence: SpinLabPersistence
    private let importPipeline: SpinLabImportPipeline
    private let analysisModule: AnalysisModuleExtension
    private let viewExtension: ViewExtension
    private let managedStorage: SpinLabManagedStorage
    private var sampleRegistry: SampleRegistryIndexing

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

    func loadSampleRegistry(from url: URL) {
        guard let installedURL = managedStorage.installSampleRegistry(from: url) else {
            return
        }

        sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(installedURL, previewRowCount: 10)
        updateRegistryPresentation()
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

        if let sampleID = resolvedSampleID,
           draft.sampleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.sampleName = resolvedPhysicalSampleName(for: pending, registryLookup: registryLookup(for: pending), sampleID: sampleID) ?? sampleID
        }

        return draft
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
        if let lookup = registryLookup,
           let resolved = resolvedPhysicalSampleName(from: lookup, substrateTags: pending.parsedHints.substrateTags) {
            return resolved
        }

        guard let sampleID else {
            return nil
        }

        if pending.parsedHints.substrateTags.isEmpty {
            return sampleID
        }

        return formatPhysicalSampleName(
            sampleID: sampleID,
            substrate: pending.parsedHints.substrateTags.joined(separator: " ")
        )
    }

    private func resolvedPhysicalSampleName(
        from lookup: SampleRegistryLookupResult,
        substrateTags: [String]
    ) -> String? {
        let sampleID = metadataValue(in: lookup, keys: ["Sample", "SampleID", "Sample Id", "sample_id", "编号"]) ?? lookup.sampleID

        guard let substrate = resolvedSubstrate(from: lookup, substrateTags: substrateTags) else {
            return sampleID
        }

        return formatPhysicalSampleName(sampleID: sampleID, substrate: substrate)
    }

    private func resolvedSubstrate(from lookup: SampleRegistryLookupResult, substrateTags: [String]) -> String? {
        guard let substrateValue = metadataValue(in: lookup, keys: ["substrate", "Substrate", "衬底"]) else {
            return nil
        }

        let variants = substrateValue
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !variants.isEmpty else {
            return substrateValue
        }

        if variants.count == 1 {
            return variants[0]
        }

        let normalizedTags = substrateTags.map(normalizeSubstrateTag)
        let wantsHF = normalizedTags.contains("hf")
        let wantsBaked = normalizedTags.contains("baked")
        let wantsOrigin = normalizedTags.isEmpty || normalizedTags.contains("origin")
        let wants111 = normalizedTags.contains("sto111") || normalizedTags.contains("111")
        let wants001 = normalizedTags.contains("sto001") || normalizedTags.contains("001")

        func matches(_ variant: String, contains needle: String) -> Bool {
            normalizeSubstrateTag(variant).contains(needle)
        }

        if wantsHF,
           let match = variants.first(where: { matches($0, contains: "hf") && (!wants111 || matches($0, contains: "111")) && (!wants001 || matches($0, contains: "001")) }) {
            return match
        }

        if wantsBaked,
           let match = variants.first(where: { matches($0, contains: "bake") || matches($0, contains: "baked") }) {
            return match
        }

        if wantsOrigin,
           let match = variants.first(where: { matches($0, contains: "origin") || matches($0, contains: "original") }) {
            return match
        }

        if wants111, let match = variants.first(where: { matches($0, contains: "111") }) {
            return match
        }

        if wants001, let match = variants.first(where: { matches($0, contains: "001") }) {
            return match
        }

        return variants.first
    }

    private func normalizeSubstrateTag(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
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

        return lines.joined(separator: "\n")
    }

    private func applyRegistryMetadata(_ lookup: SampleRegistryLookupResult, to draft: inout PendingImportConfirmationDraft) {
        if draft.batchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let batch = metadataValue(in: lookup, keys: ["Batch", "BatchID", "Batch Name", "编号"]) {
            draft.batchName = batch
        }
        if draft.sampleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let sample = resolvedPhysicalSampleName(from: lookup, substrateTags: []) {
            draft.sampleName = sample
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
