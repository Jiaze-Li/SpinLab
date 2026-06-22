import Foundation
import CryptoKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SpinLabAppState {

    // MARK: - Public stored properties

    var selectedArea: AppArea = .inbox {
        didSet { persistInteractionSnapshotIfReady() }
    }
    var inbox: InboxFeatureStore { inboxFeatureStore }
    var registry: RegistryFeatureStore { registryFeatureStore }
    var library: LibraryFeatureStore { libraryFeatureStore }
    var workbench: WorkbenchFeatureStore { workbenchFeatureStore }
    var rulesPanel: RulesManagementStore { rulesPanelStore }
    var workflowDefinitions: [WorkflowDefinition] = []
    var activeAlert: AppAlertState?
    private(set) var appStateRevision: Int = 0
    var applyProgressState: ApplyProgressState = .init()
    let workflow: SpinLabDomain.WorkflowKind

    // MARK: - Internal stored properties (cross-file extension access)

    let importPipeline: SpinLabImportPipeline
    let archivedRecordResolverService: ArchivedRecordResolverService
    let analysisModule: AnalysisModuleExtension
    let viewExtension: ViewExtension
    let libraryArchiveScan: LibraryArchiveScanService
    var sampleRegistry: SampleRegistryIndexing
    let inboxFeatureStore: InboxFeatureStore
    var registryFeatureStore: RegistryFeatureStore
    let libraryFeatureStore: LibraryFeatureStore
    let workbenchFeatureStore: WorkbenchFeatureStore
    let webLibraryPublisher: any WebLibraryPublishingCapability
    let appLogger = AppLogger.shared
    let interactionSnapshotCoordinator: InteractionSnapshotCoordinator
    var hasRestoredInteractionSnapshot = false
    var lastLibraryCacheValidationRootPath: String?
    var lastLibraryCacheValidationAt: Date?
    let dataActor: any SpinLabDataActing
    let registryLifecycleService = RegistryLifecycleService()
    @ObservationIgnored
    var contentFingerprintCache: [String: String] = [:]
    @ObservationIgnored
    var libraryImportedOriginalPathsCache: (rootPath: String, batchesFingerprint: String, paths: Set<String>)?
    let registryCoordinator = RegistryCoordinator()
    @ObservationIgnored
    lazy var registryFacade = RegistryFacade(
        libraryArchiveScan: libraryArchiveScan,
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
    @ObservationIgnored
    lazy var inboxFacade = InboxFacade(
        inboxWorkflowService: inboxWorkflowService,
        inboxStore: inboxFeatureStore,
        inboxImportFilter: inboxImportFilter,
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
    let libraryPreviewComputationService = LibraryPreviewComputationService()
    let libraryMutationService = LibraryMutationService()
    let coordinator = AppCoordinator()
    let applyCoordinator = ApplyCoordinator()
    let inboxArchiveApplyService = InboxArchiveApplyService()
    @ObservationIgnored
    lazy var archivedRecordDomainContext: SpinLabDomainContext = ArchivedRecordDomainContextAdapter(
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

    // MARK: - Private stored properties

    private let persistence: SpinLabPersistence
    private let inboxRepository: InboxRepository
    private let libraryRepository: LibraryRepository
    private let inboxImportFilter: InboxImportFilterService
    private let saveLibrarySampleEditsUseCase = SaveLibrarySampleEditsUseCase()
    let rulesBookSettings: RulesBookSettings
    private let inboxWorkflowService = InboxWorkflowService()
    private static let webLibraryRepoRootURL = URL(
        fileURLWithPath: "/Users/jack/Downloads/scripts/Codex SpinLab/SpinLab-html",
        isDirectory: true
    )
    @ObservationIgnored
    private lazy var rulesPanelStore: RulesManagementStore = {
        RulesManagementStore(
            onRulesSaved: { [weak self] in
                self?.refreshAfterRulesBookChange()
            },
            rulesBookPaths: self.rulesBookSettings.rulesBookPaths
        )
    }()

    // MARK: - Init

    init(
        workflowBundle: WorkflowBundle = WorkflowRegistry.shared.defaultBundle(),
        environment: AppEnvironment = .live(),
        rulesBookSettings: RulesBookSettings
    ) {
        self.persistence = environment.persistence
        self.inboxRepository = InboxRepository(persistence: environment.persistence)
        self.libraryRepository = LibraryRepository(persistence: environment.persistence)
        self.workflow = workflowBundle.workflowExtension.workflow
        self.importPipeline = workflowBundle.importPipeline
        self.analysisModule = workflowBundle.analysisModule
        self.viewExtension = workflowBundle.viewExtension
        self.inboxImportFilter = environment.inboxImportFilter
        self.libraryArchiveScan = environment.libraryArchiveScan
        self.archivedRecordResolverService = ArchivedRecordResolverService(registrySubstrateRules: environment.registrySubstrateRules)
        self.rulesBookSettings = rulesBookSettings
        self.inboxFeatureStore = InboxFeatureStore(
            inboxRepository: self.inboxRepository,
            routingCapabilities: environment.routingCapabilities,
            ruleRuntime: environment.ruleRuntime
        )
        self.registryFeatureStore = RegistryFeatureStore()
        self.libraryFeatureStore = LibraryFeatureStore()
        self.webLibraryPublisher = environment.webLibraryPublisher
        let interactionMemory = InteractionMemoryStore(persistence: environment.persistence)
        self.interactionSnapshotCoordinator = InteractionSnapshotCoordinator(interactionMemory: interactionMemory)
        self.dataActor = environment.dataActor

        var sampleRegistry = environment.sampleRegistry

        if !sampleRegistry.isLoaded, let currentRegistryURL = environment.libraryArchiveScan.currentSampleRegistryFileURL() {
            sampleRegistry = XLSXPrefixSampleRegistryIndex.fromFileURL(currentRegistryURL, previewRowCount: 10)
        }
        self.sampleRegistry = sampleRegistry

        WorkflowRegistryRetirementService(paths: rulesBookSettings.rulesBookPaths).runIfNeeded()
        if let bookPaths = rulesBookSettings.rulesBookPaths {
            RulesBootstrapper.migrateRulesBookIfNeeded(paths: bookPaths, internalPaths: rulesBookSettings.internalPaths)
            RulesBootstrapper.seedLibraryImportRulesIfNeeded(paths: bookPaths)
        }
        RuleLoader.configure(bookPaths: rulesBookSettings.rulesBookPaths, internalPaths: rulesBookSettings.internalPaths)
        _ = RuleLoader.shared.reloadCached()

        self.workbenchFeatureStore = WorkbenchFeatureStore(
            libraryRepository: self.libraryRepository,
            dataActor: environment.dataActor,
            workflowDefinitionStore: environment.workflowDefinitionStore
        )
        self.workflowDefinitions = self.workbenchFeatureStore.workflowDefinitions
        self.workbenchFeatureStore.onDefinitionsChanged = { [weak self] definitions in
            self?.workflowDefinitions = definitions
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
        libraryArchiveScan.clearManagedMeasurementCopies()
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
        environment: AppEnvironment = .live()
    ) {
        self.init(
            workflowBundle: workflowBundle,
            environment: environment,
            rulesBookSettings: RulesBookSettings()
        )
    }

    convenience init(
        workflowBundle: WorkflowBundle = WorkflowRegistry.shared.defaultBundle(),
        persistence: SpinLabPersistence = LocalJSONPersistence(),
        inboxImportFilter: InboxImportFilterService = InboxImportFilterService(),
        libraryArchiveScan: LibraryArchiveScanService = LibraryArchiveScanService(),
        sampleRegistry: SampleRegistryIndexing = XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10),
        registrySubstrateRules: any RegistrySubstrateRuleProviding = RegistrySubstrateRuleBook(),
        routingCapabilities: RoutingCapabilities = .live,
        ruleRuntime: any RuleRuntimeCapability = DefaultRuleRuntimeCapability()
    ) {
        self.init(
            workflowBundle: workflowBundle,
            environment: AppEnvironment(
                persistence: persistence,
                inboxImportFilter: inboxImportFilter,
                libraryArchiveScan: libraryArchiveScan,
                sampleRegistry: sampleRegistry,
                registrySubstrateRules: registrySubstrateRules,
                routingCapabilities: routingCapabilities,
                ruleRuntime: ruleRuntime,
                dataActor: SpinLabDataActor()
            )
        )
    }

    // MARK: - App state revision

    func bumpAppStateRevision() {
        appStateRevision &+= 1
    }

    func refreshAfterRulesBookChange() {
        _ = RuleLoader.shared.reloadCached()
        refreshRoutingRuleMetadata(forceReload: true)
        recomputeAllPendingParsedHints()
        workbenchFeatureStore.reloadWorkflowDefinitionsAfterRulesChange()
    }

    func configureRulesBook(at url: URL) {
        rulesBookSettings.configure(url: url)
        prepareConfiguredRulesBookForLoad()
        RuleLoader.configure(
            bookPaths: rulesBookSettings.rulesBookPaths,
            internalPaths: rulesBookSettings.internalPaths
        )
        rulesPanelStore.updateRulesBookPaths(rulesBookSettings.rulesBookPaths)
        refreshAfterRulesBookChange()
    }

    private func prepareConfiguredRulesBookForLoad() {
        WorkflowRegistryRetirementService(paths: rulesBookSettings.rulesBookPaths).runIfNeeded()
        if let bookPaths = rulesBookSettings.rulesBookPaths {
            RulesBootstrapper.migrateRulesBookIfNeeded(paths: bookPaths, internalPaths: rulesBookSettings.internalPaths)
            RulesBootstrapper.seedLibraryImportRulesIfNeeded(paths: bookPaths)
        }
    }

    func publishWebLibrary() {
        guard !libraryFeatureStore.webLibraryPublishState.isRunning else {
            return
        }
        let repoRootURL = Self.webLibraryRepoRootURL

        libraryFeatureStore.beginWebLibraryPublish()
        let publisher = webLibraryPublisher

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let exitCode = try await publisher.publishWebLibrary(repoRootURL: repoRootURL) { kind, line in
                    Task { @MainActor in
                        self.libraryFeatureStore.appendWebLibraryPublishOutput(kind: kind, line: line)
                    }
                }
                await MainActor.run {
                    self.libraryFeatureStore.finishWebLibraryPublish(exitCode: exitCode)
                }
            } catch {
                let appError = AppError.from(error, fallback: "Failed to publish web library.")
                await MainActor.run {
                    self.libraryFeatureStore.failWebLibraryPublish(summary: appError.localizedDescription)
                }
            }
        }
    }
}
