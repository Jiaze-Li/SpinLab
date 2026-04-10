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

/// Typed key for per-workflow search state (query text, results, messages).
/// Add new cases as workflows are implemented.
enum WorkbenchWorkflowID: String, CaseIterable, Hashable {
    case ahe
    case threeOmega = "3w"
    case xyRotation = "xy"

    /// Default search prefix pre-filled into the search box.
    var searchPrefix: String {
        switch self {
        case .ahe:        return "ahe "
        case .threeOmega: return "3w "
        case .xyRotation: return "xy "
        }
    }
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
    private struct WorkflowMatchRuleSemantic: Equatable {
        let scope: FilenameRuleSet.MatchScope
        let type: FilenameRuleSet.MatchType
        let matchValues: [String]
        let workflowID: String
    }

    private struct SubstrateTagRuleSemantic: Equatable {
        let scope: FilenameRuleSet.MatchScope
        let type: FilenameRuleSet.MatchType
        let matchValues: [String]
        let value: String
    }

    private struct SubstrateRulesSemantic: Equatable {
        let tokenSeparators: String
        let originStandaloneTokens: [String]
        let originContainsTokens: [String]
        let tagRules: [SubstrateTagRuleSemantic]
    }

    private let workbenchState = WorkbenchState()

    var archivedRecords: [SpinLabDomain.ArchivedRecord]
    var projectCatalog: [SpinLabDomain.Project]
    var selectedArchivedRecordID: UUID?
    var workbenchResultDraft: String = ""
    /// Per-workflow search state, keyed by WorkbenchWorkflowID.
    var searchQueryTexts: [WorkbenchWorkflowID: String] = [:]
    private(set) var searchResults: [WorkbenchWorkflowID: [WorkflowMeasurementSearchHit]] = [:]
    var searchMessages: [WorkbenchWorkflowID: String] = [:]
    private(set) var searchRunning: [WorkbenchWorkflowID: Bool] = [:]

    // MARK: - Per-workflow search persistence

    private static let searchQueryDefaultsPrefix = "workbench.searchQuery."

    private static func restoreSearchQueryTexts() -> [WorkbenchWorkflowID: String] {
        var result: [WorkbenchWorkflowID: String] = [:]
        for wf in WorkbenchWorkflowID.allCases {
            if let saved = UserDefaults.standard.string(forKey: searchQueryDefaultsPrefix + wf.rawValue) {
                result[wf] = saved
            }
        }
        return result
    }

    private static func persistSearchQueryText(_ text: String, for wf: WorkbenchWorkflowID) {
        UserDefaults.standard.set(text, forKey: searchQueryDefaultsPrefix + wf.rawValue)
    }

    // MARK: - Per-workflow search accessors

    func searchQueryText(for wf: WorkbenchWorkflowID) -> String {
        searchQueryTexts[wf] ?? wf.searchPrefix
    }

    func setSearchQueryText(_ text: String, for wf: WorkbenchWorkflowID) {
        searchQueryTexts[wf] = text
        Self.persistSearchQueryText(text, for: wf)
    }

    func searchResultsList(for wf: WorkbenchWorkflowID) -> [WorkflowMeasurementSearchHit] {
        searchResults[wf] ?? []
    }

    func searchMessage(for wf: WorkbenchWorkflowID) -> String? {
        searchMessages[wf]
    }

    func isSearchRunning(for wf: WorkbenchWorkflowID) -> Bool {
        searchRunning[wf] ?? false
    }
    /// AHE-specific workspace state. All plot, selection, and artifact state lives here.
    let aheWorkspace = AHEWorkspaceStore()
    /// 3w workspace state. Independent workflow — parsing, fitting, scaling, 6 plots.
    let threeOmegaWorkspace = ThreeOmegaWorkspaceStore()
    /// In-memory vault for saved analysis packs (shared across workflows).
    let analysisVault = AnalysisVault()
    /// XY Rotation workspace state. Angle-dependent resistance R(φ), dual parser (LVM + DAT).
    let xyRotationWorkspace = XYRotationWorkspaceStore()

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
    private var workflowSearchTask: Task<Void, Never>?

    @ObservationIgnored
    private let libraryRepository: LibraryRepository
    @ObservationIgnored
    private let dataActor: any SpinLabDataActing
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
    private(set) var workflowMatchRules: [WorkflowMatchRuleEntry]
    @ObservationIgnored
    private var persistedWorkflowMatchRulesSemantics: [WorkflowMatchRuleSemantic]
    private(set) var sampleIDPatterns: [String]
    @ObservationIgnored
    private var persistedSampleIDPatterns: [String]
    private(set) var substrateTokenSeparators: String
    private(set) var substrateOriginStandaloneTokens: [String]
    private(set) var substrateOriginContainsTokens: [String]
    private(set) var substrateTagRules: [MatchRuleEntry]
    @ObservationIgnored
    private var persistedSubstrateRulesSemantic: SubstrateRulesSemantic

