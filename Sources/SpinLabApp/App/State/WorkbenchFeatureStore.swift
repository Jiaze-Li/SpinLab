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

struct ConditionDefinitionOption: Identifiable, Equatable {
    let id: String
    let label: String

    var description: String { label }
}

enum TokenMatchType: String, CaseIterable, Equatable {
    case equals
    case regex
}

struct TokenMapping: Identifiable, Equatable {
    var id: UUID = UUID()
    var matchType: TokenMatchType = .equals
    var pattern: String
    var value: String
}

struct RuleEntry: Identifiable, Equatable {
    var ruleID: String
    var label: String
    var kind: RuleEntryKind
    var units: [String] = []
    var mappings: [TokenMapping] = []
    var readOnlyMessage: String?

    var id: String { "\(ruleID):\(kind.rawValue)" }
}

struct ConditionChangeProposal: Identifiable {
    struct FieldChange {
        let label: String
        let before: String?
        let after: String?
    }
    let id = UUID()
    let pendingID: UUID
    let fileName: String
    let changes: [FieldChange]
}

struct WorkflowMatchRuleEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var scope: FilenameRuleSet.MatchScope
    var type: FilenameRuleSet.MatchType
    var matchValues: [String]
    var workflowID: String
}

struct SeparatedConditionsPatch: Equatable {
    var extraConditions: [String: String]
    var deletedExtraConditionKeys: Set<String>
    var tokenMapRules: [String: [TokenMapping]]
}

struct MatchRuleEntry: Identifiable, Equatable {
    var id: UUID = UUID()
    var scope: FilenameRuleSet.MatchScope
    var type: FilenameRuleSet.MatchType
    var matchValues: [String]
    var value: String
}

struct SeparatedSubstratePatch {
    var substrateTagRules: [MatchRuleEntry]?
    var sharedSubstrate: FilenameRuleSet.SharedSubstrateRules?
}

enum ConditionRulesHandbookStore {
    struct SharedSubstratePayload: Codable {
        var tokenSeparators: String
        var originStandaloneTokens: [String]
        var originContainsTokens: [String]
        var treatmentKeywords: [String: [String]]
        var materialTokens: [String]
        var materialAliases: [String: String]?
        var materialDisplayNames: [String: String]?
        var orientationTokens: [String]?
        var orientationAliases: [String: String]?
        var orientationPattern: String

        var asRuleSetValue: FilenameRuleSet.SharedSubstrateRules {
            .init(
                tokenSeparators: tokenSeparators,
                originStandaloneTokens: originStandaloneTokens,
                originContainsTokens: originContainsTokens,
                treatmentKeywords: treatmentKeywords,
                materialTokens: materialTokens,
                materialAliases: materialAliases,
                materialDisplayNames: materialDisplayNames,
                orientationTokens: orientationTokens,
                orientationAliases: orientationAliases,
                orientationPattern: orientationPattern
            )
        }
    }
}

struct RulePatternCodec {
    static let canonicalPrefix = #"^-?\d+(?:\.\d+)?(?:"#
    static let canonicalSuffix = #")$"#

    static func isCanonical(_ pattern: String) -> Bool {
        pattern.hasPrefix(canonicalPrefix) && pattern.hasSuffix(canonicalSuffix)
    }

    static func units(from pattern: String) -> [String]? {
        guard isCanonical(pattern) else { return nil }
        let inner = String(pattern.dropFirst(canonicalPrefix.count).dropLast(canonicalSuffix.count))
        guard !inner.isEmpty else { return nil }
        return inner
            .components(separatedBy: "|")
            .map(unescapeRegexLiteral)
            .filter { !$0.isEmpty }
    }

    static func pattern(from units: [String]) -> String {
        let escaped = units.map { NSRegularExpression.escapedPattern(for: $0) }
        return canonicalPrefix + escaped.joined(separator: "|") + canonicalSuffix
    }

    static func regexPattern(from shorthandOrRegex: String) -> String {
        let trimmed = shorthandOrRegex.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = numericSuffixShorthandSuffix(from: trimmed) {
            let escaped = NSRegularExpression.escapedPattern(for: suffix)
            return canonicalPrefix + escaped + canonicalSuffix
        }
        return trimmed
    }

    static func displayPattern(from storedPattern: String) -> String {
        if let suffix = numericSuffixRegexSuffix(from: storedPattern) {
            return "xx\(suffix)"
        }
        return storedPattern
    }

