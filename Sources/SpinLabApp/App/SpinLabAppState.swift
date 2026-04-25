import Foundation
import CryptoKit
import Observation
import SwiftUI

struct ApplyProgressState {
    var isRunning: Bool = false
    var totalCount: Int = 0
    var processedCount: Int = 0
    var appliedCount: Int = 0
    var skippedCount: Int = 0
    var failedCount: Int = 0
    var currentFileName: String = ""
}

enum PendingTagReadiness {
    case notLibraryMatched
    case allGood
    case tagsMissing([String])
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
    var workflowDefinitions: [WorkflowDefinition] = []

    var selectedPendingImportID: UUID? {
        get { inboxFeatureStore.selectedPendingImportID }
        set {
            inboxFeatureStore.selectedPendingImportID = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    var activeAlert: AppAlertState?
    private(set) var appStateRevision: Int = 0
    var applyProgressState: ApplyProgressState = .init()
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
    private var hasRestoredInteractionSnapshot = false
    private var lastLibraryCacheValidationRootPath: String?
    private var lastLibraryCacheValidationAt: Date?
    private let dataActor: any SpinLabDataActing
    private let registryLifecycleService = RegistryLifecycleService()
    @ObservationIgnored
    private var contentFingerprintCache: [String: String] = [:]
    @ObservationIgnored
    private var libraryImportedOriginalPathsCache: (rootPath: String, batchesFingerprint: String, paths: Set<String>)?
    private let registryCoordinator = RegistryCoordinator()
    @ObservationIgnored
    private lazy var registryFacade = RegistryFacade(
        managedStorage: managedStorage,
        registryLifecycleService: registryLifecycleService,
        registryCoordinator: registryCoordinator,
        dataActor: dataActor,
        appLogger: appLogger,
        currentLibrarySettings: { [weak self] in
            self?.libraryFeatureStore.librarySettings ?? .default
        },
        resolveRegistrySourceURL: { [weak self] in
            self?.resolveRegistrySourceURL()
        },
        onApplyRegistryContext: { [weak self] context in
            self?.applyLoadedRegistryContext(context)
        },
        onPresentError: { [weak self] error, title in
            self?.present(error: error, title: title)
        },
        onForwardLoad: { [weak self] url in
            self?.loadSampleRegistry(from: url)
        }
    )
    private let inboxWorkflowService = InboxWorkflowService()
    @ObservationIgnored
    private lazy var inboxFacade = InboxFacade(
        inboxWorkflowService: inboxWorkflowService,
        inboxStore: inboxFeatureStore,
        managedStorage: managedStorage,
        importPipeline: importPipeline,
        existingImportedOriginalPaths: { [weak self] in
            self?.existingImportedOriginalPaths() ?? []
        },
        existingImportedContentFingerprints: { [weak self] in
            self?.existingImportedContentFingerprints() ?? []
        },
        existingImportedFileNames: { [weak self] in
            self?.existingImportedFileNames() ?? []
        },
        syncInboxWorkspaceToPendingImports: { [weak self] in
            self?.syncInboxWorkspaceToPendingImports()
        },
        persistInteractionSnapshotIfReady: { [weak self] in
            self?.persistInteractionSnapshotIfReady()
        },
        selectFirstImportedPendingAndFocusInbox: { [weak self] pendingID in
            guard let self else { return }
            self.selectedPendingImportID = pendingID
            self.selectedArea = .inbox
        },
        refreshRoutingRuleMetadata: { [weak self] in
            self?.refreshRoutingRuleMetadata(forceReload: true)
        },
        readInboxWorkspace: { [weak self] in
            self?.interactionValue(\.inboxWorkspaceByPendingID) ?? [:]
        },
        writeInboxWorkspace: { [weak self] workspace in
            self?.updateInteractionValue(\.inboxWorkspaceByPendingID, to: workspace)
        },
        recomputedParsedHints: { [weak self] pending in
            self?.recomputedParsedHints(for: pending) ?? pending.parsedHints
        },
        conditionDefinitions: { [weak self] in
            self?.workbenchFeatureStore.conditionDefinitionOptions ?? []
        },
        pendingDisplayDraft: { [weak self] pending in
            self?.pendingDisplayDraft(for: pending) ?? PendingImportConfirmationDraft(
                batchName: "",
                sampleName: "",
                measurementName: pending.fileName,
                workflowID: "",
                conditionValues: [:],
                selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
                newProjectName: ""
            )
        },
        bumpAppStateRevision: { [weak self] in
            self?.bumpAppStateRevision()
        },
        applySelected: { [weak self] in
            self?.performApplySelectedPendingImport()
        },
        applyAll: { [weak self] in
            self?.performApplyAllPendingImports()
        }
    )
    private let libraryPreviewComputationService = LibraryPreviewComputationService()
    private let libraryMutationService = LibraryMutationService()
    private let coordinator = AppCoordinator()
    private let applyCoordinator = ApplyCoordinator()
    private let inboxArchiveApplyService = InboxArchiveApplyService()
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
        self.workbenchFeatureStore = WorkbenchFeatureStore(
            libraryRepository: self.libraryRepository,
            dataActor: environment.dataActor,
            workflowRegistryStore: environment.workflowRegistryStore,
            workflowIDAllocator: environment.workflowIDAllocator
        )
        let interactionMemory = InteractionMemoryStore(persistence: environment.persistence)
        self.interactionSnapshotCoordinator = InteractionSnapshotCoordinator(interactionMemory: interactionMemory)
        self.dataActor = environment.dataActor
        self.workflowDefinitions = self.workbenchFeatureStore.workflowDefinitions
        self.workbenchFeatureStore.onDefinitionsChanged = { [weak self] definitions in
            self?.workflowDefinitions = definitions
        }

        if !self.sampleRegistry.isLoaded, let currentRegistryURL = environment.managedStorage.currentSampleRegistryFileURL() {
            self.sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(currentRegistryURL, previewRowCount: 10)
        }

        libraryFeatureStore.configureFacade(
            mutationService: libraryMutationService,
            saveEditsUseCase: saveLibrarySampleEditsUseCase,
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
            },
            persistInteractionSnapshot: { [weak self] in
                self?.persistInteractionSnapshotIfReady()
            }
        )

        load()
        if let rootPath = libraryFeatureStore.librarySettings.rootPath, !rootPath.isEmpty {
            workbenchFeatureStore.analysisVault.configurePersistence(libraryRootPath: rootPath)
        }
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
        wireNameConflictChecker()
        loadExistingDrawers()
        restoreInteractionSnapshot()
        notifyIfRoutingRulesChanged()
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
            workbenchFeatureStore.selectedSection = .workflows
            workbenchFeatureStore.currentRoute = .registry(selectedID: nil)
        case let .workbenchWorkflow(id):
            selectedArea = .workbench
            workbenchFeatureStore.selectedSection = .workflows
            workbenchFeatureStore.selectWorkflow(id)
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

    private func wireNameConflictChecker() {
        inboxFeatureStore.inboxRoutingState.nameExistsInLibraryDrawer = { [weak self] fileName, matchedSampleID, workflowID in
            guard let self,
                  let rootPath = self.libraryFeatureStore.librarySettings.rootPath else {
                return false
            }
            let sample = self.libraryFeatureStore.libraryExistingGroups.values
                .flatMap { $0 }
                .flatMap { $0.samples }
                .first { $0.id == matchedSampleID }
            guard let sample else { return false }
            let rootURL = URL(fileURLWithPath: rootPath)
            let drawerRoot = self.libraryFeatureStore.libraryStore.drawerRootURL(for: sample, rootURL: rootURL)
            let subpath = LibraryDestinationSubpath.subpath(workflowName: workflowID)
            let destinationURL = drawerRoot
                .appending(path: subpath, directoryHint: .isDirectory)
                .appending(path: fileName, directoryHint: .notDirectory)
            return FileManager.default.fileExists(atPath: destinationURL.path)
        }
    }

    private func refreshRoutingRuleMetadata(forceReload: Bool) {
        registryFacade.refreshRoutingRuleMetadata(inboxStore: inboxFeatureStore, forceReload: forceReload)
        if hasRestoredInteractionSnapshot {
            notifyIfRoutingRulesChanged()
        }
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
        let sanitizedWorkspace = prunedWorkspace.mapValues { state in
            InboxPendingWorkspaceState.snapshotSafe(
                draft: state.draft,
                editableFileContents: state.editableFileContents,
                hasEditableFileContents: state.hasEditableFileContents,
                routingDraft: nil
            )
        }
        updateInteractionValue(\.inboxWorkspaceByPendingID, to: sanitizedWorkspace)
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
        hasRestoredInteractionSnapshot = true
    }

    private func notifyIfRoutingRulesChanged() {
        let currentFingerprint = inboxFeatureStore.routingRuleFingerprint
        let trimmedCurrent = currentFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCurrent.isEmpty, trimmedCurrent != "unknown" else {
            return
        }

        let previousFingerprint = interactionValue(\.lastSeenRoutingRuleFingerprint)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let previousFingerprint,
           !previousFingerprint.isEmpty,
           previousFingerprint != trimmedCurrent {
            presentAlert(
                title: "Rules Updated",
                message: "Routing rules changed since last run. Please run Library Sync Registry and Apply All to rebuild existing drawer samples."
            )
        }

        updateInteractionValue(\.lastSeenRoutingRuleFingerprint, to: trimmedCurrent)
    }

    private func persistInteractionSnapshotIfReady() {
        interactionSnapshotCoordinator.captureAll(
            selectedArea: selectedArea,
            inboxStore: inboxFeatureStore,
            libraryStore: libraryFeatureStore,
            workbenchStore: workbenchFeatureStore
        )
    }

    func flushInteractionSnapshotNow() {
        persistInteractionSnapshotIfReady()
        interactionSnapshotCoordinator.flushNow()
    }

    func importFiles(from urls: [URL]) {
        inboxFacade.importFiles(from: urls)
    }

    func clearPendingImports() {
        inboxFacade.clearPendingImports()
    }

    func clearSelectedPendingImport() {
        inboxFacade.clearSelectedPendingImport()
    }

    func recomputeAllPendingParsedHints() {
        inboxFacade.recomputeAllPendingParsedHints()
    }

    func dryRunConditionRuleRecompute() -> [ConditionChangeProposal] {
        inboxFacade.dryRunConditionRecompute()
    }

    func applyConditionRuleProposals(pendingIDs: Set<UUID>) {
        inboxFacade.applyConditionProposals(pendingIDs: pendingIDs)
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
                self?.libraryFeatureStore.prepareLibrarySyncReview()
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
            libraryFeatureStore.refreshLibraryIncremental()
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
            libraryFeatureStore.librarySelectedPrefix = nil
            libraryFeatureStore.librarySelectedBatchId = nil
            libraryFeatureStore.librarySelectedSampleId = nil
            refreshPendingDrawerMatches()
            return
        }
        applyExistingIndex(index)
    }

