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

struct ConditionDefinitionOption: Identifiable, Equatable {
    let id: String
    let label: String

    var description: String { label }
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

    /// AHE-specific workspace state. All plot, selection, and artifact state lives here.
    let aheWorkspace: AHEWorkspaceStore
    /// 3w workspace state. Independent workflow — parsing, fitting, scaling, 6 plots.
    let threeOmegaWorkspace: ThreeOmegaWorkspaceStore
    /// In-memory vault for saved analysis packs (shared across workflows).
    let analysisVault = AnalysisVault()
    /// XY Rotation workspace state. Angle-dependent resistance R(φ), dual parser (LVM + DAT).
    let xyRotationWorkspace: XYRotationWorkspaceStore
    /// IV workspace state. Current-voltage measurement workflow.
    let ivWorkspace: IVWorkspaceStore
    /// RSM workspace state. Reciprocal Space Map single-file heatmap workflow.
    let rsmWorkspace: RSMWorkspaceStore
    /// RT workspace state. Resistance vs Temperature multi-file workflow.
    let rtWorkspace: RTWorkspaceStore
    /// Legacy search status bridge retained for compatibility with existing callers/tests.
    var searchMessages: [String: String] = [:]
    /// Shared plot appearance defaults across workflows.
    var globalPlotDefaults: [String: String] = [:] {
        didSet { syncGlobalPlotDefaultsToWorkspaces() }
    }
    @ObservationIgnored
    private lazy var mainSearchRuntime = WorkbenchMainSearchRuntime(store: self, dataActor: dataActor)
    @ObservationIgnored
    private(set) lazy var secondaryInputRuntime = WorkbenchSecondaryInputSearchRuntime(store: self, dataActor: dataActor)
    @ObservationIgnored
    private lazy var selectionRuntime = WorkbenchSelectionRuntime()
    @ObservationIgnored
    let overlayRuntime = WorkbenchAnalysisOverlayRuntime()

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
    private let dataActor: any SpinLabDataActing
    @ObservationIgnored
    private let workflowDefinitionStore: WorkflowDefinitionStore
    @ObservationIgnored
    var onDefinitionsChanged: (([WorkflowDefinition]) -> Void)?

