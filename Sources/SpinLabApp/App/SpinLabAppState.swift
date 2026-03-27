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
    var pendingImports: [SpinLabDomain.PendingImport] {
        get { inboxFeatureStore.pendingImports }
        set { inboxFeatureStore.pendingImports = newValue }
    }
    var selectedPendingImportID: UUID? {
        get { inboxFeatureStore.selectedPendingImportID }
        set {
            inboxFeatureStore.selectedPendingImportID = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    private(set) var registryFileName: String?
    private(set) var registrySourceFilePath: String?
    private(set) var registryPrefixEntries: [RegistryPrefixEntry] = []
    var routingRuleVersion: Int { inboxFeatureStore.routingRuleVersion }
    var routingRuleSourceLabel: String { inboxFeatureStore.routingRuleSourceLabel }
    var routingRuleSourcePath: String { inboxFeatureStore.routingRuleSourcePath }
    var routingRuleFingerprint: String { inboxFeatureStore.routingRuleFingerprint }
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
    var librarySettings: LibrarySettings {
        get { libraryFeatureStore.librarySettings }
        set { libraryFeatureStore.librarySettings = newValue }
    }
    private(set) var libraryRootVerificationPath: String? {
        get { libraryFeatureStore.libraryRootVerificationPath }
        set { libraryFeatureStore.libraryRootVerificationPath = newValue }
    }
    private(set) var libraryRootVerificationMessage: String? {
        get { libraryFeatureStore.libraryRootVerificationMessage }
        set { libraryFeatureStore.libraryRootVerificationMessage = newValue }
    }
    private(set) var libraryBackupMessage: String? {
        get { libraryFeatureStore.libraryBackupMessage }
        set { libraryFeatureStore.libraryBackupMessage = newValue }
    }
    private(set) var libraryBackupError: String? {
        get { libraryFeatureStore.libraryBackupError }
        set { libraryFeatureStore.libraryBackupError = newValue }
    }
    private(set) var libraryPreview: LibraryPreview? {
        get { libraryFeatureStore.libraryPreview }
        set { libraryFeatureStore.libraryPreview = newValue }
    }
    private(set) var libraryPreviewMessage: String? {
        get { libraryFeatureStore.libraryPreviewMessage }
        set { libraryFeatureStore.libraryPreviewMessage = newValue }
    }
    private(set) var libraryLastSyncedAt: Date? {
        get { libraryFeatureStore.libraryLastSyncedAt }
        set { libraryFeatureStore.libraryLastSyncedAt = newValue }
    }
    private(set) var librarySyncStatusMessage: String? {
        get { libraryFeatureStore.librarySyncStatusMessage }
        set { libraryFeatureStore.librarySyncStatusMessage = newValue }
    }
    private(set) var libraryPreviewWarnings: [LibraryWarning] {
        get { libraryFeatureStore.libraryPreviewWarnings }
        set { libraryFeatureStore.libraryPreviewWarnings = newValue }
    }
    private(set) var libraryPreviewGroups: [String: [LibraryPreviewBatchGroup]] {
        get { libraryFeatureStore.libraryPreviewGroups }
        set { libraryFeatureStore.libraryPreviewGroups = newValue }
    }
    private(set) var libraryExistingGroups: [String: [LibraryPreviewBatchGroup]] {
        get { libraryFeatureStore.libraryExistingGroups }
        set { libraryFeatureStore.libraryExistingGroups = newValue }
    }
    private(set) var libraryExistingMessage: String? {
        get { libraryFeatureStore.libraryExistingMessage }
        set { libraryFeatureStore.libraryExistingMessage = newValue }
    }
    private(set) var librarySelectionVersion: Int {
        get { libraryFeatureStore.librarySelectionVersion }
        set { libraryFeatureStore.librarySelectionVersion = newValue }
    }
    private(set) var libraryDrawerMessage: String? {
        get { libraryFeatureStore.libraryDrawerMessage }
        set { libraryFeatureStore.libraryDrawerMessage = newValue }
    }
    private(set) var libraryDrawerError: String? {
        get { libraryFeatureStore.libraryDrawerError }
        set { libraryFeatureStore.libraryDrawerError = newValue }
    }
    private(set) var libraryRefreshReview: LibraryRefreshReview? {
        get { libraryFeatureStore.libraryRefreshReview }
        set { libraryFeatureStore.libraryRefreshReview = newValue }
    }
    private(set) var libraryBatchSyncStatusByID: [String: LibrarySyncBatchStatus] {
        get { libraryFeatureStore.libraryBatchSyncStatusByID }
        set { libraryFeatureStore.libraryBatchSyncStatusByID = newValue }
    }
    private(set) var librarySampleSyncChangesByID: [String: [LibraryFieldChange]] {
        get { libraryFeatureStore.librarySampleSyncChangesByID }
        set { libraryFeatureStore.librarySampleSyncChangesByID = newValue }
    }
    private(set) var libraryBatchSyncChangesByID: [String: [LibraryFieldChange]] {
        get { libraryFeatureStore.libraryBatchSyncChangesByID }
        set { libraryFeatureStore.libraryBatchSyncChangesByID = newValue }
    }
    private(set) var librarySampleEditDraft: LibrarySampleEditDraft? {
        get { libraryFeatureStore.librarySampleEditDraft }
        set { libraryFeatureStore.librarySampleEditDraft = newValue }
    }
    private(set) var librarySampleEditError: String? {
        get { libraryFeatureStore.librarySampleEditError }
        set { libraryFeatureStore.librarySampleEditError = newValue }
    }
    private(set) var librarySampleEditMessage: String? {
        get { libraryFeatureStore.librarySampleEditMessage }
        set { libraryFeatureStore.librarySampleEditMessage = newValue }
    }
    private(set) var librarySampleEditIsSaving: Bool {
        get { libraryFeatureStore.librarySampleEditIsSaving }
        set { libraryFeatureStore.librarySampleEditIsSaving = newValue }
    }
    private(set) var libraryPendingSelectionChangePrompt: String? {
        get { libraryFeatureStore.libraryPendingSelectionChangePrompt }
        set { libraryFeatureStore.libraryPendingSelectionChangePrompt = newValue }
    }
    private(set) var libraryGlobalManualLogs: [LibraryManualUpdateLogEntry] {
        get { libraryFeatureStore.libraryGlobalManualLogs }
        set { libraryFeatureStore.libraryGlobalManualLogs = newValue }
    }
    private(set) var libraryGlobalManualLogError: String? {
        get { libraryFeatureStore.libraryGlobalManualLogError }
        set { libraryFeatureStore.libraryGlobalManualLogError = newValue }
    }
    private(set) var libraryGlobalManualLogMessage: String? {
        get { libraryFeatureStore.libraryGlobalManualLogMessage }
        set { libraryFeatureStore.libraryGlobalManualLogMessage = newValue }
    }
    private(set) var libraryMetadataSyncLogs: [LibraryMetadataSyncLogEntry] {
        get { libraryFeatureStore.libraryMetadataSyncLogs }
        set { libraryFeatureStore.libraryMetadataSyncLogs = newValue }
    }
    private(set) var libraryMetadataSyncLogError: String? {
        get { libraryFeatureStore.libraryMetadataSyncLogError }
        set { libraryFeatureStore.libraryMetadataSyncLogError = newValue }
    }
    private(set) var libraryMetadataSyncLogMessage: String? {
        get { libraryFeatureStore.libraryMetadataSyncLogMessage }
        set { libraryFeatureStore.libraryMetadataSyncLogMessage = newValue }
    }
    var archivedRecords: [SpinLabDomain.ArchivedRecord] {
        get { workbenchFeatureStore.archivedRecords }
        set { workbenchFeatureStore.archivedRecords = newValue }
    }
    var projectCatalog: [SpinLabDomain.Project] {
        get { workbenchFeatureStore.projectCatalog }
        set { workbenchFeatureStore.projectCatalog = newValue }
    }
    var selectedArchivedRecordID: UUID? {
        get { workbenchFeatureStore.selectedArchivedRecordID }
        set {
            workbenchFeatureStore.selectedArchivedRecordID = newValue
            persistInteractionSnapshotIfReady()
        }
    }
    var workbenchResultDraft: String {
        get { workbenchFeatureStore.workbenchResultDraft }
        set {
            workbenchFeatureStore.workbenchResultDraft = newValue
            persistInteractionSnapshotIfReady()
        }
    }

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
    private let inboxFeatureStore: InboxFeatureStore
    private let libraryFeatureStore: LibraryFeatureStore
    private let workbenchFeatureStore: WorkbenchFeatureStore
    private let appLogger = AppLogger.shared
    private let interactionMemory: InteractionMemoryStore
    private let dataActor: any SpinLabDataActing
    private let coordinator = AppCoordinator()
    private let confirmPendingImportUseCase = ConfirmPendingImportUseCase()
    private let saveLibrarySampleEditsUseCase = SaveLibrarySampleEditsUseCase()
    @ObservationIgnored
    private lazy var archivedRecordDomainContext: SpinLabDomainContext = ArchivedRecordDomainContextAdapter(
        normalizedValueProvider: { [weak self] value in
            self?.normalized(value)
        },
        metadataValueProvider: { [weak self] lookup, keys in
            self?.metadataValue(in: lookup, keys: keys)
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
            self?.measurementNotes(for: pending, draft: draft, registryLookup: lookup) ?? ""
        },
        defaultResultSummaryProvider: { [weak self] measurement in
            self?.analysisModule.defaultResultSummary(for: measurement) ?? ""
        }
    )
    private var librarySettingsStore: LibrarySettingsStore { libraryFeatureStore.librarySettingsStore }
    private var libraryStore: LibraryStore { libraryFeatureStore.libraryStore }
    private var libraryLogger: LibraryLogger { libraryFeatureStore.libraryLogger }
    private var libraryDiffEngine: LibraryDiffEngine { libraryFeatureStore.libraryDiffEngine }
    private var librarySampleEditService: LibrarySampleEditService { libraryFeatureStore.librarySampleEditService }
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
        self.registrySubstrateRules = environment.registrySubstrateRules
        self.inboxFeatureStore = InboxFeatureStore(
            inboxRepository: self.inboxRepository,
            routingCapabilities: environment.routingCapabilities,
            ruleRuntime: environment.ruleRuntime
        )
        self.libraryFeatureStore = LibraryFeatureStore()
        self.workbenchFeatureStore = WorkbenchFeatureStore(libraryRepository: self.libraryRepository)
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
        let loadResult = inboxFeatureStore.refreshRoutingRuleMetadata(forceReload: forceReload)
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
        applyPendingImportsProjection(inboxFeatureStore.pendingImports)
        applyArchivedRecordsProjection(archivedRecords)
        applyProjectCatalogProjection(projectCatalog)
        if let selectedArchivedRecord {
            _ = workbenchFeatureStore.selectArchivedRecord(selectedArchivedRecord.id, analysisModule: analysisModule)
        } else {
            workbenchResultDraft = ""
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
            selectedArea = snapshot.selectedArea
            libraryFeatureStore.restoreInteraction(
                libraryActiveSelectionSource: snapshot.libraryActiveSelectionSource,
                librarySelectedPrefix: snapshot.librarySelectedPrefix,
                librarySelectedBatchId: snapshot.librarySelectedBatchId,
                librarySelectedSampleId: snapshot.librarySelectedSampleId
            )
            inboxFeatureStore.restoreInteraction(
                selectedPendingImportID: snapshot.selectedPendingImportID
            )
            workbenchFeatureStore.restoreInteraction(
                selectedArchivedRecordID: snapshot.selectedArchivedRecordID,
                workbenchResultDraft: snapshot.workbenchResultDraft
            )
            snapshot.inboxWorkspaceByPendingID = inboxFeatureStore.pruneWorkspaceByValidPendingIDs(
                snapshot.inboxWorkspaceByPendingID
            )
            inboxFeatureStore.restoreRoutingDrafts(from: snapshot.inboxWorkspaceByPendingID)
        }
        normalizeLibrarySelection()
    }

    private func persistInteractionSnapshotIfReady() {
        interactionMemory.captureIfReady { snapshot in
            snapshot.selectedArea = selectedArea
            libraryFeatureStore.captureInteraction(into: &snapshot)
            inboxFeatureStore.captureInteraction(into: &snapshot)
            workbenchFeatureStore.captureInteraction(into: &snapshot)
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
        inboxFeatureStore.clearPendingState()
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
        inboxFeatureStore.clearPendingState()

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
            libraryDrawerError = message
            appLogger.warning(.library, "Apply all skipped: no sync review")
        case let .noChanges(message):
            libraryDrawerMessage = message
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
            appLogger.info(.function, "Apply selected completed", metadata: [
                "batchId": id,
                "action": action,
                "sampleChanges": "\(touched)"
            ])
        }
    }

    func loadExistingDrawers() {
        guard let index = libraryFeatureStore.loadExistingDrawersIndexForCurrentRoot() else {
            libraryExistingGroups = [:]
            inboxFeatureStore.clearDrawerMatchCandidates()
            libraryExistingMessage = "No Library Root selected."
            librarySelectedPrefix = nil
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            refreshPendingDrawerMatches()
            return
        }
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
        guard let outcome = libraryFeatureStore.syncLibraryFromFilesForCurrentRoot() else {
            return
        }
        applyExistingIndex(outcome.syncedIndex)
        refreshActionablePreviewGroups()
        libraryRootVerificationMessage = outcome.summaryMessage
        libraryRootVerificationPath = outcome.rootPath
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
        let outcome = libraryFeatureStore.saveLibrarySampleEdits(
            useCase: saveLibrarySampleEditsUseCase,
            resolveRegistrySourceURL: { [weak self] in
                self?.resolveRegistrySourceURL()
            }
        )

        switch outcome {
        case let .success(rootURLForCommit, nonFatalError, message):
            if let rootURL = rootURLForCommit {
                commitLibraryMutation(rootURL: rootURL, previewIndex: libraryPreview?.index)
            }
            if let nonFatalError {
                present(error: nonFatalError, title: "Sync Warning")
                appLogger.warning(.library, "Library sample edit saved with sync warning", metadata: [
                    "reason": nonFatalError.localizedDescription
                ])
            }
            appLogger.info(.library, "Library sample edits saved", metadata: [
                "message": message
            ])
        case let .failure(error):
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
        inboxFeatureStore.clearRoutingData(for: pending.id)
        updateInteractionEntryValue(for: pending.id, in: \.inboxWorkspaceByPendingID, value: nil)

        let route = coordinator.routeAfterPendingConfirmation(
            archivedRecordID: output.archivedRecord.id,
            nextPendingID: pendingImports.first?.id
        )
        _ = workbenchFeatureStore.selectArchivedRecord(route.archivedRecordID, analysisModule: analysisModule)
        selectedPendingImportID = route.nextPendingID
        selectedArea = route.selectedArea
        appLogger.info(.import, "Pending import confirmed", metadata: [
            "pendingID": pending.id.uuidString,
            "archivedRecordID": output.archivedRecord.id.uuidString,
            "measurementID": output.archivedRecord.measurement.id.uuidString,
            "workflow": workflow.rawValue
        ])
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
            libraryExistingGroups = [:]
            inboxFeatureStore.clearDrawerMatchCandidates()
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
        inboxFeatureStore.rebuildDrawerMatchCandidates(from: index.samples)
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
