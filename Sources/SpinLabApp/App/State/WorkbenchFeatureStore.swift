import Foundation
import Observation

/// Routing state for the Workbench area.
///
/// - `registry(selectedID:)`: The top-level configuration panel is shown.
///   `selectedID` tracks which workflow row is highlighted in the registry list
///   for editing purposes only — it does not represent a sub-route navigation.
/// - `workflow(id:)`: The workspace for a specific workflow is shown.
enum WorkbenchRoute: Equatable {
    case registry(selectedID: String?)
    case workflow(id: String)
}

enum WorkbenchSection: String, CaseIterable, Identifiable {
    case workflows
    case measurements

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workflows:
            return "Workflows"
        case .measurements:
            return "Measurements"
        }
    }
}

@MainActor
@Observable
final class WorkbenchFeatureStore {
    private let workbenchState = WorkbenchState()

    var archivedRecords: [SpinLabDomain.ArchivedRecord]
    var projectCatalog: [SpinLabDomain.Project]
    var selectedArchivedRecordID: UUID?
    var workbenchResultDraft: String = ""

    @ObservationIgnored
    private var archivedRecordsProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var projectCatalogProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var bufferedArchivedRecordsProjection: [SpinLabDomain.ArchivedRecord]?
    @ObservationIgnored
    private var bufferedProjectCatalogProjection: [SpinLabDomain.Project]?
    @ObservationIgnored
    private var isArchivedRecordsProjectionDrainScheduled = false
    @ObservationIgnored
    private var isProjectCatalogProjectionDrainScheduled = false

    @ObservationIgnored
    private let libraryRepository: LibraryRepository
    @ObservationIgnored
    private let workflowRegistryStore: WorkflowRegistryStore
    @ObservationIgnored
    private let workflowIDAllocator: any WorkflowIDAllocating
    @ObservationIgnored
    private let conditionRulesHandbookStore: ConditionRulesHandbookStore
    @ObservationIgnored
    var onDefinitionsChanged: (([WorkflowDefinition]) -> Void)?

    var selectedSection: WorkbenchSection = .workflows
    var currentRoute: WorkbenchRoute
    var workflowDefinitions: [WorkflowDefinition]
    var workflowRegistryMessage: String?
    private(set) var conditionDefinitionOptions: [ConditionDefinitionOption]

    var selectedWorkflowID: String? {
        switch currentRoute {
        case .registry(let id): return id ?? workflowDefinitions.first?.id
        case .workflow(let id): return id
        }
    }

    init(
        libraryRepository: LibraryRepository,
        workflowRegistryStore: WorkflowRegistryStore,
        workflowIDAllocator: any WorkflowIDAllocating = DefaultWorkflowIDAllocator(),
        conditionRulesHandbookStore: ConditionRulesHandbookStore = ConditionRulesHandbookStore()
    ) {
        let initialArchivedRecords = libraryRepository.archivedRecords
        let initialProjectCatalog = libraryRepository.projects
        let initialWorkflowDefinitions = workflowRegistryStore.load()
        let initialConditionOptions = conditionRulesHandbookStore.conditionDefinitionOptions()

        self.libraryRepository = libraryRepository
        self.workflowRegistryStore = workflowRegistryStore
        self.workflowIDAllocator = workflowIDAllocator
        self.conditionRulesHandbookStore = conditionRulesHandbookStore
        self.archivedRecords = initialArchivedRecords
        self.projectCatalog = initialProjectCatalog
        self.selectedArchivedRecordID = initialArchivedRecords.first?.id
        self.workflowDefinitions = initialWorkflowDefinitions
        self.conditionDefinitionOptions = initialConditionOptions
        self.currentRoute = .registry(selectedID: initialWorkflowDefinitions.first?.id)
    }

    deinit {
        archivedRecordsProjectionTask?.cancel()
        projectCatalogProjectionTask?.cancel()
    }

