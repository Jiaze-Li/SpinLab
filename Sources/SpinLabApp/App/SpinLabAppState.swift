import Foundation
import Observation
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

@MainActor
@Observable
final class SpinLabAppState {
    private final class ArchivedRecordDomainContextAdapter: SpinLabDomainContext {
        private weak var appState: SpinLabAppState?

        init(appState: SpinLabAppState) {
            self.appState = appState
        }

        func normalizedValue(_ value: String?) -> String? {
            MainActor.assumeIsolated {
                appState?.normalized(value)
            }
        }

        func metadataValue(in lookup: SampleRegistryLookupResult?, keys: [String]) -> String? {
            MainActor.assumeIsolated {
                appState?.metadataValue(in: lookup, keys: keys)
            }
        }

        func canonicalProject(named name: String) -> SpinLabDomain.Project? {
            MainActor.assumeIsolated {
                appState?.canonicalProject(named: name)
            }
        }

        func createProject(named name: String) -> String? {
            MainActor.assumeIsolated {
                appState?.createProject(named: name)
            }
        }

        func canonicalBatch(named name: String) -> SpinLabDomain.Batch? {
            MainActor.assumeIsolated {
                appState?.canonicalBatch(named: name)
            }
        }

        func canonicalSample(named name: String) -> SpinLabDomain.Sample? {
            MainActor.assumeIsolated {
                appState?.canonicalSample(named: name)
            }
        }

        func canonicalDevice(named name: String, sampleID: UUID) -> SpinLabDomain.Device? {
            MainActor.assumeIsolated {
                appState?.canonicalDevice(named: name, sampleID: sampleID)
            }
        }

        func canonicalMeasurement(forSourcePath path: String) -> SpinLabDomain.Measurement? {
            MainActor.assumeIsolated {
                appState?.canonicalMeasurement(forSourcePath: path)
            }
        }

        func canonicalDataset(forSourcePath path: String) -> SpinLabDomain.Dataset? {
            MainActor.assumeIsolated {
                appState?.canonicalDataset(forSourcePath: path)
            }
        }

        func measurementNotes(
            for pending: SpinLabDomain.PendingImport,
            draft: PendingImportConfirmationDraft,
            registryLookup: SampleRegistryLookupResult?
        ) -> String {
            MainActor.assumeIsolated {
                appState?.measurementNotes(for: pending, draft: draft, registryLookup: registryLookup) ?? ""
            }
        }

        func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String {
            MainActor.assumeIsolated {
                appState?.analysisModule.defaultResultSummary(for: measurement) ?? ""
            }
        }
    }

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

    var selectedArea: AppArea = .inbox {
        didSet { persistInteractionSnapshotIfReady() }
    }
    var pendingImports: [SpinLabDomain.PendingImport] = []
    var archivedRecords: [SpinLabDomain.ArchivedRecord] = []
    var projectCatalog: [SpinLabDomain.Project] = []
    var selectedPendingImportID: UUID? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    var selectedArchivedRecordID: UUID? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    var workbenchResultDraft: String = "" {
        didSet { persistInteractionSnapshotIfReady() }
    }
    private(set) var registryFileName: String?
    private(set) var registrySourceFilePath: String?
    private(set) var registryPrefixEntries: [RegistryPrefixEntry] = []
    private(set) var routingRuleVersion: Int = 0
    private(set) var routingRuleSourceLabel: String = "unknown"
    private(set) var routingRuleSourcePath: String = "unknown"
    private(set) var routingRuleFingerprint: String = "unknown"
    var librarySettings: LibrarySettings
    private(set) var libraryRootVerificationPath: String?
    private(set) var libraryRootVerificationMessage: String?
    private(set) var libraryBackupMessage: String?
    private(set) var libraryBackupError: String?
    private(set) var libraryPreview: LibraryPreview?
    private(set) var libraryPreviewMessage: String?
    private(set) var libraryLastSyncedAt: Date?
    private(set) var librarySyncStatusMessage: String?
    private(set) var libraryPreviewWarnings: [LibraryWarning] = []
    private(set) var libraryPreviewGroups: [String: [LibraryPreviewBatchGroup]] = [:]
    private(set) var libraryExistingGroups: [String: [LibraryPreviewBatchGroup]] = [:]
    private(set) var libraryExistingMessage: String?
    var librarySelectedPrefix: String? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    var librarySelectedBatchId: String? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    var librarySelectedSampleId: String? {
        didSet { persistInteractionSnapshotIfReady() }
    }
    private(set) var librarySelectionVersion: Int = 0
    var libraryActiveSelectionSource: LibrarySelectionSource = .browser {
        didSet { persistInteractionSnapshotIfReady() }
    }
    private(set) var libraryDrawerMessage: String?
    private(set) var libraryDrawerError: String?
    private(set) var libraryRefreshReview: LibraryRefreshReview?
    private(set) var libraryBatchSyncStatusByID: [String: LibrarySyncBatchStatus] = [:]
    private(set) var librarySampleSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    private(set) var libraryBatchSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    private(set) var librarySampleEditDraft: LibrarySampleEditDraft?
    private(set) var librarySampleEditError: String?
    private(set) var librarySampleEditMessage: String?
    private(set) var librarySampleEditIsSaving: Bool = false
    private(set) var libraryPendingSelectionChangePrompt: String?
    private(set) var libraryGlobalManualLogs: [LibraryManualUpdateLogEntry] = []
    private(set) var libraryGlobalManualLogError: String?
    private(set) var libraryGlobalManualLogMessage: String?
    private(set) var libraryMetadataSyncLogs: [LibraryMetadataSyncLogEntry] = []
    private(set) var libraryMetadataSyncLogError: String?
    private(set) var libraryMetadataSyncLogMessage: String?
    var activeAlert: AppAlertState?
    private(set) var appStateRevision: Int = 0

