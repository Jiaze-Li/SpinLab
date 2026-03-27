import Foundation

struct LibraryActionablePreviewState {
    var groups: [String: [LibraryPreviewBatchGroup]]
    var message: String
}

struct PrepareLibrarySyncReviewPlan {
    var rootURL: URL
    var baselineIndex: LibraryIndex
    var diff: LibraryDiff
    var review: LibraryRefreshReview
    var message: String
}

enum PrepareLibrarySyncReviewResult {
    case failure(message: String)
    case success(PrepareLibrarySyncReviewPlan)
}

struct RefreshLibraryIncrementalPlan {
    var rootURL: URL
    var preview: LibraryPreview
    var diff: LibraryDiff
    var message: String
}

enum RefreshLibraryIncrementalResult {
    case failure(message: String)
    case success(RefreshLibraryIncrementalPlan)
}

struct CommitLibraryMutationPlan {
    var review: LibraryRefreshReview?
    var diff: LibraryDiff?
    var baselineIndexForPreview: LibraryIndex?
    var lastRefreshAt: Date
}

struct LibraryMutationOrchestrator {
    func diffAgainstExisting(
        previewIndex: LibraryIndex,
        baselineIndex: LibraryIndex?,
        rootPath: String?,
        libraryStore: LibraryStore,
        libraryDiffEngine: LibraryDiffEngine
    ) -> LibraryDiff? {
        let effectiveBaseline: LibraryIndex
        if let baselineIndex {
            effectiveBaseline = baselineIndex
        } else {
            guard let rootPath else {
                return nil
            }
            let rootURL = URL(fileURLWithPath: rootPath)
            effectiveBaseline = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        }
        return libraryDiffEngine.diff(current: effectiveBaseline, updated: previewIndex)
    }

    func buildActionablePreviewState(
        preview: LibraryPreview,
        precomputedDiff: LibraryDiff?,
        baselineIndex: LibraryIndex?,
        rootPath: String?,
        libraryStore: LibraryStore,
        libraryDiffEngine: LibraryDiffEngine,
        previewComputationService: LibraryPreviewComputationService
    ) -> LibraryActionablePreviewState {
        let diff = precomputedDiff ?? diffAgainstExisting(
            previewIndex: preview.index,
            baselineIndex: baselineIndex,
            rootPath: rootPath,
            libraryStore: libraryStore,
            libraryDiffEngine: libraryDiffEngine
        )
        let removedCount = diff?.removedSamples.count ?? 0
        let newCount = diff?.newSamples.count ?? preview.index.samples.count
        let actionable = previewComputationService.actionablePreviewIndex(
            from: preview.index,
            diff: diff,
            hasLibraryRoot: rootPath != nil
        )
        let groups = previewComputationService.buildPreviewGroups(from: actionable)
        let changedCount = max(actionable.samples.count - newCount, 0)
        return LibraryActionablePreviewState(
            groups: groups,
            message: "Sync diff loaded: \(actionable.samples.count) actionable (\(newCount) new, \(changedCount) changed, \(removedCount) removed)"
        )
    }

    func prepareLibrarySyncReview(
        preview: LibraryPreview?,
        rootPath: String?,
        precomputedDiff: LibraryDiff?,
        libraryStore: LibraryStore,
        libraryDiffEngine: LibraryDiffEngine,
        librarySyncService: LibrarySyncService
    ) -> PrepareLibrarySyncReviewResult {
        guard let preview else {
            return .failure(message: "Load the registry preview first.")
        }
        guard let rootPath else {
            return .failure(message: "Select a Library Root first.")
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let baselineIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        let diff = precomputedDiff ?? libraryDiffEngine.diff(current: baselineIndex, updated: preview.index)
        let review = librarySyncService.makeReview(diff: diff)
        let message = "Sync review prepared: \(diff.newSamples.count) new, \(diff.changedSamples.count) changed, \(diff.removedSamples.count) removed."

        return .success(
            PrepareLibrarySyncReviewPlan(
                rootURL: rootURL,
                baselineIndex: baselineIndex,
                diff: diff,
                review: review,
                message: message
            )
        )
    }

    func planIncrementalRefresh(
        preview: LibraryPreview?,
        rootPath: String?,
        libraryStore: LibraryStore,
        librarySyncService: LibrarySyncService
    ) -> RefreshLibraryIncrementalResult {
        guard let preview else {
            return .failure(message: "Load the registry preview first.")
        }
        guard let rootPath else {
            return .failure(message: "Select a Library Root first.")
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)
        let (_, diff) = librarySyncService.diff(rootURL: rootURL, previewIndex: preview.index)
        let message = "Registry aligned: \(diff.newSamples.count) new, \(diff.changedSamples.count) changed, \(diff.removedSamples.count) removed, \(diff.changedBatches.count) batch updates, \(diff.removedBatches.count) batch removals."

        return .success(
            RefreshLibraryIncrementalPlan(
                rootURL: rootURL,
                preview: preview,
                diff: diff,
                message: message
            )
        )
    }

    func makeCommitPlan(
        syncedIndex: LibraryIndex,
        previewIndex: LibraryIndex?,
        precomputedDiff: LibraryDiff?,
        precomputedReview: LibraryRefreshReview?,
        libraryDiffEngine: LibraryDiffEngine,
        librarySyncService: LibrarySyncService
    ) -> CommitLibraryMutationPlan {
        if let previewIndex {
            let diff = precomputedDiff ?? libraryDiffEngine.diff(current: syncedIndex, updated: previewIndex)
            let review = precomputedReview ?? librarySyncService.makeReview(diff: diff)
            return CommitLibraryMutationPlan(
                review: review,
                diff: diff,
                baselineIndexForPreview: syncedIndex,
                lastRefreshAt: Date()
            )
        }

        return CommitLibraryMutationPlan(
            review: nil,
            diff: nil,
            baselineIndexForPreview: nil,
            lastRefreshAt: Date()
        )
    }
}
