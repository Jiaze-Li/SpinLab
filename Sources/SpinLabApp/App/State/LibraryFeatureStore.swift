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
    private(set) var workbenchResults: WorkbenchResultsIndex? = nil

    // MARK: - Measurement Plot Index (v4.1.2.17)

    /// Reverse index mapping source measurement filename → chart identity keys.
    /// Stale keys (not present in `workbenchResults.references`) are filtered out in memory.
    /// Nil when no sample is selected, the root is not set, or no index file exists.
    private(set) var measurementPlotIndex: MeasurementPlotIndex? = nil

    // MARK: - Measurement Data projection (V3.4.3)

    /// Latest `WorkbenchMeasurementDataStore` for the currently selected Library sample.
    /// Nil when no sample is selected, root is not set, or no measurement data file exists.
    private(set) var measurementData: WorkbenchMeasurementDataStore? = nil

    /// Condition alias book loaded from `_spinlab/condition_aliases.json` at the library root.
    /// Nil when the file is absent or fails to load (best-effort, non-fatal per Adj-5).
    private(set) var conditionAliasBook: ConditionAliasBook? = nil

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
    lazy var librarySyncService = LibrarySyncService(libraryStore: libraryStore, libraryDiffEngine: libraryDiffEngine)
    @ObservationIgnored
    private var appliedMeasurementsCacheBySampleID: [String: AppliedMeasurementsCacheEntry] = [:]
    @ObservationIgnored
    private var measurementSetsPersistTask: Task<Void, Never>?

    private struct AppliedMeasurementsCacheEntry {
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
        self.librarySettings = librarySettingsStore.load()
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
        orchestrator: LibraryMutationOrchestrator,
        precomputedDiff: LibraryDiff? = nil
    ) -> (diff: LibraryDiff, baselineIndex: LibraryIndex)? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        let result = mutationService.prepareSyncReview(
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            precomputedDiff: precomputedDiff,
            libraryStore: libraryStore,
            libraryDiffEngine: libraryDiffEngine,
            librarySyncService: librarySyncService,
            orchestrator: orchestrator
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
        mutationService: LibraryMutationService,
        orchestrator: LibraryMutationOrchestrator
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.refreshIncremental(
            libraryStore: libraryStore,
            librarySyncService: librarySyncService,
            orchestrator: orchestrator,
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

        let message = "Applied selected sync for \(batchId): \(applyResult.batchAction), \(applyResult.touchedSamples) sample changes."
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
        let result = libraryStore.backfillMissingMeasurementSidecars(rootURL: rootURL)
        appliedMeasurementsCacheBySampleID.removeAll()
        refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        let summary = """
        Sidecar backfill complete: scanned \(result.scannedSampleCount) samples, \
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

    func saveLibrarySampleEdits(
        useCase: SaveLibrarySampleEditsUseCase,
        resolveRegistrySourceURL: () -> URL?
    ) -> SaveLibrarySampleEditsOutcome {
        librarySampleEditError = nil
        librarySampleEditMessage = nil
        librarySampleEditIsSaving = true
        defer { librarySampleEditIsSaving = false }

        let result = useCase.execute(
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
            resolveRegistrySourceURL: resolveRegistrySourceURL,
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
            if let nonFatalError = output.nonFatalError {
                librarySampleEditError = nonFatalError.localizedDescription
            }

            let message = makeLibrarySampleEditMessage(
                syncSummary: output.syncSummary,
                syncIssue: output.syncIssue,
                nonFatalError: output.nonFatalError
            )
            librarySampleEditMessage = message
            return .success(
                rootURLForCommit: output.rootURLForCommit,
                nonFatalError: output.nonFatalError,
                message: message
            )
        case let .failure(error):
            librarySampleEditError = error.localizedDescription
            return .failure(error)
        }
    }

    private func makeLibrarySampleEditMessage(
        syncSummary: LibraryRegistrySourceSyncResult?,
        syncIssue: SaveLibrarySampleEditsUseCase.RegistrySyncIssue?,
        nonFatalError: AppError?
    ) -> String {
        if let syncSummary {
            return """
            已保存样品编辑。
            Metadata 写回 XLSX：成功 \(syncSummary.metadataWrittenCount) 项，失败 \(syncSummary.metadataFailedCount) 项。
            Numeric 日志新增：\(syncSummary.manualLoggedCount) 项（\(syncSummary.manualLogSheetName)）。
            Metadata 日志表：\(syncSummary.metadataLogSheetName)。
            """
        }

        switch syncIssue {
        case .sourceMissing:
            return """
            已保存样品编辑。
            XLSX 同步警告：未找到 registry source。
            """
        case .syncFailed:
            return """
            已保存样品编辑。
            XLSX 同步警告：\(nonFatalError?.localizedDescription ?? "未知错误")
            """
        case .none:
            return "已保存样品编辑。"
        }
    }

    func beginEditingSelectedLibrarySample(selectedSample: LibrarySample?) {
        librarySampleEditError = nil
        librarySampleEditMessage = nil

        guard let selectedSample else {
            librarySampleEditError = "Select an existing drawer sample to edit."
            return
        }

        libraryState.sampleEditBaseSample = selectedSample
        let draft = librarySampleEditService.makeDraft(from: selectedSample)
        librarySampleEditDraft = draft
        libraryState.sampleEditOriginalDraft = draft
    }

    func beginEditingSelectedDrawerSampleIfNeeded() {
        let selectedSample = libraryActiveSelectionSource == .drawer ? selectedExistingDrawerSample() : nil
        beginEditingSelectedLibrarySample(selectedSample: selectedSample)
    }

    func cancelEditingSelectedLibrarySample(message: String = "Edit canceled.") {
        librarySampleEditDraft = nil
        libraryState.sampleEditBaseSample = nil
        libraryState.sampleEditOriginalDraft = nil
        librarySampleEditError = nil
        librarySampleEditMessage = message
    }

    func discardEditingSelectedLibrarySample() {
        librarySampleEditDraft = nil
        libraryState.sampleEditBaseSample = nil
        libraryState.sampleEditOriginalDraft = nil
        librarySampleEditError = nil
        librarySampleEditMessage = "Edit discarded."
    }

    func updateLibrarySampleEditSubstrateTags(_ value: String) {
        guard var draft = librarySampleEditDraft else {
            return
        }
        draft.substrateTagsText = value
        librarySampleEditDraft = draft
    }

    func updateLibrarySampleEditNumericValue(key: String, value: String) {
        guard var draft = librarySampleEditDraft,
              let index = draft.numericValues.firstIndex(where: { $0.key == key }) else {
            return
        }
        draft.numericValues[index].value = value
        librarySampleEditDraft = draft
    }

    func updateLibrarySampleEditMetadataValue(key: String, value: String) {
        guard var draft = librarySampleEditDraft,
              let index = draft.metadataValues.firstIndex(where: { $0.key == key }) else {
            return
        }
        draft.metadataValues[index].value = value
        librarySampleEditDraft = draft
    }

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

    private func updateSampleMeasurementSets(
        prefix: String,
        batchId: String,
        sampleId: String,
        sets: [MeasurementSet]
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
        sample.measurementSets = sets
        group.samples[sampleIndex] = sample
        groups[groupIndex] = group
        libraryExistingGroups[prefix] = groups
    }

    // MARK: - Measurement Set CRUD

    func createMeasurementSet(name: String, workflow: String, initialMember: String?) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        var members: [String] = []
        if let member = initialMember { members.append(member) }
        let newSet = MeasurementSet(
            id: UUID().uuidString,
            name: name,
            workflow: workflow,
            memberFileNames: members,
            createdAt: Date()
        )
        sets.append(newSet)
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func addToMeasurementSet(setID: String, fileName: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        if !sets[idx].memberFileNames.contains(fileName) {
            sets[idx].memberFileNames.append(fileName)
        }
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func removeFromMeasurementSet(setID: String, fileName: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[idx].memberFileNames.removeAll { $0 == fileName }
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func renameMeasurementSet(setID: String, newName: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[idx].name = newName
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func deleteMeasurementSet(setID: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        sets.removeAll { $0.id == setID }
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    private func persistAndUpdateSets(
        _ sets: [MeasurementSet],
        sample: LibrarySample,
        rootPath: String,
        prefix: String,
        batchId: String
    ) {
        let rootURL = URL(fileURLWithPath: rootPath)
        // Serialize writes: cancel any in-flight persist before starting a new one
        // to prevent an older snapshot from overwriting a newer one.
        measurementSetsPersistTask?.cancel()
        measurementSetsPersistTask = Task.detached { [libraryStore] in
            do {
                try libraryStore.saveMeasurementSets(sets, for: sample, rootURL: rootURL)
            } catch {
                fputs("[SpinLab] persistAndUpdateSets: save failed for \(sample.id): \(error)\n", stderr)
            }
        }
        updateSampleMeasurementSets(
            prefix: prefix,
            batchId: batchId,
            sampleId: sample.id,
            sets: sets
        )
    }

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
            incrementLibrarySelectionVersion()
            reconcileLibrarySampleEditingSelection()
            loadWorkbenchResultsForCurrentSelection()
            loadMeasurementDataForCurrentSelection()
            return .appliedDrawer(prefix: prefix, batchId: batchId, sampleId: librarySelectedSampleId)

        case .browser:
            libraryActiveSelectionSource = .browser
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

    // MARK: - Workbench Results load (V3.4.2)

    /// Loads the `WorkbenchResultsIndex` for the currently selected sample.
    /// Called automatically from selection changes; idempotent when called manually.
    func loadWorkbenchResultsForCurrentSelection() {
        guard let sampleKey = librarySelectedSampleId,
              let rootPath = librarySettings.rootPath else {
            workbenchResults = nil
            return
        }
        let resolver = LibraryPathResolver(libraryRootURL: URL(fileURLWithPath: rootPath))
        workbenchResults = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
        // Refresh measurement plot index after results are loaded so dirty-key filtering is current.
        loadMeasurementPlotIndexForCurrentSelection()
    }

    // MARK: - Measurement Plot Index load (v4.1.2.17)

    /// Loads `MeasurementPlotIndex` and filters out stale chart identity keys
    /// (those absent from the current `workbenchResults.references`).
    /// Must be called after `loadWorkbenchResultsForCurrentSelection()` to ensure valid filtering.
    func loadMeasurementPlotIndexForCurrentSelection() {
        guard let sampleKey = librarySelectedSampleId,
              let rootPath = librarySettings.rootPath else {
            measurementPlotIndex = nil
            return
        }
        let resolver = LibraryPathResolver(libraryRootURL: URL(fileURLWithPath: rootPath))
        let raw: MeasurementPlotIndex?
        if let loaded = LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sampleKey) {
            raw = loaded
        } else if let results = workbenchResults, !results.references.isEmpty {
            // Index missing but old charts exist — backfill once from manifests.
            raw = BackfillMeasurementPlotIndexUseCase(pathResolver: resolver)
                .execute(sampleKey: sampleKey, results: results)
        } else {
            raw = nil
        }
        guard let raw else {
            measurementPlotIndex = nil
            return
        }
        // Filter out chartIdentityKeys that no longer exist in results_index.json.
        let validKeys = Set(workbenchResults?.references.map(\.chartIdentityKey) ?? [])
        var clean = raw
        clean.entries = raw.entries
            .mapValues { $0.filter { validKeys.contains($0) } }
            .filter { !$0.value.isEmpty }
        measurementPlotIndex = clean
    }

    // MARK: - Measurement Data load (V3.4.3)

    /// Loads the `WorkbenchMeasurementDataStore` and `ConditionAliasBook` for the current selection.
    /// Called automatically from selection changes; idempotent when called manually.
    func loadMeasurementDataForCurrentSelection() {
        guard let sampleKey = librarySelectedSampleId,
              let rootPath = librarySettings.rootPath else {
            measurementData = nil
            conditionAliasBook = nil
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        measurementData = LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
        // Alias config is library-level; nil on any failure is non-fatal (Adj-5).
        let aliasConfigURL = rootURL.appending(path: "_spinlab/condition_aliases.json")
        conditionAliasBook = try? ConditionAliasConfigLoader().load(from: aliasConfigURL)
    }

    // MARK: - Metric record deletion (V4.1.11)

    /// Deletes a single metric record from measurement_data.json by identity key.
    /// Removes the record from `records` and `latestIndex`, then writes back atomically.
    func deleteMetricRecord(identityKey: String) {
        guard let sampleKey = librarySelectedSampleId,
              let rootPath = librarySettings.rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        guard Self.deleteMetricRecordOnDisk(identityKey: identityKey, sampleKey: sampleKey, rootURL: rootURL) else {
            librarySampleEditError = "Failed to delete metric record."
            return
        }

        loadMeasurementDataForCurrentSelection()
    }

    @discardableResult
    nonisolated static func deleteMetricRecordOnDisk(
        identityKey: String,
        sampleKey: String,
        rootURL: URL
    ) -> Bool {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"

        guard let absURL = try? resolver.absoluteURL(for: relPath),
              let data = try? Data(contentsOf: absURL) else {
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var store = try? decoder.decode(WorkbenchMeasurementDataStore.self, from: data) else {
            fputs("[SpinLab] deleteMetricRecord: measurement_data.json unreadable for \(sampleKey), aborting\n", stderr)
            return false
        }

        // Find the recordID referenced by this identity key
        guard let pointer = store.latestIndex[identityKey] else {
            fputs("[SpinLab] deleteMetricRecord: identity key not found in latestIndex\n", stderr)
            return false
        }

        // Remove from records and latestIndex
        store.records.removeAll { $0.recordID == pointer.recordID }
        store.latestIndex.removeValue(forKey: identityKey)

        // Write back atomically
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(store) else {
            fputs("[SpinLab] deleteMetricRecord: encode failed for \(sampleKey)\n", stderr)
            return false
        }

        let writer = AtomicFileWriter()
        do {
            try writer.commit([AtomicWriteEntry(destinationURL: absURL, data: encoded)])
        } catch {
            fputs("[SpinLab] deleteMetricRecord: write failed: \(error)\n", stderr)
            return false
        }

        return true
    }

    // MARK: - Workbench Results deletion (V3.4.3)

    /// Removes `ref` from every sample's `results_index.json`, then deletes the chart files.
    ///
    /// Algorithm (fail-closed, index-first):
    /// 1. Enumerate ALL `results_index.json` files directly from the filesystem under `samples/*/`
    ///    — does not depend on LibraryIndex being loadable, so a corrupt or missing library index
    ///    cannot cause partial cleanup.
    /// 2. For each index that contains this identity key, prepare an atomic write entry.
    ///    If ANY write entry cannot be prepared (path resolution or encode failure), abort entirely.
    /// 3. Atomically commit all index rewrites. Abort if the commit throws.
    /// 4. Only after all indexes are consistent, delete the PNG and manifest (best-effort).
    func deleteWorkbenchResult(_ ref: WorkbenchResultReference) {
        guard let rootPath = librarySettings.rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        guard Self.deleteWorkbenchResultOnDisk(ref, rootURL: rootURL) else { return }

        // Refresh the in-memory projection (both indexes).
        loadWorkbenchResultsForCurrentSelection()
        loadMeasurementPlotIndexForCurrentSelection()
    }

    /// Pure filesystem operation: removes `ref` from all `results_index.json` and
    /// `measurement_plot_index.json` files, then deletes chart files.
    /// Returns `true` on success, `false` if aborted (fail-closed).
    @discardableResult
    nonisolated static func deleteWorkbenchResultOnDisk(
        _ ref: WorkbenchResultReference,
        rootURL: URL
    ) -> Bool {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let writer = AtomicFileWriter()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // 1. Enumerate all results_index.json files directly from the filesystem.
        let samplesURL = rootURL.appending(path: "samples")
        let sampleDirs = (try? FileManager.default.contentsOfDirectory(
            at: samplesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        // 2. For every index that references this identity key, build an updated write entry.
        let now = Date()
        var indexWrites: [AtomicWriteEntry] = []
        var preparationFailed = false

        for sampleDir in sampleDirs {
            let indexURL = sampleDir.appending(path: "_spinlab/results_index.json")
            guard FileManager.default.fileExists(atPath: indexURL.path) else { continue }
            let sk = sampleDir.lastPathComponent

            // Fail-closed: if the file exists but cannot be decoded, abort entirely.
            // A corrupt index may still reference this chart; deleting the chart files
            // without cleaning the reference would leave a dangling pointer.
            guard var index = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sk) else {
                fputs("[SpinLab] deleteWorkbenchResult: results_index unreadable for \(sk), aborting\n", stderr)
                preparationFailed = true
                break
            }
            guard index.references.contains(where: { $0.chartIdentityKey == ref.chartIdentityKey }) else {
                continue  // This sample does not reference the chart — nothing to do
            }

            // Reference found: build the write entry. Any failure here must abort the whole operation.
            index.references.removeAll { $0.chartIdentityKey == ref.chartIdentityKey }
            index.updatedAt = now
            guard let data = try? encoder.encode(index) else {
                fputs("[SpinLab] deleteWorkbenchResult: encode failed for \(sk)\n", stderr)
                preparationFailed = true
                break
            }
            indexWrites.append(AtomicWriteEntry(destinationURL: indexURL, data: data))

            // Also clean measurement_plot_index.json for this sample (P1: disk-level cleanup).
            let plotIndexURL = sampleDir.appending(path: "_spinlab/measurement_plot_index.json")
            if var plotIndex = LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sk) {
                let keyToRemove = ref.chartIdentityKey
                var changed = false
                plotIndex.entries = plotIndex.entries
                    .mapValues { keys in
                        let filtered = keys.filter { $0 != keyToRemove }
                        if filtered.count != keys.count { changed = true }
                        return filtered
                    }
                    .filter { !$0.value.isEmpty }
                if changed {
                    plotIndex.updatedAt = now
                    guard let plotData = try? encoder.encode(plotIndex) else {
                        fputs("[SpinLab] deleteWorkbenchResult: plot index encode failed for \(sk)\n", stderr)
                        preparationFailed = true
                        break
                    }
                    indexWrites.append(AtomicWriteEntry(destinationURL: plotIndexURL, data: plotData))
                }
            }
            // measurement_plot_index.json missing → nothing to clean (not an error).
        }

        // Abort if any write entry could not be prepared — do not touch files.
        guard !preparationFailed else { return false }

        // 3. Atomically commit all index updates. Abort if the commit fails.
        guard (try? writer.commit(indexWrites)) != nil else { return false }

        // 4. Delete the chart files only after all indexes are consistent.
        for relPath in [ref.chartImagePath, ref.manifestPath] {
            if let url = try? resolver.absoluteURL(for: relPath) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return true
    }

    // MARK: - Applied Measurement delete (V4.1.6)

    /// Cascade-deletes an applied measurement: associated charts, sidecar, data file,
    /// and measurement set membership. Refreshes all in-memory projections afterward.
    func deleteAppliedMeasurement(_ measurement: AppliedMeasurement) {
        guard !measurement.id.isEmpty else { return }
        guard let rootPath = librarySettings.rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        guard Self.deleteAppliedMeasurementOnDisk(measurement, rootURL: rootURL) else {
            librarySampleEditError = "Failed to delete measurement (index may be corrupt)."
            return
        }

        // Invalidate the cache so the next refresh re-scans from disk.
        if let sample = selectedExistingDrawerSample() {
            appliedMeasurementsCacheBySampleID.removeValue(forKey: sample.id)
        }
        refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        // Internally also refreshes measurement plot index (line 1038).
        loadWorkbenchResultsForCurrentSelection()
    }

    /// Pure filesystem operation: cascade-deletes an applied measurement's charts,
    /// sidecar, data file, and measurement set membership.
    ///
    /// Fail-closed: if any index file exists but cannot be decoded, returns `false`
    /// without deleting any files. Missing sidecar or data file is non-fatal.
    @discardableResult
    nonisolated static func deleteAppliedMeasurementOnDisk(
        _ measurement: AppliedMeasurement,
        rootURL: URL
    ) -> Bool {
        let sidecarURL = URL(fileURLWithPath: measurement.id).standardizedFileURL
        let sidecarPath = sidecarURL.path
        let rootPath = rootURL.standardizedFileURL.path
        let fm = FileManager.default

        // Guard: sidecar must be inside library root.
        guard sidecarPath.hasPrefix(rootPath + "/") else {
            fputs("[SpinLab] deleteAppliedMeasurement: sidecar outside library root\n", stderr)
            return false
        }

        // Dual condition: (1) path is in a /measurements/ subtree,
        //                 (2) derived sample dir contains a measurements/ subdirectory.
        guard let measurementsRange = sidecarPath.range(of: "/measurements/") else {
            fputs("[SpinLab] deleteAppliedMeasurement: sidecar not in measurements/ subtree\n", stderr)
            return false
        }
        let batchSampleDirPath = String(sidecarPath[..<measurementsRange.lowerBound])
        let batchSampleDirURL = URL(fileURLWithPath: batchSampleDirPath)

        guard fm.fileExists(atPath: batchSampleDirURL.appending(path: "measurements").path) else {
            fputs("[SpinLab] deleteAppliedMeasurement: derived sample dir missing measurements/\n", stderr)
            return false
        }

        let sampleKey = batchSampleDirURL.lastPathComponent
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let sourceFileName = measurement.sourceFileName

        // --- Step 1: Cascade-delete associated charts (scoped to this sample) ---

        let plotIndexRelPath = "samples/\(sampleKey)/_spinlab/measurement_plot_index.json"
        if let plotIndexAbsURL = try? resolver.absoluteURL(for: plotIndexRelPath),
           fm.fileExists(atPath: plotIndexAbsURL.path) {
            // File exists — must be decodable or fail-closed.
            guard let plotIndex = LoadMeasurementPlotIndexUseCase(pathResolver: resolver)
                .execute(sampleKey: sampleKey) else {
                fputs("[SpinLab] deleteAppliedMeasurement: measurement_plot_index corrupt for \(sampleKey), aborting\n", stderr)
                return false
            }

            if let chartKeys = plotIndex.entries[sourceFileName], !chartKeys.isEmpty {
                let resultsIndexRelPath = "samples/\(sampleKey)/_spinlab/results_index.json"
                if let resultsIndexAbsURL = try? resolver.absoluteURL(for: resultsIndexRelPath),
                   fm.fileExists(atPath: resultsIndexAbsURL.path) {
                    // File exists — must be decodable or fail-closed.
                    guard let resultsIndex = LoadWorkbenchResultsUseCase(pathResolver: resolver)
                        .execute(sampleKey: sampleKey) else {
                        fputs("[SpinLab] deleteAppliedMeasurement: results_index corrupt for \(sampleKey), aborting\n", stderr)
                        return false
                    }

                    for chartKey in chartKeys {
                        if let ref = resultsIndex.references.first(where: { $0.chartIdentityKey == chartKey }) {
                            guard deleteWorkbenchResultOnDisk(ref, rootURL: rootURL) else {
                                fputs("[SpinLab] deleteAppliedMeasurement: chart cascade failed for \(chartKey), aborting\n", stderr)
                                return false
                            }
                        }
                    }
                }
            }
        }
        // measurement_plot_index absent → no charts to cascade (not an error).

        // --- Step 2: Delete sidecar (missing = non-fatal, delete failure = fatal) ---

        if fm.fileExists(atPath: sidecarPath) {
            do {
                try fm.removeItem(atPath: sidecarPath)
            } catch {
                fputs("[SpinLab] deleteAppliedMeasurement: failed to delete sidecar: \(error)\n", stderr)
                return false
            }
        } else {
            fputs("[SpinLab] deleteAppliedMeasurement: sidecar already absent\n", stderr)
        }

        // --- Step 3: Delete data file (missing = non-fatal, delete failure = fatal) ---

        let sidecarFileName = sidecarURL.lastPathComponent
        let sidecarSuffix = ".spinlab.json"
        if sidecarFileName.hasSuffix(sidecarSuffix) {
            let dataFileName = String(sidecarFileName.dropLast(sidecarSuffix.count))
            let dataFileURL = sidecarURL.deletingLastPathComponent().appending(path: dataFileName)
            if fm.fileExists(atPath: dataFileURL.path) {
                do {
                    try fm.removeItem(at: dataFileURL)
                } catch {
                    fputs("[SpinLab] deleteAppliedMeasurement: failed to delete data file: \(error)\n", stderr)
                    return false
                }
            } else {
                fputs("[SpinLab] deleteAppliedMeasurement: data file already absent\n", stderr)
            }
        }

        // --- Step 4: Remove from measurement sets (scoped to matching workflow) ---

        let setsFileURL = batchSampleDirURL.appending(path: "measurement_sets.json")
        if fm.fileExists(atPath: setsFileURL.path),
           let setsData = try? Data(contentsOf: setsFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if var sets = try? decoder.decode([MeasurementSet].self, from: setsData) {
                var changed = false
                for i in sets.indices {
                    guard sets[i].workflow == measurement.workflow else { continue }
                    if sets[i].memberFileNames.contains(sourceFileName) {
                        sets[i].memberFileNames.removeAll { $0 == sourceFileName }
                        changed = true
                    }
                }
                let beforeCount = sets.count
                sets.removeAll { $0.memberFileNames.isEmpty }
                if sets.count != beforeCount { changed = true }

                if changed {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    do {
                        if sets.isEmpty {
                            try fm.removeItem(at: setsFileURL)
                        } else {
                            let data = try encoder.encode(sets)
                            try data.write(to: setsFileURL, options: .atomic)
                        }
                    } catch {
                        fputs("[SpinLab] deleteAppliedMeasurement: failed to update measurement_sets.json: \(error)\n", stderr)
                        return false
                    }
                }
            }
        }

        return true
    }

    func reconcileLibrarySampleEditingSelection() {
        guard let draft = librarySampleEditDraft else {
            return
        }

        guard libraryActiveSelectionSource == .drawer,
              let selectedSample = selectedExistingDrawerSample() else {
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

    func sampleChangeLog(for sample: LibrarySample) -> [LibrarySampleChangeLogEntry] {
        guard let rootPath = librarySettings.rootPath else {
            return []
        }
        return libraryStore.sampleChangeLog(for: sample, rootURL: URL(fileURLWithPath: rootPath))
    }

    func loadLibraryGlobalManualLogs(resolveRegistrySourceURL: () -> URL?) -> LoadLibraryLogOutcome {
        libraryGlobalManualLogError = nil
        libraryGlobalManualLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Library first.")
            libraryGlobalManualLogError = error.localizedDescription
            libraryGlobalManualLogs = []
            return .failure(error)
        }

        do {
            let entries = try libraryStore.loadRegistryManualUpdateLogEntries(registrySourceURL: registrySourceURL)
            libraryGlobalManualLogs = entries
            let message = "Loaded \(entries.count) global log entries."
            libraryGlobalManualLogMessage = message
            return .success(count: entries.count, message: message)
        } catch {
            let appError = AppError.from(error, fallback: "Failed to load global manual logs.")
            libraryGlobalManualLogError = appError.localizedDescription
            libraryGlobalManualLogs = []
            return .failure(appError)
        }
    }

    func loadLibraryMetadataSyncLogs(resolveRegistrySourceURL: () -> URL?) -> LoadLibraryLogOutcome {
        libraryMetadataSyncLogError = nil
        libraryMetadataSyncLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Library first.")
            libraryMetadataSyncLogError = error.localizedDescription
            libraryMetadataSyncLogs = []
            return .failure(error)
        }

        do {
            let entries = try libraryStore.loadRegistryMetadataSyncLogEntries(registrySourceURL: registrySourceURL)
            libraryMetadataSyncLogs = entries
            let message = "Loaded \(entries.count) metadata log entries."
            libraryMetadataSyncLogMessage = message
            return .success(count: entries.count, message: message)
        } catch {
            let appError = AppError.from(error, fallback: "Failed to load metadata sync logs.")
            libraryMetadataSyncLogError = appError.localizedDescription
            libraryMetadataSyncLogs = []
            return .failure(appError)
        }
    }

    func markLibraryGlobalManualLogStatus(
        rowIndex: Int,
        status: LibraryManualLogStatus,
        statusChangedBy: String = "user",
        resolveRegistrySourceURL: () -> URL?
    ) -> MarkLibraryLogStatusOutcome {
        libraryGlobalManualLogError = nil
        libraryGlobalManualLogMessage = nil

        guard let registrySourceURL = resolveRegistrySourceURL() else {
            let error = AppError.notFound("No registry source found. Load registry from Library first.")
            libraryGlobalManualLogError = error.localizedDescription
            return .failure(error)
        }

        do {
            try libraryStore.updateRegistryManualUpdateLogStatus(
                registrySourceURL: registrySourceURL,
                rowIndex: rowIndex,
                status: status,
                statusChangedBy: statusChangedBy
            )
        } catch {
            let appError = AppError.from(error, fallback: "Failed to update manual log status.")
            libraryGlobalManualLogError = appError.localizedDescription
            return .failure(appError)
        }

        switch loadLibraryGlobalManualLogs(resolveRegistrySourceURL: resolveRegistrySourceURL) {
        case .success:
            let message = "Updated status for log row \(rowIndex) to \(status.rawValue)."
            libraryGlobalManualLogMessage = message
            return .success(message: message)
        case let .failure(error):
            return .failure(error)
        }
    }

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
}
