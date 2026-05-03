import Foundation
import Observation

@MainActor
@Observable
final class LibraryFeatureStore {
    struct MutationCommitContext {
        var rootURL: URL
        var previewIndex: LibraryIndex?
    }

    enum SaveLibrarySampleEditsOutcome {
        case success(rootURLForCommit: URL?, nonFatalError: AppError?, message: String)
        case failure(AppError)
    }

    enum ApplyPreparedSyncReviewDecision {
        case missingReview(message: String)
        case noChanges(message: String)
        case apply(totalChanges: Int)
    }

    enum ApplySelectedRegistryDiffOutcome {
        case failure(message: String)
        case noPendingChanges(batchId: String, message: String)
        case success(
            rootURL: URL,
            previewIndex: LibraryIndex,
            batchId: String,
            batchAction: String,
            touchedSamples: Int,
            message: String
        )
    }

    enum LoadLibraryLogOutcome {
        case success(count: Int, message: String)
        case failure(AppError)
    }

    enum MarkLibraryLogStatusOutcome {
        case success(message: String)
        case failure(AppError)
    }

    enum SelectionChangeOutcome {
        case deferred
        case appliedDrawer(prefix: String, batchId: String, sampleId: String?)
        case appliedBrowser(prefix: String?, batchId: String?, sampleId: String?)
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

    struct SyncLibraryFromFilesOutcome {
        var rootPath: String
        var syncedIndex: LibraryIndex
        var summaryMessage: String
    }

    struct BackfillSidecarsOutcome {
        var rootPath: String
        var result: LibraryStore.BackfillSidecarsResult
        var summaryMessage: String
    }

    var librarySelectedPrefix: String?
    var librarySelectedBatchId: String?
    var librarySelectedSampleId: String?
    var libraryActiveSelectionSource: LibrarySelectionSource = .browser

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

    // MARK: - Recompute preview panel (§3.2 / §3.3)

    var isShowingRecomputePreview: Bool = false
    var recomputeDiffItems: [RecomputeDiffItem] = []
    var isComputingRecomputePreview: Bool = false
    var recomputeApplyMessage: String? = nil
    var recomputeApplyError: String? = nil
    var isApplyingRecompute: Bool = false

    @ObservationIgnored
    private var recomputeDismissedFingerprintByRoot: [String: String] = [:]

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
    let librarySidecarService: LibrarySidecarService
    @ObservationIgnored
    lazy var librarySyncService = LibrarySyncService(libraryStore: libraryStore, libraryDiffEngine: libraryDiffEngine)
    @ObservationIgnored
    var appliedMeasurementsCacheBySampleID: [String: AppliedMeasurementsCacheEntry] = [:]
    @ObservationIgnored
    var measurementSetsPersistTask: Task<Void, Never>?

    // MARK: - Facade dependencies (injected via configureFacade)
    @ObservationIgnored
    private var mutationService: LibraryMutationService?
    @ObservationIgnored
    private var saveEditsUseCase: SaveLibrarySampleEditsUseCase?
    @ObservationIgnored
    private var facadeLogger: AppLogger?
    @ObservationIgnored
    private var resolveRegistrySourceURL: (() -> URL?)?
    @ObservationIgnored
    private var onApplyExistingIndex: ((LibraryIndex) -> Void)?
    @ObservationIgnored
    private var onRefreshActionablePreviewGroups: ((LibraryDiff?, LibraryIndex?) -> Void)?
    @ObservationIgnored
    private var onCommitLibraryMutation: ((URL, LibraryIndex?) -> Void)?
    @ObservationIgnored
    private var onLoadExistingDrawers: (() -> Void)?
    @ObservationIgnored
    private var onPresentError: ((AppError, String) -> Void)?
    @ObservationIgnored
    private var onPersistInteractionSnapshot: (() -> Void)?

    struct AppliedMeasurementsCacheEntry {
        var snapshot: LibraryStore.SidecarSnapshot
        var measurements: [AppliedMeasurement]
    }