    var hasUnsavedWorkflowMatchRules: Bool {
        Self.workflowMatchRulesSemantics(workflowMatchRules) != persistedWorkflowMatchRulesSemantics
    }

    var hasUnsavedSampleIDPatterns: Bool {
        sampleIDPatterns != persistedSampleIDPatterns
    }

    var hasUnsavedSubstrateRules: Bool {
        Self.substrateRulesSemantic(
            tokenSeparators: substrateTokenSeparators,
            originStandaloneTokens: substrateOriginStandaloneTokens,
            originContainsTokens: substrateOriginContainsTokens,
            tagRules: substrateTagRules
        ) != persistedSubstrateRulesSemantic
    }

    var selectedWorkflowID: String? {
        switch currentRoute {
        case .registry(let id): return id ?? workflowDefinitions.first?.id
        case .workflow(let id): return id
        }
    }

    init(
        libraryRepository: LibraryRepository,
        dataActor: any SpinLabDataActing = SpinLabDataActor(),
        workflowRegistryStore: WorkflowRegistryStore,
        workflowIDAllocator: any WorkflowIDAllocating = DefaultWorkflowIDAllocator(),
        conditionRulesHandbookStore: ConditionRulesHandbookStore = ConditionRulesHandbookStore()
    ) {
        let initialArchivedRecords = libraryRepository.archivedRecords
        let initialProjectCatalog = libraryRepository.projects
        let initialWorkflowDefinitions = workflowRegistryStore.load()
        let initialConditionOptions = conditionRulesHandbookStore.conditionDefinitionOptions()
        let initialRuleSet = RuleLoader.shared.loadCached().ruleSet

        self.libraryRepository = libraryRepository
        self.dataActor = dataActor
        self.workflowRegistryStore = workflowRegistryStore
        self.workflowIDAllocator = workflowIDAllocator
        self.conditionRulesHandbookStore = conditionRulesHandbookStore
        self.archivedRecords = initialArchivedRecords
        self.projectCatalog = initialProjectCatalog
        self.selectedArchivedRecordID = initialArchivedRecords.first?.id
        self.workflowDefinitions = initialWorkflowDefinitions
        self.conditionDefinitionOptions = initialConditionOptions
        let initialWorkflowMatchRules = Self.canonicalized(
            conditionRulesHandbookStore.loadWorkflowMatchRules(),
            against: initialWorkflowDefinitions
        )
        self.workflowMatchRules = initialWorkflowMatchRules
        self.persistedWorkflowMatchRulesSemantics = Self.workflowMatchRulesSemantics(initialWorkflowMatchRules)
        let initialSampleIDPatterns = conditionRulesHandbookStore.loadSampleIDPatterns()
        self.sampleIDPatterns = initialSampleIDPatterns
        self.persistedSampleIDPatterns = initialSampleIDPatterns
        let initialSubstrateState = Self.makeInitialSubstrateState(
            ruleSet: initialRuleSet,
            separatedPatch: conditionRulesHandbookStore.loadSeparatedSubstrateRules()
        )
        self.substrateTokenSeparators = initialSubstrateState.tokenSeparators
        self.substrateOriginStandaloneTokens = initialSubstrateState.originStandaloneTokens
        self.substrateOriginContainsTokens = initialSubstrateState.originContainsTokens
        self.substrateTagRules = initialSubstrateState.tagRules
        self.persistedSubstrateRulesSemantic = Self.substrateRulesSemantic(
            tokenSeparators: initialSubstrateState.tokenSeparators,
            originStandaloneTokens: initialSubstrateState.originStandaloneTokens,
            originContainsTokens: initialSubstrateState.originContainsTokens,
            tagRules: initialSubstrateState.tagRules
        )
        self.searchQueryTexts = Self.restoreSearchQueryTexts()
        self.currentRoute = .registry(selectedID: initialWorkflowDefinitions.first?.id)
        self.threeOmegaWorkspace.vault = analysisVault
    }

