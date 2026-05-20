import Foundation

extension LibraryFeatureStore {

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
}