    init(
        librarySettingsStore: LibrarySettingsStore = LibrarySettingsStore(),
        libraryStore: LibraryStore = LibraryStore(),
        libraryLogger: LibraryLogger = LibraryLogger(),
        libraryDiffEngine: LibraryDiffEngine = LibraryDiffEngine(),
        librarySampleEditService: LibrarySampleEditService = LibrarySampleEditService()
    ) {
        self.librarySettingsStore = librarySettingsStore
        self.libraryStore = libraryStore
        self.libraryLogger = libraryLogger
        self.libraryDiffEngine = libraryDiffEngine
        self.librarySampleEditService = librarySampleEditService
        self.librarySidecarService = LibrarySidecarService(libraryStore: libraryStore)
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
        persistInteractionSnapshot: @escaping () -> Void
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
    }

    // MARK: - Facade API (formerly LibraryFacade + LibraryCommandCoordinator)
    // These methods are the public interface for coordinated Library operations.
    // They wrap the detailed methods (which take explicit dependencies) with the
    // injected facade dependencies and cross-store callbacks.
    // Requires: configureFacade(...) must be called before any facade method is invoked.

    private var isFacadeConfigured: Bool {
        mutationService != nil
    }

    private func assertFacadeConfigured(_ method: String = #function) {
        assert(isFacadeConfigured, "\(method) called before configureFacade()")
    }

    func syncLibraryFromFiles() {
        assertFacadeConfigured()
        guard let outcome = syncLibraryFromFilesForCurrentRoot() else { return }
        onApplyExistingIndex?(outcome.syncedIndex)
        onRefreshActionablePreviewGroups?(nil, nil)
        libraryRootVerificationMessage = outcome.summaryMessage
        libraryRootVerificationPath = outcome.rootPath
    }

    func backfillLibraryMeasurementSidecars() {
        assertFacadeConfigured()
        guard let outcome = backfillSidecarsForCurrentRoot() else { return }
        libraryRootVerificationMessage = outcome.summaryMessage
        libraryRootVerificationPath = outcome.rootPath
    }

    func deleteExistingDrawer(batchId: String) {
        assertFacadeConfigured()
        guard let mutationService else { return }
        if let context = deleteExistingDrawer(mutationService: mutationService, batchId: batchId) {
            onCommitLibraryMutation?(context.rootURL, context.previewIndex)
        }
    }

    func loadLibraryGlobalManualLogs() {
        assertFacadeConfigured()
        guard let resolveRegistrySourceURL else { return }
        switch loadLibraryGlobalManualLogs(resolveRegistrySourceURL: resolveRegistrySourceURL) {
        case .success:
            break
        case let .failure(error):
            onPresentError?(error, "Log Load Failed")
        }
    }

    func markLibraryGlobalManualLogStatus(rowIndex: Int, status: LibraryManualLogStatus) {
        assertFacadeConfigured()
        guard let resolveRegistrySourceURL else { return }
        switch markLibraryGlobalManualLogStatus(rowIndex: rowIndex, status: status, resolveRegistrySourceURL: resolveRegistrySourceURL) {
        case .success:
            break
        case let .failure(error):
            onPresentError?(error, "Status Update Failed")
        }
    }

    func loadLibraryMetadataSyncLogs() {
        assertFacadeConfigured()
        guard let resolveRegistrySourceURL else { return }
        switch loadLibraryMetadataSyncLogs(resolveRegistrySourceURL: resolveRegistrySourceURL) {
        case .success:
            break
        case let .failure(error):
            onPresentError?(error, "Log Load Failed")
        }
    }