    deinit {
        archivedRecordsProjectionTask?.cancel()
        projectCatalogProjectionTask?.cancel()
        workflowSearchTask?.cancel()
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
        workbenchResultDraft: String,
        threeOmegaGeometryLxx: Double? = nil,
        threeOmegaGeometryLxy: Double? = nil,
        threeOmegaGeometryDNm: Double? = nil,
        threeOmegaV3Method: String? = nil,
        threeOmegaTitleTemplate: String? = nil,
        threeOmegaStackOffsetMultiplier: Double? = nil,
        threeOmegaMinGapFraction: Double? = nil,
        threeOmegaRTSidecarPath: String? = nil,
        threeOmegaFitRanges: [ThreeOmegaFitRange]? = nil,
        threeOmegaPlotLegendPoints: [String: [Double]]? = nil,
        aheTitleTemplate: String? = nil
    ) {
        if let selectedArchivedRecordID,
           archivedRecords.contains(where: { $0.id == selectedArchivedRecordID }) {
            self.selectedArchivedRecordID = selectedArchivedRecordID
        }
        self.workbenchResultDraft = workbenchResultDraft
        if let v = threeOmegaGeometryLxx, v > 0 { threeOmegaWorkspace.geometry.lxx = v }
        if let v = threeOmegaGeometryLxy, v > 0 { threeOmegaWorkspace.geometry.lxy = v }
        if let v = threeOmegaGeometryDNm, v > 0 { threeOmegaWorkspace.geometry.dNm = v }
        if let m = threeOmegaV3Method, let method = ThreeOmegaV3Method(rawValue: m) {
            threeOmegaWorkspace.v3Method = method
        }
        if let t = threeOmegaTitleTemplate { threeOmegaWorkspace.titleTemplate = t }
        if let v = threeOmegaStackOffsetMultiplier { threeOmegaWorkspace.stackOffsetMultiplier = v }
        if let v = threeOmegaMinGapFraction { threeOmegaWorkspace.minGapFraction = v }
        if let p = threeOmegaRTSidecarPath { threeOmegaWorkspace.pendingRTSidecarPath = p }
        if let ranges = threeOmegaFitRanges, !ranges.isEmpty { threeOmegaWorkspace.fitRanges = ranges }
        if let legendMap = threeOmegaPlotLegendPoints {
            for (key, arr) in legendMap where arr.count == 2 {
                if let tab = ThreeOmegaWorkbenchTab.allCases.first(where: { $0.stableKey == key }) {
                    threeOmegaWorkspace.plotLegendPoints[tab] = CGPoint(x: arr[0], y: arr[1])
                }
            }
        }
        if let t = aheTitleTemplate { aheWorkspace.titleTemplate = t }
    }

    func captureInteraction(into snapshot: inout SpinLabInteractionSnapshot) {
        snapshot.selectedArchivedRecordID = selectedArchivedRecordID
        snapshot.workbenchResultDraft = workbenchResultDraft
        let geo = threeOmegaWorkspace.geometry
        snapshot.threeOmegaGeometryLxx = geo.lxx > 0 ? geo.lxx : nil
        snapshot.threeOmegaGeometryLxy = geo.lxy > 0 ? geo.lxy : nil
        snapshot.threeOmegaGeometryDNm = geo.dNm > 0 ? geo.dNm : nil
        snapshot.threeOmegaV3Method = threeOmegaWorkspace.v3Method.rawValue
        snapshot.threeOmegaTitleTemplate = threeOmegaWorkspace.titleTemplate
        snapshot.threeOmegaStackOffsetMultiplier = threeOmegaWorkspace.stackOffsetMultiplier
        snapshot.threeOmegaMinGapFraction = threeOmegaWorkspace.minGapFraction
        snapshot.threeOmegaRTSidecarPath = threeOmegaWorkspace.selectedRTHit?.sidecarPath
            ?? threeOmegaWorkspace.pendingRTSidecarPath
        snapshot.threeOmegaFitRanges = threeOmegaWorkspace.fitRanges
        if !threeOmegaWorkspace.plotLegendPoints.isEmpty {
            var legendMap: [String: [Double]] = [:]
            for (tab, pt) in threeOmegaWorkspace.plotLegendPoints {
                legendMap[tab.stableKey] = [pt.x, pt.y]
            }
            snapshot.threeOmegaPlotLegendPoints = legendMap
        }
        snapshot.aheTitleTemplate = aheWorkspace.titleTemplate
    }

