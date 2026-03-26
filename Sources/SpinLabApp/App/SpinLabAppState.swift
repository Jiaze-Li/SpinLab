import Foundation
import SwiftUI

enum AppArea: String, CaseIterable, Identifiable, Codable {
    case inbox = "Inbox"
    case workbench = "Workbench"
    case library = "Library"

    var id: String { rawValue }
}

enum LibrarySelectionSource: String, Codable {
    case browser
    case drawer
}

enum LibraryPendingSelectionChange: Equatable {
    case browser
    case drawer(prefix: String, batchId: String, sampleId: String?)
}

struct PendingImportConfirmationDraft: Codable, Equatable {
    static let noProjectOption = "None"

    var batchName: String
    var sampleName: String
    var measurementName: String
    var workflowTag: String
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

struct PendingRoutingDraft: Codable, Equatable {
    var defaultSampleKey: String
    var channelSampleKeyOverrides: [String: String]
}

struct InboxPendingWorkspaceState: Codable, Equatable {
    var draft: PendingImportConfirmationDraft
    var editableFileContents: String
    var hasEditableFileContents: Bool
    var routingDraft: PendingRoutingDraft?

    static let maxStoredEditableContentsLength = 200_000
    static let truncatedSuffix = "\n\n[SpinLab] Editable file preview was truncated for interaction-memory snapshot."

    static func snapshotSafe(
        draft: PendingImportConfirmationDraft,
        editableFileContents: String,
        hasEditableFileContents: Bool,
        routingDraft: PendingRoutingDraft? = nil
    ) -> InboxPendingWorkspaceState {
        InboxPendingWorkspaceState(
            draft: draft,
            editableFileContents: sanitizedEditableContents(editableFileContents),
            hasEditableFileContents: hasEditableFileContents,
            routingDraft: routingDraft
        )
    }

    private static func sanitizedEditableContents(_ text: String) -> String {
        guard text.count > maxStoredEditableContentsLength else {
            return text
        }
        let prefixLength = max(0, maxStoredEditableContentsLength - truncatedSuffix.count)
        let prefix = String(text.prefix(prefixLength))
        return prefix + truncatedSuffix
    }
}

struct SidebarInteractionState: Codable, Equatable {
    var isLibraryTreeExpanded: Bool = true
    var expandedPrefixes: Set<String> = []
    var expandedNodeIDs: Set<String> = []

    init(
        isLibraryTreeExpanded: Bool = true,
        expandedPrefixes: Set<String> = [],
        expandedNodeIDs: Set<String> = []
    ) {
        self.isLibraryTreeExpanded = isLibraryTreeExpanded
        self.expandedPrefixes = expandedPrefixes
        self.expandedNodeIDs = expandedNodeIDs
    }

    private enum CodingKeys: String, CodingKey {
        case isLibraryTreeExpanded
        case expandedPrefixes
        case expandedNodeIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isLibraryTreeExpanded = try container.decodeIfPresent(Bool.self, forKey: .isLibraryTreeExpanded) ?? true
        expandedPrefixes = try container.decodeIfPresent(Set<String>.self, forKey: .expandedPrefixes) ?? []
        expandedNodeIDs = try container.decodeIfPresent(Set<String>.self, forKey: .expandedNodeIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isLibraryTreeExpanded, forKey: .isLibraryTreeExpanded)
        try container.encode(expandedPrefixes, forKey: .expandedPrefixes)
        try container.encode(expandedNodeIDs, forKey: .expandedNodeIDs)
    }
}

struct LibraryInteractionState: Codable, Equatable {
    var selectedPrefix: String?
    var selectedBatchId: String?
    var selectedSampleId: String?
    var isLibrarySettingsExpanded: Bool = true
    var isRegistryWorkspaceExpanded: Bool = true
    var isSearchWorkspaceExpanded: Bool = true
    var searchBatchIdText: String = ""
    var searchSubstrateText: String = ""
    var searchKeywordText: String = ""
    var searchThicknessText: String = ""
    var searchOxygenText: String = ""
    var searchTemperatureText: String = ""
    var searchEnergyText: String = ""
    var searchHasExecuted: Bool = false
}

struct InboxInteractionState: Codable, Equatable {
    var isImportSourceExpanded: Bool = true
    var isPendingQueueExpanded: Bool = true
    var isRoutingReviewExpanded: Bool = true
    var isApplyExpanded: Bool = true
}

struct SpinLabInteractionSnapshot: Codable, Equatable {
    var selectedArea: AppArea = .inbox
    var selectedPendingImportID: UUID?
    var selectedArchivedRecordID: UUID?
    var workbenchResultDraft: String = ""
    var libraryActiveSelectionSource: LibrarySelectionSource = .browser
    var librarySelectedPrefix: String?
    var librarySelectedBatchId: String?
    var librarySelectedSampleId: String?
    var inboxWorkspaceByPendingID: [String: InboxPendingWorkspaceState] = [:]
    var sidebar: SidebarInteractionState = SidebarInteractionState()
    var libraryView: LibraryInteractionState = LibraryInteractionState()
    var inboxView: InboxInteractionState = InboxInteractionState()
}

final class SpinLabAppState: ObservableObject {
    private struct InteractionBinding {
        let restore: (SpinLabAppState, SpinLabInteractionSnapshot) -> Void
        let capture: (SpinLabAppState, inout SpinLabInteractionSnapshot) -> Void
    }

    private static func bind<Value>(
        state stateKeyPath: ReferenceWritableKeyPath<SpinLabAppState, Value>,
        snapshot snapshotKeyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>
    ) -> InteractionBinding {
        InteractionBinding(
            restore: { state, snapshot in
                state[keyPath: stateKeyPath] = snapshot[keyPath: snapshotKeyPath]
            },
            capture: { state, snapshot in
                snapshot[keyPath: snapshotKeyPath] = state[keyPath: stateKeyPath]
            }
        )
    }

    private static func bindOptionalUUID(
        state stateKeyPath: ReferenceWritableKeyPath<SpinLabAppState, UUID?>,
        snapshot snapshotKeyPath: WritableKeyPath<SpinLabInteractionSnapshot, UUID?>,
        isValid: @escaping (SpinLabAppState, UUID) -> Bool
    ) -> InteractionBinding {
        InteractionBinding(
            restore: { state, snapshot in
                guard let id = snapshot[keyPath: snapshotKeyPath], isValid(state, id) else {
                    return
                }
                state[keyPath: stateKeyPath] = id
            },
            capture: { state, snapshot in
                snapshot[keyPath: snapshotKeyPath] = state[keyPath: stateKeyPath]
            }
        )
    }

    private static let interactionBindings: [InteractionBinding] = [
        bind(state: \.selectedArea, snapshot: \.selectedArea),
        bindOptionalUUID(
            state: \.selectedPendingImportID,
            snapshot: \.selectedPendingImportID,
            isValid: { state, id in
                state.pendingImports.contains(where: { $0.id == id })
            }
        ),
        bindOptionalUUID(
            state: \.selectedArchivedRecordID,
            snapshot: \.selectedArchivedRecordID,
            isValid: { state, id in
                state.archivedRecords.contains(where: { $0.id == id })
            }
        ),
        bind(state: \.workbenchResultDraft, snapshot: \.workbenchResultDraft),
        bind(state: \.libraryActiveSelectionSource, snapshot: \.libraryActiveSelectionSource),
        bind(state: \.librarySelectedPrefix, snapshot: \.librarySelectedPrefix),
        bind(state: \.librarySelectedBatchId, snapshot: \.librarySelectedBatchId),
        bind(state: \.librarySelectedSampleId, snapshot: \.librarySelectedSampleId)
    ]

