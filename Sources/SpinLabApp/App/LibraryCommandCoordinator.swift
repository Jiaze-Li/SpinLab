import Foundation

@MainActor
final class LibraryCommandCoordinator {
    private unowned let featureStore: LibraryFeatureStore
    private let mutationService: LibraryMutationService
    private let orchestrator: LibraryMutationOrchestrator

    init(
        featureStore: LibraryFeatureStore,
        mutationService: LibraryMutationService,
        orchestrator: LibraryMutationOrchestrator
    ) {
        self.featureStore = featureStore
        self.mutationService = mutationService
        self.orchestrator = orchestrator
    }

    func prepareSyncReview(precomputedDiff: LibraryDiff? = nil) -> (diff: LibraryDiff, baselineIndex: LibraryIndex)? {
        featureStore.prepareLibrarySyncReview(
            mutationService: mutationService,
            orchestrator: orchestrator,
            precomputedDiff: precomputedDiff
        )
    }

    func refreshIncremental() -> LibraryFeatureStore.MutationCommitContext? {
        featureStore.refreshLibraryIncremental(
            mutationService: mutationService,
            orchestrator: orchestrator
        )
    }

    func confirmNumericRefreshChanges() -> Bool {
        featureStore.confirmLibraryNumericRefreshChanges(mutationService: mutationService)
    }

    func createDrawersFromPreview() -> LibraryFeatureStore.MutationCommitContext? {
        featureStore.createDrawersFromPreview(mutationService: mutationService)
    }

    func createDrawersForSelection(batchId: String?, sampleId: String?) -> LibraryFeatureStore.MutationCommitContext? {
        featureStore.createDrawersForSelection(
            mutationService: mutationService,
            batchId: batchId,
            sampleId: sampleId
        )
    }

    func deleteExistingDrawer(batchId: String) -> LibraryFeatureStore.MutationCommitContext? {
        featureStore.deleteExistingDrawer(
            mutationService: mutationService,
            batchId: batchId
        )
    }
}