    let workflow: SpinLabDomain.WorkflowKind

    private let persistence: SpinLabPersistence
    private let inboxRepository: InboxRepository
    private let libraryRepository: LibraryRepository
    private let importPipeline: SpinLabImportPipeline
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
    @ObservationIgnored
    private lazy var librarySyncService = LibrarySyncService(libraryStore: libraryStore, libraryDiffEngine: libraryDiffEngine)
    private let appLogger = AppLogger.shared
    private let interactionMemory: InteractionMemoryStore
    private let inboxState: InboxState
    private var libraryState = LibraryState()
    private let workbenchState = WorkbenchState()
    private let dataActor: any SpinLabDataActing
    private let coordinator = AppCoordinator()
    private let confirmPendingImportUseCase = ConfirmPendingImportUseCase()
    private let saveLibrarySampleEditsUseCase = SaveLibrarySampleEditsUseCase()
    @ObservationIgnored
    private lazy var archivedRecordDomainContext: SpinLabDomainContext = ArchivedRecordDomainContextAdapter(appState: self)
    @ObservationIgnored
    private var pendingImportsProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var archivedRecordsProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var projectCatalogProjectionTask: Task<Void, Never>?
    @ObservationIgnored
    private var bufferedPendingImportsProjection: [SpinLabDomain.PendingImport]?
    @ObservationIgnored
    private var bufferedArchivedRecordsProjection: [SpinLabDomain.ArchivedRecord]?
    @ObservationIgnored
    private var bufferedProjectCatalogProjection: [SpinLabDomain.Project]?
    @ObservationIgnored
    private var isPendingImportsProjectionDrainScheduled = false
    @ObservationIgnored
    private var isArchivedRecordsProjectionDrainScheduled = false
    @ObservationIgnored
    private var isProjectCatalogProjectionDrainScheduled = false

    init(
        workflowBundle: WorkflowBundle = WorkflowRegistry.shared.defaultBundle(),
        environment: AppEnvironment = .live()
    ) {
        self.persistence = environment.persistence
        self.inboxRepository = InboxRepository(persistence: environment.persistence)
        self.libraryRepository = LibraryRepository(persistence: environment.persistence)
        self.workflow = workflowBundle.workflowExtension.workflow
        self.importPipeline = workflowBundle.importPipeline
        self.analysisModule = workflowBundle.analysisModule
        self.viewExtension = workflowBundle.viewExtension
        self.managedStorage = environment.managedStorage
        self.sampleRegistry = environment.sampleRegistry
        self.registrySubstrateRules = environment.registrySubstrateRules
        self.inboxState = InboxState(
            routing: InboxRoutingState(
                routingCapabilities: environment.routingCapabilities,
                ruleRuntime: environment.ruleRuntime
            )
        )
        self.librarySettings = librarySettingsStore.load()
        self.interactionMemory = InteractionMemoryStore(persistence: environment.persistence)
        self.dataActor = environment.dataActor

        if !self.sampleRegistry.isLoaded, let currentRegistryURL = environment.managedStorage.currentSampleRegistryFileURL() {
            self.sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(currentRegistryURL, previewRowCount: 10)
        }

        load()
        setupRepositoryProjectionTasks()
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

    deinit {
        pendingImportsProjectionTask?.cancel()
        archivedRecordsProjectionTask?.cancel()
        projectCatalogProjectionTask?.cancel()
    }

    convenience init(
        workflowBundle: WorkflowBundle = WorkflowRegistry.shared.defaultBundle(),
        persistence: SpinLabPersistence = LocalJSONPersistence(),
        managedStorage: SpinLabManagedStorage = SpinLabManagedStorage(),
        sampleRegistry: SampleRegistryIndexing = XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10),
        registrySubstrateRules: any RegistrySubstrateRuleProviding = RegistrySubstrateRuleBook(),
        routingCapabilities: RoutingCapabilities = .live,
        ruleRuntime: any RuleRuntimeCapability = DefaultRuleRuntimeCapability()
    ) {
        self.init(
            workflowBundle: workflowBundle,
            environment: AppEnvironment(
                persistence: persistence,
                managedStorage: managedStorage,
                sampleRegistry: sampleRegistry,
                registrySubstrateRules: registrySubstrateRules,
                routingCapabilities: routingCapabilities,
                ruleRuntime: ruleRuntime,
                dataActor: SpinLabDataActor()
            )
        )
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

    func navigate(to routeStack: AppRouteStack) {
        let router = AppRouter()
        router.navigate(to: routeStack, appState: self)
    }

    func openDeepLink(_ path: String) -> Bool {
        let router = AppRouter()
        guard let stack = router.deepLinkToRouteStack(path) else {
            return false
        }
        router.navigate(to: stack, appState: self)
        return true
    }

    func hasExistingLibraryDrawer(sampleKey: String) -> Bool {
        matchedExistingLibraryDrawer(sampleInput: sampleKey) != nil
    }

    func matchedExistingLibraryDrawer(sampleInput: String) -> String? {
        inboxState.routing.matchedExistingLibraryDrawer(sampleInput: sampleInput)
    }

    func refreshPendingDrawerMatches(for pendingIDs: [UUID]? = nil) {
        inboxState.routing.refreshPendingDrawerMatches(
            pendingImports: pendingImports,
            for: pendingIDs
        )
    }

    func pendingRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
        inboxState.routing.pendingRoutingSnapshot(for: pending)
    }