    /// Bridge method: restores search state into WorkbenchFeatureStore when loading a pack.
    func restoreThreeOmegaSearchState(results: [WorkflowMeasurementSearchHit], queryText: String) {
        searchResults[.threeOmega] = results
        setSearchQueryText(queryText, for: .threeOmega)
        searchMessages[.threeOmega] = "Restored from analysis pack (\(results.count) hit(s))."
        searchRunning[.threeOmega] = false
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

    var selectedWorkflowMatchRules: [WorkflowMatchRuleEntry] {
        guard let definition = selectedWorkflowDefinition,
              !definition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let canonicalID = definition.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return workflowMatchRules.filter { entry in
            entry.workflowID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == canonicalID
        }
    }

    func matchRuleValuesCSV(_ id: UUID) -> String {
        guard let entry = workflowMatchRules.first(where: { $0.id == id }) else {
            return ""
        }
        return entry.matchValues.joined(separator: ", ")
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
        do {
            try workflowRegistryStore.add(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
    }

    func removeSelectedWorkflow() {
        guard let selectedWorkflowID else {
            return
        }
        if workflowDefinitions.count <= 1 {
            workflowRegistryMessage = "At least one workflow is required."
            return
        }
        do {
            try workflowRegistryStore.remove(id: selectedWorkflowID)
            reloadWorkflowDefinitions(selectedID: nil)
            removeWorkflowMatchRules(for: selectedWorkflowID)
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
    }

    func updateSelectedWorkflow(
        id: String,
        displayName: String,
        parentID: String?
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
        let originalID = definition.id
        definition.id = normalizedID
        definition.displayName = normalizedDisplayName.isEmpty ? normalizedID : normalizedDisplayName
        definition.parentID = normalizeOptional(parentID)
        do {
            try workflowRegistryStore.update(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            if originalID.caseInsensitiveCompare(definition.id) != .orderedSame {
                migrateWorkflowMatchRules(from: originalID, to: definition.id)
            } else {
                workflowRegistryMessage = nil
            }
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
    }

    func selectWorkflow(_ id: String?) {
        guard let id else {
            currentRoute = .registry(selectedID: workflowDefinitions.first?.id)
            return
        }
        let resolvedID = workflowDefinitions.contains(where: { $0.id == id }) ? id : (workflowDefinitions.first?.id ?? id)
        currentRoute = .workflow(id: resolvedID)
    }

    func addMatchRuleToSelectedWorkflow() {
        guard let selectedWorkflowID else { return }
        let defaultToken = selectedWorkflowID.lowercased()
        workflowMatchRules.append(
            WorkflowMatchRuleEntry(
                scope: .tokens,
                type: .equals,
                matchValues: [defaultToken],
                workflowID: selectedWorkflowID
            )
        )
    }

    func removeMatchRule(_ id: UUID) {
        guard let index = workflowMatchRules.firstIndex(where: { $0.id == id }) else { return }
        workflowMatchRules.remove(at: index)
    }

    func updateMatchRuleScope(_ id: UUID, scope: FilenameRuleSet.MatchScope) {
        guard let index = workflowMatchRules.firstIndex(where: { $0.id == id }) else { return }
        workflowMatchRules[index].scope = scope
    }

    func updateMatchRuleType(_ id: UUID, type: FilenameRuleSet.MatchType) {
        guard let index = workflowMatchRules.firstIndex(where: { $0.id == id }) else { return }
        workflowMatchRules[index].type = type
    }

    func updateMatchRuleValuesCSV(_ id: UUID, csv: String) {
        guard let index = workflowMatchRules.firstIndex(where: { $0.id == id }) else { return }
        workflowMatchRules[index].matchValues = parseCSV(csv)
    }

    func commitMatchRuleValuesCSV(_ id: UUID) {
        guard let entry = workflowMatchRules.first(where: { $0.id == id }) else { return }
        guard !entry.matchValues.isEmpty else {
            workflowRegistryMessage = "Match values cannot be empty in match rules."
            return
        }
        workflowRegistryMessage = nil
    }

    func confirmWorkflowMatchRulesSave() {
        persistWorkflowMatchRules()
    }

    func discardWorkflowMatchRulesEdits() {
        workflowMatchRules = Self.canonicalized(
            conditionRulesHandbookStore.loadWorkflowMatchRules(),
            against: workflowDefinitions
        )
        persistedWorkflowMatchRulesSemantics = Self.workflowMatchRulesSemantics(workflowMatchRules)
        workflowRegistryMessage = nil
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
        do {
            try workflowRegistryStore.update(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
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
        do {
            try workflowRegistryStore.update(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
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
        do {
            try workflowRegistryStore.update(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
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
        do {
            try workflowRegistryStore.update(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
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
        do {
            try workflowRegistryStore.update(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = "Workflow could not be saved: \(error.localizedDescription)"
        }
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

    func runWorkflowMeasurementSearch(workflowID wf: WorkbenchWorkflowID, libraryRootPath: String?) {
        let query = searchQueryText(for: wf).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults[wf] = []
            searchMessages[wf] = "Enter workflow query, for example: AHE PN31 80K"
            searchRunning[wf] = false
            workflowSearchTask?.cancel()
            workflowSearchTask = nil
            if wf == .threeOmega { _clearThreeOmegaTitleContext() }
            return
        }
        guard let libraryRootPath = libraryRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !libraryRootPath.isEmpty else {
            searchResults[wf] = []
            searchMessages[wf] = "Set Library Root before searching."
            searchRunning[wf] = false
            workflowSearchTask?.cancel()
            workflowSearchTask = nil
            if wf == .threeOmega { _clearThreeOmegaTitleContext() }
            return
        }

        aheWorkspace.lastLibraryRootPath = libraryRootPath
        threeOmegaWorkspace.lastLibraryRootPath = libraryRootPath
        analysisVault.configurePersistence(libraryRootPath: libraryRootPath)

        workflowSearchTask?.cancel()
        searchRunning[wf] = true
        searchMessages[wf] = nil

        workflowSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await dataActor.searchWorkflowMeasurements(
                    libraryRootPath: libraryRootPath,
                    query: WorkflowSearchQuery(rawText: query),
                    workflowDefinitions: workflowDefinitions
                )
                guard !Task.isCancelled else { return }
                searchResults[wf] = result
                switch wf {
                case .ahe:
                    aheWorkspace.cachedSearchResults = result
                    // Cache numericDisplay for AHE title template
                    let aheUniqueSampleKeys = Set(result.map { $0.sampleKey })
                    var aheDisplayCache: [String: [String: String]] = [:]
                    for sk in aheUniqueSampleKeys {
                        do {
                            let nd = try await dataActor.lookupSampleNumericDisplay(
                                libraryRootPath: libraryRootPath, sampleKey: sk
                            )
                            if !nd.isEmpty { aheDisplayCache[sk] = nd }
                        } catch {
                            print("[SpinLab][Workbench] numericDisplay lookup failed for \(sk): \(error)")
                        }
                    }
                    aheWorkspace.cachedSampleNumericDisplay = aheDisplayCache
                case .threeOmega:
                    threeOmegaWorkspace.cachedSearchResults = result
                    // Cache numericDisplay for title suffix
                    let uniqueSampleKeys = Set(result.map { $0.sampleKey })
                    var displayCache: [String: [String: String]] = [:]
                    for sk in uniqueSampleKeys {
                        do {
                            let nd = try await dataActor.lookupSampleNumericDisplay(
                                libraryRootPath: libraryRootPath, sampleKey: sk
                            )
                            if !nd.isEmpty { displayCache[sk] = nd }
                        } catch {
                            print("[SpinLab][Workbench] numericDisplay lookup failed for \(sk): \(error)")
                        }
                    }
                    threeOmegaWorkspace.cachedSampleNumericDisplay = displayCache
                case .xyRotation:
                    xyRotationWorkspace.cachedSearchResults = result
                    // Cache numericDisplay for XY Rotation title template
                    let xyUniqueSampleKeys = Set(result.map { $0.sampleKey })
                    var xyDisplayCache: [String: [String: String]] = [:]
                    for sk in xyUniqueSampleKeys {
                        do {
                            let nd = try await dataActor.lookupSampleNumericDisplay(
                                libraryRootPath: libraryRootPath, sampleKey: sk
                            )
                            if !nd.isEmpty { xyDisplayCache[sk] = nd }
                        } catch {
                            print("[SpinLab][Workbench] numericDisplay lookup failed for \(sk): \(error)")
                        }
                    }
                    xyRotationWorkspace.cachedSampleNumericDisplay = xyDisplayCache
                }
                searchMessages[wf] = result.isEmpty
                    ? "No files matched query: \(query)"
                    : "Found \(result.count) file(s)."
                searchRunning[wf] = false
                if wf == .ahe, let firstSampleKey = result.first?.sampleKey {
                    aheWorkspace.loadPersistedArtifact(sampleKey: firstSampleKey)
                }
                if wf == .threeOmega, let rtPath = threeOmegaWorkspace.pendingRTSidecarPath {
                    // Restore RT selection in background (avoid main-thread I/O)
                    let hit = await Task.detached {
                        ThreeOmegaWorkspaceStore.rebuildRTHit(fromSidecarPath: rtPath)
                    }.value
                    if let hit {
                        threeOmegaWorkspace.applyRestoredRTHit(hit)
                    } else {
                        threeOmegaWorkspace.clearPendingRTRestore()
                    }
                }
            } catch is CancellationError {
                searchRunning[wf] = false
            } catch let error as AppError {
                searchResults[wf] = []
                searchMessages[wf] = error.localizedDescription
                searchRunning[wf] = false
                if wf == .threeOmega { _clearThreeOmegaTitleContext() }
            } catch {
                searchResults[wf] = []
                searchMessages[wf] = AppError.from(error, fallback: "Workflow search failed.").localizedDescription
                searchRunning[wf] = false
                if wf == .threeOmega { _clearThreeOmegaTitleContext() }
            }
        }
    }

    func runThreeOmegaRTSearch(libraryRootPath: String?) {
        let store = threeOmegaWorkspace
        let query = store.rtQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            store.rtSearchResults = []
            store.rtSearchMessage = "Enter RT search query."
            store.isRTSearching = false
            return
        }
        guard let libraryRootPath = libraryRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !libraryRootPath.isEmpty else {
            store.rtSearchResults = []
            store.rtSearchMessage = "Set Library Root before searching."
            store.isRTSearching = false
            return
        }

        store.isRTSearching = true
        store.rtSearchMessage = nil
        store.rtSearchResults = []
        store.showRTPopover = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await dataActor.searchWorkflowMeasurements(
                    libraryRootPath: libraryRootPath,
                    query: WorkflowSearchQuery(rawText: query),
                    workflowDefinitions: workflowDefinitions
                )
                store.rtSearchResults = result
                store.rtSearchMessage = result.isEmpty
                    ? "No files matched: \(query)"
                    : "Found \(result.count) file(s)."
                store.isRTSearching = false
            } catch is CancellationError {
                store.isRTSearching = false
            } catch {
                store.rtSearchResults = []
                store.rtSearchMessage = "Search failed."
                store.isRTSearching = false
            }
        }
    }

    func clearWorkflowMeasurementSearch(workflowID wf: WorkbenchWorkflowID) {
        workflowSearchTask?.cancel()
        workflowSearchTask = nil
        searchResults[wf] = []
        switch wf {
        case .ahe:        aheWorkspace.cachedSearchResults = []
        case .threeOmega:
            threeOmegaWorkspace.cachedSearchResults = []
            _clearThreeOmegaTitleContext()
        case .xyRotation:
            xyRotationWorkspace.cachedSearchResults = []
            xyRotationWorkspace.cachedSampleNumericDisplay = [:]
        }
        searchMessages[wf] = nil
        searchRunning[wf] = false
        searchQueryTexts[wf] = wf.searchPrefix
        Self.persistSearchQueryText(wf.searchPrefix, for: wf)
    }

    private func _clearThreeOmegaTitleContext() {
        threeOmegaWorkspace.cachedSampleNumericDisplay = [:]
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

    private func reloadWorkflowDefinitions(selectedID: String?) {
        conditionDefinitionOptions = conditionRulesHandbookStore.conditionDefinitionOptions()
        workflowDefinitions = workflowRegistryStore.load()
        workflowMatchRules = Self.canonicalized(
            conditionRulesHandbookStore.loadWorkflowMatchRules(),
            against: workflowDefinitions
        )
        persistedWorkflowMatchRulesSemantics = Self.workflowMatchRulesSemantics(workflowMatchRules)
        sampleIDPatterns = conditionRulesHandbookStore.loadSampleIDPatterns()
        persistedSampleIDPatterns = sampleIDPatterns
        restoreSubstrateRulesFromSource()
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

    func addSampleIDPattern() {
        sampleIDPatterns.append("")
    }

    func removeSampleIDPattern(at index: Int) {
        guard sampleIDPatterns.indices.contains(index) else { return }
        sampleIDPatterns.remove(at: index)
    }

    func updateSampleIDPattern(at index: Int, value: String) {
        guard sampleIDPatterns.indices.contains(index) else { return }
        sampleIDPatterns[index] = value
    }

    func commitSampleIDPatterns() {
        persistSampleIDPatterns()
    }

    func confirmSampleIDPatternsSave() {
        persistSampleIDPatterns()
    }

    func discardSampleIDPatternEdits() {
        sampleIDPatterns = conditionRulesHandbookStore.loadSampleIDPatterns()
        persistedSampleIDPatterns = sampleIDPatterns
        workflowRegistryMessage = nil
    }

    func updateSubstrateTokenSeparators(_ value: String) {
        substrateTokenSeparators = value
    }

    func updateSubstrateOriginStandaloneTokensCSV(_ csv: String) {
        substrateOriginStandaloneTokens = parseCSV(csv)
    }

    func updateSubstrateOriginContainsTokensCSV(_ csv: String) {
        substrateOriginContainsTokens = parseCSV(csv)
    }

    func substrateTagRuleValuesCSV(_ id: UUID) -> String {
        guard let entry = substrateTagRules.first(where: { $0.id == id }) else {
            return ""
        }
        return entry.matchValues.joined(separator: ", ")
    }

    func addSubstrateTagRule() {
        substrateTagRules.append(
            MatchRuleEntry(
                scope: .tokens,
                type: .equals,
                matchValues: ["O"],
                value: "o"
            )
        )
    }

    func removeSubstrateTagRule(_ id: UUID) {
        guard let index = substrateTagRules.firstIndex(where: { $0.id == id }) else { return }
        substrateTagRules.remove(at: index)
    }

    func updateSubstrateTagRuleScope(_ id: UUID, scope: FilenameRuleSet.MatchScope) {
        guard let index = substrateTagRules.firstIndex(where: { $0.id == id }) else { return }
        substrateTagRules[index].scope = scope
    }

    func updateSubstrateTagRuleType(_ id: UUID, type: FilenameRuleSet.MatchType) {
        guard let index = substrateTagRules.firstIndex(where: { $0.id == id }) else { return }
        substrateTagRules[index].type = type
    }

    func updateSubstrateTagRuleValuesCSV(_ id: UUID, csv: String) {
        guard let index = substrateTagRules.firstIndex(where: { $0.id == id }) else { return }
        substrateTagRules[index].matchValues = parseCSV(csv)
    }

    func updateSubstrateTagRuleValue(_ id: UUID, value: String) {
        guard let index = substrateTagRules.firstIndex(where: { $0.id == id }) else { return }
        substrateTagRules[index].value = value
    }

    func confirmSubstrateRulesSave() {
        persistSubstrateRules()
    }

    func discardSubstrateRuleEdits() {
        restoreSubstrateRulesFromSource()
        workflowRegistryMessage = nil
    }

    private func persistSampleIDPatterns() {
        do {
            let approvalToken = conditionRulesHandbookStore.issueWriteApproval(
                for: .sampleIDPatterns,
                actor: "WorkbenchFeatureStore.persistSampleIDPatterns"
            )
            try conditionRulesHandbookStore.saveSampleIDPatterns(sampleIDPatterns, approvalToken: approvalToken)
            sampleIDPatterns = conditionRulesHandbookStore.loadSampleIDPatterns()
            persistedSampleIDPatterns = sampleIDPatterns
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = error.localizedDescription
        }
    }

    private func persistWorkflowMatchRules() {
        do {
            let approvalToken = conditionRulesHandbookStore.issueWriteApproval(
                for: .workflowMatchRules,
                actor: "WorkbenchFeatureStore.persistWorkflowMatchRules"
            )
            try conditionRulesHandbookStore.saveWorkflowMatchRules(workflowMatchRules, approvalToken: approvalToken)
            workflowMatchRules = conditionRulesHandbookStore.loadWorkflowMatchRules()
            persistedWorkflowMatchRulesSemantics = Self.workflowMatchRulesSemantics(workflowMatchRules)
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = error.localizedDescription
        }
    }

    private func persistSubstrateRules() {
        do {
            let activeRuleSet = RuleLoader.shared.loadCached().ruleSet
            let baseShared = activeRuleSet.sharedSubstrate ?? FilenameRuleSet.SharedSubstrateRules(
                tokenSeparators: "_-",
                originStandaloneTokens: ["O"],
                originContainsTokens: ["ORIGIN", "ORIGINAL"],
                treatmentKeywords: [:],
                materialTokens: [],
                materialAliases: nil,
                materialDisplayNames: nil,
                orientationTokens: nil,
                orientationAliases: nil,
                orientationPattern: "^(?:[0-9]{2,3}|[A-Za-z][0-9]{2,3})$"
            )
            let updatedShared = FilenameRuleSet.SharedSubstrateRules(
                tokenSeparators: substrateTokenSeparators,
                originStandaloneTokens: substrateOriginStandaloneTokens,
                originContainsTokens: substrateOriginContainsTokens,
                treatmentKeywords: baseShared.treatmentKeywords,
                materialTokens: baseShared.materialTokens,
                materialAliases: baseShared.materialAliases,
                materialDisplayNames: baseShared.materialDisplayNames,
                orientationTokens: baseShared.orientationTokens,
                orientationAliases: baseShared.orientationAliases,
                orientationPattern: baseShared.orientationPattern
            )

            let approvalToken = conditionRulesHandbookStore.issueWriteApproval(
                for: .substrateRules,
                actor: "WorkbenchFeatureStore.persistSubstrateRules"
            )
            let patch = SeparatedSubstratePatch(
                substrateTagRules: substrateTagRules,
                sharedSubstrate: updatedShared
            )
            try conditionRulesHandbookStore.saveSubstrateRules(patch, approvalToken: approvalToken)
            restoreSubstrateRulesFromSource()
            workflowRegistryMessage = nil
        } catch {
            workflowRegistryMessage = error.localizedDescription
        }
    }

    private func migrateWorkflowMatchRules(from oldID: String, to newID: String) {
        guard !oldID.isEmpty else { return }
        workflowMatchRules = workflowMatchRules.map { entry in
            guard entry.workflowID.caseInsensitiveCompare(oldID) == .orderedSame else { return entry }
            var updated = entry
            updated.workflowID = newID
            return updated
        }
        persistWorkflowMatchRules()
    }

    private func removeWorkflowMatchRules(for workflowID: String) {
        workflowMatchRules.removeAll { $0.workflowID.caseInsensitiveCompare(workflowID) == .orderedSame }
        persistWorkflowMatchRules()
    }

    private func parseCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func canonicalized(
        _ rules: [WorkflowMatchRuleEntry],
        against definitions: [WorkflowDefinition]
    ) -> [WorkflowMatchRuleEntry] {
        rules.map { entry in
            if definitions.contains(where: {
                $0.id.caseInsensitiveCompare(entry.workflowID) == .orderedSame
            }) {
                return entry
            }
            guard let definition = definitions.first(where: {
                $0.displayName.caseInsensitiveCompare(entry.workflowID) == .orderedSame
            }) else {
                return entry
            }
            var migrated = entry
            migrated.workflowID = definition.id
            return migrated
        }
    }

    private static func workflowMatchRulesSemantics(_ rules: [WorkflowMatchRuleEntry]) -> [WorkflowMatchRuleSemantic] {
        rules.map { entry in
            WorkflowMatchRuleSemantic(
                scope: entry.scope,
                type: entry.type,
                matchValues: entry.matchValues,
                workflowID: entry.workflowID
            )
        }
    }

    private func restoreSubstrateRulesFromSource() {
        let ruleSet = RuleLoader.shared.loadCached().ruleSet
        let state = Self.makeInitialSubstrateState(
            ruleSet: ruleSet,
            separatedPatch: conditionRulesHandbookStore.loadSeparatedSubstrateRules()
        )
        substrateTokenSeparators = state.tokenSeparators
        substrateOriginStandaloneTokens = state.originStandaloneTokens
        substrateOriginContainsTokens = state.originContainsTokens
        substrateTagRules = state.tagRules
        persistedSubstrateRulesSemantic = Self.substrateRulesSemantic(
            tokenSeparators: state.tokenSeparators,
            originStandaloneTokens: state.originStandaloneTokens,
            originContainsTokens: state.originContainsTokens,
            tagRules: state.tagRules
        )
    }

    private static func makeInitialSubstrateState(
        ruleSet: FilenameRuleSet,
        separatedPatch: SeparatedSubstratePatch?
    ) -> (tokenSeparators: String, originStandaloneTokens: [String], originContainsTokens: [String], tagRules: [MatchRuleEntry]) {
        let shared = separatedPatch?.sharedSubstrate ?? ruleSet.sharedSubstrate ?? FilenameRuleSet.SharedSubstrateRules(
            tokenSeparators: "_-",
            originStandaloneTokens: ["O"],
            originContainsTokens: ["ORIGIN", "ORIGINAL"],
            treatmentKeywords: [:],
            materialTokens: [],
            materialAliases: nil,
            materialDisplayNames: nil,
            orientationTokens: nil,
            orientationAliases: nil,
            orientationPattern: "^(?:[0-9]{2,3}|[A-Za-z][0-9]{2,3})$"
        )
        let tagRules = (separatedPatch?.substrateTagRules ?? mapRulesToEntries(ruleSet.substrateTagRules))
        return (
            tokenSeparators: shared.tokenSeparators,
            originStandaloneTokens: shared.originStandaloneTokens,
            originContainsTokens: shared.originContainsTokens,
            tagRules: tagRules
        )
    }

    private static func mapRulesToEntries(_ rules: [FilenameRuleSet.MapRule]) -> [MatchRuleEntry] {
        rules.map { rule in
            let values = (rule.match.values ?? []).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let single = rule.match.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchValues = values.isEmpty ? (single.map { [$0] } ?? []) : values
            return MatchRuleEntry(
                scope: rule.match.scope,
                type: rule.match.type,
                matchValues: matchValues,
                value: rule.value
            )
        }
    }

    private static func substrateRulesSemantic(
        tokenSeparators: String,
        originStandaloneTokens: [String],
        originContainsTokens: [String],
        tagRules: [MatchRuleEntry]
    ) -> SubstrateRulesSemantic {
        SubstrateRulesSemantic(
            tokenSeparators: tokenSeparators,
            originStandaloneTokens: originStandaloneTokens,
            originContainsTokens: originContainsTokens,
            tagRules: tagRules.map {
                SubstrateTagRuleSemantic(
                    scope: $0.scope,
                    type: $0.type,
                    matchValues: $0.matchValues,
                    value: $0.value
                )
            }
        )
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
