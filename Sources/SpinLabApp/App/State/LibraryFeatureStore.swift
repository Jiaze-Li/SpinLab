import Foundation
import Observation

@MainActor
@Observable
final class LibraryFeatureStore {
    struct WebLibraryPublishState {
        static let publishedSiteMessage = "Site: https://spinlab-web-library.pages.dev"
        static let publishingMessage = "Publishing..."
        static let publishedSuccessfullyMessage = "Published successfully."
        static let noChangesMessage = "No changes to publish."
        static let publishFailedMessage = "Publish failed."

        var isRunning: Bool = false
        var statusMessage: String?
        var summaryMessage: String?
        var outputLines: [WebLibraryPublishOutputLine] = []
        var completedAt: Date?
        var presentationRevision: Int = 0
    }

    struct WebLibraryPublishOutputLine: Sendable, Hashable {
        var kind: WebLibraryPublishOutputKind
        var line: String
    }

    struct MutationCommitContext {
        var rootURL: URL
        var previewIndex: LibraryIndex?
    }

    struct AppliedMeasurementsCacheEntry {
        var snapshot: LibraryStore.SidecarSnapshot
        var measurements: [AppliedMeasurement]
    }

    var librarySampleEditIsDirty: Bool {
        guard let draft = librarySampleEditDraft,
              let original = libraryState.sampleEditOriginalDraft else {
            return false
        }
        return draft != original
    }

    var canEditSelectedLibrarySample: Bool {
        libraryActiveSelectionSource == .drawer && selectedExistingDrawerSample() != nil
    }

    /// Single permission gate for every Detail-reachable mutation: Detail may
    /// mutate the Drawer-owned record only while Drawer owns Detail focus.
    /// Browser-focused Detail is read-only, even for callbacks wired to a
    /// Browser-displayed sample — mutations always target Drawer state, so an
    /// accidentally-exposed UI callback must not be able to fire while
    /// Browser owns focus. Checked both here (view-gating) and again inside
    /// each mutation method (domain-layer gating).
    var canMutateLibraryDetailSelection: Bool {
        libraryActiveSelectionSource == .drawer
    }

    // Drawer selection — the sample chosen in the Existing Drawer / search list.
    // Owns the record that Detail editing/mutations always act on.
    var librarySelectedPrefix: String?
    var librarySelectedBatchId: String?
    var librarySelectedSampleId: String?

    // Browser selection — the sample chosen in the Registry/Preview tree.
    // Independent of the drawer triple above; browser navigation never
    // mutates drawer selection and vice versa.
    var libraryBrowserSelectedPrefix: String?
    var libraryBrowserSelectedBatchId: String?
    var libraryBrowserSelectedSampleId: String?

    // Detail-pane presentation/focus state: which of the two independent
    // selections above the Detail pane currently displays. Not an ownership
    // marker for a single shared selection.
    var libraryActiveSelectionSource: LibrarySelectionSource = .browser

    /// The sample id belonging to whichever selection is currently focused
    /// in the Detail pane. Used to load Detail-facing projections
    /// (Workbench Results / Measurement Data) without conflating the two panes.
    var currentSelectionSampleId: String? {
        switch libraryActiveSelectionSource {
        case .browser:
            return libraryBrowserSelectedSampleId
        case .drawer:
            return librarySelectedSampleId
        }
    }

    var librarySettings: LibrarySettings
    var libraryRootVerificationPath: String?
    var libraryRootVerificationMessage: String?
    var libraryBackupMessage: String?
    var libraryBackupError: String?
    var libraryPreview: LibraryPreview?
    var libraryPreviewMessage: String?
    var libraryLastSyncedAt: Date?
    var librarySyncStatusMessage: String?
    var libraryPreviewWarnings: [LibraryWarning] = []
    var libraryPreviewGroups: [String: [LibraryPreviewBatchGroup]] = [:]
    var libraryExistingGroups: [String: [LibraryPreviewBatchGroup]] = [:]
    var libraryExistingMessage: String?
    var librarySelectionVersion: Int = 0
    var libraryDrawerMessage: String?
    var libraryDrawerError: String?
    var libraryRefreshReview: LibraryRefreshReview?
    var libraryBatchSyncStatusByID: [String: LibrarySyncBatchStatus] = [:]
    var librarySampleSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    var libraryBatchSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    var librarySampleEditDraft: LibrarySampleEditDraft?
    var librarySampleEditError: String?
    var librarySampleEditMessage: String?
    var librarySampleEditIsSaving: Bool = false
    var libraryPendingSelectionChangePrompt: String?
    var libraryGlobalManualLogs: [LibraryManualUpdateLogEntry] = []
    var libraryGlobalManualLogError: String?
    var libraryGlobalManualLogMessage: String?
    var libraryMetadataSyncLogs: [LibraryMetadataSyncLogEntry] = []
    var libraryMetadataSyncLogError: String?
    var libraryMetadataSyncLogMessage: String?
    var webLibraryPublishState: WebLibraryPublishState = .init()
    var libraryState = LibraryState()