    func cachedPendingRoutingSnapshot(for pendingID: UUID) -> SpinLabDomain.PendingRoutingSnapshot? {
        inboxState.routing.cachedPendingRoutingSnapshot(for: pendingID)
    }

    private func refreshRoutingRuleMetadata(forceReload: Bool) {
        let loadResult = inboxState.routing.refreshRoutingRuleMetadata(forceReload: forceReload)
        routingRuleVersion = loadResult.metadata.version
        routingRuleSourceLabel = loadResult.metadata.sourceLabel
        routingRuleSourcePath = loadResult.metadata.sourcePath
        routingRuleFingerprint = loadResult.metadata.fingerprint
        appLogger.info(.import, "Routing rule metadata updated", metadata: [
            "version": "\(loadResult.metadata.version)",
            "source": loadResult.metadata.sourceLabel,
            "path": loadResult.metadata.sourcePath,
            "fingerprint": loadResult.metadata.fingerprint
        ])
    }

    var registryPrefixMap: [String: String] {
        sampleRegistry.prefixToSheet
    }

    private func load() {
        applyPendingImportsProjection(inboxRepository.pendingImports)
        applyArchivedRecordsProjection(libraryRepository.archivedRecords)
        applyProjectCatalogProjection(libraryRepository.projects)
        workbenchResultDraft = selectedArchivedRecord?.latestResult?.summary ?? ""
        inboxState.routing.clearPendingState()
    }

    private func replacePendingImports(_ imports: [SpinLabDomain.PendingImport], persist: Bool = true) {
        let updated = inboxRepository.replacePendingImports(imports, persist: persist)
        applyPendingImportsProjection(updated)
    }

