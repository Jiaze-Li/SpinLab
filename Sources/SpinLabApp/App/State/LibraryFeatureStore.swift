import Foundation
import Observation

@MainActor
@Observable
final class LibraryFeatureStore {
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

    struct SyncLibraryFromFilesOutcome {
        var rootPath: String
        var syncedIndex: LibraryIndex
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
            libraryPreviewMessage = "No registry available. Load it from Inbox first."
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
            libraryPreviewMessage = "No registry available. Load it from Inbox first."
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
}