    // MARK: - Workbench Results projection (V3.4.2)

    /// Most recent `WorkbenchResultsIndex` for the currently selected Library sample.
    /// Nil when no sample is selected, the library root is not set, or no results file exists.
    /// Updated each time the Library sample selection changes.
    var workbenchResults: WorkbenchResultsIndex? = nil

    // MARK: - Measurement Plot Index (v4.1.2.17)

    /// Reverse index mapping source measurement filename → chart identity keys.
    /// Stale keys (not present in `workbenchResults.references`) are filtered out in memory.
    /// Nil when no sample is selected, the root is not set, or no index file exists.
    var measurementPlotIndex: MeasurementPlotIndex? = nil

    // MARK: - Measurement Data projection (V3.4.3)

    /// Latest `WorkbenchMeasurementDataStore` for the currently selected Library sample.
    /// Nil when no sample is selected, root is not set, or no measurement data file exists.
    var measurementData: WorkbenchMeasurementDataStore? = nil

    /// Condition alias book loaded from `_spinlab/condition_aliases.json` at the library root.
    /// Nil when the file is absent or fails to load (best-effort, non-fatal per Adj-5).
    var conditionAliasBook: ConditionAliasBook? = nil

    // MARK: - Recompute stale banner (§3.1)

    var recomputeStaleCount: Int = 0

    // MARK: - Chart Asset Audit (v5.3.8)

    var chartAuditReport: ChartAssetAuditReport? = nil
    var isChartAuditRunning: Bool = false
    var chartAuditMessage: String? = nil
    var isShowingChartAudit: Bool = false

    // MARK: - Recompute preview panel (§3.2 / §3.3)

    var isShowingRecomputePreview: Bool = false
    var recomputeDiffItems: [RecomputeDiffItem] = []
    var isComputingRecomputePreview: Bool = false
    var recomputeApplyMessage: String? = nil
    var recomputeApplyError: String? = nil
    var isApplyingRecompute: Bool = false

    // MARK: - Obsidian → Registry import preview (Phase 5B)

    var isShowingRegistryGrowthImportSheet: Bool = false
    var registryGrowthImportPlan: RegistryGrowthImportPlan?
    var registryGrowthImportSelectedReadyBatchIds: Set<String> = []
    var registryGrowthImportSelectedFilter: RegistryGrowthImportPresentation.Filter = .ready
    var registryGrowthImportSelectedItemId: String?
    var isRegistryGrowthImportPreviewLoading: Bool = false
    var isRegistryGrowthImportApplying: Bool = false
    var registryGrowthImportError: String?
    var registryGrowthImportMessage: String?
    var registryGrowthImportNeedsRefresh: Bool = false
    var registryGrowthImportLastApplyResult: RegistryGrowthApplyResult?
    /// Transient, per-preview Existing field edits (Phase 5C) — batchId →
    /// column header → user-confirmed Final value. Only ever holds entries
    /// where Final differs from the plan's `registryValue` for that field
    /// (spec §5/§10: "Final == Registry value → no mutation"); resetting a
    /// field to its Registry value removes its entry entirely. Never
    /// persisted — cleared on sheet close, preview refresh, and apply.
    var registryGrowthImportExistingFieldEdits: [String: [String: String]] = [:]

    @ObservationIgnored
    var recomputeDismissedFingerprintByRoot: [String: String] = [:]