    private func replaceArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord], persist: Bool = true) {
        let updated = libraryRepository.replaceArchivedRecords(records, persist: persist)
        applyArchivedRecordsProjection(updated)
    }

    private func replaceProjectCatalog(_ projects: [SpinLabDomain.Project], persist: Bool = true) {
        let updated = libraryRepository.replaceProjects(projects, persist: persist)
        applyProjectCatalogProjection(updated)
    }

    private func setupRepositoryProjectionTasks() {
        pendingImportsProjectionTask?.cancel()
        archivedRecordsProjectionTask?.cancel()
        projectCatalogProjectionTask?.cancel()

        pendingImportsProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await imports in inboxRepository.pendingImportsStream {
                await MainActor.run {
                    self.bufferedPendingImportsProjection = imports
                    self.schedulePendingImportsProjectionDrainIfNeeded()
                }
            }
        }

        archivedRecordsProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await records in libraryRepository.archivedRecordsStream {
                await MainActor.run {
                    self.bufferedArchivedRecordsProjection = records
                    self.scheduleArchivedRecordsProjectionDrainIfNeeded()
                }
            }
        }

        projectCatalogProjectionTask = Task { [weak self] in
            guard let self else { return }
            for await projects in libraryRepository.projectsStream {
                await MainActor.run {
                    self.bufferedProjectCatalogProjection = projects
                    self.scheduleProjectCatalogProjectionDrainIfNeeded()
                }
            }
        }
    }

    @MainActor
    private func schedulePendingImportsProjectionDrainIfNeeded() {
        guard !isPendingImportsProjectionDrainScheduled else {
            return
        }
        isPendingImportsProjectionDrainScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if let pending = bufferedPendingImportsProjection {
                applyPendingImportsProjection(pending)
                bufferedPendingImportsProjection = nil
            }
            isPendingImportsProjectionDrainScheduled = false
        }
    }

    @MainActor
    private func scheduleArchivedRecordsProjectionDrainIfNeeded() {
        guard !isArchivedRecordsProjectionDrainScheduled else {
            return
        }
        isArchivedRecordsProjectionDrainScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if let records = bufferedArchivedRecordsProjection {
                applyArchivedRecordsProjection(records)
                bufferedArchivedRecordsProjection = nil
            }
            isArchivedRecordsProjectionDrainScheduled = false
        }
    }

    @MainActor
    private func scheduleProjectCatalogProjectionDrainIfNeeded() {
        guard !isProjectCatalogProjectionDrainScheduled else {
            return
        }
        isProjectCatalogProjectionDrainScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            if let projects = bufferedProjectCatalogProjection {
                applyProjectCatalogProjection(projects)
                bufferedProjectCatalogProjection = nil
            }
            isProjectCatalogProjectionDrainScheduled = false
        }
    }

    private func applyPendingImportsProjection(_ imports: [SpinLabDomain.PendingImport]) {
        pendingImports = imports
        if let selectedPendingImportID,
           !imports.contains(where: { $0.id == selectedPendingImportID }) {
            self.selectedPendingImportID = imports.first?.id
        } else if selectedPendingImportID == nil {
            selectedPendingImportID = imports.first?.id
        }
    }

    private func applyArchivedRecordsProjection(_ records: [SpinLabDomain.ArchivedRecord]) {
        archivedRecords = records
        if let selectedArchivedRecordID,
           !records.contains(where: { $0.id == selectedArchivedRecordID }) {
            self.selectedArchivedRecordID = records.first?.id
        } else if selectedArchivedRecordID == nil {
            selectedArchivedRecordID = records.first?.id
        }
    }

    private func applyProjectCatalogProjection(_ projects: [SpinLabDomain.Project]) {
        projectCatalog = projects
    }

    private func migrateManagedMeasurementPathsToOriginalIfPossible() {
        let fileManager = FileManager.default
        var pendingChanged = false
        var archivedChanged = false

        let migratedPendingImports = pendingImports.map { pending in
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

        let migratedArchivedRecords = archivedRecords.map { record in
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
            replacePendingImports(migratedPendingImports)
        }
        if archivedChanged {
            replaceArchivedRecords(migratedArchivedRecords)
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
            inboxState.routing.restoreDrafts(from: snapshot.inboxWorkspaceByPendingID)
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

        var nextPendingImports = pendingImports
        nextPendingImports.insert(contentsOf: imported, at: 0)
        refreshPendingDrawerMatches(for: imported.map(\.id))
        replacePendingImports(nextPendingImports)
        selectedPendingImportID = imported.first?.id
        selectedArea = .inbox
    }

    func clearPendingImports() {
        let clearedPendingImports: [SpinLabDomain.PendingImport] = []
        selectedPendingImportID = nil
        inboxState.routing.clearPendingState()
        updateInteractionValue(\.inboxWorkspaceByPendingID, to: [:])
        replacePendingImports(clearedPendingImports)
    }

    func recomputeAllPendingParsedHints() {
        refreshRoutingRuleMetadata(forceReload: true)
        let recomputedPendingImports = pendingImports.map { pending in
            var next = pending
            next.parsedHints = recomputedParsedHints(for: pending)
            return next
        }
        inboxState.routing.clearPendingState()

        var updatedWorkspaceByPendingID: [String: InboxPendingWorkspaceState] = [:]
        let existingWorkspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        for pending in recomputedPendingImports {
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
        replacePendingImports(recomputedPendingImports)
        bumpAppStateRevision()
    }

    func loadSampleRegistry(from url: URL) {
        let installedURL: URL
        do {
            installedURL = try managedStorage.installSampleRegistry(from: url)
        } catch {
            let appError = AppError.from(error, fallback: "Failed to install sample registry.")
            present(error: appError, title: "Registry Install Failed")
            appLogger.warning(.import, "Sample registry install failed", metadata: ["error": appError.localizedDescription])
            return
        }
        let sourceURL = url
        Task {
            do {
                let snapshot = try await dataActor.loadRegistrySnapshot(from: installedURL, previewRowCount: 10)
                await MainActor.run {
                    applyLoadedRegistrySnapshot(snapshot, installedURL: installedURL, sourceURL: sourceURL)
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to load sample registry.")
                    present(error: appError, title: "Registry Load Failed")
                    appLogger.warning(.import, "Sample registry load failed", metadata: ["error": appError.localizedDescription])
                }
            }
        }
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

        Task {
            do {
                let snapshot = try await dataActor.loadRegistrySnapshot(from: fallbackURL, previewRowCount: 10)
                await MainActor.run {
                    applyLoadedRegistrySnapshot(snapshot, installedURL: fallbackURL, sourceURL: nil)
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to reload sample registry.")
                    present(error: appError, title: "Registry Reload Failed")
                    appLogger.warning(.import, "Sample registry reload failed", metadata: ["error": appError.localizedDescription])
                }
            }
        }
    }

    private func applyLoadedRegistrySnapshot(_ snapshot: SampleRegistrySnapshot, installedURL: URL, sourceURL: URL?) {
        sampleRegistry = SnapshotSampleRegistryIndex(snapshot: snapshot)
        updateLibraryRegistryPaths(installedURL: installedURL, sourceURL: sourceURL)
        libraryPreview = nil
        libraryPreviewWarnings = []
        libraryPreviewMessage = nil
        librarySyncStatusMessage = nil
        updateRegistryPresentation()
        refreshPendingDrawerMatches()
    }

    private func resolvedLibraryRegistryPath() -> String? {
        let fileManager = FileManager.default
        let sourcePath = librarySettings.registrySourcePath
        let internalPath = librarySettings.registryInternalPath ?? managedStorage.currentSampleRegistryFileURL()?.path
        if let sourcePath, fileManager.fileExists(atPath: sourcePath) {
            return sourcePath
        }
        return internalPath
    }

    private func applyLoadedLibraryPreview(_ snapshot: LibraryPreviewParseSnapshot) {
        let preview = LibraryPreview(index: snapshot.index, warnings: snapshot.warnings)
        libraryPreview = preview
        libraryPreviewWarnings = snapshot.warnings
        refreshActionablePreviewGroups()
        libraryLogger.write(snapshot.warnings)
    }

    func loadLibraryPreview() {
        guard let registryPath = resolvedLibraryRegistryPath() else {
            libraryPreviewMessage = "No registry available. Load it from Inbox first."
            return
        }

        let settings = librarySettings
        Task {
            do {
                let snapshot = try await dataActor.parseLibraryPreview(registryPath: registryPath, settings: settings)
                await MainActor.run {
                    applyLoadedLibraryPreview(snapshot)
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to load registry preview.")
                    libraryPreview = nil
                    libraryPreviewWarnings = []
                    libraryPreviewMessage = appError.localizedDescription
                    present(error: appError, title: "Preview Load Failed")
                    appLogger.warning(.library, "Library preview load failed", metadata: ["error": appError.localizedDescription])
                }
            }
        }
    }

    func syncLibraryFromRegistry(onComplete: (() -> Void)? = nil) {
        appLogger.info(.function, "Library sync requested", metadata: ["area": "registry"])
        guard let registryPath = resolvedLibraryRegistryPath() else {
            libraryPreviewMessage = "No registry available. Load it from Inbox first."
            librarySyncStatusMessage = nil
            appLogger.warning(.library, "Library preview unavailable during sync request")
            onComplete?()
            return
        }

        let settings = librarySettings
        Task {
            do {
                let snapshot = try await dataActor.parseLibraryPreview(registryPath: registryPath, settings: settings)
                await MainActor.run {
                    applyLoadedLibraryPreview(snapshot)
                    guard libraryPreview != nil else {
                        librarySyncStatusMessage = nil
                        appLogger.warning(.library, "Library preview unavailable during sync request")
                        onComplete?()
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
                    onComplete?()
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to prepare library sync preview.")
                    librarySyncStatusMessage = nil
                    libraryPreview = nil
                    libraryPreviewWarnings = []
                    libraryPreviewMessage = appError.localizedDescription
                    present(error: appError, title: "Sync Preview Failed")
                    appLogger.warning(.library, "Library sync preview failed", metadata: ["error": appError.localizedDescription])
                    onComplete?()
                }
            }
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
            inboxState.routing.clearDrawerMatchCandidates()
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

    func validateLibraryCacheOnAppear() {
        guard let rootPath = librarySettings.rootPath else {
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard libraryStore.needsIndexRefresh(rootURL: rootURL) else {
            return
        }
        syncLibraryFromFiles()
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
        guard libraryState.pendingSelectionChange != nil else {
            return
        }
        saveLibrarySampleEdits()
        guard librarySampleEditError == nil else {
            return
        }
        applyAndClearPendingLibrarySelectionChange()
    }

    func discardAndContinuePendingLibrarySelectionChange() {
        guard libraryState.pendingSelectionChange != nil else {
            return
        }
        librarySampleEditDraft = nil
        libraryState.sampleEditBaseSample = nil
        libraryState.sampleEditOriginalDraft = nil
        librarySampleEditError = nil
        librarySampleEditMessage = "Edit discarded."
        applyAndClearPendingLibrarySelectionChange()
    }

    func cancelPendingLibrarySelectionChange() {
        libraryState.pendingSelectionChange = nil
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

        libraryState.pendingSelectionChange = requested
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
        guard let pending = libraryState.pendingSelectionChange else {
            return
        }
        libraryState.pendingSelectionChange = nil
        libraryPendingSelectionChangePrompt = nil
        applySelectionChange(pending)
    }

    func hasPendingLibrarySelectionChange() -> Bool {
        libraryState.pendingSelectionChange != nil
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
              let original = libraryState.sampleEditOriginalDraft else {
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

        libraryState.sampleEditBaseSample = sample
        let draft = librarySampleEditService.makeDraft(from: sample)
        librarySampleEditDraft = draft
        libraryState.sampleEditOriginalDraft = draft
    }

    func cancelEditingSelectedLibrarySample() {
        librarySampleEditDraft = nil
        libraryState.sampleEditBaseSample = nil
        libraryState.sampleEditOriginalDraft = nil
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
            let error = AppError.notFound("No registry source found. Load registry from Inbox first.")
            libraryGlobalManualLogError = error.localizedDescription
            libraryGlobalManualLogs = []
            present(error: error, title: "Log Load Failed")
            return
        }

        do {
            let entries = try libraryStore.loadRegistryManualUpdateLogEntries(registrySourceURL: registrySourceURL)
            libraryGlobalManualLogs = entries
            libraryGlobalManualLogMessage = "Loaded \(entries.count) global log entries."
        } catch {
            let appError = AppError.from(error, fallback: "Failed to load global manual logs.")
            libraryGlobalManualLogError = appError.localizedDescription
            libraryGlobalManualLogs = []
            present(error: appError, title: "Log Load Failed")
        }
    }

    func markLibraryGlobalManualLogStatus(rowIndex: Int, status: LibraryManualLogStatus) {
        libraryGlobalManualLogError = nil
        libraryGlobalManualLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Inbox first.")
            libraryGlobalManualLogError = error.localizedDescription
            present(error: error, title: "Status Update Failed")
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
            let appError = AppError.from(error, fallback: "Failed to update manual log status.")
            libraryGlobalManualLogError = appError.localizedDescription
            present(error: appError, title: "Status Update Failed")
        }
    }

    func loadLibraryMetadataSyncLogs() {
        libraryMetadataSyncLogError = nil
        libraryMetadataSyncLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Inbox first.")
            libraryMetadataSyncLogError = error.localizedDescription
            libraryMetadataSyncLogs = []
            present(error: error, title: "Log Load Failed")
            return
        }

        do {
            let entries = try libraryStore.loadRegistryMetadataSyncLogEntries(registrySourceURL: registrySourceURL)
            libraryMetadataSyncLogs = entries
            libraryMetadataSyncLogMessage = "Loaded \(entries.count) metadata log entries."
        } catch {
            let appError = AppError.from(error, fallback: "Failed to load metadata sync logs.")
            libraryMetadataSyncLogError = appError.localizedDescription
            libraryMetadataSyncLogs = []
            present(error: appError, title: "Log Load Failed")
        }
    }

    func saveLibrarySampleEdits() {
        librarySampleEditError = nil
        librarySampleEditMessage = nil
        librarySampleEditIsSaving = true
        defer { librarySampleEditIsSaving = false }

        let result = saveLibrarySampleEditsUseCase.execute(
            input: SaveLibrarySampleEditsUseCase.Input(
                rootPath: librarySettings.rootPath,
                draft: librarySampleEditDraft,
                baseSample: libraryState.sampleEditBaseSample
            ),
            snapshotIndexFromFilesystem: { [libraryStore] rootURL in
                libraryStore.snapshotIndexFromFilesystem(rootURL: rootURL)
            },
            applyDraft: { [librarySampleEditService] draft, current in
                try librarySampleEditService.apply(draft: draft, to: current)
            },
            updateSample: { [libraryStore] updated, rootURL in
                libraryStore.updateSample(updated, rootURL: rootURL, changeSource: "manual_edit")
            },
            resolveRegistrySourceURL: { [weak self] in
                self?.resolveRegistrySourceURL()
            },
            syncRegistrySource: { [libraryStore] current, updated, registrySourceURL in
                try libraryStore.syncRegistrySourceForEditedSample(
                    oldSample: current,
                    updatedSample: updated,
                    registrySourceURL: registrySourceURL
                )
            }
        )

        switch result {
        case let .success(output):
            if output.clearDraft {
                librarySampleEditDraft = nil
                libraryState.sampleEditBaseSample = nil
                libraryState.sampleEditOriginalDraft = nil
            }
            if let rootURL = output.rootURLForCommit {
                commitLibraryMutation(rootURL: rootURL, previewIndex: libraryPreview?.index)
            }
            if let nonFatalError = output.nonFatalError {
                librarySampleEditError = nonFatalError.localizedDescription
                present(error: nonFatalError, title: "Sync Warning")
                appLogger.warning(.library, "Library sample edit saved with sync warning", metadata: [
                    "reason": nonFatalError.localizedDescription
                ])
            }
            librarySampleEditMessage = output.message
            appLogger.info(.library, "Library sample edits saved", metadata: [
                "message": output.message ?? "saved"
            ])
        case let .failure(error):
            librarySampleEditError = error.localizedDescription
            present(error: error, title: "Save Failed")
            appLogger.error(.library, "Library sample edit failed", metadata: [
                "reason": error.localizedDescription
            ])
        }
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
        guard let area = coordinator.routeToWorkbenchForPendingSelection(
            hasPendingSelection: selectedPendingImport != nil
        ) else {
            return
        }

        selectedArea = area
    }

    func openArchivedRecordInWorkbench(_ recordID: UUID) {
        guard let route = coordinator.routeToWorkbenchForArchivedRecord(
            recordID: recordID,
            archivedRecords: archivedRecords
        ),
        let record = archivedRecords.first(where: { $0.id == route.archivedRecordID }) else {
            return
        }

        selectedArchivedRecordID = route.archivedRecordID
        workbenchResultDraft = workbenchState.resolvedSummary(
            for: record.measurement,
            draftSummary: record.latestResult?.summary ?? "",
            analysisModule: analysisModule
        )
        selectedArea = route.selectedArea
    }

    func defaultConfirmationDraft(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        let resolvedSampleID = pending.parsedHints.sampleIDs.first ?? sampleRegistry.sampleID(from: pending.fileName)
        return importPipeline.metadataExtension.defaultConfirmationDraft(
            pending: pending,
            suggestedProjectName: suggestedProject(for: pending)?.name,
            registryLookup: registryLookup(for: pending),
            fallbackSampleID: resolvedSampleID
        )
    }

    func pendingDisplayDraft(for pending: SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft {
        defaultConfirmationDraft(for: pending)
    }

    func pendingRoutePresentation(for pending: SpinLabDomain.PendingImport) -> PendingRoutePresentation {
        let substrate = substrateWarning(for: pending, registryLookup: registryLookup(for: pending))
        return inboxState.routing.pendingRoutePresentation(
            for: pending,
            substrateWarning: substrate
        )
    }

    func pendingRoutePresentationByID() -> [UUID: PendingRoutePresentation] {
        inboxState.routing.pendingRoutePresentationByID(
            pendingImports: pendingImports,
            substrateWarning: { [weak self] pending in
                guard let self else { return nil }
                return self.substrateWarning(for: pending, registryLookup: self.registryLookup(for: pending))
            }
        )
    }

    func pendingDisplayWarningItems(for pending: SpinLabDomain.PendingImport) -> [PendingDisplayWarning] {
        pendingRoutePresentation(for: pending).warningItems
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
        inboxState.routing.pendingRoutePlan(for: pending)
    }

    func pendingRouteStatus(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RouteStatus {
        inboxState.routing.pendingRouteStatus(for: pending)
    }

    func hasSavedRoutingDraft(for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxState.routing.hasSavedRoutingDraft(for: pending)
    }

    func routingDraft(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxState.routing.routingDraft(for: pending)
    }

    func routingDraftBaseline(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxState.routing.routingDraftBaseline(for: pending)
    }

    func isRoutingDraftDirty(_ draft: PendingRoutingDraft, for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxState.routing.isRoutingDraftDirty(draft, for: pending)
    }

    func saveRoutingDraft(_ draft: PendingRoutingDraft, for pendingID: UUID) {
        inboxState.routing.saveRoutingDraft(
            draft,
            for: pendingID,
            pendingImports: pendingImports
        )
        bumpAppStateRevision()
    }

    func confirmSelectedPendingImport(with draft: PendingImportConfirmationDraft) {
        confirmSelectedPendingImport(with: draft, editedFileContents: nil)
    }

    func confirmSelectedPendingImport(with draft: PendingImportConfirmationDraft, editedFileContents: String?) {
        guard let pending = selectedPendingImport else {
            return
        }

        if let editedFileContents {
            do {
                try savePendingImportContents(editedFileContents, for: pending)
            } catch {
                appLogger.error(.import, "Failed to persist edited pending contents", metadata: [
                    "pendingID": pending.id.uuidString,
                    "fileName": pending.fileName
                ])
                present(
                    error: AppError.from(error, fallback: "Failed to save edited import contents."),
                    title: "Save Failed"
                )
                return
            }
        }

        let result = confirmPendingImportUseCase.execute(
            input: ConfirmPendingImportUseCase.Input(
                pending: pending,
                draft: draft
            ),
            inboxRepository: inboxRepository,
            libraryRepository: libraryRepository,
            makeArchivedRecord: { pending, draft in
                let lookup = self.registryLookup(for: pending)
                return self.makeArchivedRecord(from: pending, draft: draft, registryLookup: lookup)
            }
        )
        guard case let .success(output) = result else {
            if case let .failure(error) = result {
                appLogger.error(.import, "Pending import confirmation failed", metadata: [
                    "pendingID": pending.id.uuidString,
                    "fileName": pending.fileName,
                    "reason": error.localizedDescription
                ])
                present(error: error, title: "Import Failed")
            }
            return
        }

        applyArchivedRecordsProjection(output.archivedRecords)
        applyPendingImportsProjection(output.pendingImports)
        inboxState.routing.clearRoutingData(for: pending.id)
        updateInteractionEntryValue(for: pending.id, in: \.inboxWorkspaceByPendingID, value: nil)

        let route = coordinator.routeAfterPendingConfirmation(
            archivedRecordID: output.archivedRecord.id,
            nextPendingID: pendingImports.first?.id
        )
        selectedArchivedRecordID = route.archivedRecordID
        selectedPendingImportID = route.nextPendingID
        workbenchResultDraft = workbenchState.resolvedSummary(
            for: output.archivedRecord.measurement,
            draftSummary: output.archivedRecord.latestResult?.summary ?? "",
            analysisModule: analysisModule
        )
        selectedArea = route.selectedArea
        appLogger.info(.import, "Pending import confirmed", metadata: [
            "pendingID": pending.id.uuidString,
            "archivedRecordID": output.archivedRecord.id.uuidString,
            "measurementID": output.archivedRecord.measurement.id.uuidString,
            "workflow": workflow.rawValue
        ])
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
        replaceProjectCatalog(projectCatalog)
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
            summary: workbenchState.resolvedSummary(
                for: record.measurement,
                draftSummary: workbenchResultDraft,
                analysisModule: analysisModule
            ),
            rating: record.latestResult?.rating,
            updatedAt: .now
        )

        archivedRecords[recordIndex] = record
        replaceArchivedRecords(archivedRecords)
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
        let context = ArchivedRecordBuildContext(
            pending: pending,
            draft: draft,
            registryLookup: registryLookup,
            domainContext: archivedRecordDomainContext
        )
        return importPipeline.workflowExtension.createArchivedRecord(context: context)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applyExistingIndex(_ index: LibraryIndex) {
        guard !index.samples.isEmpty else {
            libraryExistingGroups = [:]
            inboxState.routing.clearDrawerMatchCandidates()
            libraryExistingMessage = "No existing drawers found."
            librarySelectedPrefix = nil
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            librarySampleEditDraft = nil
            libraryState.sampleEditBaseSample = nil
            libraryState.sampleEditOriginalDraft = nil
            refreshPendingDrawerMatches()
            return
        }

        libraryExistingGroups = buildPreviewGroups(from: index)
        inboxState.routing.rebuildDrawerMatchCandidates(from: index.samples)
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
            libraryState.sampleEditBaseSample = nil
            libraryState.sampleEditOriginalDraft = nil
            librarySampleEditError = nil
            librarySampleEditMessage = "Edit canceled after leaving existing drawer selection."
            return
        }

        guard selectedSample.id == draft.sampleId else {
            librarySampleEditDraft = nil
            libraryState.sampleEditBaseSample = nil
            libraryState.sampleEditOriginalDraft = nil
            librarySampleEditError = nil
            librarySampleEditMessage = "Edit canceled after sample selection changed."
            return
        }
    }

    private func savePendingImportContents(_ contents: String, for pending: SpinLabDomain.PendingImport) throws {
        try contents.write(to: URL(fileURLWithPath: pending.sourceFilePath), atomically: true, encoding: .utf8)
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

    func clearActiveAlert() {
        activeAlert = nil
    }

    func presentAlert(title: String, message: String) {
        activeAlert = AppAlertState(title: title, message: message)
    }

    func exportAuditTrail(to destinationURL: URL, note: String? = nil) throws -> AppLogger.AuditTrailExportSummary {
        var context: [String: String] = [
            "workflow": workflow.rawValue,
            "appVersion": AppVersion.current,
            "routingRuleVersion": "\(routingRuleVersion)",
            "routingRuleSource": routingRuleSourceLabel,
            "routingRulePath": routingRuleSourcePath,
            "routingRuleFingerprint": routingRuleFingerprint,
            "pendingImportCount": "\(pendingImports.count)",
            "archivedRecordCount": "\(archivedRecords.count)",
            "selectedArea": selectedArea.rawValue
        ]
        if let selectedPendingImportID {
            context["selectedPendingImportID"] = selectedPendingImportID.uuidString
        }
        if let selectedArchivedRecordID {
            context["selectedArchivedRecordID"] = selectedArchivedRecordID.uuidString
        }
        if let note = normalized(note) {
            context["note"] = note
        }
        do {
            let summary = try appLogger.exportAuditTrail(to: destinationURL, context: context)
            appLogger.info(.system, "Audit trail exported", metadata: [
                "entryCount": "\(summary.entryCount)",
                "workflow": workflow.rawValue
            ])
            return summary
        } catch {
            appLogger.error(.system, "Audit trail export failed", metadata: [
                "reason": error.localizedDescription,
                "workflow": workflow.rawValue
            ])
            throw error
        }
    }

    private func present(error: AppError, title: String) {
        activeAlert = AppAlertState(
            title: title,
            message: error.localizedDescription
        )
    }

    private func bumpAppStateRevision() {
        appStateRevision &+= 1
    }
}