    func saveLibrarySampleEdits() {
        assertFacadeConfigured()
        guard let saveEditsUseCase, let resolveRegistrySourceURL else { return }
        let outcome = saveLibrarySampleEdits(useCase: saveEditsUseCase, resolveRegistrySourceURL: resolveRegistrySourceURL)
        switch outcome {
        case let .success(rootURLForCommit, nonFatalError, message):
            if let rootURL = rootURLForCommit {
                onCommitLibraryMutation?(rootURL, libraryPreview?.index)
            }
            if let nonFatalError {
                onPresentError?(nonFatalError, "Sync Warning")
                facadeLogger?.warning(.library, "Library sample edit saved with sync warning", metadata: [
                    "reason": nonFatalError.localizedDescription
                ])
            }
            facadeLogger?.info(.library, "Library sample edits saved", metadata: [
                "message": message
            ])
        case let .failure(error):
            onPresentError?(error, "Save Failed")
            facadeLogger?.error(.library, "Library sample edit failed", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    func prepareLibrarySyncReview(precomputedDiff: LibraryDiff? = nil) {
        assertFacadeConfigured()
        guard let mutationService else { return }
        if let refreshState = prepareLibrarySyncReview(mutationService: mutationService, precomputedDiff: precomputedDiff) {
            onRefreshActionablePreviewGroups?(refreshState.diff, refreshState.baselineIndex)
        }
    }

    func refreshLibraryIncremental() {
        assertFacadeConfigured()
        guard let mutationService else { return }
        if let context = refreshLibraryIncremental(mutationService: mutationService) {
            onCommitLibraryMutation?(context.rootURL, context.previewIndex)
        }
    }

    func confirmLibraryNumericRefreshChanges() {
        assertFacadeConfigured()
        guard let mutationService else { return }
        if confirmLibraryNumericRefreshChanges(mutationService: mutationService) {
            onLoadExistingDrawers?()
        }
    }

    func createDrawersFromPreview() {
        assertFacadeConfigured()
        guard let mutationService else { return }
        if let context = createDrawersFromPreview(mutationService: mutationService) {
            onCommitLibraryMutation?(context.rootURL, context.previewIndex)
        }
    }

    func createDrawersForSelection(batchId: String?, sampleId: String?) {
        assertFacadeConfigured()
        guard let mutationService else { return }
        if let context = createDrawersForSelection(mutationService: mutationService, batchId: batchId, sampleId: sampleId) {
            onCommitLibraryMutation?(context.rootURL, context.previewIndex)
        }
    }

    func incrementLibrarySelectionVersion() {
        librarySelectionVersion &+= 1
    }

    func restoreInteraction(
        libraryActiveSelectionSource: LibrarySelectionSource,
        librarySelectedPrefix: String?,
        librarySelectedBatchId: String?,
        librarySelectedSampleId: String?
    ) {
        self.libraryActiveSelectionSource = libraryActiveSelectionSource
        self.librarySelectedPrefix = librarySelectedPrefix
        self.librarySelectedBatchId = librarySelectedBatchId
        self.librarySelectedSampleId = librarySelectedSampleId
    }

    func captureInteraction(into snapshot: inout SpinLabInteractionSnapshot) {
        snapshot.libraryActiveSelectionSource = libraryActiveSelectionSource
        snapshot.librarySelectedPrefix = librarySelectedPrefix
        snapshot.librarySelectedBatchId = librarySelectedBatchId
        snapshot.librarySelectedSampleId = librarySelectedSampleId
    }

    func commitSelection() {
        onPersistInteractionSnapshot?()
    }

    func applyPreparedSyncReviewDecision() -> ApplyPreparedSyncReviewDecision {
        guard let review = libraryRefreshReview else {
            return .missingReview(message: "No sync review available. Run Sync Registry first.")
        }
        guard review.totalChangesCount > 0 else {
            return .noChanges(message: "No changes to apply.")
        }
        return .apply(totalChanges: review.totalChangesCount)
    }

    func applySyncChangeIndicators(_ indicators: LibrarySyncChangeIndicators) {
        libraryBatchSyncStatusByID = indicators.batchStatusByID
        librarySampleSyncChangesByID = indicators.sampleChangesByID
        libraryBatchSyncChangesByID = indicators.batchChangesByID
    }

    func refreshSyncChangeIndicators(using mutationService: LibraryMutationService) {
        applySyncChangeIndicators(
            mutationService.makeSyncChangeIndicators(review: libraryRefreshReview)
        )
    }

    func prepareLibrarySyncReview(
        mutationService: LibraryMutationService,
        precomputedDiff: LibraryDiff? = nil
    ) -> (diff: LibraryDiff, baselineIndex: LibraryIndex)? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        let result = mutationService.prepareSyncReview(
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            precomputedDiff: precomputedDiff,
            librarySyncService: librarySyncService
        )

        switch result {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(review, diff, baselineIndex, message, indicators):
            libraryRefreshReview = review
            applySyncChangeIndicators(indicators)
            libraryDrawerMessage = message
            return (diff: diff, baselineIndex: baselineIndex)
        }
    }

    func refreshLibraryIncremental(
        mutationService: LibraryMutationService
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.refreshIncremental(
            librarySyncService: librarySyncService,
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            settings: librarySettings
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func confirmLibraryNumericRefreshChanges(
        mutationService: LibraryMutationService
    ) -> Bool {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.confirmNumericRefreshChanges(
            review: libraryRefreshReview,
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            settings: librarySettings,
            libraryStore: libraryStore
        ) {
        case let .failure(message):
            if message == "No numeric changes pending confirmation." {
                libraryDrawerMessage = message
            } else {
                libraryDrawerError = message
            }
            return false
        case let .success(updatedReview, appliedCount, lastRefreshAt):
            librarySettings.lastRefreshAt = lastRefreshAt
            librarySettingsStore.save(librarySettings)
            libraryRefreshReview = updatedReview
            libraryDrawerMessage = "Confirmed and applied \(appliedCount) numeric changes."
            refreshSyncChangeIndicators(using: mutationService)
            return true
        }
    }

    func createDrawersFromPreview(
        mutationService: LibraryMutationService
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.createDrawersFromPreview(
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            libraryStore: libraryStore,
            settings: librarySettings
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, _, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func createDrawersForSelection(
        mutationService: LibraryMutationService,
        batchId: String?,
        sampleId: String?
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.createDrawersForSelection(
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            batchId: batchId,
            sampleId: sampleId,
            libraryStore: libraryStore,
            settings: librarySettings
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, _, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func deleteExistingDrawer(
        mutationService: LibraryMutationService,
        batchId: String
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.deleteExistingDrawer(
            batchId: batchId,
            rootPath: librarySettings.rootPath,
            previewIndex: libraryPreview?.index,
            libraryStore: libraryStore
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func applySelectedRegistryDiff(batchId: String?) -> ApplySelectedRegistryDiffOutcome {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        guard let batchId else {
            let message = "Select a batch first."
            libraryDrawerError = message
            return .failure(message: message)
        }
        guard let preview = libraryPreview else {
            let message = "Load the registry preview first."
            libraryDrawerError = message
            return .failure(message: message)
        }
        guard let rootPath = librarySettings.rootPath else {
            let message = "Select a Library Root first."
            libraryDrawerError = message
            return .failure(message: message)
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)
        guard let applyResult = librarySyncService.applyBatch(
            batchId: batchId,
            preview: preview,
            rootURL: rootURL,
            settings: librarySettings
        ) else {
            let message = "No pending sync changes for \(batchId)."
            libraryDrawerMessage = message
            return .noPendingChanges(batchId: batchId, message: message)
        }

        let failureSuffix = applyResult.failedSamples > 0 ? ", \(applyResult.failedSamples) failed (see console)" : ""
        let message = "Applied selected sync for \(batchId): \(applyResult.batchAction), \(applyResult.touchedSamples) sample changes\(failureSuffix)."
        libraryDrawerMessage = message
        return .success(
            rootURL: rootURL,
            previewIndex: preview.index,
            batchId: batchId,
            batchAction: applyResult.batchAction,
            touchedSamples: applyResult.touchedSamples,
            message: message
        )
    }

    func loadExistingDrawersIndexForCurrentRoot() -> LibraryIndex? {
        guard let rootPath = librarySettings.rootPath else {
            return nil
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        return libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
    }

    func syncLibraryFromFilesForCurrentRoot() -> SyncLibraryFromFilesOutcome? {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return nil
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let previousIndex = libraryStore.loadIndex(from: rootURL)
        let syncedIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)

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

        return SyncLibraryFromFilesOutcome(
            rootPath: rootPath,
            syncedIndex: syncedIndex,
            summaryMessage: "File sync complete: \(syncedIndex.samples.count) samples (+\(addedCount) / -\(removedCount) / ~\(updatedCount))."
        )
    }

    func backfillSidecarsForCurrentRoot() -> BackfillSidecarsOutcome? {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return nil
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let result = librarySidecarService.recomputeAllMeasurementSidecars(rootURL: rootURL)
        appliedMeasurementsCacheBySampleID.removeAll()
        refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        let summary = """
        Sidecar recompute complete: scanned \(result.scannedSampleCount) samples, \
        \(result.scannedMeasurementFileCount) measurement files; created \(result.createdSidecarCount), \
        updated \(result.updatedSidecarCount), \
        skipped \(result.skippedExistingSidecarCount), failed \(result.failedSidecarCount).
        """
        return BackfillSidecarsOutcome(
            rootPath: rootPath,
            result: result,
            summaryMessage: summary
        )
    }

    func applyLoadedLibraryPreview(
        _ snapshot: LibraryPreviewParseSnapshot,
        refreshActionablePreviewGroups: () -> Void
    ) {
        let preview = LibraryPreview(index: snapshot.index, warnings: snapshot.warnings)
        libraryPreview = preview
        libraryPreviewWarnings = snapshot.warnings
        refreshActionablePreviewGroups()
        libraryLogger.write(snapshot.warnings)
    }

    func loadLibraryPreview(
        resolvedRegistryPath: String?,
        dataActor: any SpinLabDataActing,
        refreshActionablePreviewGroups: @escaping () -> Void,
        onFailure: @escaping (AppError) -> Void
    ) {
        guard let registryPath = resolvedRegistryPath else {
            libraryPreviewMessage = "No registry available. Load it from Library first."
            return
        }

        let settings = librarySettings
        Task {
            do {
                let snapshot = try await dataActor.parseLibraryPreview(registryPath: registryPath, settings: settings)
                await MainActor.run {
                    self.applyLoadedLibraryPreview(snapshot, refreshActionablePreviewGroups: refreshActionablePreviewGroups)
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to load registry preview.")
                    self.libraryPreview = nil
                    self.libraryPreviewWarnings = []
                    self.libraryPreviewMessage = appError.localizedDescription
                    onFailure(appError)
                }
            }
        }
    }

    func syncLibraryFromRegistry(
        resolvedRegistryPath: String?,
        dataActor: any SpinLabDataActing,
        prepareLibrarySyncReview: @escaping () -> Void,
        refreshActionablePreviewGroups: @escaping () -> Void,
        formatSyncDate: @escaping (Date) -> String,
        onFailure: @escaping (AppError) -> Void,
        onComplete: (() -> Void)?
    ) {
        guard let registryPath = resolvedRegistryPath else {
            libraryPreviewMessage = "No registry available. Load it from Library first."
            librarySyncStatusMessage = nil
            onComplete?()
            return
        }

        let settings = librarySettings
        Task {
            do {
                let snapshot = try await dataActor.parseLibraryPreview(registryPath: registryPath, settings: settings)
                await MainActor.run {
                    self.applyLoadedLibraryPreview(snapshot, refreshActionablePreviewGroups: refreshActionablePreviewGroups)
                    guard self.libraryPreview != nil else {
                        self.librarySyncStatusMessage = nil
                        onComplete?()
                        return
                    }
                    prepareLibrarySyncReview()
                    self.libraryLastSyncedAt = Date()
                    if let syncedAt = self.libraryLastSyncedAt {
                        self.librarySyncStatusMessage = "Registry diff prepared at \(formatSyncDate(syncedAt)); waiting for manual apply."
                    }
                    onComplete?()
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to prepare library sync preview.")
                    self.librarySyncStatusMessage = nil
                    self.libraryPreview = nil
                    self.libraryPreviewWarnings = []
                    self.libraryPreviewMessage = appError.localizedDescription
                    onFailure(appError)
                    onComplete?()
                }
            }
        }
    }

    // Sample edit methods moved to LibraryFeatureStore+SampleEdit.swift

    func selectedExistingDrawerSample() -> LibrarySample? {
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

    func refreshSelectedDrawerAppliedMeasurementsIfNeeded() {
        guard libraryActiveSelectionSource == .drawer,
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId,
              let sample = selectedExistingDrawerSample() else {
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let snapshot = libraryStore.sidecarSnapshot(for: sample, rootURL: rootURL)
        let measurements: [AppliedMeasurement]
        if let cached = appliedMeasurementsCacheBySampleID[sample.id], cached.snapshot == snapshot {
            measurements = cached.measurements
        } else {
            measurements = libraryStore.loadAppliedMeasurements(for: sample, rootURL: rootURL)
            appliedMeasurementsCacheBySampleID[sample.id] = AppliedMeasurementsCacheEntry(
                snapshot: snapshot,
                measurements: measurements
            )
        }

        let sets = libraryStore.loadMeasurementSets(for: sample, rootURL: rootURL)

        guard sample.appliedMeasurements != measurements || sample.measurementSets != sets else {
            return
        }
        updateSampleAppliedMeasurements(
            prefix: prefix,
            batchId: batchId,
            sampleId: sample.id,
            measurements: measurements
        )
        if sample.measurementSets != sets {
            updateSampleMeasurementSets(
                prefix: prefix,
                batchId: batchId,
                sampleId: sample.id,
                sets: sets
            )
        }
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) -> SelectionChangeOutcome {
        performSelectionChange(.drawer(prefix: prefix, batchId: batchId, sampleId: sampleId))
    }

    func selectBrowserSample() -> SelectionChangeOutcome {
        performSelectionChange(.browser)
    }

    func applyPendingSelectionChangeIfNeeded() -> SelectionChangeOutcome? {
        guard let pending = libraryState.pendingSelectionChange else {
            return nil
        }
        libraryState.pendingSelectionChange = nil
        libraryPendingSelectionChangePrompt = nil
        return applySelectionChange(pending)
    }

    func cancelPendingSelectionChange() {
        libraryState.pendingSelectionChange = nil
        libraryPendingSelectionChangePrompt = nil
    }

    func hasPendingSelectionChange() -> Bool {
        libraryState.pendingSelectionChange != nil
    }

    func normalizeLibrarySelection() {
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
        commitSelection()
    }

    private func updateSampleAppliedMeasurements(
        prefix: String,
        batchId: String,
        sampleId: String,
        measurements: [AppliedMeasurement]
    ) {
        guard var groups = libraryExistingGroups[prefix],
              let groupIndex = groups.firstIndex(where: { $0.batchId == batchId }) else {
            return
        }
        var group = groups[groupIndex]
        guard let sampleIndex = group.samples.firstIndex(where: { $0.id == sampleId }) else {
            return
        }
        var sample = group.samples[sampleIndex]
        sample.appliedMeasurements = measurements
        group.samples[sampleIndex] = sample
        groups[groupIndex] = group
        libraryExistingGroups[prefix] = groups
    }

    // Measurement Set CRUD + helpers moved to LibraryFeatureStore+Projection.swift

    private func performSelectionChange(_ requested: LibraryPendingSelectionChange) -> SelectionChangeOutcome {
        guard !deferSelectionChangeIfNeeded(requested) else {
            return .deferred
        }
        return applySelectionChange(requested)
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
            return .drawer(
                prefix: librarySelectedPrefix ?? "",
                batchId: librarySelectedBatchId ?? "",
                sampleId: librarySelectedSampleId
            )
        }
    }

    private func applySelectionChange(_ requested: LibraryPendingSelectionChange) -> SelectionChangeOutcome {
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
            commitSelection()
            incrementLibrarySelectionVersion()
            reconcileLibrarySampleEditingSelection()
            loadWorkbenchResultsForCurrentSelection()
            loadMeasurementDataForCurrentSelection()
            return .appliedDrawer(prefix: prefix, batchId: batchId, sampleId: librarySelectedSampleId)

        case .browser:
            libraryActiveSelectionSource = .browser
            commitSelection()
            incrementLibrarySelectionVersion()
            reconcileLibrarySampleEditingSelection()
            loadWorkbenchResultsForCurrentSelection()
            loadMeasurementDataForCurrentSelection()
            return .appliedBrowser(
                prefix: librarySelectedPrefix,
                batchId: librarySelectedBatchId,
                sampleId: librarySelectedSampleId
            )
        }
    }

    // Methods moved to LibraryFeatureStore+Projection.swift, +Logs.swift, +SampleEdit.swift
    // Static disk operations moved to LibraryDiskCleanupService.swift

    func sampleChangeLog(for sample: LibrarySample) -> [LibrarySampleChangeLogEntry] {
        guard let rootPath = librarySettings.rootPath else {
            return []
        }
        return libraryStore.sampleChangeLog(for: sample, rootURL: URL(fileURLWithPath: rootPath))
    }

    // Log methods moved to LibraryFeatureStore+Logs.swift

    func updateLibraryRoot(to url: URL) {
        librarySettings.rootPath = url.path
        librarySettingsStore.save(librarySettings)
        libraryRootVerificationPath = nil
        libraryRootVerificationMessage = nil
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

    func syncLibraryBackup(formatSyncDate: (Date) -> String) {
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
            libraryBackupMessage = "Backup sync successful at \(formatSyncDate(syncedAt))."
        } else {
            libraryBackupError = "Backup sync failed."
        }
    }

    func refreshLibraryBackupMessage(formatSyncDate: (Date) -> String) {
        guard let lastSyncedAt = librarySettings.backupLastSyncedAt else {
            return
        }
        libraryBackupMessage = "Backup sync successful at \(formatSyncDate(lastSyncedAt))."
    }

    // MARK: - Recompute facade (§3.1 / §3.2 / §3.4)

    func refreshRecomputeStaleCount() {
        guard let rootPath = librarySettings.rootPath else {
            recomputeStaleCount = 0
            return
        }
        let fingerprint = SpinLabRuleProvider.shared.loadResult().ruleSetFingerprint
        if recomputeDismissedFingerprintByRoot[rootPath] == fingerprint {
            recomputeStaleCount = 0
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let store = libraryStore
        let snapshotRoot = rootPath
        let snapshotFingerprint = fingerprint
        Task {
            let count = await Task.detached(priority: .utility) {
                store.computeStaleCount(rootURL: rootURL, currentFingerprint: snapshotFingerprint)
            }.value
            guard self.librarySettings.rootPath == snapshotRoot,
                  SpinLabRuleProvider.shared.loadResult().ruleSetFingerprint == snapshotFingerprint else { return }
            self.recomputeStaleCount = count
        }
    }

    func dismissRecomputeBanner() {
        guard let rootPath = librarySettings.rootPath else { return }
        let fingerprint = SpinLabRuleProvider.shared.loadResult().ruleSetFingerprint
        recomputeDismissedFingerprintByRoot[rootPath] = fingerprint
        recomputeStaleCount = 0
    }

    func openRecomputePreview() {
        isShowingRecomputePreview = true
        isComputingRecomputePreview = true
        recomputeApplyMessage = nil
        recomputeApplyError = nil
        guard let rootPath = librarySettings.rootPath else {
            isComputingRecomputePreview = false
            recomputeDiffItems = []
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let service = librarySidecarService
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                service.computeRecomputeDiff(rootURL: rootURL)
            }.value
            self.recomputeDiffItems = items
            self.isComputingRecomputePreview = false
        }
    }

    func applyRecompute() {
        isApplyingRecompute = true
        recomputeApplyMessage = nil
        recomputeApplyError = nil
        guard let outcome = backfillSidecarsForCurrentRoot() else {
            isApplyingRecompute = false
            recomputeApplyError = "No library root selected."
            return
        }
        isApplyingRecompute = false
        let succeeded = outcome.result.updatedSidecarCount + outcome.result.createdSidecarCount
        let failed = outcome.result.failedSidecarCount
        if failed > 0 {
            recomputeApplyError = "\(succeeded) 成功 / \(failed) 失败，详情见 Logs"
        } else {
            recomputeApplyMessage = "\(succeeded) 个测量已重算"
        }
        isShowingRecomputePreview = false
        refreshRecomputeStaleCount()
    }

    func loadSidecar(for measurement: AppliedMeasurement) -> SpinLabFileSidecar? {
        libraryStore.loadSidecar(atPath: measurement.id)
    }

    func saveConditionOverride(measurement: AppliedMeasurement, conditionId: String, value: String) {
        let updated = libraryStore.saveConditionOverride(
            sidecarPath: measurement.id,
            conditionId: conditionId,
            value: value
        )
        if updated {
            appliedMeasurementsCacheBySampleID.removeAll()
            refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        }
    }

    func removeConditionOverride(measurement: AppliedMeasurement, conditionId: String) {
        let updated = libraryStore.removeConditionOverride(
            sidecarPath: measurement.id,
            conditionId: conditionId
        )
        if updated {
            appliedMeasurementsCacheBySampleID.removeAll()
            refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        }
    }
}
