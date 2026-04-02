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

        guard sample.appliedMeasurements != measurements else {
            return
        }
        updateSampleAppliedMeasurements(
            prefix: prefix,
            batchId: batchId,
            sampleId: sample.id,
            measurements: measurements
        )
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
            return .appliedDrawer(prefix: prefix, batchId: batchId, sampleId: librarySelectedSampleId)

        case .browser:
            libraryActiveSelectionSource = .browser
            incrementLibrarySelectionVersion()
            reconcileLibrarySampleEditingSelection()
            return .appliedBrowser(
                prefix: librarySelectedPrefix,
                batchId: librarySelectedBatchId,
                sampleId: librarySelectedSampleId
            )
        }
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
