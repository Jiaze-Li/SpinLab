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
        private let normalizedValueProvider: @MainActor (String?) -> String?
        private let metadataValueProvider: @MainActor (SampleRegistryLookupResult?, [String]) -> String?
        private let canonicalProjectProvider: @MainActor (String) -> SpinLabDomain.Project?
        private let canonicalBatchProvider: @MainActor (String) -> SpinLabDomain.Batch?
        private let canonicalSampleProvider: @MainActor (String) -> SpinLabDomain.Sample?
        private let canonicalDeviceProvider: @MainActor (String, UUID) -> SpinLabDomain.Device?
        private let canonicalMeasurementProvider: @MainActor (String) -> SpinLabDomain.Measurement?
        private let canonicalDatasetProvider: @MainActor (String) -> SpinLabDomain.Dataset?
        private let measurementNotesProvider: @MainActor (SpinLabDomain.PendingImport, PendingImportConfirmationDraft, SampleRegistryLookupResult?) -> String
        private let defaultResultSummaryProvider: @MainActor (SpinLabDomain.Measurement) -> String

        init(
            normalizedValueProvider: @escaping @MainActor (String?) -> String?,
            metadataValueProvider: @escaping @MainActor (SampleRegistryLookupResult?, [String]) -> String?,
            canonicalProjectProvider: @escaping @MainActor (String) -> SpinLabDomain.Project?,
            canonicalBatchProvider: @escaping @MainActor (String) -> SpinLabDomain.Batch?,
            canonicalSampleProvider: @escaping @MainActor (String) -> SpinLabDomain.Sample?,
            canonicalDeviceProvider: @escaping @MainActor (String, UUID) -> SpinLabDomain.Device?,
            canonicalMeasurementProvider: @escaping @MainActor (String) -> SpinLabDomain.Measurement?,
            canonicalDatasetProvider: @escaping @MainActor (String) -> SpinLabDomain.Dataset?,
            measurementNotesProvider: @escaping @MainActor (SpinLabDomain.PendingImport, PendingImportConfirmationDraft, SampleRegistryLookupResult?) -> String,
            defaultResultSummaryProvider: @escaping @MainActor (SpinLabDomain.Measurement) -> String
        ) {
            self.normalizedValueProvider = normalizedValueProvider
            self.metadataValueProvider = metadataValueProvider
            self.canonicalProjectProvider = canonicalProjectProvider
            self.canonicalBatchProvider = canonicalBatchProvider
            self.canonicalSampleProvider = canonicalSampleProvider
            self.canonicalDeviceProvider = canonicalDeviceProvider
            self.canonicalMeasurementProvider = canonicalMeasurementProvider
            self.canonicalDatasetProvider = canonicalDatasetProvider
            self.measurementNotesProvider = measurementNotesProvider
            self.defaultResultSummaryProvider = defaultResultSummaryProvider
        }

        func normalizedValue(_ value: String?) -> String? {
            MainActor.assumeIsolated {
                normalizedValueProvider(value)
            }
        }

        func metadataValue(in lookup: SampleRegistryLookupResult?, keys: [String]) -> String? {
            MainActor.assumeIsolated {
                metadataValueProvider(lookup, keys)
            }
        }

        func canonicalProject(named name: String) -> SpinLabDomain.Project? {
            MainActor.assumeIsolated {
                canonicalProjectProvider(name)
            }
        }

        func createProject(named name: String) -> String? {
            nil
        }

        func canonicalBatch(named name: String) -> SpinLabDomain.Batch? {
            MainActor.assumeIsolated {
                canonicalBatchProvider(name)
            }
        }

        func canonicalSample(named name: String) -> SpinLabDomain.Sample? {
            MainActor.assumeIsolated {
                canonicalSampleProvider(name)
            }
        }

        func canonicalDevice(named name: String, sampleID: UUID) -> SpinLabDomain.Device? {
            MainActor.assumeIsolated {
                canonicalDeviceProvider(name, sampleID)
            }
        }

        func canonicalMeasurement(forSourcePath path: String) -> SpinLabDomain.Measurement? {
            MainActor.assumeIsolated {
                canonicalMeasurementProvider(path)
            }
        }

        func canonicalDataset(forSourcePath path: String) -> SpinLabDomain.Dataset? {
            MainActor.assumeIsolated {
                canonicalDatasetProvider(path)
            }
        }

        func measurementNotes(
            for pending: SpinLabDomain.PendingImport,
            draft: PendingImportConfirmationDraft,
            registryLookup: SampleRegistryLookupResult?
        ) -> String {
            MainActor.assumeIsolated {
                measurementNotesProvider(pending, draft, registryLookup)
            }
        }

        func defaultResultSummary(for measurement: SpinLabDomain.Measurement) -> String {
            MainActor.assumeIsolated {
                defaultResultSummaryProvider(measurement)
            }
        }
    }

    var selectedArea: AppArea = .inbox {
        didSet { persistInteractionSnapshotIfReady() }
    }
    var inbox: InboxFeatureStore { inboxFeatureStore }
    var registry: RegistryFeatureStore { registryFeatureStore }
    var library: LibraryFeatureStore { libraryFeatureStore }
    var workbench: WorkbenchFeatureStore { workbenchFeatureStore }

    var selectedPendingImportID: UUID? {
        get { inboxFeatureStore.selectedPendingImportID }
        set {
            inboxFeatureStore.selectedPendingImportID = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    var librarySelectedPrefix: String? {
        get { libraryFeatureStore.librarySelectedPrefix }
        set {
            libraryFeatureStore.librarySelectedPrefix = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    var librarySelectedBatchId: String? {
        get { libraryFeatureStore.librarySelectedBatchId }
        set {
            libraryFeatureStore.librarySelectedBatchId = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    var librarySelectedSampleId: String? {
        get { libraryFeatureStore.librarySelectedSampleId }
        set {
            libraryFeatureStore.librarySelectedSampleId = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    var libraryActiveSelectionSource: LibrarySelectionSource {
        get { libraryFeatureStore.libraryActiveSelectionSource }
        set {
            libraryFeatureStore.libraryActiveSelectionSource = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    var activeAlert: AppAlertState?
    private(set) var appStateRevision: Int = 0
    let workflow: SpinLabDomain.WorkflowKind

    private let persistence: SpinLabPersistence
    private let inboxRepository: InboxRepository
    private let libraryRepository: LibraryRepository
    private let importPipeline: SpinLabImportPipeline
    private let archivedRecordResolverService: ArchivedRecordResolverService
    private let analysisModule: AnalysisModuleExtension
    private let viewExtension: ViewExtension
    private let managedStorage: SpinLabManagedStorage
    private var sampleRegistry: SampleRegistryIndexing
    private let inboxFeatureStore: InboxFeatureStore
    private var registryFeatureStore: RegistryFeatureStore
    private let libraryFeatureStore: LibraryFeatureStore
    private let workbenchFeatureStore: WorkbenchFeatureStore
    private let appLogger = AppLogger.shared
    private let interactionSnapshotCoordinator: InteractionSnapshotCoordinator
    private let dataActor: any SpinLabDataActing
    private let registryLifecycleService = RegistryLifecycleService()
    private let registryCoordinator = RegistryCoordinator()
    @ObservationIgnored
    private lazy var registryFacade = RegistryFacade(
        managedStorage: managedStorage,
        registryLifecycleService: registryLifecycleService,
        registryCoordinator: registryCoordinator,
        dataActor: dataActor,
        appLogger: appLogger,
        currentLibrarySettings: { [unowned self] in
            libraryFeatureStore.librarySettings
        },
        resolveRegistrySourceURL: { [unowned self] in
            resolveRegistrySourceURL()
        },
        onApplyRegistryContext: { [unowned self] context in
            applyLoadedRegistryContext(context)
        },
        onPresentError: { [unowned self] error, title in
            present(error: error, title: title)
        },
        onForwardLoad: { [unowned self] url in
            loadSampleRegistry(from: url)
        }
    )
    private let inboxWorkflowService = InboxWorkflowService()
    @ObservationIgnored
    private lazy var inboxFacade = InboxFacade(
        inboxWorkflowService: inboxWorkflowService,
        inboxStore: inboxFeatureStore,
        managedStorage: managedStorage,
        importPipeline: importPipeline,
        existingImportedOriginalPaths: { [unowned self] in
            existingImportedOriginalPaths()
        },
        syncInboxWorkspaceToPendingImports: { [unowned self] in
            syncInboxWorkspaceToPendingImports()
        },
        persistInteractionSnapshotIfReady: { [unowned self] in
            persistInteractionSnapshotIfReady()
        },
        selectFirstImportedPendingAndFocusInbox: { [unowned self] pendingID in
            selectedPendingImportID = pendingID
            selectedArea = .inbox
        },
        refreshRoutingRuleMetadata: { [unowned self] in
            refreshRoutingRuleMetadata(forceReload: true)
        },
        readInboxWorkspace: { [unowned self] in
            interactionValue(\.inboxWorkspaceByPendingID)
        },
        writeInboxWorkspace: { [unowned self] workspace in
            updateInteractionValue(\.inboxWorkspaceByPendingID, to: workspace)
        },
        recomputedParsedHints: { [unowned self] pending in
            recomputedParsedHints(for: pending)
        },
        pendingDisplayDraft: { [unowned self] pending in
            pendingDisplayDraft(for: pending)
        },
        bumpAppStateRevision: { [unowned self] in
            bumpAppStateRevision()
        }
    )
    private let libraryPreviewComputationService = LibraryPreviewComputationService()
    private let libraryMutationOrchestrator = LibraryMutationOrchestrator()
    private let libraryMutationService = LibraryMutationService()
    @ObservationIgnored
    private lazy var libraryCommandCoordinator = LibraryCommandCoordinator(
        featureStore: libraryFeatureStore,
        mutationService: libraryMutationService,
        orchestrator: libraryMutationOrchestrator
    )
    @ObservationIgnored
    private lazy var libraryFacade = LibraryFacade(
        featureStore: libraryFeatureStore,
        commandCoordinator: libraryCommandCoordinator,
        saveLibrarySampleEditsUseCase: saveLibrarySampleEditsUseCase,
        appLogger: appLogger,
        resolveRegistrySourceURL: { [weak self] in
            self?.resolveRegistrySourceURL()
        },
        applyExistingIndex: { [weak self] index in
            self?.applyExistingIndex(index)
        },
        refreshActionablePreviewGroups: { [weak self] diff, baseline in
            self?.refreshActionablePreviewGroups(precomputedDiff: diff, baselineIndex: baseline)
        },
        commitLibraryMutation: { [weak self] rootURL, previewIndex in
            self?.commitLibraryMutation(rootURL: rootURL, previewIndex: previewIndex)
        },
        loadExistingDrawers: { [weak self] in
            self?.loadExistingDrawers()
        },
        presentError: { [weak self] error, title in
            self?.present(error: error, title: title)
        }
    )
    private let coordinator = AppCoordinator()
    private let confirmPendingImportUseCase = ConfirmPendingImportUseCase()
    private let saveLibrarySampleEditsUseCase = SaveLibrarySampleEditsUseCase()
    @ObservationIgnored
    private lazy var archivedRecordDomainContext: SpinLabDomainContext = ArchivedRecordDomainContextAdapter(
        normalizedValueProvider: { [weak self] value in
            self?.normalized(value)
        },
        metadataValueProvider: { [weak self] lookup, keys in
            self?.archivedRecordResolverService.metadataValue(in: lookup, keys: keys)
        },
        canonicalProjectProvider: { [weak self] name in
            self?.workbenchFeatureStore.canonicalProject(named: name)
        },
        canonicalBatchProvider: { [weak self] name in
            self?.workbenchFeatureStore.canonicalBatch(named: name)
        },
        canonicalSampleProvider: { [weak self] name in
            self?.workbenchFeatureStore.canonicalSample(named: name)
        },
        canonicalDeviceProvider: { [weak self] name, sampleID in
            self?.workbenchFeatureStore.canonicalDevice(named: name, sampleID: sampleID)
        },
        canonicalMeasurementProvider: { [weak self] path in
            self?.workbenchFeatureStore.canonicalMeasurement(forSourcePath: path)
        },
        canonicalDatasetProvider: { [weak self] path in
            self?.workbenchFeatureStore.canonicalDataset(forSourcePath: path)
        },
        measurementNotesProvider: { [weak self] pending, draft, lookup in
            self?.archivedRecordResolverService.measurementNotes(
                for: pending,
                draft: draft,
                registryLookup: lookup
            ) ?? ""
        },
        defaultResultSummaryProvider: { [weak self] measurement in
            self?.analysisModule.defaultResultSummary(for: measurement) ?? ""
        }
    )
    private var librarySyncService: LibrarySyncService { libraryFeatureStore.librarySyncService }
    private var libraryState: LibraryState {
        get { libraryFeatureStore.libraryState }
        set { libraryFeatureStore.libraryState = newValue }
    }
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
        self.archivedRecordResolverService = ArchivedRecordResolverService(registrySubstrateRules: environment.registrySubstrateRules)
        self.inboxFeatureStore = InboxFeatureStore(
            inboxRepository: self.inboxRepository,
            routingCapabilities: environment.routingCapabilities,
            ruleRuntime: environment.ruleRuntime
        )
        self.registryFeatureStore = RegistryFeatureStore()
        self.libraryFeatureStore = LibraryFeatureStore()
        self.workbenchFeatureStore = WorkbenchFeatureStore(libraryRepository: self.libraryRepository)
        let interactionMemory = InteractionMemoryStore(persistence: environment.persistence)
        self.interactionSnapshotCoordinator = InteractionSnapshotCoordinator(interactionMemory: interactionMemory)
        self.dataActor = environment.dataActor

        if !self.sampleRegistry.isLoaded, let currentRegistryURL = environment.managedStorage.currentSampleRegistryFileURL() {
            self.sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(currentRegistryURL, previewRowCount: 10)
        }

        load()
        setupRepositoryProjectionTasks()
        migrateManagedMeasurementPathsToOriginalIfPossible()
        managedStorage.clearManagedMeasurementCopies()
        registryFeatureStore.applyPresentation(
            registryCoordinator.makePresentation(
                sampleRegistry: sampleRegistry,
                registryLifecycleService: registryLifecycleService
            )
        )
        refreshRoutingRuleMetadata(forceReload: false)
        loadExistingDrawers()
        restoreInteractionSnapshot()
        refreshPendingDrawerMatches()
        libraryFeatureStore.refreshLibraryBackupMessage(formatSyncDate: { Self.syncStatusTimeFormatter.string(from: $0) })
        interactionSnapshotCoordinator.markReady()
        persistInteractionSnapshotIfReady()
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
        inboxFeatureStore.pendingImports.first { $0.id == selectedPendingImportID }
    }

    var selectedArchivedRecord: SpinLabDomain.ArchivedRecord? {
        workbenchFeatureStore.selectedArchivedRecord()
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
        registryFacade.canReloadSampleRegistry()
    }

    var pendingDrawerMatchByID: [UUID: Bool] {
        Dictionary(uniqueKeysWithValues: inboxFeatureStore.pendingImports.map { pending in
            let presentation = pendingRoutePresentation(for: pending)
            return (pending.id, presentation.isLibraryMatched)
        })
    }

    var knownProjectNames: [String] {
        let archivedNames = workbenchFeatureStore.archivedRecords.compactMap { $0.project?.name }
        let catalogNames = workbenchFeatureStore.projectCatalog.map(\.name)
        return Array(Set(archivedNames + catalogNames)).sorted()
    }

    func navigate(to routeStack: AppRouteStack) {
        let router = AppRouter()
        router.navigate(to: routeStack) { [weak self] route in
            self?.navigate(to: route)
        }
    }

    func openDeepLink(_ path: String) -> Bool {
        let router = AppRouter()
        guard let stack = router.deepLinkToRouteStack(path) else {
            return false
        }
        navigate(to: stack)
        return true
    }

    func navigate(to route: AppRoutePath) {
        switch route {
        case .inbox:
            selectedArea = .inbox
        case .workbench:
            selectedArea = .workbench
        case .library:
            selectedArea = .library
        case let .libraryDrawer(prefix, batchId, sampleId):
            selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
            selectedArea = .library
        }
    }

    func hasExistingLibraryDrawer(sampleKey: String) -> Bool {
        matchedExistingLibraryDrawer(sampleInput: sampleKey) != nil
    }

    func matchedExistingLibraryDrawer(sampleInput: String) -> String? {
        inboxFeatureStore.matchedExistingLibraryDrawer(sampleInput: sampleInput)
    }

    func refreshPendingDrawerMatches(for pendingIDs: [UUID]? = nil) {
        inboxFeatureStore.refreshPendingDrawerMatches(for: pendingIDs)
    }

    func pendingRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
        inboxFeatureStore.pendingRoutingSnapshot(for: pending)
    }

    func cachedPendingRoutingSnapshot(for pendingID: UUID) -> SpinLabDomain.PendingRoutingSnapshot? {
        inboxFeatureStore.cachedPendingRoutingSnapshot(for: pendingID)
    }

    private func refreshRoutingRuleMetadata(forceReload: Bool) {
        registryFacade.refreshRoutingRuleMetadata(inboxStore: inboxFeatureStore, forceReload: forceReload)
    }

    var registryPrefixMap: [String: String] {
        sampleRegistry.prefixToSheet
    }

    private func load() {
        applyPendingImportsProjection(inboxFeatureStore.pendingImports)
        applyArchivedRecordsProjection(workbenchFeatureStore.archivedRecords)
        applyProjectCatalogProjection(workbenchFeatureStore.projectCatalog)
        if let selectedArchivedRecord {
            _ = workbenchFeatureStore.selectArchivedRecord(selectedArchivedRecord.id, analysisModule: analysisModule)
        } else {
            workbenchFeatureStore.workbenchResultDraft = ""
        }
        inboxFeatureStore.clearPendingState()
    }

    private func replacePendingImports(_ imports: [SpinLabDomain.PendingImport], persist: Bool = true) {
        _ = inboxFeatureStore.replacePendingImports(imports, persist: persist)
        syncInboxWorkspaceToPendingImports()
        persistInteractionSnapshotIfReady()
    }

    private func replaceArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord], persist: Bool = true) {
        let updated = workbenchFeatureStore.replaceArchivedRecords(records, persist: persist)
        applyArchivedRecordsProjection(updated)
    }

    private func setupRepositoryProjectionTasks() {
        inboxFeatureStore.setupProjectionTask { [weak self] in
            guard let self else { return }
            syncInboxWorkspaceToPendingImports()
            persistInteractionSnapshotIfReady()
        }

        workbenchFeatureStore.setupProjectionTasks(
            onArchivedRecordsProjected: { [weak self] records in
                self?.applyArchivedRecordsProjection(records)
            },
            onProjectCatalogProjected: { [weak self] projects in
                self?.applyProjectCatalogProjection(projects)
            }
        )
    }

    private func applyPendingImportsProjection(_ imports: [SpinLabDomain.PendingImport]) {
        inboxFeatureStore.projectPendingImports(imports)
        syncInboxWorkspaceToPendingImports()
        persistInteractionSnapshotIfReady()
    }

    private func syncInboxWorkspaceToPendingImports() {
        let prunedWorkspace = inboxFeatureStore.pruneWorkspaceByValidPendingIDs(
            interactionValue(\.inboxWorkspaceByPendingID)
        )
        updateInteractionValue(\.inboxWorkspaceByPendingID, to: prunedWorkspace)
    }

    private func applyArchivedRecordsProjection(_ records: [SpinLabDomain.ArchivedRecord]) {
        workbenchFeatureStore.archivedRecords = records
        if let selectedArchivedRecordID = workbenchFeatureStore.selectedArchivedRecordID,
           !records.contains(where: { $0.id == selectedArchivedRecordID }) {
            workbenchFeatureStore.selectedArchivedRecordID = records.first?.id
        } else if workbenchFeatureStore.selectedArchivedRecordID == nil {
            workbenchFeatureStore.selectedArchivedRecordID = records.first?.id
        }
    }

    private func applyProjectCatalogProjection(_ projects: [SpinLabDomain.Project]) {
        workbenchFeatureStore.projectCatalog = projects
    }

    private func migrateManagedMeasurementPathsToOriginalIfPossible() {
        let fileManager = FileManager.default
        var pendingChanged = false
        var archivedChanged = false

        let migratedPendingImports = inboxFeatureStore.pendingImports.map { pending in
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

        let migratedArchivedRecords = workbenchFeatureStore.archivedRecords.map { record in
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
        interactionSnapshotCoordinator.value(keyPath)
    }

    func updateInteractionValue<Value>(_ keyPath: WritableKeyPath<SpinLabInteractionSnapshot, Value>, to value: Value) {
        interactionSnapshotCoordinator.updateValue(keyPath, to: value)
    }

    func interactionEntryValue<Value>(
        for id: UUID,
        in keyPath: KeyPath<SpinLabInteractionSnapshot, [String: Value]>
    ) -> Value? {
        interactionSnapshotCoordinator.entryValue(for: id, in: keyPath)
    }

    func updateInteractionEntryValue<Value>(
        for id: UUID,
        in keyPath: WritableKeyPath<SpinLabInteractionSnapshot, [String: Value]>,
        value: Value?
    ) {
        interactionSnapshotCoordinator.updateEntryValue(for: id, in: keyPath, value: value)
    }

    private func restoreInteractionSnapshot() {
        interactionSnapshotCoordinator.restoreAll(
            selectedAreaSetter: { [weak self] in self?.selectedArea = $0 },
            inboxStore: inboxFeatureStore,
            libraryStore: libraryFeatureStore,
            workbenchStore: workbenchFeatureStore
        )
        libraryFeatureStore.normalizeLibrarySelection()
    }

    private func persistInteractionSnapshotIfReady() {
        interactionSnapshotCoordinator.captureAll(
            selectedArea: selectedArea,
            inboxStore: inboxFeatureStore,
            libraryStore: libraryFeatureStore,
            workbenchStore: workbenchFeatureStore
        )
    }

    func importFiles(from urls: [URL]) {
        inboxFacade.importFiles(from: urls)
    }

    func clearPendingImports() {
        inboxFacade.clearPendingImports()
    }

    func recomputeAllPendingParsedHints() {
        inboxFacade.recomputeAllPendingParsedHints()
    }

    func loadSampleRegistry(from url: URL) {
        registryFacade.loadSampleRegistry(from: url)
    }

    func reloadSampleRegistry() {
        registryFacade.reloadSampleRegistry()
    }

    private func applyLoadedRegistryContext(_ context: RegistryLoadContext) {
        sampleRegistry = context.registryState
        updateLibraryRegistryPaths(installedURL: context.installedURL, sourceURL: context.sourceURL)
        libraryFeatureStore.libraryPreview = nil
        libraryFeatureStore.libraryPreviewWarnings = []
        libraryFeatureStore.libraryPreviewMessage = nil
        libraryFeatureStore.librarySyncStatusMessage = nil
        registryFeatureStore.applyPresentation(context.presentation)
        refreshPendingDrawerMatches()
    }

    private func resolvedLibraryRegistryPath() -> String? {
        let fileManager = FileManager.default
        let sourcePath = libraryFeatureStore.librarySettings.registrySourcePath
        let internalPath = libraryFeatureStore.librarySettings.registryInternalPath ?? managedStorage.currentSampleRegistryFileURL()?.path
        if let sourcePath, fileManager.fileExists(atPath: sourcePath) {
            return sourcePath
        }
        return internalPath
    }

    func loadLibraryPreview() {
        libraryFeatureStore.loadLibraryPreview(
            resolvedRegistryPath: resolvedLibraryRegistryPath(),
            dataActor: dataActor,
            refreshActionablePreviewGroups: { [weak self] in
                self?.refreshActionablePreviewGroups()
            },
            onFailure: { [weak self] appError in
                guard let self else { return }
                present(error: appError, title: "Preview Load Failed")
                appLogger.warning(.library, "Library preview load failed", metadata: ["error": appError.localizedDescription])
            }
        )
    }

    func syncLibraryFromRegistry(onComplete: (() -> Void)? = nil) {
        appLogger.info(.function, "Library sync requested", metadata: ["area": "registry"])
        let resolvedPath = resolvedLibraryRegistryPath()
        libraryFeatureStore.syncLibraryFromRegistry(
            resolvedRegistryPath: resolvedPath,
            dataActor: dataActor,
            prepareLibrarySyncReview: { [weak self] in
                self?.prepareLibrarySyncReview()
            },
            refreshActionablePreviewGroups: { [weak self] in
                self?.refreshActionablePreviewGroups()
            },
            formatSyncDate: { Self.syncStatusTimeFormatter.string(from: $0) },
            onFailure: { [weak self] appError in
                guard let self else { return }
                present(error: appError, title: "Sync Preview Failed")
                appLogger.warning(.library, "Library sync preview failed", metadata: ["error": appError.localizedDescription])
            },
            onComplete: onComplete
        )
        if resolvedPath == nil {
            appLogger.warning(.library, "Library preview unavailable during sync request")
        }
    }

    func applyPreparedLibrarySyncReview() {
        switch libraryFeatureStore.applyPreparedSyncReviewDecision() {
        case let .missingReview(message):
            libraryFeatureStore.libraryDrawerError = message
            appLogger.warning(.library, "Apply all skipped: no sync review")
        case let .noChanges(message):
            libraryFeatureStore.libraryDrawerMessage = message
            appLogger.info(.library, "Apply all skipped: no pending changes")
        case let .apply(totalChanges):
            appLogger.info(.function, "Apply all requested", metadata: [
                "changes": "\(totalChanges)"
            ])
            refreshLibraryIncremental()
        }
    }

    func applySelectedRegistryDiff(batchId: String?) {
        switch libraryFeatureStore.applySelectedRegistryDiff(batchId: batchId) {
        case let .failure(message):
            appLogger.warning(.library, "Apply selected failed", metadata: [
                "batchId": batchId ?? "-",
                "reason": message
            ])
        case let .noPendingChanges(id, _):
            appLogger.info(.library, "Apply selected skipped: no pending changes", metadata: ["batchId": id])
        case let .success(rootURL, previewIndex, id, action, touched, _):
            commitLibraryMutation(rootURL: rootURL, previewIndex: previewIndex)
            libraryFeatureStore.libraryDrawerMessage = "Applied selected sync for \(id): \(action), \(touched) sample changes."
            appLogger.info(.function, "Apply selected completed", metadata: [
                "batchId": id,
                "action": action,
                "sampleChanges": "\(touched)"
            ])
        }
    }

    func loadExistingDrawers() {
        guard let index = libraryFeatureStore.loadExistingDrawersIndexForCurrentRoot() else {
            libraryFeatureStore.libraryExistingGroups = [:]
            inboxFeatureStore.clearDrawerMatchCandidates()
            libraryFeatureStore.libraryExistingMessage = "No Library Root selected."
            librarySelectedPrefix = nil
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            refreshPendingDrawerMatches()
            return
        }
        applyExistingIndex(index)
    }

    func validateLibraryCacheOnAppear() {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath else {
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard libraryFeatureStore.libraryStore.needsIndexRefresh(rootURL: rootURL) else {
            return
        }
        syncLibraryFromFiles()
    }

    func syncLibraryFromFiles() {
        libraryFacade.syncLibraryFromFiles()
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) {
        let outcome = libraryFeatureStore.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
        handleLibrarySelectionChangeOutcome(outcome)
    }

    func selectBrowserSample() {
        let outcome = libraryFeatureStore.selectBrowserSample()
        handleLibrarySelectionChangeOutcome(outcome)
    }

    func saveAndContinuePendingLibrarySelectionChange() {
        guard libraryFeatureStore.hasPendingSelectionChange() else {
            return
        }
        saveLibrarySampleEdits()
        guard libraryFeatureStore.librarySampleEditError == nil else {
            return
        }
        if let outcome = libraryFeatureStore.applyPendingSelectionChangeIfNeeded() {
            handleLibrarySelectionChangeOutcome(outcome)
        }
    }

    func discardAndContinuePendingLibrarySelectionChange() {
        guard libraryFeatureStore.hasPendingSelectionChange() else {
            return
        }
        libraryFeatureStore.discardEditingSelectedLibrarySample()
        if let outcome = libraryFeatureStore.applyPendingSelectionChangeIfNeeded() {
            handleLibrarySelectionChangeOutcome(outcome)
        }
    }

    func cancelPendingLibrarySelectionChange() {
        libraryFeatureStore.cancelPendingSelectionChange()
    }

    func hasPendingLibrarySelectionChange() -> Bool {
        libraryFeatureStore.hasPendingSelectionChange()
    }

    private func handleLibrarySelectionChangeOutcome(_ outcome: LibraryFeatureStore.SelectionChangeOutcome) {
        switch outcome {
        case .deferred:
            break
        case let .appliedDrawer(prefix, batchId, sampleId):
            appLogger.info(.ui, "Existing drawer selected", metadata: [
                "prefix": prefix,
                "batchId": batchId,
                "sampleId": sampleId ?? "-"
            ])
        case let .appliedBrowser(prefix, batchId, sampleId):
            appLogger.info(.usage, "Pending browser selection updated", metadata: [
                "prefix": prefix ?? "-",
                "batchId": batchId ?? "-",
                "sampleId": sampleId ?? "-"
            ])
        }
    }

    func deleteExistingDrawer(batchId: String) {
        libraryFacade.deleteExistingDrawer(batchId: batchId)
    }

    func beginEditingSelectedLibrarySample() {
        let sample = libraryActiveSelectionSource == .drawer ? libraryFeatureStore.selectedExistingDrawerSample() : nil
        libraryFeatureStore.beginEditingSelectedLibrarySample(selectedSample: sample)
    }

    func cancelEditingSelectedLibrarySample() {
        libraryFeatureStore.cancelEditingSelectedLibrarySample()
    }

    func updateLibrarySampleEditSubstrateTags(_ value: String) {
        libraryFeatureStore.updateLibrarySampleEditSubstrateTags(value)
    }

    func updateLibrarySampleEditNumericValue(key: String, value: String) {
        libraryFeatureStore.updateLibrarySampleEditNumericValue(key: key, value: value)
    }

    func updateLibrarySampleEditMetadataValue(key: String, value: String) {
        libraryFeatureStore.updateLibrarySampleEditMetadataValue(key: key, value: value)
    }

    func librarySampleChangeLog(for sample: LibrarySample) -> [LibrarySampleChangeLogEntry] {
        libraryFeatureStore.sampleChangeLog(for: sample)
    }

    func loadLibraryGlobalManualLogs() {
        libraryFacade.loadLibraryGlobalManualLogs()
    }

    func markLibraryGlobalManualLogStatus(rowIndex: Int, status: LibraryManualLogStatus) {
        libraryFacade.markLibraryGlobalManualLogStatus(rowIndex: rowIndex, status: status)
    }

    func loadLibraryMetadataSyncLogs() {
        libraryFacade.loadLibraryMetadataSyncLogs()
    }

    func saveLibrarySampleEdits() {
        libraryFacade.saveLibrarySampleEdits()
    }

    func prepareLibrarySyncReview(precomputedDiff: LibraryDiff? = nil) {
        libraryFacade.prepareLibrarySyncReview(precomputedDiff: precomputedDiff)
    }

    func refreshLibraryIncremental() {
        libraryFacade.refreshLibraryIncremental()
    }

    func confirmLibraryNumericRefreshChanges() {
        libraryFacade.confirmLibraryNumericRefreshChanges()
    }

    func createDrawersFromPreview() {
        libraryFacade.createDrawersFromPreview()
    }

    func createDrawersForSelection(batchId: String?, sampleId: String?) {
        libraryFacade.createDrawersForSelection(batchId: batchId, sampleId: sampleId)
    }

    func updateLibraryRoot(to url: URL) {
        libraryFeatureStore.updateLibraryRoot(to: url)
        loadExistingDrawers()
    }

    func updateLibraryBackupPath(to url: URL) {
        libraryFeatureStore.updateLibraryBackupPath(to: url)
    }

    func updateAllowedBatchPrefixes(from rawValue: String) {
        libraryFeatureStore.updateAllowedBatchPrefixes(from: rawValue)
    }

    func verifyLibraryRoot() {
        libraryFeatureStore.verifyLibraryRoot()
    }

    func syncLibraryBackup() {
        libraryFeatureStore.syncLibraryBackup(formatSyncDate: { Self.syncStatusTimeFormatter.string(from: $0) })
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
            archivedRecords: workbenchFeatureStore.archivedRecords
        ),
        workbenchFeatureStore.selectArchivedRecord(route.archivedRecordID, analysisModule: analysisModule) else {
            return
        }
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
        return inboxFeatureStore.pendingRoutePresentation(
            for: pending,
            substrateWarning: substrate
        )
    }

    func pendingRoutePresentationByID() -> [UUID: PendingRoutePresentation] {
        inboxFeatureStore.pendingRoutePresentationByID(
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
        inboxFeatureStore.pendingRoutePlan(for: pending)
    }

    func pendingRouteStatus(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.RouteStatus {
        inboxFeatureStore.pendingRouteStatus(for: pending)
    }

    func hasSavedRoutingDraft(for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxFeatureStore.hasSavedRoutingDraft(for: pending)
    }

    func routingDraft(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxFeatureStore.routingDraft(for: pending)
    }

    func routingDraftBaseline(for pending: SpinLabDomain.PendingImport) -> PendingRoutingDraft {
        inboxFeatureStore.routingDraftBaseline(for: pending)
    }

    func isRoutingDraftDirty(_ draft: PendingRoutingDraft, for pending: SpinLabDomain.PendingImport) -> Bool {
        inboxFeatureStore.isRoutingDraftDirty(draft, for: pending)
    }

    func saveRoutingDraft(_ draft: PendingRoutingDraft, for pendingID: UUID) {
        inboxFeatureStore.saveRoutingDraft(draft, for: pendingID)
        bumpAppStateRevision()
    }

    func confirmSelectedPendingImport(with draft: PendingImportConfirmationDraft) {
        confirmSelectedPendingImport(with: draft, editedFileContents: nil)
    }

    func confirmSelectedPendingImport(with draft: PendingImportConfirmationDraft, editedFileContents: String?) {
        let outcome = inboxWorkflowService.confirmPendingImport(
            selectedPending: selectedPendingImport,
            draft: draft,
            editedFileContents: editedFileContents,
            savePendingImportContents: { contents, pending in
                try savePendingImportContents(contents, for: pending)
            },
            inboxStore: inboxFeatureStore,
            confirmUseCase: confirmPendingImportUseCase,
            libraryRepository: libraryRepository,
            makeArchivedRecord: { pending, draft in
                let lookup = registryLookup(for: pending)
                return makeArchivedRecord(from: pending, draft: draft, registryLookup: lookup)
            },
            coordinator: coordinator
        )

        switch outcome {
        case .skipped:
            return
        case let .failure(pending, error, phase):
            switch phase {
            case .saveEditedFile:
                appLogger.error(.import, "Failed to persist edited pending contents", metadata: [
                    "pendingID": pending.id.uuidString,
                    "fileName": pending.fileName
                ])
                present(error: error, title: "Save Failed")
            case .confirm:
                appLogger.error(.import, "Pending import confirmation failed", metadata: [
                    "pendingID": pending.id.uuidString,
                    "fileName": pending.fileName,
                    "reason": error.localizedDescription
                ])
                present(error: error, title: "Import Failed")
            }
        case let .success(success):
            applyArchivedRecordsProjection(success.output.archivedRecords)
            updateInteractionEntryValue(for: success.clearWorkspaceEntryPendingID, in: \.inboxWorkspaceByPendingID, value: nil)
            _ = workbenchFeatureStore.selectArchivedRecord(success.selectArchivedRecordID, analysisModule: analysisModule)
            selectedPendingImportID = success.route.nextPendingID
            selectedArea = success.route.selectedArea
            appLogger.info(.import, "Pending import confirmed", metadata: [
                "pendingID": success.confirmedPending.id.uuidString,
                "archivedRecordID": success.output.archivedRecord.id.uuidString,
                "measurementID": success.output.archivedRecord.measurement.id.uuidString,
                "workflow": workflow.rawValue
            ])
        }
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
        guard let updated = workbenchFeatureStore.saveWorkbenchResult(analysisModule: analysisModule) else {
            return
        }
        replaceArchivedRecords(updated)
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
            libraryFeatureStore.libraryExistingGroups = [:]
            inboxFeatureStore.clearDrawerMatchCandidates()
            libraryFeatureStore.libraryExistingMessage = "No existing drawers found."
            librarySelectedPrefix = nil
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            libraryFeatureStore.librarySampleEditDraft = nil
            libraryState.sampleEditBaseSample = nil
            libraryState.sampleEditOriginalDraft = nil
            refreshPendingDrawerMatches()
            return
        }

        libraryFeatureStore.libraryExistingGroups = buildPreviewGroups(from: index)
        inboxFeatureStore.rebuildDrawerMatchCandidates(from: index.samples)
        libraryFeatureStore.libraryExistingMessage = "Loaded existing drawers: \(index.samples.count) samples"
        libraryFeatureStore.normalizeLibrarySelection()
        libraryFeatureStore.reconcileLibrarySampleEditingSelection()
        refreshPendingDrawerMatches()
    }

    private func updateLibraryRegistryPaths(installedURL: URL, sourceURL: URL?) {
        libraryFeatureStore.librarySettings.registryInternalPath = installedURL.path
        libraryFeatureStore.librarySettings.registrySourcePath = sourceURL?.path
        libraryFeatureStore.librarySettingsStore.save(libraryFeatureStore.librarySettings)
    }

    private func buildPreviewGroups(from preview: LibraryPreview) -> [String: [LibraryPreviewBatchGroup]] {
        buildPreviewGroups(from: preview.index)
    }

    private func buildPreviewGroups(from index: LibraryIndex) -> [String: [LibraryPreviewBatchGroup]] {
        libraryPreviewComputationService.buildPreviewGroups(from: index)
    }

    private func refreshActionablePreviewGroups(precomputedDiff: LibraryDiff? = nil, baselineIndex: LibraryIndex? = nil) {
        guard let preview = libraryFeatureStore.libraryPreview else {
            libraryFeatureStore.libraryPreviewGroups = [:]
            libraryFeatureStore.libraryPreviewMessage = "No preview loaded."
            return
        }
        let state = libraryMutationOrchestrator.buildActionablePreviewState(
            preview: preview,
            precomputedDiff: precomputedDiff,
            baselineIndex: baselineIndex,
            rootPath: libraryFeatureStore.librarySettings.rootPath,
            libraryStore: libraryFeatureStore.libraryStore,
            libraryDiffEngine: libraryFeatureStore.libraryDiffEngine,
            previewComputationService: libraryPreviewComputationService
        )
        libraryFeatureStore.libraryPreviewGroups = state.groups
        libraryFeatureStore.libraryPreviewMessage = state.message
    }

    private func commitLibraryMutation(
        rootURL: URL,
        previewIndex: LibraryIndex?,
        precomputedDiff: LibraryDiff? = nil,
        precomputedReview: LibraryRefreshReview? = nil
    ) {
        let outcome = libraryMutationService.commitMutation(
            rootURL: rootURL,
            previewIndex: previewIndex,
            precomputedDiff: precomputedDiff,
            precomputedReview: precomputedReview,
            libraryStore: libraryFeatureStore.libraryStore,
            libraryDiffEngine: libraryFeatureStore.libraryDiffEngine,
            librarySyncService: librarySyncService,
            orchestrator: libraryMutationOrchestrator
        )
        applyExistingIndex(outcome.syncedIndex)

        libraryFeatureStore.libraryRefreshReview = outcome.plan.review
        libraryFeatureStore.refreshSyncChangeIndicators(using: libraryMutationService)
        if let diff = outcome.plan.diff, let baseline = outcome.plan.baselineIndexForPreview {
            refreshActionablePreviewGroups(precomputedDiff: diff, baselineIndex: baseline)
        } else {
            refreshActionablePreviewGroups()
        }

        libraryFeatureStore.librarySettings.lastRefreshAt = outcome.plan.lastRefreshAt
        libraryFeatureStore.librarySettingsStore.save(libraryFeatureStore.librarySettings)
    }

    private static let syncStatusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

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

    private func savePendingImportContents(_ contents: String, for pending: SpinLabDomain.PendingImport) throws {
        try contents.write(to: URL(fileURLWithPath: pending.sourceFilePath), atomically: true, encoding: .utf8)
    }

    private func resolveRegistrySourceURL() -> URL? {
        let fileManager = FileManager.default
        if let sourcePath = libraryFeatureStore.librarySettings.registrySourcePath, fileManager.fileExists(atPath: sourcePath) {
            return URL(fileURLWithPath: sourcePath)
        }
        if let internalPath = libraryFeatureStore.librarySettings.registryInternalPath, fileManager.fileExists(atPath: internalPath) {
            return URL(fileURLWithPath: internalPath)
        }
        if let current = managedStorage.currentSampleRegistryFileURL(), fileManager.fileExists(atPath: current.path) {
            return current
        }
        return nil
    }

    private func existingImportedOriginalPaths() -> Set<String> {
        var paths: Set<String> = []

        for pending in inboxFeatureStore.pendingImports {
            if let original = pending.originalFilePath {
                paths.insert(normalizedPath(original))
            }
        }

        for record in workbenchFeatureStore.archivedRecords {
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
        archivedRecordResolverService.metadataValue(in: lookup, keys: keys)
    }

    private func measurementNotes(
        for pending: SpinLabDomain.PendingImport,
        draft: PendingImportConfirmationDraft,
        registryLookup: SampleRegistryLookupResult?
    ) -> String {
        archivedRecordResolverService.measurementNotes(
            for: pending,
            draft: draft,
            registryLookup: registryLookup
        )
    }

    private func substrateWarning(
        for pending: SpinLabDomain.PendingImport,
        registryLookup: SampleRegistryLookupResult?
    ) -> String? {
        archivedRecordResolverService.substrateWarning(
            for: pending,
            registryLookup: registryLookup
        )
    }

    private func suggestedProject(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.Project? {
        workbenchFeatureStore.suggestedProject(for: pending)
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
            "routingRuleVersion": "\(inboxFeatureStore.routingRuleVersion)",
            "routingRuleSource": inboxFeatureStore.routingRuleSourceLabel,
            "routingRulePath": inboxFeatureStore.routingRuleSourcePath,
            "routingRuleFingerprint": inboxFeatureStore.routingRuleFingerprint,
            "pendingImportCount": "\(inboxFeatureStore.pendingImports.count)",
            "archivedRecordCount": "\(workbenchFeatureStore.archivedRecords.count)",
            "selectedArea": selectedArea.rawValue
        ]
        if let selectedPendingImportID {
            context["selectedPendingImportID"] = selectedPendingImportID.uuidString
        }
        if let selectedArchivedRecordID = workbenchFeatureStore.selectedArchivedRecordID {
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
