import Foundation

@MainActor
final class LibraryFacade {
    private let featureStore: LibraryFeatureStore
    private let commandCoordinator: LibraryCommandCoordinator
    private let saveLibrarySampleEditsUseCase: SaveLibrarySampleEditsUseCase
    private let appLogger: AppLogger

    private let resolveRegistrySourceURL: () -> URL?
    private let applyExistingIndex: (LibraryIndex) -> Void
    private let refreshActionablePreviewGroups: (LibraryDiff?, LibraryIndex?) -> Void
    private let commitLibraryMutation: (URL, LibraryIndex?) -> Void
    private let loadExistingDrawers: () -> Void
    private let presentError: (AppError, String) -> Void

    init(
        featureStore: LibraryFeatureStore,
        commandCoordinator: LibraryCommandCoordinator,
        saveLibrarySampleEditsUseCase: SaveLibrarySampleEditsUseCase,
        appLogger: AppLogger,
        resolveRegistrySourceURL: @escaping () -> URL?,
        applyExistingIndex: @escaping (LibraryIndex) -> Void,
        refreshActionablePreviewGroups: @escaping (LibraryDiff?, LibraryIndex?) -> Void,
        commitLibraryMutation: @escaping (URL, LibraryIndex?) -> Void,
        loadExistingDrawers: @escaping () -> Void,
        presentError: @escaping (AppError, String) -> Void
    ) {
        self.featureStore = featureStore
        self.commandCoordinator = commandCoordinator
        self.saveLibrarySampleEditsUseCase = saveLibrarySampleEditsUseCase
        self.appLogger = appLogger
        self.resolveRegistrySourceURL = resolveRegistrySourceURL
        self.applyExistingIndex = applyExistingIndex
        self.refreshActionablePreviewGroups = refreshActionablePreviewGroups
        self.commitLibraryMutation = commitLibraryMutation
        self.loadExistingDrawers = loadExistingDrawers
        self.presentError = presentError
    }

    func syncLibraryFromFiles() {
        guard let outcome = featureStore.syncLibraryFromFilesForCurrentRoot() else {
            return
        }
        applyExistingIndex(outcome.syncedIndex)
        refreshActionablePreviewGroups(nil, nil)
        featureStore.libraryRootVerificationMessage = outcome.summaryMessage
        featureStore.libraryRootVerificationPath = outcome.rootPath
    }

    func backfillLibraryMeasurementSidecars() {
        guard let outcome = featureStore.backfillSidecarsForCurrentRoot() else {
            return
        }
        featureStore.libraryRootVerificationMessage = outcome.summaryMessage
        featureStore.libraryRootVerificationPath = outcome.rootPath
    }

    func deleteExistingDrawer(batchId: String) {
        if let context = commandCoordinator.deleteExistingDrawer(batchId: batchId) {
            commitLibraryMutation(context.rootURL, context.previewIndex)
        }
    }

    func loadLibraryGlobalManualLogs() {
        switch featureStore.loadLibraryGlobalManualLogs(resolveRegistrySourceURL: resolveRegistrySourceURL) {
        case .success:
            break
        case let .failure(error):
            presentError(error, "Log Load Failed")
        }
    }

    func markLibraryGlobalManualLogStatus(rowIndex: Int, status: LibraryManualLogStatus) {
        switch featureStore.markLibraryGlobalManualLogStatus(
            rowIndex: rowIndex,
            status: status,
            resolveRegistrySourceURL: resolveRegistrySourceURL
        ) {
        case .success:
            break
        case let .failure(error):
            presentError(error, "Status Update Failed")
        }
    }

    func loadLibraryMetadataSyncLogs() {
        switch featureStore.loadLibraryMetadataSyncLogs(resolveRegistrySourceURL: resolveRegistrySourceURL) {
        case .success:
            break
        case let .failure(error):
            presentError(error, "Log Load Failed")
        }
    }

    func saveLibrarySampleEdits() {
        let outcome = featureStore.saveLibrarySampleEdits(
            useCase: saveLibrarySampleEditsUseCase,
            resolveRegistrySourceURL: resolveRegistrySourceURL
        )

        switch outcome {
        case let .success(rootURLForCommit, nonFatalError, message):
            if let rootURL = rootURLForCommit {
                commitLibraryMutation(rootURL, featureStore.libraryPreview?.index)
            }
            if let nonFatalError {
                presentError(nonFatalError, "Sync Warning")
                appLogger.warning(.library, "Library sample edit saved with sync warning", metadata: [
                    "reason": nonFatalError.localizedDescription
                ])
            }
            appLogger.info(.library, "Library sample edits saved", metadata: [
                "message": message
            ])
        case let .failure(error):
            presentError(error, "Save Failed")
            appLogger.error(.library, "Library sample edit failed", metadata: [
                "reason": error.localizedDescription
            ])
        }
    }

    func prepareLibrarySyncReview(precomputedDiff: LibraryDiff? = nil) {
        if let refreshState = commandCoordinator.prepareSyncReview(precomputedDiff: precomputedDiff) {
            refreshActionablePreviewGroups(refreshState.diff, refreshState.baselineIndex)
        }
    }

    func refreshLibraryIncremental() {
        if let context = commandCoordinator.refreshIncremental() {
            commitLibraryMutation(context.rootURL, context.previewIndex)
        }
    }

    func confirmLibraryNumericRefreshChanges() {
        if commandCoordinator.confirmNumericRefreshChanges() {
            loadExistingDrawers()
        }
    }

    func createDrawersFromPreview() {
        if let context = commandCoordinator.createDrawersFromPreview() {
            commitLibraryMutation(context.rootURL, context.previewIndex)
        }
    }

    func createDrawersForSelection(batchId: String?, sampleId: String?) {
        if let context = commandCoordinator.createDrawersForSelection(batchId: batchId, sampleId: sampleId) {
            commitLibraryMutation(context.rootURL, context.previewIndex)
        }
    }
}