    @Published var selectedArea: AppArea = .inbox {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published var pendingImports: [SpinLabDomain.PendingImport] = []
    @Published var archivedRecords: [SpinLabDomain.ArchivedRecord] = []
    @Published var projectCatalog: [SpinLabDomain.Project] = []
    @Published var selectedPendingImportID: UUID? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published var selectedArchivedRecordID: UUID? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published var workbenchResultDraft: String = "" {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published private(set) var registryFileName: String?
    @Published private(set) var registrySourceFilePath: String?
    @Published private(set) var registryPrefixEntries: [RegistryPrefixEntry] = []
    @Published var librarySettings: LibrarySettings
    @Published private(set) var libraryRootVerificationPath: String?
    @Published private(set) var libraryRootVerificationMessage: String?
    @Published private(set) var libraryBackupMessage: String?
    @Published private(set) var libraryBackupError: String?
    @Published private(set) var libraryPreview: LibraryPreview?
    @Published private(set) var libraryPreviewMessage: String?
    @Published private(set) var libraryLastSyncedAt: Date?
    @Published private(set) var librarySyncStatusMessage: String?
    @Published private(set) var libraryPreviewWarnings: [LibraryWarning] = []
    @Published private(set) var libraryPreviewGroups: [String: [LibraryPreviewBatchGroup]] = [:]
    @Published private(set) var libraryExistingGroups: [String: [LibraryPreviewBatchGroup]] = [:]
    @Published private(set) var libraryExistingMessage: String?
    @Published var librarySelectedPrefix: String? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published var librarySelectedBatchId: String? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published var librarySelectedSampleId: String? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published private(set) var librarySelectionVersion: Int = 0
    @Published var libraryActiveSelectionSource: LibrarySelectionSource = .browser {
        didSet { persistInteractionSnapshotIfReady() }
    }
    @Published private(set) var libraryDrawerMessage: String?
    @Published private(set) var libraryDrawerError: String?
    @Published private(set) var libraryRefreshReview: LibraryRefreshReview?
    @Published private(set) var libraryBatchSyncStatusByID: [String: LibrarySyncBatchStatus] = [:]
    @Published private(set) var librarySampleSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    @Published private(set) var libraryBatchSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    @Published private(set) var librarySampleEditDraft: LibrarySampleEditDraft?
    @Published private(set) var librarySampleEditError: String?
    @Published private(set) var librarySampleEditMessage: String?
    @Published private(set) var librarySampleEditIsSaving: Bool = false
    @Published private(set) var libraryPendingSelectionChangePrompt: String?
    @Published private(set) var libraryGlobalManualLogs: [LibraryManualUpdateLogEntry] = []
    @Published private(set) var libraryGlobalManualLogError: String?
    @Published private(set) var libraryGlobalManualLogMessage: String?
    @Published private(set) var libraryMetadataSyncLogs: [LibraryMetadataSyncLogEntry] = []
    @Published private(set) var libraryMetadataSyncLogError: String?
    @Published private(set) var libraryMetadataSyncLogMessage: String?
    @Published private(set) var pendingRoutingSnapshotByID: [UUID: SpinLabDomain.PendingRoutingSnapshot] = [:]
    @Published private(set) var routingRuleFingerprint: String = "unknown"

    let workflow: SpinLabDomain.WorkflowKind = .amrPhe

    private let persistence: SpinLabPersistence
    private let importPipeline: SpinLabImportPipeline
    private let routingCapabilities: RoutingCapabilities
    private let ruleRuntime: any RuleRuntimeCapability
    private let registrySubstrateRules: any RegistrySubstrateRuleProviding
    private let analysisModule: AnalysisModuleExtension
    private let viewExtension: ViewExtension
    private let managedStorage: SpinLabManagedStorage
    private var sampleRegistry: SampleRegistryIndexing
    private let librarySettingsStore = LibrarySettingsStore()
    private let libraryStore = LibraryStore()
    private let libraryLogger = LibraryLogger()
    private let libraryDiffEngine = LibraryDiffEngine()
    private let librarySampleEditService = LibrarySampleEditService()
    private lazy var librarySyncService = LibrarySyncService(libraryStore: libraryStore, libraryDiffEngine: libraryDiffEngine)
    private let appLogger = AppLogger.shared
    private var librarySampleEditBaseSample: LibrarySample?
    private var librarySampleEditOriginalDraft: LibrarySampleEditDraft?
    private var libraryPendingSelectionChange: LibraryPendingSelectionChange?
    private let interactionMemory: InteractionMemoryStore
    private var pendingRoutingDraftsByID: [UUID: PendingRoutingDraft] = [:]
    private var drawerMatchIndex = DrawerMatchIndex()
    private var drawerMatchSamples: [LibrarySample] = []
    private var drawerMatchRuleFingerprint: String = "unknown"
    private let pendingRoutePresentationBuilder = PendingRoutePresentationBuilder()

    init(
        persistence: SpinLabPersistence = LocalJSONPersistence(),
        importPipeline: SpinLabImportPipeline = .amrPhe,
        analysisModule: AnalysisModuleExtension = AMRPHEAnalysisModuleExtension(),
        viewExtension: ViewExtension = AMRPHEViewExtension(),
        managedStorage: SpinLabManagedStorage = SpinLabManagedStorage(),
        sampleRegistry: SampleRegistryIndexing = XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10),
        registrySubstrateRules: any RegistrySubstrateRuleProviding = RegistrySubstrateRuleBook(),
        routingCapabilities: RoutingCapabilities = .live,
        ruleRuntime: any RuleRuntimeCapability = DefaultRuleRuntimeCapability()
    ) {
        self.persistence = persistence
        self.importPipeline = importPipeline
        self.analysisModule = analysisModule
        self.viewExtension = viewExtension
        self.managedStorage = managedStorage
        self.sampleRegistry = sampleRegistry
        self.registrySubstrateRules = registrySubstrateRules
        self.routingCapabilities = routingCapabilities
        self.ruleRuntime = ruleRuntime
        self.librarySettings = librarySettingsStore.load()
        self.interactionMemory = InteractionMemoryStore(persistence: persistence)

        if !self.sampleRegistry.isLoaded, let currentRegistryURL = managedStorage.currentSampleRegistryFileURL() {
            self.sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(currentRegistryURL, previewRowCount: 10)
        }

        load()
        migrateManagedMeasurementPathsToOriginalIfPossible()
        managedStorage.clearManagedMeasurementCopies()
        updateRegistryPresentation()
        refreshRoutingRuleMetadata(forceReload: false)
        loadExistingDrawers()
        restoreInteractionSnapshot()
        refreshPendingDrawerMatches()
        refreshLibraryBackupMessage()
        interactionMemory.markReady()
        persistInteractionSnapshotIfReady()
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

    var canReloadSampleRegistry: Bool {
        resolveRegistrySourceURL() != nil
    }

    var pendingDrawerMatchByID: [UUID: Bool] {
        Dictionary(uniqueKeysWithValues: pendingImports.map { pending in
            let presentation = pendingRoutePresentation(for: pending)
            return (pending.id, presentation.isLibraryMatched)
        })
    }

    var knownProjectNames: [String] {
        let archivedNames = archivedRecords.compactMap { $0.project?.name }
        let catalogNames = projectCatalog.map(\.name)
        return Array(Set(archivedNames + catalogNames)).sorted()
    }

    func hasExistingLibraryDrawer(sampleKey: String) -> Bool {
        matchedExistingLibraryDrawer(sampleInput: sampleKey) != nil
    }

    func matchedExistingLibraryDrawer(sampleInput: String) -> String? {
        ensureDrawerMatchIndexUsesCurrentRules()
        return routingCapabilities.matcher.match(sampleInput: sampleInput, index: drawerMatchIndex)
    }

    func refreshPendingDrawerMatches(for pendingIDs: [UUID]? = nil) {
        let pendingByID = Dictionary(uniqueKeysWithValues: pendingImports.map { ($0.id, $0) })
        let targetIDs = pendingIDs ?? pendingImports.map(\.id)
        guard !targetIDs.isEmpty else {
            pendingRoutingSnapshotByID = [:]
            return
        }

        let validIDs = Set(pendingImports.map(\.id))
        var next = pendingRoutingSnapshotByID.filter { validIDs.contains($0.key) }
        for pendingID in targetIDs {
            guard let pending = pendingByID[pendingID] else {
                next.removeValue(forKey: pendingID)
                continue
            }
            next[pendingID] = evaluatePendingRoutingSnapshot(for: pending)
        }
        pendingRoutingSnapshotByID = next
    }

    func pendingRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
        if let cached = pendingRoutingSnapshotByID[pending.id] {
            return cached
        }
        return evaluatePendingRoutingSnapshot(for: pending)
    }

    func cachedPendingRoutingSnapshot(for pendingID: UUID) -> SpinLabDomain.PendingRoutingSnapshot? {
        pendingRoutingSnapshotByID[pendingID]
    }

    private func evaluatePendingRoutingSnapshot(
        for pending: SpinLabDomain.PendingImport
    ) -> SpinLabDomain.PendingRoutingSnapshot {
        let parsed = parsedHintsApplyingRoutingDraft(for: pending)
        let routePlan = routingCapabilities.planner.makeRoutePlan(from: parsed)
        return routingCapabilities.evaluator.makeSnapshot(
            routePlan: routePlan,
            matchDrawer: { [weak self] sampleInput in
                self?.matchedExistingLibraryDrawer(sampleInput: sampleInput)
            }
        )
    }

    private func rebuildDrawerMatchCandidates(from samples: [LibrarySample]) {
        drawerMatchSamples = samples
        drawerMatchIndex = routingCapabilities.matcher.makeIndex(from: samples)
        drawerMatchRuleFingerprint = ruleRuntime.loadRulesCached().metadata.fingerprint
    }

    private func refreshRoutingRuleMetadata(forceReload: Bool) {
        let loadResult = forceReload ? ruleRuntime.reloadRulesCached() : ruleRuntime.loadRulesCached()
        let previous = routingRuleFingerprint
        routingRuleFingerprint = loadResult.metadata.fingerprint
        appLogger.info(.import, "Routing rule metadata updated", metadata: [
            "version": "\(loadResult.metadata.version)",
            "source": loadResult.metadata.sourceLabel,
            "path": loadResult.metadata.sourcePath,
            "fingerprint": loadResult.metadata.fingerprint
        ])

        if previous != routingRuleFingerprint {
            ensureDrawerMatchIndexUsesCurrentRules()
        }
    }

    private func ensureDrawerMatchIndexUsesCurrentRules() {
        let current = ruleRuntime.loadRulesCached().metadata.fingerprint
        guard drawerMatchRuleFingerprint != current else {
            return
        }
        drawerMatchIndex = routingCapabilities.matcher.makeIndex(from: drawerMatchSamples)
        drawerMatchRuleFingerprint = current
    }

    var registryPrefixMap: [String: String] {
        sampleRegistry.prefixToSheet
    }

    private func load() {
        pendingImports = persistence.loadPendingImports()
        archivedRecords = persistence.loadArchivedRecords()
        projectCatalog = persistence.loadProjects()
        selectedPendingImportID = pendingImports.first?.id
        selectedArchivedRecordID = archivedRecords.first?.id
        workbenchResultDraft = selectedArchivedRecord?.latestResult?.summary ?? ""
        pendingRoutingSnapshotByID = [:]
    }

    private func migrateManagedMeasurementPathsToOriginalIfPossible() {
        let fileManager = FileManager.default
        var pendingChanged = false
        var archivedChanged = false

        pendingImports = pendingImports.map { pending in
            guard managedStorage.isManagedMeasurementPath(pending.sourceFilePath),
                  let originalPath = pending.originalFilePath,
                  fileManager.fileExists(atPath: originalPath) else {
                return pending
            }
            var migrated = pending
            migrated.sourceFilePath = URL(fileURLWithPath: originalPath).standardizedFileURL.path
            pendingChanged = true
            return migrated
        }

        archivedRecords = archivedRecords.map { record in
            var migrated = record
            var didChange = false

            if managedStorage.isManagedMeasurementPath(record.measurement.sourceFilePath),
               let originalPath = record.measurement.originalFilePath,
               fileManager.fileExists(atPath: originalPath) {
                migrated.measurement.sourceFilePath = URL(fileURLWithPath: originalPath).standardizedFileURL.path
                didChange = true
            }

            if managedStorage.isManagedMeasurementPath(record.dataset.sourceFilePath),
               let originalPath = record.dataset.originalFilePath ?? record.measurement.originalFilePath,
               fileManager.fileExists(atPath: originalPath) {
                migrated.dataset.sourceFilePath = URL(fileURLWithPath: originalPath).standardizedFileURL.path
                didChange = true
            }

            if didChange {
                archivedChanged = true
            }
            return migrated
        }

        if pendingChanged {
            persistence.savePendingImports(pendingImports)
        }
        if archivedChanged {
            persistence.saveArchivedRecords(archivedRecords)
        }
    }

    func interactionValue<Value>(_ keyPath: KeyPath<SpinLabInteractionSnapshot, Value>) -> Value {
        interactionMemory.value(keyPath)
    }

    func updateInteractionValue<Value>(_ keyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>, to value: Value) {
        interactionMemory.updateValue(keyPath, to: value)
    }

    func interactionEntryValue<Value>(
        for id: UUID,
        in keyPath: KeyPath<SpinLabInteractionSnapshot, [String: Value]>
    ) -> Value? {
        interactionMemory.entryValue(for: snapshotDictionaryKey(for: id), in: keyPath)
    }

    func updateInteractionEntryValue<Value>(
        for id: UUID,
        in keyPath: WritableKeyPath<SpinLabInteractionSnapshot, [String: Value]>,
        value: Value?
    ) {
        interactionMemory.updateEntryValue(
            for: snapshotDictionaryKey(for: id),
            in: keyPath,
            value: value
        )
    }

    private func snapshotDictionaryKey(for id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private func restoreInteractionSnapshot() {
        interactionMemory.restore { snapshot in
            for binding in Self.interactionBindings {
                binding.restore(self, snapshot)
            }
            let validPendingIDs = Set(pendingImports.map { snapshotDictionaryKey(for: $0.id) })
            snapshot.inboxWorkspaceByPendingID = snapshot.inboxWorkspaceByPendingID.filter { key, _ in
                validPendingIDs.contains(key)
            }
            pendingRoutingDraftsByID = snapshot.inboxWorkspaceByPendingID.reduce(into: [:]) { partial, entry in
                guard let uuid = UUID(uuidString: entry.key),
                      let routingDraft = entry.value.routingDraft else {
                    return
                }
                partial[uuid] = routingDraft
            }
        }
        normalizeLibrarySelection()
    }

    private func persistInteractionSnapshotIfReady() {
        interactionMemory.captureIfReady { snapshot in
            for binding in Self.interactionBindings {
                binding.capture(self, &snapshot)
            }
        }
    }

    func importFiles(from urls: [URL]) {
        let existingOriginalPaths = existingImportedOriginalPaths()
        let managedFiles = managedStorage.importMeasurementFiles(
            from: urls,
            allowedFileExtensions: importPipeline.supportedFileExtensions,
            ignoredFileExtensions: importPipeline.ignoredFileExtensions,
            excludedOriginalFilePaths: existingOriginalPaths
        )
        let imported = importPipeline.importFiles(managedFiles)
        guard !imported.isEmpty else {
            return
        }

        pendingImports.insert(contentsOf: imported, at: 0)
        refreshPendingDrawerMatches(for: imported.map(\.id))
        persistence.savePendingImports(pendingImports)
        selectedPendingImportID = imported.first?.id
        selectedArea = .inbox
    }

    func clearPendingImports() {
        pendingImports = []
        selectedPendingImportID = nil
        pendingRoutingDraftsByID = [:]
        pendingRoutingSnapshotByID = [:]
        updateInteractionValue(\.inboxWorkspaceByPendingID, to: [:])
        persistence.savePendingImports(pendingImports)
    }

    func recomputeAllPendingParsedHints() {
        refreshRoutingRuleMetadata(forceReload: true)
        pendingImports = pendingImports.map { pending in
            var next = pending
            next.parsedHints = recomputedParsedHints(for: pending)
            return next
        }
        pendingRoutingDraftsByID = [:]

        var updatedWorkspaceByPendingID: [String: InboxPendingWorkspaceState] = [:]
        let existingWorkspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        for pending in pendingImports {
            let key = snapshotDictionaryKey(for: pending.id)
            guard let existing = existingWorkspaceByPendingID[key] else {
                continue
            }
            updatedWorkspaceByPendingID[key] = InboxPendingWorkspaceState.snapshotSafe(
                draft: pendingDisplayDraft(for: pending),
                editableFileContents: existing.editableFileContents,
                hasEditableFileContents: existing.hasEditableFileContents,
                routingDraft: nil
            )
        }
        updateInteractionValue(\.inboxWorkspaceByPendingID, to: updatedWorkspaceByPendingID)

        refreshPendingDrawerMatches()
        persistence.savePendingImports(pendingImports)
        objectWillChange.send()
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
        librarySyncStatusMessage = nil
        updateRegistryPresentation()
        refreshPendingDrawerMatches()
    }

    func reloadSampleRegistry() {
        let fileManager = FileManager.default
        if let sourcePath = librarySettings.registrySourcePath,
           fileManager.fileExists(atPath: sourcePath) {
            loadSampleRegistry(from: URL(fileURLWithPath: sourcePath))
            return
        }

        guard let fallbackURL = resolveRegistrySourceURL() else {
            return
        }

        sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(fallbackURL, previewRowCount: 10)
        updateLibraryRegistryPaths(installedURL: fallbackURL, sourceURL: nil)
        libraryPreview = nil
        libraryPreviewWarnings = []
        libraryPreviewMessage = nil
        librarySyncStatusMessage = nil
        updateRegistryPresentation()
        refreshPendingDrawerMatches()
    }

    func loadLibraryPreview() {
        let fileManager = FileManager.default
        let sourcePath = librarySettings.registrySourcePath
        let internalPath = librarySettings.registryInternalPath ?? managedStorage.currentSampleRegistryFileURL()?.path
        let chosenPath: String?
        if let sourcePath, fileManager.fileExists(atPath: sourcePath) {
            chosenPath = sourcePath
        } else {
            chosenPath = internalPath
        }

        guard let registryPath = chosenPath else {
            libraryPreviewMessage = "No registry available. Load it from Inbox first."
            return
        }

        let parser = LibraryRegistryParser()
        let result = parser.parse(xlsxURL: URL(fileURLWithPath: registryPath), settings: librarySettings)
        let preview = LibraryPreview(index: result.index, warnings: result.warnings)
        libraryPreview = preview
        libraryPreviewWarnings = result.warnings
        refreshActionablePreviewGroups()
        libraryLogger.write(result.warnings)
    }

    func syncLibraryFromRegistry() {
        appLogger.info(.function, "Library sync requested", metadata: ["area": "registry"])
        loadLibraryPreview()
        guard libraryPreview != nil else {
            librarySyncStatusMessage = nil
            appLogger.warning(.library, "Library preview unavailable during sync request")
            return
        }
        prepareLibrarySyncReview()
        libraryLastSyncedAt = Date()
        if let syncedAt = libraryLastSyncedAt {
            librarySyncStatusMessage = "Registry diff prepared at \(Self.syncStatusTimeFormatter.string(from: syncedAt)); waiting for manual apply."
            appLogger.info(.library, "Library sync review prepared", metadata: [
                "syncedAt": Self.syncStatusTimeFormatter.string(from: syncedAt)
            ])
        }
    }

    func applyPreparedLibrarySyncReview() {
        guard let review = libraryRefreshReview else {
            libraryDrawerError = "No sync review available. Run Sync Registry first."
            appLogger.warning(.library, "Apply all skipped: no sync review")
            return
        }
        guard review.totalChangesCount > 0 else {
            libraryDrawerMessage = "No changes to apply."
            appLogger.info(.library, "Apply all skipped: no pending changes")
            return
        }
        appLogger.info(.function, "Apply all requested", metadata: [
            "changes": "\(review.totalChangesCount)"
        ])
        refreshLibraryIncremental()
    }

    func applySelectedRegistryDiff(batchId: String?) {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        guard let batchId else {
            libraryDrawerError = "Select a batch first."
            appLogger.warning(.library, "Apply selected failed: no batch selected")
            return
        }
        guard let preview = libraryPreview else {
            libraryDrawerError = "Load the registry preview first."
            appLogger.warning(.library, "Apply selected failed: no preview", metadata: ["batchId": batchId])
            return
        }
        guard let rootPath = librarySettings.rootPath else {
            libraryDrawerError = "Select a Library Root first."
            appLogger.warning(.library, "Apply selected failed: no root path", metadata: ["batchId": batchId])
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)
        guard let applyResult = librarySyncService.applyBatch(
            batchId: batchId,
            preview: preview,
            rootURL: rootURL,
            settings: librarySettings
        ) else {
            libraryDrawerMessage = "No pending sync changes for \(batchId)."
            appLogger.info(.library, "Apply selected skipped: no pending changes", metadata: ["batchId": batchId])
            return
        }
        commitLibraryMutation(rootURL: rootURL, previewIndex: preview.index)
        let batchAction = applyResult.batchAction
        let touched = applyResult.touchedSamples
        libraryDrawerMessage = "Applied selected sync for \(batchId): \(batchAction), \(touched) sample changes."
        appLogger.info(.function, "Apply selected completed", metadata: [
            "batchId": batchId,
            "action": batchAction,
            "sampleChanges": "\(touched)"
        ])
    }

    func loadExistingDrawers() {
        guard let rootPath = librarySettings.rootPath else {
            libraryExistingGroups = [:]
            drawerMatchSamples = []
            drawerMatchIndex = DrawerMatchIndex()
            drawerMatchRuleFingerprint = ruleRuntime.loadRulesCached().metadata.fingerprint
            libraryExistingMessage = "No Library Root selected."
            librarySelectedPrefix = nil
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            refreshPendingDrawerMatches()
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let index = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        applyExistingIndex(index)
    }

    func syncLibraryFromFiles() {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let previousIndex = libraryStore.loadIndex(from: rootURL)
        let syncedIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        applyExistingIndex(syncedIndex)
        refreshActionablePreviewGroups()

        let previousSamplesByID = Dictionary(uniqueKeysWithValues: (previousIndex?.samples ?? []).map { ($0.id, $0) })
        let syncedSamplesByID = Dictionary(uniqueKeysWithValues: syncedIndex.samples.map { ($0.id, $0) })
        let previousIDs = Set(previousSamplesByID.keys)
        let syncedIDs = Set(syncedSamplesByID.keys)
        let addedCount = syncedIDs.subtracting(previousIDs).count
        let removedCount = previousIDs.subtracting(syncedIDs).count
        let updatedCount = previousIDs.intersection(syncedIDs).reduce(into: 0) { partialResult, id in
            if previousSamplesByID[id] != syncedSamplesByID[id] {
                partialResult += 1
            }
        }

        libraryRootVerificationMessage = "File sync complete: \(syncedIndex.samples.count) samples (+\(addedCount) / -\(removedCount) / ~\(updatedCount))."
        libraryRootVerificationPath = rootPath
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) {
        let requested = LibraryPendingSelectionChange.drawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
        guard !deferSelectionChangeIfNeeded(requested) else {
            return
        }
        applySelectionChange(requested)
    }

    func selectBrowserSample() {
        let requested = LibraryPendingSelectionChange.browser
        guard !deferSelectionChangeIfNeeded(requested) else {
            return
        }
        applySelectionChange(requested)
    }

    func saveAndContinuePendingLibrarySelectionChange() {
        guard libraryPendingSelectionChange != nil else {
            return
        }
        saveLibrarySampleEdits()
        guard librarySampleEditError == nil else {
            return
        }
        applyAndClearPendingLibrarySelectionChange()
    }

    func discardAndContinuePendingLibrarySelectionChange() {
        guard libraryPendingSelectionChange != nil else {
            return
        }
        librarySampleEditDraft = nil
        librarySampleEditBaseSample = nil
        librarySampleEditOriginalDraft = nil
        librarySampleEditError = nil
        librarySampleEditMessage = "Edit discarded."
        applyAndClearPendingLibrarySelectionChange()
    }

    func cancelPendingLibrarySelectionChange() {
        libraryPendingSelectionChange = nil
        libraryPendingSelectionChangePrompt = nil
    }

    private func applySelectionChange(_ requested: LibraryPendingSelectionChange) {
        switch requested {
        case let .drawer(prefix, batchId, sampleId):
            librarySelectedPrefix = prefix
            librarySelectedBatchId = batchId
            if let sampleId {
                librarySelectedSampleId = sampleId
            } else {
                librarySelectedSampleId = libraryExistingGroups[prefix]?
                    .first(where: { $0.batchId == batchId })?
                    .samples
                    .first?
                    .id
            }
            libraryActiveSelectionSource = .drawer
            librarySelectionVersion += 1
            reconcileLibrarySampleEditingSelection()
            appLogger.info(.ui, "Existing drawer selected", metadata: [
                "prefix": prefix,
                "batchId": batchId,
                "sampleId": librarySelectedSampleId ?? "-"
            ])
        case .browser:
            libraryActiveSelectionSource = .browser
            librarySelectionVersion += 1
            reconcileLibrarySampleEditingSelection()
            appLogger.info(.usage, "Pending browser selection updated", metadata: [
                "prefix": librarySelectedPrefix ?? "-",
                "batchId": librarySelectedBatchId ?? "-",
                "sampleId": librarySelectedSampleId ?? "-"
            ])
        }
    }

    private func deferSelectionChangeIfNeeded(_ requested: LibraryPendingSelectionChange) -> Bool {
        guard librarySampleEditIsDirty,
              requested != currentSelectionChangeKey else {
            return false
        }

        libraryPendingSelectionChange = requested
        libraryPendingSelectionChangePrompt = "You have unsaved sample edits. Save before switching selection?"
        return true
    }

    private var currentSelectionChangeKey: LibraryPendingSelectionChange {
        switch libraryActiveSelectionSource {
        case .browser:
            return .browser
        case .drawer:
            return .drawer(prefix: librarySelectedPrefix ?? "", batchId: librarySelectedBatchId ?? "", sampleId: librarySelectedSampleId)
        }
    }

    private func applyAndClearPendingLibrarySelectionChange() {
        guard let pending = libraryPendingSelectionChange else {
            return
        }
        libraryPendingSelectionChange = nil
        libraryPendingSelectionChangePrompt = nil
        applySelectionChange(pending)
    }

    func hasPendingLibrarySelectionChange() -> Bool {
        libraryPendingSelectionChange != nil
    }

    func deleteExistingDrawer(batchId: String) {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        guard let rootPath = librarySettings.rootPath else {
            libraryDrawerError = "Select a Library Root first."
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let baselineIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        let targetSamples = baselineIndex.samples.filter { $0.batchId == batchId }
        let targetBatch = baselineIndex.batches.first { $0.id == batchId }
        guard targetBatch != nil || !targetSamples.isEmpty else {
            libraryDrawerError = "Drawer \(batchId) not found."
            return
        }

        for sample in targetSamples {
            libraryStore.deleteSampleDrawer(for: sample, rootURL: rootURL)
        }
        libraryStore.deleteBatchDrawer(batchID: batchId, rootURL: rootURL)

        var index = baselineIndex
        index.updatedAt = .now
        index.samples.removeAll { $0.batchId == batchId }
        index.batches.removeAll { $0.id == batchId }
        libraryStore.saveIndex(index, to: rootURL)

        commitLibraryMutation(rootURL: rootURL, previewIndex: libraryPreview?.index)
        libraryDrawerMessage = "Deleted drawer \(batchId) (\(targetSamples.count) samples)."
    }

    var canEditSelectedLibrarySample: Bool {
        libraryActiveSelectionSource == .drawer && selectedExistingDrawerSample != nil
    }

    var librarySampleEditIsDirty: Bool {
        guard let draft = librarySampleEditDraft,
              let original = librarySampleEditOriginalDraft else {
            return false
        }
        return draft != original
    }

    func beginEditingSelectedLibrarySample() {
        librarySampleEditError = nil
        librarySampleEditMessage = nil

        guard canEditSelectedLibrarySample, let sample = selectedExistingDrawerSample else {
            librarySampleEditError = "Select an existing drawer sample to edit."
            return
        }

        librarySampleEditBaseSample = sample
        let draft = librarySampleEditService.makeDraft(from: sample)
        librarySampleEditDraft = draft
        librarySampleEditOriginalDraft = draft
    }

    func cancelEditingSelectedLibrarySample() {
        librarySampleEditDraft = nil
        librarySampleEditBaseSample = nil
        librarySampleEditOriginalDraft = nil
        librarySampleEditError = nil
        librarySampleEditMessage = "Edit canceled."
    }

    func updateLibrarySampleEditSubstrateTags(_ value: String) {
        guard var draft = librarySampleEditDraft else {
            return
        }
        draft.substrateTagsText = value
        librarySampleEditDraft = draft
    }

    func updateLibrarySampleEditNumericValue(key: String, value: String) {
        guard var draft = librarySampleEditDraft else {
            return
        }
        guard let index = draft.numericValues.firstIndex(where: { $0.key == key }) else {
            return
        }
        draft.numericValues[index].value = value
        librarySampleEditDraft = draft
    }

    func updateLibrarySampleEditMetadataValue(key: String, value: String) {
        guard var draft = librarySampleEditDraft else {
            return
        }
        guard let index = draft.metadataValues.firstIndex(where: { $0.key == key }) else {
            return
        }
        draft.metadataValues[index].value = value
        librarySampleEditDraft = draft
    }

    func librarySampleChangeLog(for sample: LibrarySample) -> [LibrarySampleChangeLogEntry] {
        guard let rootPath = librarySettings.rootPath else {
            return []
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        return libraryStore.sampleChangeLog(for: sample, rootURL: rootURL)
    }

    func loadLibraryGlobalManualLogs() {
        libraryGlobalManualLogError = nil
        libraryGlobalManualLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            libraryGlobalManualLogError = "No registry source found. Load registry from Inbox first."
            libraryGlobalManualLogs = []
            return
        }

        do {
            let entries = try libraryStore.loadRegistryManualUpdateLogEntries(registrySourceURL: registrySourceURL)
            libraryGlobalManualLogs = entries
            libraryGlobalManualLogMessage = "Loaded \(entries.count) global log entries."
        } catch {
            libraryGlobalManualLogError = error.localizedDescription
            libraryGlobalManualLogs = []
        }
    }

    func markLibraryGlobalManualLogStatus(rowIndex: Int, status: LibraryManualLogStatus) {
        libraryGlobalManualLogError = nil
        libraryGlobalManualLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            libraryGlobalManualLogError = "No registry source found. Load registry from Inbox first."
            return
        }

        do {
            try libraryStore.updateRegistryManualUpdateLogStatus(
                registrySourceURL: registrySourceURL,
                rowIndex: rowIndex,
                status: status,
                statusChangedBy: "user"
            )
            loadLibraryGlobalManualLogs()
            libraryGlobalManualLogMessage = "Updated status for log row \(rowIndex) to \(status.rawValue)."
        } catch {
            libraryGlobalManualLogError = error.localizedDescription
        }
    }

    func loadLibraryMetadataSyncLogs() {
        libraryMetadataSyncLogError = nil
        libraryMetadataSyncLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            libraryMetadataSyncLogError = "No registry source found. Load registry from Inbox first."
            libraryMetadataSyncLogs = []
            return
        }

        do {
            let entries = try libraryStore.loadRegistryMetadataSyncLogEntries(registrySourceURL: registrySourceURL)
            libraryMetadataSyncLogs = entries
            libraryMetadataSyncLogMessage = "Loaded \(entries.count) metadata log entries."
        } catch {
            libraryMetadataSyncLogError = error.localizedDescription
            libraryMetadataSyncLogs = []
        }
    }

    func saveLibrarySampleEdits() {
        librarySampleEditError = nil
        librarySampleEditMessage = nil

        guard let rootPath = librarySettings.rootPath else {
            librarySampleEditError = "Select a Library Root first."
            return
        }
        guard let draft = librarySampleEditDraft,
              let base = librarySampleEditBaseSample else {
            librarySampleEditError = "No active edit draft."
            return
        }
        guard draft.sampleId == base.id else {
            librarySampleEditError = "Selection changed. Restart edit for the selected sample."
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let snapshot = libraryStore.snapshotIndexFromFilesystem(rootURL: rootURL)
        guard let current = snapshot.samples.first(where: { $0.id == draft.sampleId }) else {
            librarySampleEditError = "Selected sample no longer exists."
            librarySampleEditDraft = nil
            librarySampleEditBaseSample = nil
            librarySampleEditOriginalDraft = nil
            return
        }
        guard current.updatedAt == draft.baseUpdatedAt else {
            librarySampleEditError = "Sample changed on disk. Reload and edit again."
            return
        }

        do {
            librarySampleEditIsSaving = true
            let updated = try librarySampleEditService.apply(draft: draft, to: current)
            libraryStore.updateSample(updated, rootURL: rootURL, changeSource: "manual_edit")
            var syncSummary: String?
            if let registrySourceURL = resolveRegistrySourceURL() {
                do {
                    let syncResult = try libraryStore.syncRegistrySourceForEditedSample(
                        oldSample: current,
                        updatedSample: updated,
                        registrySourceURL: registrySourceURL
                    )
                    syncSummary = """
                    已保存样品编辑。
                    Metadata 写回 XLSX：成功 \(syncResult.metadataWrittenCount) 项，失败 \(syncResult.metadataFailedCount) 项。
                    Numeric 日志新增：\(syncResult.manualLoggedCount) 项（\(syncResult.manualLogSheetName)）。
                    Metadata 日志表：\(syncResult.metadataLogSheetName)。
                    """
                    if syncResult.metadataFailedCount > 0 {
                        librarySampleEditError = "Metadata sync partial failure: \(syncResult.metadataFailedCount) field(s) failed. Check Metadata日志."
                    }
                } catch {
                    syncSummary = """
                    已保存样品编辑。
                    XLSX 同步警告：\(error.localizedDescription)
                    """
                    librarySampleEditError = "Metadata sync failed: \(error.localizedDescription)"
                }
            } else {
                syncSummary = """
                已保存样品编辑。
                XLSX 同步警告：未找到 registry source。
                """
                librarySampleEditError = "Metadata sync failed: registry source not found."
            }
            commitLibraryMutation(rootURL: rootURL, previewIndex: libraryPreview?.index)
            librarySampleEditDraft = nil
            librarySampleEditBaseSample = nil
            librarySampleEditOriginalDraft = nil
            if let syncSummary {
                librarySampleEditMessage = syncSummary
            } else {
                librarySampleEditMessage = "已保存样品编辑。"
            }
        } catch {
            librarySampleEditError = error.localizedDescription
        }
        librarySampleEditIsSaving = false
    }

    func prepareLibrarySyncReview(precomputedDiff: LibraryDiff? = nil) {
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
        let baselineIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        let diff = precomputedDiff ?? libraryDiffEngine.diff(current: baselineIndex, updated: preview.index)
        libraryRefreshReview = librarySyncService.makeReview(diff: diff)
        refreshSyncChangeIndicators()
        refreshActionablePreviewGroups(precomputedDiff: diff, baselineIndex: baselineIndex)

        libraryDrawerMessage = "Sync review prepared: \(diff.newSamples.count) new, \(diff.changedSamples.count) changed, \(diff.removedSamples.count) removed."
    }

    func refreshLibraryIncremental() {
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
        let (_, diff) = librarySyncService.diff(rootURL: rootURL, previewIndex: preview.index)
        librarySyncService.applyAll(preview: preview, rootURL: rootURL, settings: librarySettings)
        // Recompute post-apply state from persisted filesystem/index; do not reuse pre-apply diff.
        commitLibraryMutation(rootURL: rootURL, previewIndex: preview.index)

        libraryDrawerMessage = "Registry aligned: \(diff.newSamples.count) new, \(diff.changedSamples.count) changed, \(diff.removedSamples.count) removed, \(diff.changedBatches.count) batch updates, \(diff.removedBatches.count) batch removals."
    }

    func confirmLibraryNumericRefreshChanges() {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        guard let review = libraryRefreshReview else {
            libraryDrawerError = "No refresh review available."
            return
        }
        guard !review.deferredNumericChanges.isEmpty else {
            libraryDrawerMessage = "No numeric changes pending confirmation."
            return
        }
        guard let preview = libraryPreview else {
            libraryDrawerError = "Load the registry preview first."
            return
        }
        guard let rootPath = librarySettings.rootPath else {
            libraryDrawerError = "Select a Library Root first."
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let baselineIndex = libraryStore.loadIndex(from: rootURL)
            ?? LibraryIndex(
                createdAt: .now,
                updatedAt: .now,
                registryInternalPath: librarySettings.registryInternalPath,
                registrySourcePath: librarySettings.registrySourcePath,
                metadataColumnOrder: [],
                batches: [],
                samples: []
            )
        var mergedSamplesByID = Dictionary(uniqueKeysWithValues: baselineIndex.samples.map { ($0.id, $0) })
        var mergedBatchesByID = Dictionary(uniqueKeysWithValues: baselineIndex.batches.map { ($0.id, $0) })
        let batchesByIDInPreview = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })
        var touchedBatchIDs: Set<String> = []

        for change in review.deferredNumericChanges {
            let sample = change.sample
            mergedSamplesByID[sample.id] = sample
            libraryStore.updateSample(sample, rootURL: rootURL)
            touchedBatchIDs.insert(sample.batchId)
        }

        for batchID in touchedBatchIDs {
            guard let batch = batchesByIDInPreview[batchID] else {
                continue
            }
            mergedBatchesByID[batchID] = batch
            libraryStore.updateBatch(batch, rootURL: rootURL)
        }

        var mergedIndex = baselineIndex
        mergedIndex.updatedAt = .now
        mergedIndex.registryInternalPath = librarySettings.registryInternalPath
        mergedIndex.registrySourcePath = librarySettings.registrySourcePath
        mergedIndex.metadataColumnOrder = preview.index.metadataColumnOrder
        mergedIndex.samples = Array(mergedSamplesByID.values).sorted { $0.displayName < $1.displayName }
        mergedIndex.batches = Array(mergedBatchesByID.values).sorted { $0.id < $1.id }
        libraryStore.saveIndex(mergedIndex, to: rootURL)
        loadExistingDrawers()

        librarySettings.lastRefreshAt = Date()
        librarySettingsStore.save(librarySettings)

        libraryRefreshReview = LibraryRefreshReview(
            generatedAt: review.generatedAt,
            newSamples: review.newSamples,
            changedSamples: review.changedSamples,
            removedSamples: review.removedSamples,
            changedBatches: review.changedBatches,
            removedBatches: review.removedBatches,
            autoAppliedChanges: review.autoAppliedChanges + review.deferredNumericChanges,
            deferredNumericChanges: []
        )
        libraryDrawerMessage = "Confirmed and applied \(review.deferredNumericChanges.count) numeric changes."
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
        commitLibraryMutation(rootURL: rootURL, previewIndex: preview.index)

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

        let baselineIndex = libraryStore.loadIndex(from: rootURL)
            ?? LibraryIndex(
                createdAt: .now,
                updatedAt: .now,
                registryInternalPath: librarySettings.registryInternalPath,
                registrySourcePath: librarySettings.registrySourcePath,
                metadataColumnOrder: [],
                batches: [],
                samples: []
            )
        var samplesByID = Dictionary(uniqueKeysWithValues: baselineIndex.samples.map { ($0.id, $0) })
        for sample in targetSamples {
            samplesByID[sample.id] = sample
        }

        var batchesByID = Dictionary(uniqueKeysWithValues: baselineIndex.batches.map { ($0.id, $0) })
        var mergedBatch = batchesByID[batch.id] ?? batch
        let mergedSampleKeys = Set(mergedBatch.sampleKeys).union(targetSamples.map(\.id))
        mergedBatch.sampleKeys = mergedSampleKeys.sorted()
        mergedBatch.metadata = batch.metadata
        mergedBatch.numericTags = batch.numericTags
        mergedBatch.numericDisplay = batch.numericDisplay
        mergedBatch.sheetName = batch.sheetName
        mergedBatch.updatedAt = .now
        batchesByID[batch.id] = mergedBatch

        var index = baselineIndex
        index.updatedAt = .now
        index.registryInternalPath = librarySettings.registryInternalPath
        index.registrySourcePath = librarySettings.registrySourcePath
        index.metadataColumnOrder = preview.index.metadataColumnOrder
        index.samples = Array(samplesByID.values).sorted { $0.displayName < $1.displayName }
        index.batches = Array(batchesByID.values).sorted { $0.id < $1.id }
        libraryStore.saveIndex(index, to: rootURL)
        commitLibraryMutation(rootURL: rootURL, previewIndex: preview.index)

        libraryDrawerMessage = "Created \(targetSamples.count) sample drawers."
    }

    func updateLibraryRoot(to url: URL) {
        librarySettings.rootPath = url.path
        librarySettingsStore.save(librarySettings)
        libraryRootVerificationPath = nil
        libraryRootVerificationMessage = nil
        loadExistingDrawers()
    }

    func updateLibraryBackupPath(to url: URL) {
        librarySettings.backupPath = url.path
        librarySettingsStore.save(librarySettings)
        libraryBackupError = nil
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

    func syncLibraryBackup() {
        libraryBackupError = nil

        guard let rootPath = librarySettings.rootPath else {
            libraryBackupError = "No Library Root selected."
            return
        }
        guard let backupPath = librarySettings.backupPath else {
            libraryBackupError = "No Backup Path selected."
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let backupURL = URL(fileURLWithPath: backupPath)
        let rootStandardPath = rootURL.standardizedFileURL.path
        let backupStandardPath = backupURL.standardizedFileURL.path
        if backupStandardPath == rootStandardPath {
            libraryBackupError = "Backup Path must be different from Library Root."
            return
        }
        if backupStandardPath.hasPrefix(rootStandardPath + "/") || rootStandardPath.hasPrefix(backupStandardPath + "/") {
            libraryBackupError = "Backup Path cannot overlap with Library Root."
            return
        }

        if libraryStore.syncBackup(from: rootURL, to: backupURL) {
            let syncedAt = Date()
            librarySettings.backupLastSyncedAt = syncedAt
            librarySettingsStore.save(librarySettings)
            libraryBackupMessage = "Backup sync successful at \(Self.syncStatusTimeFormatter.string(from: syncedAt))."
        } else {
            libraryBackupError = "Backup sync failed."
        }
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
            workflowTag: pending.parsedHints.workflowName ?? "",
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
            draft.sampleName = sampleID
        }

        return draft
    }

    func pendingDisplayDraft(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        defaultConfirmationDraft(for: pending)
    }

    func pendingRoutePresentation(for pending: SpinLabDomain.PendingImport) -> PendingRoutePresentation {
        let routingSnapshot = pendingRoutingSnapshot(for: pending)
        let substrate = substrateWarning(for: pending, registryLookup: registryLookup(for: pending))
        return pendingRoutePresentationBuilder.build(
            pending: pending,
            routingSnapshot: routingSnapshot,
            substrateWarning: substrate
        )
    }

    func pendingRoutePresentationByID() -> [UUID: PendingRoutePresentation] {
        Dictionary(uniqueKeysWithValues: pendingImports.map { pending in
            (pending.id, pendingRoutePresentation(for: pending))
        })
    }

    func pendingDisplayWarningItems(for pending: SpinLabDomain.PendingImport) -> [PendingDisplayWarning] {
        pendingRoutePresentation(for: pending).warningItems
    }

    func pendingDisplayWarnings(for pending: SpinLabDomain.PendingImport) -> [String] {
        pendingDisplayWarningItems(for: pending).map(\.message)
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

        return PendingImportConfirmationDraft(
            batchName: pending.parsedHints.batchName ?? resolvedSampleID ?? "",
            sampleName: pending.parsedHints.sampleName ?? "",
            measurementName: pending.parsedHints.measurementName ?? pending.fileName,
            workflowTag: pending.parsedHints.workflowName ?? "",
            deviceName: pending.parsedHints.deviceName ?? "",
            temperature: pending.parsedHints.temperature ?? "",
            selectedExistingProjectName: suggestedProject(for: pending)?.name ?? PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )
    }

    func pendingRoutePlan(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RoutePlan {
        pendingRoutingSnapshot(for: pending).routePlan
    }

    func pendingRouteStatus(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RouteStatus {
        pendingRoutingSnapshot(for: pending).verdict
    }

    func hasSavedRoutingDraft(for pending: SpinLabDomain.PendingImport) -> Bool {
        pendingRoutingDraftsByID[pending.id] != nil
    }

    func routingDraft(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        if let saved = pendingRoutingDraftsByID[pending.id] {
            return saved
        }

        return routingDraftBaseline(for: pending)
    }

    func routingDraftBaseline(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        let parsed = pending.parsedHints
        let plan = routingCapabilities.planner.makeRoutePlan(from: parsed)
        let resolutionsByChannel = Dictionary(uniqueKeysWithValues: plan.channelResolutions.map { ($0.channel, $0) })

        var overrides: [String: String] = [:]
        for channel in parsed.channelHints {
            let explicitInput = normalized(channel.sampleID)
            guard explicitInput != nil else {
                overrides[channel.channel] = ""
                continue
            }
            overrides[channel.channel] = resolutionsByChannel[channel.channel]?.sampleKey ?? explicitInput ?? ""
        }

        let defaultSampleKey = plan.channelResolutions
            .first(where: { $0.channel == "file" })?
            .sampleKey
            ?? parsed.defaultSampleKey
            ?? ""

        return PendingRoutingDraft(
            defaultSampleKey: defaultSampleKey,
            channelSampleKeyOverrides: overrides
        )
    }

    func isRoutingDraftDirty(_ draft: PendingRoutingDraft, for pending: SpinLabDomain.PendingImport) -> Bool {
        let trimmedCurrent = PendingRoutingDraft(
            defaultSampleKey: draft.defaultSampleKey.trimmingCharacters(in: .whitespacesAndNewlines),
            channelSampleKeyOverrides: draft.channelSampleKeyOverrides.mapValues {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        return trimmedCurrent != routingDraft(for: pending)
    }

    func saveRoutingDraft(_ draft: PendingRoutingDraft, for pendingID: UUID) {
        pendingRoutingDraftsByID[pendingID] = PendingRoutingDraft(
            defaultSampleKey: draft.defaultSampleKey.trimmingCharacters(in: .whitespacesAndNewlines),
            channelSampleKeyOverrides: draft.channelSampleKeyOverrides.mapValues {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        refreshPendingDrawerMatches(for: [pendingID])
        objectWillChange.send()
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
        pendingRoutingDraftsByID[pending.id] = nil
        pendingRoutingSnapshotByID[pending.id] = nil
        updateInteractionEntryValue(for: pending.id, in: \.inboxWorkspaceByPendingID, value: nil)

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
        pending.parsedHints.sampleName
            ?? pending.parsedHints.batchName
            ?? pending.parsedHints.sampleIDs.first
            ?? sampleRegistry.sampleID(from: pending.fileName)
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

    private func parsedHintsApplyingRoutingDraft(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints {
        guard let draft = pendingRoutingDraftsByID[pending.id] else {
            return pending.parsedHints
        }

        var parsed = pending.parsedHints
        let trimmedDefault = draft.defaultSampleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        parsed.defaultSampleKey = trimmedDefault.isEmpty ? nil : trimmedDefault

        var channelHints = parsed.channelHints
        for index in channelHints.indices {
            let channelID = channelHints[index].channel
            guard let override = draft.channelSampleKeyOverrides[channelID] else {
                continue
            }
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            channelHints[index].sampleID = trimmed.isEmpty ? nil : trimmed
        }
        parsed.channelHints = channelHints
        return parsed
    }

    private func applyExistingIndex(_ index: LibraryIndex) {
        guard !index.samples.isEmpty else {
            libraryExistingGroups = [:]
            drawerMatchSamples = []
            drawerMatchIndex = DrawerMatchIndex()
            drawerMatchRuleFingerprint = ruleRuntime.loadRulesCached().metadata.fingerprint
            libraryExistingMessage = "No existing drawers found."
            librarySelectedPrefix = nil
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            librarySampleEditDraft = nil
            librarySampleEditBaseSample = nil
            librarySampleEditOriginalDraft = nil
            refreshPendingDrawerMatches()
            return
        }

        libraryExistingGroups = buildPreviewGroups(from: index)
        rebuildDrawerMatchCandidates(from: index.samples)
        libraryExistingMessage = "Loaded existing drawers: \(index.samples.count) samples"
        normalizeLibrarySelection()
        reconcileLibrarySampleEditingSelection()
        refreshPendingDrawerMatches()
    }

    private func refreshSyncChangeIndicators() {
        guard let review = libraryRefreshReview else {
            libraryBatchSyncStatusByID = [:]
            librarySampleSyncChangesByID = [:]
            libraryBatchSyncChangesByID = [:]
            return
        }

        var batchStatus: [String: LibrarySyncBatchStatus] = [:]
        for sample in review.newSamples {
            batchStatus[sample.batchId] = .added
        }
        for change in review.changedSamples {
            if batchStatus[change.sample.batchId] != .added {
                batchStatus[change.sample.batchId] = .changed
            }
        }
        for sample in review.removedSamples {
            if batchStatus[sample.batchId] != .added {
                batchStatus[sample.batchId] = .changed
            }
        }
        for change in review.changedBatches {
            if batchStatus[change.batch.id] != .added {
                batchStatus[change.batch.id] = .changed
            }
        }
        for batch in review.removedBatches {
            batchStatus[batch.id] = .removed
        }

        libraryBatchSyncStatusByID = batchStatus
        librarySampleSyncChangesByID = Dictionary(uniqueKeysWithValues: review.changedSamples.map { ($0.sample.id, $0.fieldChanges) })
        libraryBatchSyncChangesByID = Dictionary(uniqueKeysWithValues: review.changedBatches.map { ($0.batch.id, $0.fieldChanges) })
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
        buildPreviewGroups(from: preview.index)
    }

    private func buildPreviewGroups(from index: LibraryIndex) -> [String: [LibraryPreviewBatchGroup]] {
        var groups: [String: [LibraryPreviewBatchGroup]] = [:]
        let samplesByBatch = Dictionary(grouping: index.samples) { $0.batchId }
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

    private func actionablePreviewIndex(from previewIndex: LibraryIndex, precomputedDiff: LibraryDiff? = nil) -> LibraryIndex {
        guard librarySettings.rootPath != nil else {
            return previewIndex
        }
        guard let diff = precomputedDiff ?? diffAgainstExisting(previewIndex: previewIndex) else {
            return previewIndex
        }
        var actionableByID: [String: LibrarySample] = [:]
        for sample in diff.newSamples {
            actionableByID[sample.id] = sample
        }
        for change in diff.changedSamples {
            actionableByID[change.sample.id] = change.sample
        }

        let actionableSamples = Array(actionableByID.values).sorted { $0.displayName < $1.displayName }
        let actionableBatchIDs = Set(actionableSamples.map(\.batchId))
        let actionableBatches = previewIndex.batches
            .filter { actionableBatchIDs.contains($0.id) }
            .map { batch in
                var next = batch
                next.sampleKeys = batch.sampleKeys.filter { actionableByID[$0] != nil }
                return next
            }
            .sorted { $0.id < $1.id }

        return LibraryIndex(
            version: previewIndex.version,
            createdAt: previewIndex.createdAt,
            updatedAt: previewIndex.updatedAt,
            registryInternalPath: previewIndex.registryInternalPath,
            registrySourcePath: previewIndex.registrySourcePath,
            metadataColumnOrder: previewIndex.metadataColumnOrder,
            batches: actionableBatches,
            samples: actionableSamples
        )
    }

    private func refreshActionablePreviewGroups(precomputedDiff: LibraryDiff? = nil, baselineIndex: LibraryIndex? = nil) {
        guard let preview = libraryPreview else {
            libraryPreviewGroups = [:]
            libraryPreviewMessage = "No preview loaded."
            return
        }
        let diff = precomputedDiff ?? diffAgainstExisting(previewIndex: preview.index, baselineIndex: baselineIndex)
        let removedCount = diff?.removedSamples.count ?? 0
        let newCount = diff?.newSamples.count ?? preview.index.samples.count
        let actionable = actionablePreviewIndex(from: preview.index, precomputedDiff: diff)
        libraryPreviewGroups = buildPreviewGroups(from: actionable)
        let changedCount = max(actionable.samples.count - newCount, 0)
        libraryPreviewMessage = "Sync diff loaded: \(actionable.samples.count) actionable (\(newCount) new, \(changedCount) changed, \(removedCount) removed)"
    }

    private func diffAgainstExisting(previewIndex: LibraryIndex, baselineIndex: LibraryIndex? = nil) -> LibraryDiff? {
        let effectiveBaseline: LibraryIndex
        if let baselineIndex {
            effectiveBaseline = baselineIndex
        } else {
            guard let rootPath = librarySettings.rootPath else {
                return nil
            }
            let rootURL = URL(fileURLWithPath: rootPath)
            effectiveBaseline = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        }
        return libraryDiffEngine.diff(current: effectiveBaseline, updated: previewIndex)
    }

    private func commitLibraryMutation(
        rootURL: URL,
        previewIndex: LibraryIndex?,
        precomputedDiff: LibraryDiff? = nil,
        precomputedReview: LibraryRefreshReview? = nil
    ) {
        let syncedIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        applyExistingIndex(syncedIndex)

        if let previewIndex {
            let diff = precomputedDiff ?? libraryDiffEngine.diff(current: syncedIndex, updated: previewIndex)
            libraryRefreshReview = precomputedReview ?? librarySyncService.makeReview(diff: diff)
            refreshSyncChangeIndicators()
            refreshActionablePreviewGroups(precomputedDiff: diff, baselineIndex: syncedIndex)
        } else {
            libraryRefreshReview = nil
            refreshSyncChangeIndicators()
            refreshActionablePreviewGroups()
        }

        librarySettings.lastRefreshAt = Date()
        librarySettingsStore.save(librarySettings)
    }

    private static let syncStatusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func refreshLibraryBackupMessage() {
        guard let lastSyncedAt = librarySettings.backupLastSyncedAt else {
            return
        }
        libraryBackupMessage = "Backup sync successful at \(Self.syncStatusTimeFormatter.string(from: lastSyncedAt))."
    }

    private func normalizeLibrarySelection() {
        let prefixes = libraryExistingGroups.keys.sorted()
        if librarySelectedPrefix == nil || !prefixes.contains(librarySelectedPrefix ?? "") {
            librarySelectedPrefix = prefixes.first
        }

        guard let prefix = librarySelectedPrefix else {
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            return
        }

        let groups = libraryExistingGroups[prefix] ?? []
        let batchIDs = groups.map(\.batchId)
        if librarySelectedBatchId == nil || !batchIDs.contains(librarySelectedBatchId ?? "") {
            librarySelectedBatchId = groups.first?.batchId
        }

        guard let batchId = librarySelectedBatchId,
              let samples = groups.first(where: { $0.batchId == batchId })?.samples else {
            librarySelectedSampleId = nil
            return
        }

        if librarySelectedSampleId == nil || !samples.contains(where: { $0.id == librarySelectedSampleId }) {
            librarySelectedSampleId = samples.first?.id
        }
    }

    private func recomputedParsedHints(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints {
        let fileManager = FileManager.default
        let parseURL: URL

        if let original = pending.originalFilePath,
           fileManager.fileExists(atPath: original) {
            parseURL = URL(fileURLWithPath: original)
        } else {
            parseURL = URL(fileURLWithPath: pending.fileName)
        }

        return importPipeline.metadataExtension.parseFilename(from: parseURL)
    }

    private var selectedExistingDrawerSample: LibrarySample? {
        guard let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId,
              let sampleId = librarySelectedSampleId else {
            return nil
        }
        let groups = libraryExistingGroups[prefix] ?? []
        guard let group = groups.first(where: { $0.batchId == batchId }) else {
            return nil
        }
        return group.samples.first(where: { $0.id == sampleId })
    }

    private func reconcileLibrarySampleEditingSelection() {
        guard let draft = librarySampleEditDraft else {
            return
        }

        guard libraryActiveSelectionSource == .drawer,
              let selectedSample = selectedExistingDrawerSample else {
            librarySampleEditDraft = nil
            librarySampleEditBaseSample = nil
            librarySampleEditOriginalDraft = nil
            librarySampleEditError = nil
            librarySampleEditMessage = "Edit canceled after leaving existing drawer selection."
            return
        }

        guard selectedSample.id == draft.sampleId else {
            librarySampleEditDraft = nil
            librarySampleEditBaseSample = nil
            librarySampleEditOriginalDraft = nil
            librarySampleEditError = nil
            librarySampleEditMessage = "Edit canceled after sample selection changed."
            return
        }
    }

    private func savePendingImportContents(_ contents: String, for pending: SpinLabDomain.PendingImport) {
        try? contents.write(to: URL(fileURLWithPath: pending.sourceFilePath), atomically: true, encoding: .utf8)
    }

    private func resolveRegistrySourceURL() -> URL? {
        let fileManager = FileManager.default
        if let sourcePath = librarySettings.registrySourcePath, fileManager.fileExists(atPath: sourcePath) {
            return URL(fileURLWithPath: sourcePath)
        }
        if let internalPath = librarySettings.registryInternalPath, fileManager.fileExists(atPath: internalPath) {
            return URL(fileURLWithPath: internalPath)
        }
        if let current = managedStorage.currentSampleRegistryFileURL(), fileManager.fileExists(atPath: current.path) {
            return current
        }
        return nil
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

    private func resolvedSubstrate(
        from lookup: SampleRegistryLookupResult,
        substrateTags: [String],
        allowsOriginToken: Bool
    ) -> RegistrySubstrateResolution {
        registrySubstrateRules.resolvedSubstrate(
            sampleID: lookup.sampleID,
            substrateValue: metadataValue(in: lookup, keys: ["substrate", "Substrate", "衬底"]),
            substrateTags: substrateTags,
            allowsOriginToken: allowsOriginToken
        )
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
        registrySubstrateRules.hasStandaloneOriginToken(
            fileName: pending.fileName,
            originalFilePath: pending.originalFilePath
        )
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