    func validateLibraryCacheOnAppear() {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath else {
            return
        }
        let now = Date()
        if lastLibraryCacheValidationRootPath == rootPath,
           let lastLibraryCacheValidationAt,
           now.timeIntervalSince(lastLibraryCacheValidationAt) < 12 {
            return
        }
        lastLibraryCacheValidationRootPath = rootPath
        lastLibraryCacheValidationAt = now

        let rootURL = URL(fileURLWithPath: rootPath)
        guard libraryFeatureStore.libraryStore.needsIndexRefresh(rootURL: rootURL) else {
            return
        }
        libraryFeatureStore.syncLibraryFromFiles()
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
        libraryFeatureStore.saveLibrarySampleEdits()
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

    private func handleLibrarySelectionChangeOutcome(_ outcome: LibraryFeatureStore.SelectionChangeOutcome) {
        switch outcome {
        case .deferred:
            break
        case let .appliedDrawer(prefix, batchId, sampleId):
            libraryFeatureStore.refreshSelectedDrawerAppliedMeasurementsIfNeeded()
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

    func updateLibraryRoot(to url: URL) {
        libraryFeatureStore.updateLibraryRoot(to: url)
        lastLibraryCacheValidationRootPath = nil
        lastLibraryCacheValidationAt = nil
        loadExistingDrawers()
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
        var draft = importPipeline.metadataExtension.defaultConfirmationDraft(
            pending: pending,
            suggestedProjectName: suggestedProject(for: pending)?.name,
            registryLookup: registryLookup(for: pending),
            fallbackSampleID: resolvedSampleID
        )
        draft.workflowID = canonicalWorkflowID(from: draft.workflowID) ?? ""
        return draft
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
            workflowID: canonicalWorkflowID(from: pending.parsedHints.workflowID) ?? "",
            conditionValues: parsedHintsConditionValues(from: pending.parsedHints),
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

    func applySelectedPendingImport() {
        inboxFacade.applySelectedPending()
    }

    func applyAllPendingImports() {
        inboxFacade.applyAllPending()
    }

    func pendingTagReadiness(
        for pending: SpinLabDomain.PendingImport,
        draftOverride: PendingImportConfirmationDraft? = nil
    ) -> PendingTagReadiness {
        guard pendingRouteStatus(for: pending) == .libraryMatched else {
            return .notLibraryMatched
        }
        let missing = pendingMissingRequiredTagLabels(for: pending, draftOverride: draftOverride)
        return missing.isEmpty ? .allGood : .tagsMissing(missing)
    }

    func pendingMissingRequiredTagLabels(
        for pending: SpinLabDomain.PendingImport,
        draftOverride: PendingImportConfirmationDraft? = nil
    ) -> [String] {
        let draft = effectivePendingDraft(for: pending, draftOverride: draftOverride)
        let workflowID = canonicalWorkflowID(from: draft.workflowID)
            ?? canonicalWorkflowID(from: pending.parsedHints.workflowID)
        guard let workflowID,
              let definition = workflowDefinitions.first(where: {
                  $0.id.caseInsensitiveCompare(workflowID) == .orderedSame
              }) else {
            return []
        }

        return definition.conditionFields.compactMap { field in
            let rawValue = draft.conditionValues[field.definitionID]
            guard isMissingConditionValue(rawValue) else {
                return nil
            }
            return workbenchFeatureStore.conditionLabel(for: field.definitionID)
        }
    }

    func hasAnyAllGoodPendingImports() -> Bool {
        let workspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        return inboxFeatureStore.pendingImports.contains { pending in
            let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
            let draftOverride = workspaceByPendingID[key]?.draft
            if case .allGood = pendingTagReadiness(for: pending, draftOverride: draftOverride) {
                return true
            }
            return false
        }
    }

    private func performApplySelectedPendingImport() {
        runApply(scope: .selected(selectedPendingImportID))
    }

    private func performApplyAllPendingImports() {
        guard !applyProgressState.isRunning else {
            return
        }
        runApply(scope: .all)
    }

    private func runApply(scope: ApplyCoordinator.ApplyScope) {
        guard let libraryRootURL = resolvedLibraryRootURLForApply() else {
            return
        }
        let workspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        let pendingImportsForScope: [SpinLabDomain.PendingImport]
        switch scope {
        case .all:
            pendingImportsForScope = inboxFeatureStore.pendingImports.filter { pending in
                let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
                let draftOverride = workspaceByPendingID[key]?.draft
                if case .allGood = pendingTagReadiness(for: pending, draftOverride: draftOverride) {
                    return true
                }
                return false
            }
        case .selected:
            pendingImportsForScope = inboxFeatureStore.pendingImports
        }

        let context = applyCoordinator.resolveContext(
            libraryRootURL: libraryRootURL,
            pendingImports: pendingImportsForScope,
            routingSnapshotFor: { pending in
                self.routingSnapshotForApply(for: pending)
            },
            libraryStore: libraryFeatureStore.libraryStore
        )
        applyProgressState = .init(
            isRunning: true,
            totalCount: 0,
            processedCount: 0,
            appliedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            currentFileName: ""
        )

        Task { @MainActor in
            let outcome = await applyCoordinator.apply(
                scope: scope,
                context: context,
                libraryStore: libraryFeatureStore.libraryStore,
                applyService: inboxArchiveApplyService,
                draftFor: { pendingID in
                    workspaceByPendingID[InteractionSnapshotKeyCodec.dictionaryKey(for: pendingID)]?.draft
                },
                workflowDefinitions: workflowDefinitions,
                onProgress: { [weak self] update in
                    self?.applyProgressState = .init(
                        isRunning: true,
                        totalCount: update.totalCount,
                        processedCount: update.processedCount,
                        appliedCount: update.appliedCount,
                        skippedCount: update.skippedCount,
                        failedCount: update.failedCount,
                        currentFileName: update.currentFileName
                    )
                }
            )
            finalizeApplyOutcome(outcome)
            applyProgressState = .init()
        }
    }

    private func finalizeApplyOutcome(_ outcome: InboxApplyOutcome) {
        let processedIDs = outcome.processedIDs

        inboxFeatureStore.applyPending(processedIDs: processedIDs)
        for pendingID in processedIDs {
            updateInteractionEntryValue(for: pendingID, in: \.inboxWorkspaceByPendingID, value: nil)
        }

        switch outcome {
        case .nothingToApply:
            appLogger.info(.import, "Apply skipped: no matched pending imports")
        case let .success(appliedIDs, skippedIDs):
            appLogger.info(.import, "Apply completed", metadata: [
                "appliedCount": "\(appliedIDs.count)",
                "skippedCount": "\(skippedIDs.count)"
            ])
            if !appliedIDs.isEmpty { libraryFeatureStore.syncLibraryFromFiles() }
        case let .partialSuccess(appliedIDs, skippedIDs, failedIDs):
            appLogger.warning(.import, "Apply partially completed", metadata: [
                "appliedCount": "\(appliedIDs.count)",
                "skippedCount": "\(skippedIDs.count)",
                "failedCount": "\(failedIDs.count)"
            ])
            if !appliedIDs.isEmpty { libraryFeatureStore.syncLibraryFromFiles() }
            present(
                error: .state("Applied \(appliedIDs.count), skipped \(skippedIDs.count) existing, failed \(failedIDs.count)."),
                title: "Apply Partially Completed"
            )
        case let .failure(message):
            appLogger.error(.import, "Apply failed", metadata: ["reason": message])
            present(error: .io(message), title: "Apply Failed")
        }

        bumpAppStateRevision()
    }

    private func routingSnapshotForApply(
        for pending: SpinLabDomain.PendingImport
    ) -> SpinLabDomain.PendingRoutingSnapshot {
        if let cached = inboxFeatureStore.cachedPendingRoutingSnapshot(for: pending.id) {
            return cached
        }
        return inboxFeatureStore.pendingRoutingSnapshot(for: pending)
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

    private func canonicalWorkflowID(from rawWorkflow: String?) -> String? {
        guard let normalizedRaw = normalized(rawWorkflow) else { return nil }
        return workflowDefinitions.first(where: {
            $0.id.caseInsensitiveCompare(normalizedRaw) == .orderedSame
        })?.id
    }

    private func effectivePendingDraft(
        for pending: SpinLabDomain.PendingImport,
        draftOverride: PendingImportConfirmationDraft?
    ) -> PendingImportConfirmationDraft {
        if let draftOverride {
            return draftOverride
        }
        let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
        if let workspaceDraft = interactionValue(\.inboxWorkspaceByPendingID)[key]?.draft {
            return workspaceDraft
        }
        return pendingDisplayDraft(for: pending)
    }

    private func isMissingConditionValue(_ value: String?) -> Bool {
        guard let normalizedValue = normalized(value) else {
            return true
        }
        return normalizedValue.caseInsensitiveCompare("UNKNOWN") == .orderedSame
    }

    private func applyExistingIndex(_ index: LibraryIndex) {
        guard !index.samples.isEmpty else {
            libraryFeatureStore.libraryExistingGroups = [:]
            inboxFeatureStore.clearDrawerMatchCandidates()
            libraryFeatureStore.libraryExistingMessage = "No existing drawers found."
            libraryFeatureStore.librarySelectedPrefix = nil
            libraryFeatureStore.librarySelectedBatchId = nil
            libraryFeatureStore.librarySelectedSampleId = nil
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
        libraryFeatureStore.refreshSelectedDrawerAppliedMeasurementsIfNeeded()
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
        let state = librarySyncService.buildActionablePreviewState(
            preview: preview,
            precomputedDiff: precomputedDiff,
            baselineIndex: baselineIndex,
            rootPath: libraryFeatureStore.librarySettings.rootPath,
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
            librarySyncService: librarySyncService
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

    private func resolvedLibraryRootURLForApply() -> URL? {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            present(error: .validation("Library Root is not configured."), title: "Apply Failed")
            return nil
        }
        return URL(fileURLWithPath: rootPath)
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

        paths.formUnion(existingLibraryImportedOriginalPaths())

        return paths
    }

    private func existingImportedContentFingerprints() -> Set<String> {
        var fingerprints: Set<String> = []
        var seenPaths: Set<String> = []

        func collectFingerprint(from path: String?) {
            guard let path, !path.isEmpty else {
                return
            }
            let normalized = normalizedPath(path)
            guard seenPaths.insert(normalized).inserted else {
                return
            }
            guard let fingerprint = contentFingerprint(atPath: normalized) else {
                return
            }
            fingerprints.insert(fingerprint)
        }

        for pending in inboxFeatureStore.pendingImports {
            collectFingerprint(from: pending.sourceFilePath)
            collectFingerprint(from: pending.originalFilePath)
        }

        for record in workbenchFeatureStore.archivedRecords {
            collectFingerprint(from: record.dataset.sourceFilePath)
            collectFingerprint(from: record.dataset.originalFilePath)
            collectFingerprint(from: record.measurement.sourceFilePath)
            collectFingerprint(from: record.measurement.originalFilePath)
        }

        for fingerprint in existingLibraryImportedContentFingerprints() {
            fingerprints.insert(fingerprint)
        }

        return fingerprints
    }

    private func existingImportedFileNames() -> Set<String> {
        var names: Set<String> = []

        for pending in inboxFeatureStore.pendingImports {
            names.insert(pending.fileName.lowercased())
        }

        for record in workbenchFeatureStore.archivedRecords {
            let path = record.measurement.sourceFilePath
            let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if !fileName.isEmpty {
                names.insert(fileName)
            }
        }

        names.formUnion(existingLibraryMeasurementFileNames())

        return names
    }

    private func existingLibraryMeasurementFileNames() -> Set<String> {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return []
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let batchesURL = rootURL.appending(path: "batches", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: batchesURL.path),
              let enumerator = FileManager.default.enumerator(
                at: batchesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var collected: Set<String> = []
        for case let url as URL in enumerator {
            guard url.path.contains("/measurements/") else {
                continue
            }
            guard !url.lastPathComponent.hasSuffix(".spinlab.json") else {
                continue
            }
            collected.insert(url.lastPathComponent.lowercased())
        }
        return collected
    }

    private func existingLibraryImportedOriginalPaths() -> Set<String> {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            libraryImportedOriginalPathsCache = nil
            return []
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let batchesURL = rootURL.appending(path: "batches", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: batchesURL.path) else {
            libraryImportedOriginalPathsCache = nil
            return []
        }

        let cacheFingerprint = batchesDirectoryFingerprint(at: batchesURL)
        if let cached = libraryImportedOriginalPathsCache,
           cached.rootPath == rootPath,
           cached.batchesFingerprint == cacheFingerprint {
            return cached.paths
        }

        guard let enumerator = FileManager.default.enumerator(
                at: batchesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var collected: Set<String> = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json") else {
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let sidecar = try? decoder.decode(SpinLabFileSidecar.self, from: data) else {
                continue
            }
            let normalized = sidecar.sourceFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }
            collected.insert(normalizedPath(normalized))
        }
        libraryImportedOriginalPathsCache = (rootPath: rootPath, batchesFingerprint: cacheFingerprint, paths: collected)
        return collected
    }

    private func batchesDirectoryFingerprint(at batchesURL: URL) -> String {
        let values = try? batchesURL.resourceValues(forKeys: [.contentModificationDateKey])
        let timestamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(Int(timestamp))"
    }

    private func existingLibraryImportedContentFingerprints() -> Set<String> {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return []
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let batchesURL = rootURL.appending(path: "batches", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: batchesURL.path),
              let enumerator = FileManager.default.enumerator(
                at: batchesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var collected: Set<String> = []
        for case let url as URL in enumerator {
            guard url.path.contains("/measurements/") else {
                continue
            }
            guard !url.lastPathComponent.hasSuffix(".spinlab.json") else {
                continue
            }
            if let fingerprint = contentFingerprint(atPath: url.path) {
                collected.insert(fingerprint)
            }
        }
        return collected
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func contentFingerprint(atPath path: String) -> String? {
        if let cached = contentFingerprintCache[path] {
            return cached
        }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        contentFingerprintCache[path] = fingerprint
        return fingerprint
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

    private func parsedHintsConditionValues(from hints: SpinLabDomain.ParsedFilenameHints) -> [String: String] {
        ConditionFieldCatalog.conditionValues(from: hints)
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
            "routingRuleHashPrefix": inboxFeatureStore.routingRuleHashPrefix,
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
