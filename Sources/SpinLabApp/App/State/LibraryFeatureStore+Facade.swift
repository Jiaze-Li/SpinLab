import Foundation

@MainActor extension LibraryFeatureStore {

    // MARK: - Facade API (formerly LibraryFacade + LibraryCommandCoordinator)
    // These methods are the public interface for coordinated Library operations.
    // They wrap the detailed methods (which take explicit dependencies) with the
    // injected facade dependencies and cross-store callbacks.
    // Requires: configureFacade(...) must be called before any facade method is invoked.

    var isFacadeConfigured: Bool {
        mutationService != nil
    }

    func assertFacadeConfigured(_ method: String = #function) {
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
}