    var selectedSection: WorkbenchSection = .workflows
    var currentRoute: WorkbenchRoute
    var workflowDefinitions: [WorkflowDefinition]
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
        workflowDefinitionStore: WorkflowDefinitionStore = WorkflowDefinitionStore()
    ) {
        let initialArchivedRecords = libraryRepository.archivedRecords
        let initialProjectCatalog = libraryRepository.projects
        let initialWorkflowDefinitions = workflowDefinitionStore.load()
        let initialRuleSet = RuleLoader.shared.loadCached().ruleSet
        let initialConditionOptions: [ConditionDefinitionOption] = initialRuleSet.conditionDefinitions.compactMap { def in
            let id = def.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let label = def.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedLabel = (label?.isEmpty == false)
                ? label!
                : (ConditionFieldCatalog.labelMap(from: initialRuleSet)[id] ?? ConditionFieldCatalog.defaultLabel(for: id))
            return ConditionDefinitionOption(id: id, label: resolvedLabel)
        }

        let wfIDs = WorkspaceWorkflowIDResolver(definitions: initialWorkflowDefinitions)
        guard
            let resolvedAheID        = wfIDs.aheID,
            let resolvedThreeOmegaID = wfIDs.threeOmegaID,
            let resolvedXYRotationID = wfIDs.xyRotationID,
            let resolvedIVID         = wfIDs.ivID,
            let resolvedRSMID        = wfIDs.rsmID,
            let resolvedRTID         = wfIDs.rtID
        else {
            preconditionFailure("One or more workflow definitions are missing from the active rule book")
        }
        self.aheWorkspace        = AHEWorkspaceStore(workflowID: resolvedAheID)
        self.threeOmegaWorkspace = ThreeOmegaWorkspaceStore(
            workflowID: resolvedThreeOmegaID,
            relatedRTWorkflowID: resolvedRTID
        )
        self.xyRotationWorkspace = XYRotationWorkspaceStore(workflowID: resolvedXYRotationID)
        self.ivWorkspace         = IVWorkspaceStore(workflowID: resolvedIVID)
        self.rsmWorkspace        = RSMWorkspaceStore(workflowID: resolvedRSMID)
        self.rtWorkspace         = RTWorkspaceStore(workflowID: resolvedRTID)

        self.libraryRepository = libraryRepository
        self.dataActor = dataActor
        self.workflowDefinitionStore = workflowDefinitionStore
        self.archivedRecords = initialArchivedRecords
        self.projectCatalog = initialProjectCatalog
        self.selectedArchivedRecordID = initialArchivedRecords.first?.id
        self.workflowDefinitions = initialWorkflowDefinitions
        self.conditionDefinitionOptions = initialConditionOptions
        self.currentRoute = .registry(selectedID: initialWorkflowDefinitions.first?.id)
        self.threeOmegaWorkspace.vault = analysisVault
        self.xyRotationWorkspace.vault = analysisVault
        self.aheWorkspace.vault = analysisVault
        self.ivWorkspace.vault = analysisVault
        self.rsmWorkspace.vault = analysisVault
        self.rtWorkspace.vault = analysisVault

        self.aheWorkspace.selectionReading = self.selectionRuntime
        self.xyRotationWorkspace.selectionReading = self.selectionRuntime
        self.threeOmegaWorkspace.selectionReading = self.selectionRuntime
        self.ivWorkspace.selectionReading = self.selectionRuntime
        self.rsmWorkspace.selectionReading = self.selectionRuntime
        self.rtWorkspace.selectionReading = self.selectionRuntime

        // Route 3ω RT session state through the secondary input runtime.
        // Forces lazy init of secondaryInputRuntime while self is fully constructed.
        self.threeOmegaWorkspace.secondaryInputRuntime = self.secondaryInputRuntime

        // Route overlay display/control state through the common overlay runtime.
        self.threeOmegaWorkspace.overlayRuntime = self.overlayRuntime

        syncGlobalPlotDefaultsToWorkspaces()
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
        ivTitleTemplate: String? = nil,
        ivStackOffsetMultiplier: Double? = nil,
        ivMinGapFraction: Double? = nil,
        workbenchPlotDefaults: [String: String]? = nil,
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
        let legacyOverrides = workbenchChartStyleOverrides ?? [:]
        let splitLegacy = WorkbenchChartStyle.splitGlobalPlotDefaults(from: legacyOverrides)
        if let defaults = workbenchPlotDefaults, !defaults.isEmpty {
            globalPlotDefaults = defaults
        } else if !splitLegacy.global.isEmpty {
            globalPlotDefaults = splitLegacy.global
        }

        // IV workspace plot controls.
        if let t = ivTitleTemplate { ivWorkspace.titleTemplate = t }
        if let v = ivStackOffsetMultiplier { ivWorkspace.stackOffsetMultiplier = v }
        if let v = ivMinGapFraction { ivWorkspace.minGapFraction = v }

        let localOverrides = workbenchPlotDefaults == nil
            ? splitLegacy.local
            : legacyOverrides.filter { !WorkbenchChartStyle.isGlobalPlotDefaultKey($0.key) }
        if !localOverrides.isEmpty {
            threeOmegaWorkspace.tabs.chartStyleOverrides = localOverrides
            xyRotationWorkspace.tabs.chartStyleOverrides = localOverrides
            aheWorkspace.tabs.chartStyleOverrides = localOverrides
            ivWorkspace.tabs.chartStyleOverrides = localOverrides
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
        // IV workspace plot controls.
        snapshot.ivTitleTemplate = ivWorkspace.titleTemplate
        snapshot.ivStackOffsetMultiplier = ivWorkspace.stackOffsetMultiplier
        snapshot.ivMinGapFraction = ivWorkspace.minGapFraction

        snapshot.workbenchPlotDefaults = globalPlotDefaults.isEmpty ? nil : globalPlotDefaults

        // Chart style overrides remain workflow-local for non-global keys.
        var overrides: [String: String] = [:]
        for (k, v) in threeOmegaWorkspace.tabs.chartStyleOverrides
            where !WorkbenchChartStyle.isGlobalPlotDefaultKey(k) {
            overrides[k] = v
        }
        for (k, v) in xyRotationWorkspace.tabs.chartStyleOverrides
            where !WorkbenchChartStyle.isGlobalPlotDefaultKey(k) {
            overrides[k] = v
        }
        for (k, v) in aheWorkspace.tabs.chartStyleOverrides
            where !WorkbenchChartStyle.isGlobalPlotDefaultKey(k) {
            overrides[k] = v
        }
        for (k, v) in ivWorkspace.tabs.chartStyleOverrides
            where !WorkbenchChartStyle.isGlobalPlotDefaultKey(k) {
            overrides[k] = v
        }
        snapshot.workbenchChartStyleOverrides = overrides.isEmpty ? nil : overrides
    }

    /// Restores search state for any workflow (used by shell's Load Pack popover).
    func restoreSearchState(results: [WorkflowMeasurementSearchHit], queryText: String, for wf: String) {
        mainSearchRuntime.restoreSearchState(results: results, queryText: queryText, for: wf)
    }

    func searchQueryText(for wf: String) -> String {
        mainSearchRuntime.searchQueryText(for: wf)
    }

    func setSearchQueryText(_ text: String, for wf: String) {
        mainSearchRuntime.setSearchQueryText(text, for: wf)
    }

    func searchResultsList(for wf: String) -> [WorkflowMeasurementSearchHit] {
        mainSearchRuntime.searchResultsList(for: wf)
    }

    func searchMessage(for wf: String) -> String? {
        mainSearchRuntime.searchMessage(for: wf)
    }

    func isSearchRunning(for wf: String) -> Bool {
        mainSearchRuntime.isSearchRunning(for: wf)
    }

    func searchSnapshot(for wf: String) -> WorkbenchSearchSnapshot {
        mainSearchRuntime.searchSnapshot(for: wf)
    }

    // MARK: - Selection facade

    func selectedSearchResultIDs(for wf: String) -> Set<String> {
        selectionRuntime.selectedIDs(for: wf)
    }

    func selectedCount(for wf: String) -> Int {
        selectionRuntime.selectedCount(for: wf)
    }

    func isAllSelected(for wf: String) -> Bool {
        selectionRuntime.isAllSelected(for: wf, denominator: denominatorHits(for: wf))
    }

    func toggleSearchHitSelection(_ id: String, for wf: String) {
        let hit = denominatorHits(for: wf).first { $0.id == id }
        selectionRuntime.toggle(id, for: wf, hit: hit)
    }

    func selectAll(for wf: String) {
        selectionRuntime.selectAll(for: wf, denominator: denominatorHits(for: wf))
    }

    /// Removes only the current search result IDs from selection; keeps hits from other searches.
    func deselectCurrentResults(for wf: String) {
        selectionRuntime.deselectCurrentResults(for: wf, denominator: denominatorHits(for: wf))
    }

    /// Clears the entire selection basket for the workflow (tray Clear button).
    func deselectAll(for wf: String) {
        selectionRuntime.deselectAll(for: wf)
    }

    func selectedHitDisplayInfos(for wf: String) -> [SelectedHitDisplayInfo] {
        selectionRuntime.selectedHitDisplayInfos(for: wf)
    }

    func seedSelection(_ ids: Set<String>, hits: [WorkflowMeasurementSearchHit] = [], for wf: String) {
        selectionRuntime.seed(ids: ids, for: wf, availableHits: hits)
    }

    func selectedHitsSnapshot(for wf: String) -> WorkbenchSelectedHitsSnapshot {
        let ids = selectionRuntime.selectedIDs(for: wf)
        let hitCache = selectionRuntime.selectedHitCache(for: wf)
        return mainSearchRuntime.selectedHitsSnapshot(for: wf, selectedIDs: ids, hitCache: hitCache)
    }

    private func denominatorHits(for wf: String) -> [WorkflowMeasurementSearchHit] {
        let canonical = mainSearchRuntime.searchResultsList(for: wf)
        if !canonical.isEmpty { return canonical }
        if wf == aheWorkspace.workflowID        { return aheWorkspace.cachedSearchResults }
        if wf == threeOmegaWorkspace.workflowID { return threeOmegaWorkspace.cachedSearchResults }
        if wf == xyRotationWorkspace.workflowID { return xyRotationWorkspace.cachedSearchResults }
        if wf == ivWorkspace.workflowID         { return ivWorkspace.cachedSearchResults }
        if wf == rsmWorkspace.workflowID        { return rsmWorkspace.cachedSearchResults }
        if wf == rtWorkspace.workflowID         { return rtWorkspace.cachedSearchResults }
        return []
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

    private func syncGlobalPlotDefaultsToWorkspaces() {
        aheWorkspace.globalPlotDefaults = globalPlotDefaults
        xyRotationWorkspace.globalPlotDefaults = globalPlotDefaults
        threeOmegaWorkspace.globalPlotDefaults = globalPlotDefaults
        ivWorkspace.globalPlotDefaults = globalPlotDefaults
        rsmWorkspace.globalPlotDefaults = globalPlotDefaults
        rtWorkspace.globalPlotDefaults = globalPlotDefaults
    }

    func selectWorkflow(_ id: String?) {
        guard let id else {
            currentRoute = .registry(selectedID: workflowDefinitions.first?.id)
            return
        }
        let resolvedID = workflowDefinitions.contains(where: { $0.id == id }) ? id : (workflowDefinitions.first?.id ?? id)
        currentRoute = .workflow(id: resolvedID)
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

    func runWorkflowMeasurementSearch(
        workflowID wf: String,
        libraryRootPath: String?,
        librarySettings: LibrarySettings? = nil
    ) {
        mainSearchRuntime.runWorkflowMeasurementSearch(
            workflowID: wf,
            libraryRootPath: libraryRootPath,
            librarySettings: librarySettings
        )
    }

    func runThreeOmegaRTSearch(libraryRootPath: String?, librarySettings: LibrarySettings? = nil) {
        secondaryInputRuntime.runSearch(
            forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID,
            libraryRootPath: libraryRootPath,
            librarySettings: librarySettings
        )
    }

    func clearWorkflowMeasurementSearch(workflowID wf: String) {
        mainSearchRuntime.clearWorkflowMeasurementSearch(workflowID: wf)
    }

    private func namesEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }


    // Called by SpinLabAppState.onRulesSaved to refresh conditionDefinitionOptions after rules save
    func reloadWorkflowDefinitionsAfterRulesChange() {
        reloadWorkflowDefinitions(selectedID: currentSelectedWorkflowID)
    }

    private var currentSelectedWorkflowID: String? {
        switch currentRoute {
        case .registry(let id): return id
        case .workflow(let id): return id
        }
    }

    private func reloadWorkflowDefinitions(selectedID: String?) {
        let ruleSet = RuleLoader.shared.loadCached().ruleSet
        conditionDefinitionOptions = ruleSet.conditionDefinitions.compactMap { def in
            let id = def.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let label = def.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedLabel = (label?.isEmpty == false)
                ? label!
                : (ConditionFieldCatalog.labelMap(from: ruleSet)[id] ?? ConditionFieldCatalog.defaultLabel(for: id))
            return ConditionDefinitionOption(id: id, label: resolvedLabel)
        }
        workflowDefinitions = workflowDefinitionStore.load()
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