    private static func numericSuffixShorthandSuffix(from value: String) -> String? {
        guard value.lowercased().hasPrefix("xx"), value.count > 2 else {
            return nil
        }
        return String(value.dropFirst(2))
    }

    private static func numericSuffixRegexSuffix(from pattern: String) -> String? {
        guard isCanonical(pattern) else { return nil }
        let inner = String(pattern.dropFirst(canonicalPrefix.count).dropLast(canonicalSuffix.count))
        guard !inner.isEmpty, !inner.contains("|") else { return nil }
        return unescapeRegexLiteral(inner)
    }

    private static func unescapeRegexLiteral(_ value: String) -> String {
        var output = ""
        var escaping = false
        for char in value {
            if escaping {
                output.append(char)
                escaping = false
            } else if char == "\\" {
                escaping = true
            } else {
                output.append(char)
            }
        }
        if escaping { output.append("\\") }
        return output
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
        dataActor: any SpinLabDataActing = SpinLabDataActor(),
        workflowRegistryStore: WorkflowRegistryStore
    ) {
        let initialArchivedRecords = libraryRepository.archivedRecords
        let initialProjectCatalog = libraryRepository.projects
        let initialWorkflowDefinitions = workflowRegistryStore.load()
        let initialRuleSet = RuleLoader.shared.loadCached().ruleSet
        let initialConditionOptions: [ConditionDefinitionOption] = initialRuleSet.conditionDefinitions.compactMap { def in
            let id = def.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let label = def.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedLabel = (label?.isEmpty == false)
                ? label!
                : (ConditionFieldCatalog.labelMap(from: initialRuleSet)[id] ?? ConditionFieldCatalog.defaultLabel(for: id))
            return ConditionDefinitionOption(id: id, label: resolvedLabel)
        }

        self.libraryRepository = libraryRepository
        self.dataActor = dataActor
        self.workflowRegistryStore = workflowRegistryStore
        self.archivedRecords = initialArchivedRecords
        self.projectCatalog = initialProjectCatalog
        self.selectedArchivedRecordID = initialArchivedRecords.first?.id
        self.workflowDefinitions = initialWorkflowDefinitions
        self.conditionDefinitionOptions = initialConditionOptions
        self.searchQueryTexts = Self.restoreSearchQueryTexts()
        self.currentRoute = .registry(selectedID: initialWorkflowDefinitions.first?.id)
        self.threeOmegaWorkspace.vault = analysisVault
        self.xyRotationWorkspace.vault = analysisVault
        self.aheWorkspace.vault = analysisVault
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
        aheTitleTemplate: String? = nil,
        xyRotationPhiOffsets: [String: Double]? = nil,
        xyRotationActiveTab: String? = nil,
        xyRotationTitleTemplate: String? = nil,
        xyRotationStackOffset: Double? = nil,
        xyRotationCenterBaseline: Bool? = nil,
        xyRotationLinearDetrend: Bool? = nil,
        xyRotationPlotLegendPoints: [String: [Double]]? = nil,
        workbenchChartStyleOverrides: [String: String]? = nil
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
                    var state = threeOmegaWorkspace.tabs.state(for: tab)
                    state.legendPoint = CGPointCodable(CGPoint(x: arr[0], y: arr[1]))
                    threeOmegaWorkspace.tabs.tabStates[tab] = state
                }
            }
        }
        if let t = aheTitleTemplate { aheWorkspace.titleTemplate = t }
        // XY Rotation
        if let offsets = xyRotationPhiOffsets, !offsets.isEmpty {
            xyRotationWorkspace.phiOffsetOverrides = offsets
        }
        if let tabRaw = xyRotationActiveTab, let tab = XYRotationWorkbenchTab(rawValue: tabRaw) {
            xyRotationWorkspace.tabs.activeTab = tab
        }
        if let t = xyRotationTitleTemplate { xyRotationWorkspace.titleTemplate = t }
        if let v = xyRotationStackOffset { xyRotationWorkspace.stackOffsetMultiplier = v }
        if let v = xyRotationCenterBaseline { xyRotationWorkspace.centerBaseline = v }
        if let v = xyRotationLinearDetrend { xyRotationWorkspace.linearDetrend = v }
        if let legendMap = xyRotationPlotLegendPoints {
            for (key, arr) in legendMap where arr.count == 2 {
                if let tab = XYRotationWorkbenchTab(rawValue: key) {
                    var state = xyRotationWorkspace.tabs.state(for: tab)
                    state.legendPoint = CGPointCodable(CGPoint(x: arr[0], y: arr[1]))
                    xyRotationWorkspace.tabs.tabStates[tab] = state
                }
            }
        }
        // Chart style overrides (font sizes) — apply to all three workflows
        if let overrides = workbenchChartStyleOverrides, !overrides.isEmpty {
            threeOmegaWorkspace.tabs.chartStyleOverrides = overrides
            xyRotationWorkspace.tabs.chartStyleOverrides = overrides
            aheWorkspace.tabs.chartStyleOverrides = overrides
        }
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
        if !threeOmegaWorkspace.tabs.tabStates.isEmpty {
            var legendMap: [String: [Double]] = [:]
            for (tab, state) in threeOmegaWorkspace.tabs.tabStates {
                if let lp = state.legendPoint {
                    legendMap[tab.stableKey] = [lp.x, lp.y]
                }
            }
            if !legendMap.isEmpty {
                snapshot.threeOmegaPlotLegendPoints = legendMap
            }
        }
        snapshot.aheTitleTemplate = aheWorkspace.titleTemplate
        // XY Rotation
        snapshot.xyRotationPhiOffsets = xyRotationWorkspace.phiOffsetOverrides.isEmpty
            ? nil : xyRotationWorkspace.phiOffsetOverrides
        snapshot.xyRotationActiveTab = xyRotationWorkspace.tabs.activeTab.rawValue
        snapshot.xyRotationTitleTemplate = xyRotationWorkspace.titleTemplate
        snapshot.xyRotationStackOffset = xyRotationWorkspace.stackOffsetMultiplier
        snapshot.xyRotationCenterBaseline = xyRotationWorkspace.centerBaseline
        snapshot.xyRotationLinearDetrend = xyRotationWorkspace.linearDetrend
        do {
            var legendMap: [String: [Double]] = [:]
            for (tab, state) in xyRotationWorkspace.tabs.tabStates {
                if let lp = state.legendPoint {
                    legendMap[tab.rawValue] = [lp.x, lp.y]
                }
            }
            if !legendMap.isEmpty { snapshot.xyRotationPlotLegendPoints = legendMap }
        }
        // Chart style overrides — merge from all workflows (user may edit in any one)
        var overrides: [String: String] = [:]
        for (k, v) in threeOmegaWorkspace.tabs.chartStyleOverrides { overrides[k] = v }
        for (k, v) in xyRotationWorkspace.tabs.chartStyleOverrides { overrides[k] = v }
        for (k, v) in aheWorkspace.tabs.chartStyleOverrides { overrides[k] = v }
        snapshot.workbenchChartStyleOverrides = overrides.isEmpty ? nil : overrides
    }

    /// Restores search state for any workflow (used by shell's Load Pack popover).
    func restoreSearchState(results: [WorkflowMeasurementSearchHit], queryText: String, for wf: WorkbenchWorkflowID) {
        searchResults[wf] = results
        setSearchQueryText(queryText, for: wf)
        searchMessages[wf] = "Restored from analysis pack (\(results.count) hit(s))."
        searchRunning[wf] = false
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
        // s5: replace with user-input ID sheet
        let newID = String(UUID().uuidString.prefix(6)).uppercased()
        let defaultConditionID = conditionDefinitionOptions.first?.id ?? "temperature"
        let definition = WorkflowDefinition(
            id: newID,
            displayName: "New Workflow",
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
        definition.id = normalizedID
        definition.displayName = normalizedDisplayName.isEmpty ? normalizedID : normalizedDisplayName
        definition.parentID = normalizeOptional(parentID)
        do {
            try workflowRegistryStore.update(definition)
            reloadWorkflowDefinitions(selectedID: definition.id)
            workflowRegistryMessage = nil
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
                    xyRotationWorkspace.lastLibraryRootPath = libraryRootPath
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
        let ruleSet = RuleLoader.shared.loadCached().ruleSet
        conditionDefinitionOptions = ruleSet.conditionDefinitions.compactMap { def in
            let id = def.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let label = def.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedLabel = (label?.isEmpty == false)
                ? label!
                : (ConditionFieldCatalog.labelMap(from: ruleSet)[id] ?? ConditionFieldCatalog.defaultLabel(for: id))
            return ConditionDefinitionOption(id: id, label: resolvedLabel)
        }
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