    @ObservationIgnored
    let librarySettingsStore: LibrarySettingsStore
    @ObservationIgnored
    let libraryStore: LibraryStore
    @ObservationIgnored
    let libraryLogger: LibraryLogger
    @ObservationIgnored
    let libraryDiffEngine: LibraryDiffEngine
    @ObservationIgnored
    let librarySampleEditService: LibrarySampleEditService
    @ObservationIgnored
    let librarySidecarService: any LibrarySidecarCapability
    @ObservationIgnored
    let libraryRegistrySyncService: LibraryRegistrySyncService
    @ObservationIgnored
    lazy var librarySyncService = LibrarySyncService(libraryStore: libraryStore, libraryDiffEngine: libraryDiffEngine)
    @ObservationIgnored
    var appliedMeasurementsCacheBySampleID: [String: AppliedMeasurementsCacheEntry] = [:]
    @ObservationIgnored
    var measurementSetsPersistTask: Task<Void, Never>?

    // MARK: - Facade dependencies (injected via configureFacade)
    @ObservationIgnored
    var mutationService: LibraryMutationService?
    @ObservationIgnored
    var saveEditsUseCase: SaveLibrarySampleEditsUseCase?
    @ObservationIgnored
    var facadeLogger: AppLogger?
    @ObservationIgnored
    var resolveRegistrySourceURL: (() -> URL?)?
    @ObservationIgnored
    var onApplyExistingIndex: ((LibraryIndex) -> Void)?
    @ObservationIgnored
    var onRefreshActionablePreviewGroups: ((LibraryDiff?, LibraryIndex?) -> Void)?
    @ObservationIgnored
    var onCommitLibraryMutation: ((URL, LibraryIndex?) -> Void)?
    @ObservationIgnored
    var onLoadExistingDrawers: (() -> Void)?
    @ObservationIgnored
    var onPresentError: ((AppError, String) -> Void)?
    @ObservationIgnored
    var onPersistInteractionSnapshot: (() -> Void)?
    @ObservationIgnored
    var onReloadSampleRegistry: (() -> Void)?

    init(
        librarySettingsStore: LibrarySettingsStore = LibrarySettingsStore(),
        libraryStore: LibraryStore = LibraryStore(),
        libraryLogger: LibraryLogger = LibraryLogger(),
        libraryDiffEngine: LibraryDiffEngine = LibraryDiffEngine(),
        librarySampleEditService: LibrarySampleEditService = LibrarySampleEditService(),
        librarySidecarService: (any LibrarySidecarCapability)? = nil,
        libraryRegistrySyncService: LibraryRegistrySyncService? = nil
    ) {
        self.librarySettingsStore = librarySettingsStore
        self.libraryStore = libraryStore
        self.libraryLogger = libraryLogger
        self.libraryDiffEngine = libraryDiffEngine
        self.librarySampleEditService = librarySampleEditService
        self.librarySidecarService = librarySidecarService ?? LibrarySidecarService(libraryStore: libraryStore)
        self.libraryRegistrySyncService = libraryRegistrySyncService ?? LibraryRegistrySyncService(libraryStore: libraryStore)
        self.librarySettings = librarySettingsStore.load()
    }

    func configureFacade(
        mutationService: LibraryMutationService,
        saveEditsUseCase: SaveLibrarySampleEditsUseCase,
        appLogger: AppLogger,
        resolveRegistrySourceURL: @escaping () -> URL?,
        applyExistingIndex: @escaping (LibraryIndex) -> Void,
        refreshActionablePreviewGroups: @escaping (LibraryDiff?, LibraryIndex?) -> Void,
        commitLibraryMutation: @escaping (URL, LibraryIndex?) -> Void,
        loadExistingDrawers: @escaping () -> Void,
        presentError: @escaping (AppError, String) -> Void,
        persistInteractionSnapshot: @escaping () -> Void,
        reloadSampleRegistry: @escaping () -> Void = {}
    ) {
        self.mutationService = mutationService
        self.saveEditsUseCase = saveEditsUseCase
        self.facadeLogger = appLogger
        self.resolveRegistrySourceURL = resolveRegistrySourceURL
        self.onApplyExistingIndex = applyExistingIndex
        self.onRefreshActionablePreviewGroups = refreshActionablePreviewGroups
        self.onCommitLibraryMutation = commitLibraryMutation
        self.onLoadExistingDrawers = loadExistingDrawers
        self.onPresentError = presentError
        self.onPersistInteractionSnapshot = persistInteractionSnapshot
        self.onReloadSampleRegistry = reloadSampleRegistry
    }
}