    func replaceArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord], persist: Bool = true) -> [SpinLabDomain.ArchivedRecord] {
        let updated = libraryRepository.replaceArchivedRecords(records, persist: persist)
        archivedRecords = updated
        return updated
    }

    func replaceProjectCatalog(_ projects: [SpinLabDomain.Project], persist: Bool = true) -> [SpinLabDomain.Project] {
        let updated = libraryRepository.replaceProjects(projects, persist: persist)
        projectCatalog = updated
        return updated
    }

    func setupProjectionTasks(
        onArchivedRecordsProjected: @escaping @MainActor ([SpinLabDomain.ArchivedRecord]) -> Void,
        onProjectCatalogProjected: @escaping @MainActor ([SpinLabDomain.Project]) -> Void
    ) {
        archivedRecordsProjectionTask?.cancel()
        projectCatalogProjectionTask?.cancel()

        archivedRecordsProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await records in libraryRepository.archivedRecordsStream {
                self.bufferArchivedRecordsProjection(records, onProjected: onArchivedRecordsProjected)
            }
        }

        projectCatalogProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await projects in libraryRepository.projectsStream {
                self.bufferProjectCatalogProjection(projects, onProjected: onProjectCatalogProjected)
            }
        }
    }

    func restoreInteraction(
        selectedArchivedRecordID: UUID?,
        workbenchResultDraft: String
    ) {
        if let selectedArchivedRecordID,
           archivedRecords.contains(where: { $0.id == selectedArchivedRecordID }) {
            self.selectedArchivedRecordID = selectedArchivedRecordID
        }
        self.workbenchResultDraft = workbenchResultDraft
    }

    func captureInteraction(into snapshot: inout SpinLabInteractionSnapshot) {
        snapshot.selectedArchivedRecordID = selectedArchivedRecordID
        snapshot.workbenchResultDraft = workbenchResultDraft
    }

    func selectedArchivedRecord() -> SpinLabDomain.ArchivedRecord? {
        guard let selectedArchivedRecordID else {
            return nil
        }
        return archivedRecords.first { $0.id == selectedArchivedRecordID }
    }

    var selectedWorkflowDefinition: WorkflowDefinition? {
        guard let selectedWorkflowID else {
            return workflowDefinitions.first
        }
        return workflowDefinitions.first { $0.id.caseInsensitiveCompare(selectedWorkflowID) == .orderedSame }
    }

    func addWorkflow() {
        let newID = workflowIDAllocator.nextID(existingIDs: workflowDefinitions.map(\.id))
        let defaultConditionID = conditionDefinitionOptions.first?.id ?? "temperature"
        let definition = WorkflowDefinition(
            id: newID,
            displayName: "New Workflow",
            parentID: nil,
            conditionFields: [
                WorkflowConditionField(
                    definitionID: defaultConditionID
                )
            ]
        )
        workflowRegistryStore.add(definition)
        reloadWorkflowDefinitions(selectedID: definition.id)
        workflowRegistryMessage = nil
    }

    func removeSelectedWorkflow() {
        guard let selectedWorkflowID else {
            return
        }
        if workflowDefinitions.count <= 1 {
            workflowRegistryMessage = "At least one workflow is required."
            return
        }
        workflowRegistryStore.remove(id: selectedWorkflowID)
        reloadWorkflowDefinitions(selectedID: nil)
        workflowRegistryMessage = nil
    }

    func updateSelectedWorkflow(
        id: String,
        displayName: String,
        parentID: String?,
        aliases: [String]? = nil
    ) {
        guard var definition = selectedWorkflowDefinition else {
            return
        }
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedID.isEmpty {
            workflowRegistryMessage = "Workflow ID cannot be empty."
            return
        }
        if workflowDefinitions.contains(where: {
            $0.id.caseInsensitiveCompare(definition.id) != .orderedSame &&
            $0.id.caseInsensitiveCompare(normalizedID) == .orderedSame
        }) {
            workflowRegistryMessage = "Workflow ID must be unique."
            return
        }

        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAliases = aliases ?? definition.aliases
        if let conflict = conflictingAlias(in: normalizedAliases, excludingWorkflowID: definition.id) {
            workflowRegistryMessage = "Alias '\(conflict)' is already used by another workflow."
            return
        }
        definition.id = normalizedID
        definition.displayName = normalizedDisplayName.isEmpty ? normalizedID : normalizedDisplayName
        definition.parentID = normalizeOptional(parentID)
        definition.aliases = normalizedAliases
        workflowRegistryStore.update(definition)
        reloadWorkflowDefinitions(selectedID: definition.id)
        workflowRegistryMessage = nil
    }

    func updateSelectedWorkflowAliasesCSV(_ aliasesCSV: String) {
        guard let definition = selectedWorkflowDefinition else { return }
        let aliases = parseAliasesCSV(aliasesCSV)
        updateSelectedWorkflow(
            id: definition.id,
            displayName: definition.displayName,
            parentID: definition.parentID,
            aliases: aliases
        )
    }

    func selectWorkflow(_ id: String?) {
        guard let id else {
            currentRoute = .registry(selectedID: workflowDefinitions.first?.id)
            return
        }
        let resolvedID = workflowDefinitions.contains(where: { $0.id == id }) ? id : (workflowDefinitions.first?.id ?? id)
        currentRoute = .workflow(id: resolvedID)
    }

    func addConditionFieldToSelectedWorkflow() {
        guard var definition = selectedWorkflowDefinition else {
            return
        }
        let existingIDs = Set(definition.conditionFields.map(\.definitionID))
        guard let nextDefinitionID = conditionDefinitionOptions.first(where: { !existingIDs.contains($0.id) })?.id else {
            workflowRegistryMessage = "All available condition labels are already selected."
            return
        }
        definition.conditionFields.append(
            WorkflowConditionField(
                definitionID: nextDefinitionID
            )
        )
        workflowRegistryStore.update(definition)
        reloadWorkflowDefinitions(selectedID: definition.id)
        workflowRegistryMessage = nil
    }

    func addConditionFieldToSelectedWorkflow(definitionID: String) {
        guard var definition = selectedWorkflowDefinition else {
            return
        }
        let normalizedDefinitionID = definitionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDefinitionID.isEmpty else {
            workflowRegistryMessage = "Condition label cannot be empty."
            return
        }
        guard conditionDefinitionOptions.contains(where: { $0.id == normalizedDefinitionID }) else {
            workflowRegistryMessage = "Unsupported condition label."
            return
        }
        guard !definition.conditionFields.contains(where: {
            $0.definitionID.caseInsensitiveCompare(normalizedDefinitionID) == .orderedSame
        }) else {
            workflowRegistryMessage = "Condition labels must be unique within a workflow."
            return
        }

        definition.conditionFields.append(WorkflowConditionField(definitionID: normalizedDefinitionID))
        workflowRegistryStore.update(definition)
        reloadWorkflowDefinitions(selectedID: definition.id)
        workflowRegistryMessage = nil
    }

    func removeConditionFieldFromSelectedWorkflow(at index: Int) {
        guard var definition = selectedWorkflowDefinition,
              definition.conditionFields.indices.contains(index) else {
            return
        }
        if definition.conditionFields.count <= 1 {
            workflowRegistryMessage = "At least one condition field is required."
            return
        }
        definition.conditionFields.remove(at: index)
        workflowRegistryStore.update(definition)
        reloadWorkflowDefinitions(selectedID: definition.id)
        workflowRegistryMessage = nil
    }

    func moveConditionFieldOnSelectedWorkflow(from sourceIndex: Int, to destinationIndex: Int) {
        guard var definition = selectedWorkflowDefinition else {
            return
        }
        guard definition.conditionFields.indices.contains(sourceIndex),
              definition.conditionFields.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }

        let moved = definition.conditionFields.remove(at: sourceIndex)
        definition.conditionFields.insert(moved, at: destinationIndex)
        workflowRegistryStore.update(definition)
        reloadWorkflowDefinitions(selectedID: definition.id)
        workflowRegistryMessage = nil
    }

    func updateConditionFieldOnSelectedWorkflow(
        at index: Int,
        definitionID: String
    ) {
        guard var definition = selectedWorkflowDefinition,
              definition.conditionFields.indices.contains(index) else {
            return
        }
        let normalizedDefinitionID = definitionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedDefinitionID.isEmpty {
            workflowRegistryMessage = "Condition label cannot be empty."
            return
        }
        if !conditionDefinitionOptions.contains(where: { $0.id == normalizedDefinitionID }) {
            workflowRegistryMessage = "Unsupported condition label."
            return
        }
        if definition.conditionFields.enumerated().contains(where: { currentIndex, field in
            currentIndex != index && field.definitionID.caseInsensitiveCompare(normalizedDefinitionID) == .orderedSame
        }) {
            workflowRegistryMessage = "Condition labels must be unique within a workflow."
            return
        }
        definition.conditionFields[index] = WorkflowConditionField(
            definitionID: normalizedDefinitionID
        )
        workflowRegistryStore.update(definition)
        reloadWorkflowDefinitions(selectedID: definition.id)
        workflowRegistryMessage = nil
    }

    func canonicalProject(named name: String) -> SpinLabDomain.Project? {
        archivedRecords.compactMap { $0.project }.first { namesEqual($0.name, name) }
            ?? projectCatalog.first { namesEqual($0.name, name) }
    }

    func canonicalBatch(named name: String) -> SpinLabDomain.Batch? {
        archivedRecords.compactMap { $0.batch }.first { namesEqual($0.name, name) }
    }

    func canonicalSample(named name: String) -> SpinLabDomain.Sample? {
        archivedRecords.map(\.sample).first { namesEqual($0.name, name) }
    }

    func canonicalDevice(named name: String, sampleID: UUID) -> SpinLabDomain.Device? {
        archivedRecords.compactMap(\.device).first {
            $0.sampleID == sampleID && namesEqual($0.name, name)
        }
    }

    func canonicalMeasurement(forSourcePath path: String) -> SpinLabDomain.Measurement? {
        archivedRecords.map(\.measurement).first {
            $0.sourceFilePath == path
        }
    }

    func conditionLabel(for definitionID: String) -> String {
        conditionDefinitionOptions.first(where: { $0.id == definitionID })?.label ?? definitionID
    }

    func canonicalDataset(forSourcePath path: String) -> SpinLabDomain.Dataset? {
        archivedRecords.map(\.dataset).first {
            $0.sourceFilePath == path
        }
    }

    func suggestedProject(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.Project? {
        guard let sampleName = pending.parsedHints.sampleName else {
            return nil
        }
        return archivedRecords.first { $0.sample.name == sampleName }?.project
    }

    @discardableResult
    func selectArchivedRecord(
        _ recordID: UUID,
        analysisModule: AnalysisModuleExtension
    ) -> Bool {
        guard let record = archivedRecords.first(where: { $0.id == recordID }) else {
            return false
        }
        selectedArchivedRecordID = recordID
        workbenchResultDraft = workbenchState.resolvedSummary(
            for: record.measurement,
            draftSummary: record.latestResult?.summary ?? "",
            analysisModule: analysisModule
        )
        return true
    }

    func saveWorkbenchResult(analysisModule: AnalysisModuleExtension) -> [SpinLabDomain.ArchivedRecord]? {
        guard let selectedArchivedRecordID else {
            return nil
        }
        guard let recordIndex = archivedRecords.firstIndex(where: { $0.id == selectedArchivedRecordID }) else {
            return nil
        }

        var record = archivedRecords[recordIndex]
        let existingResultID = record.latestResult?.id ?? UUID()
        record.latestResult = SpinLabDomain.Result(
            id: existingResultID,
            measurementID: record.measurement.id,
            summary: workbenchState.resolvedSummary(
                for: record.measurement,
                draftSummary: workbenchResultDraft,
                analysisModule: analysisModule
            ),
            rating: record.latestResult?.rating,
            updatedAt: .now
        )

        archivedRecords[recordIndex] = record
        return archivedRecords
    }

    private func namesEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func normalizeOptional(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseAliasesCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func conflictingAlias(in aliases: [String], excludingWorkflowID: String) -> String? {
        let normalizedSet = Set(aliases.map { $0.lowercased() })
        guard !normalizedSet.isEmpty else { return nil }

        for workflow in workflowDefinitions where workflow.id.caseInsensitiveCompare(excludingWorkflowID) != .orderedSame {
            let existingTerms = [workflow.id, workflow.displayName] + workflow.aliases
            for term in existingTerms {
                let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalizedSet.contains(normalized) {
                    return term
                }
            }
        }
        return nil
    }

    private func reloadWorkflowDefinitions(selectedID: String?) {
        conditionDefinitionOptions = conditionRulesHandbookStore.conditionDefinitionOptions()
        workflowDefinitions = workflowRegistryStore.load()
        if let selectedID,
           workflowDefinitions.contains(where: { $0.id.caseInsensitiveCompare(selectedID) == .orderedSame }) {
            let resolvedID = workflowDefinitions.first(where: {
                $0.id.caseInsensitiveCompare(selectedID) == .orderedSame
            })!.id
            switch currentRoute {
            case .registry:
                currentRoute = .registry(selectedID: resolvedID)
            case .workflow:
                currentRoute = .workflow(id: resolvedID)
            }
        } else {
            let fallbackID = workflowDefinitions.first?.id
            currentRoute = .registry(selectedID: fallbackID)
        }
        onDefinitionsChanged?(workflowDefinitions)
    }

    @MainActor
    private func bufferArchivedRecordsProjection(
        _ records: [SpinLabDomain.ArchivedRecord],
        onProjected: @escaping @MainActor ([SpinLabDomain.ArchivedRecord]) -> Void
    ) {
        bufferedArchivedRecordsProjection = records
        scheduleProjectionDrainIfNeeded(
            scheduledFlag: \.isArchivedRecordsProjectionDrainScheduled,
            bufferedValue: \.bufferedArchivedRecordsProjection,
            apply: { [weak self] value in
                guard let self else { return }
                self.archivedRecords = value
                onProjected(value)
            }
        )
    }

    @MainActor
    private func bufferProjectCatalogProjection(
        _ projects: [SpinLabDomain.Project],
        onProjected: @escaping @MainActor ([SpinLabDomain.Project]) -> Void
    ) {
        bufferedProjectCatalogProjection = projects
        scheduleProjectionDrainIfNeeded(
            scheduledFlag: \.isProjectCatalogProjectionDrainScheduled,
            bufferedValue: \.bufferedProjectCatalogProjection,
            apply: { [weak self] value in
                guard let self else { return }
                self.projectCatalog = value
                onProjected(value)
            }
        )
    }

    @MainActor
    private func scheduleProjectionDrainIfNeeded<T>(
        scheduledFlag: ReferenceWritableKeyPath<WorkbenchFeatureStore, Bool>,
        bufferedValue: ReferenceWritableKeyPath<WorkbenchFeatureStore, T?>,
        apply: @escaping @MainActor (T) -> Void
    ) {
        guard !self[keyPath: scheduledFlag] else {
            return
        }
        self[keyPath: scheduledFlag] = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if let value = self[keyPath: bufferedValue] {
                apply(value)
                self[keyPath: bufferedValue] = nil
            }
            self[keyPath: scheduledFlag] = false
        }
    }
}
