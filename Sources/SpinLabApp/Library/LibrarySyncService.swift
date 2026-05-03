import Foundation

struct LibraryApplyBatchResult {
    var touchedSamples: Int
    var failedSamples: Int
    var batchAction: String
}

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

final class LibrarySyncService {
    private let libraryStore: LibraryStore
    private let libraryDiffEngine: LibraryDiffEngine

    init(libraryStore: LibraryStore, libraryDiffEngine: LibraryDiffEngine) {
        self.libraryStore = libraryStore
        self.libraryDiffEngine = libraryDiffEngine
    }

    // MARK: - Index

    func syncIndexFromFilesystem(rootURL: URL) -> LibraryIndex {
        libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
    }

    // MARK: - Diff & Review

    func diff(rootURL: URL, previewIndex: LibraryIndex) -> (baseline: LibraryIndex, diff: LibraryDiff) {
        let baseline = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        return (baseline, libraryDiffEngine.diff(current: baseline, updated: previewIndex))
    }

    func diffAgainstExisting(
        previewIndex: LibraryIndex,
        baselineIndex: LibraryIndex?,
        rootPath: String?
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

    func makeReview(diff: LibraryDiff, generatedAt: Date = Date()) -> LibraryRefreshReview {
        LibraryRefreshReview(
            generatedAt: generatedAt,
            newSamples: diff.newSamples.sorted { $0.displayName < $1.displayName },
            changedSamples: diff.changedSamples.sorted { $0.sample.displayName < $1.sample.displayName },
            removedSamples: diff.removedSamples.sorted { $0.displayName < $1.displayName },
            changedBatches: diff.changedBatches.sorted { LibrarySort.compareBatch($0.batch.id, $1.batch.id) },
            removedBatches: diff.removedBatches.sorted { LibrarySort.compareBatch($0.id, $1.id) },
            autoAppliedChanges: diff.changedSamples.sorted { $0.sample.displayName < $1.sample.displayName },
            deferredNumericChanges: []
        )
    }

    // MARK: - Planning (formerly LibraryMutationOrchestrator)

    func buildActionablePreviewState(
        preview: LibraryPreview,
        precomputedDiff: LibraryDiff?,
        baselineIndex: LibraryIndex?,
        rootPath: String?,
        previewComputationService: LibraryPreviewComputationService
    ) -> LibraryActionablePreviewState {
        let diff = precomputedDiff ?? diffAgainstExisting(
            previewIndex: preview.index,
            baselineIndex: baselineIndex,
            rootPath: rootPath
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
        precomputedDiff: LibraryDiff?
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
        let review = makeReview(diff: diff)
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
        rootPath: String?
    ) -> RefreshLibraryIncrementalResult {
        guard let preview else {
            return .failure(message: "Load the registry preview first.")
        }
        guard let rootPath else {
            return .failure(message: "Select a Library Root first.")
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)
        let (_, diff) = self.diff(rootURL: rootURL, previewIndex: preview.index)
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
        precomputedReview: LibraryRefreshReview?
    ) -> CommitLibraryMutationPlan {
        if let previewIndex {
            let diff = precomputedDiff ?? libraryDiffEngine.diff(current: syncedIndex, updated: previewIndex)
            let review = precomputedReview ?? makeReview(diff: diff)
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

    // MARK: - Apply

    func applyBatch(
        batchId: String,
        preview: LibraryPreview,
        rootURL: URL,
        settings: LibrarySettings
    ) -> LibraryApplyBatchResult? {
        let baselineIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        let diff = libraryDiffEngine.diff(current: baselineIndex, updated: preview.index)
        let batchesByIDInPreview = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })

        let newSamples = diff.newSamples.filter { $0.batchId == batchId }
        let changedSamples = diff.changedSamples.filter { $0.sample.batchId == batchId }.map(\.sample)
        let removedSamples = diff.removedSamples.filter { $0.batchId == batchId }
        let changedBatch = diff.changedBatches.first { $0.batch.id == batchId }?.batch
        let removedBatch = diff.removedBatches.contains { $0.id == batchId }

        guard !newSamples.isEmpty || !changedSamples.isEmpty || !removedSamples.isEmpty || changedBatch != nil || removedBatch else {
            return nil
        }

        var touched = 0
        var failed = 0
        for sample in newSamples {
            guard let batch = batchesByIDInPreview[sample.batchId] else { continue }
            do {
                try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
                touched += 1
            } catch {
                failed += 1
                fputs("[LibrarySyncService.applyBatch] createDrawer failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }
        for sample in changedSamples {
            do {
                try libraryStore.updateSample(sample, rootURL: rootURL)
                touched += 1
            } catch {
                failed += 1
                fputs("[LibrarySyncService.applyBatch] updateSample failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }
        for sample in removedSamples {
            do {
                try libraryStore.deleteSampleDrawer(for: sample, rootURL: rootURL)
                touched += 1
            } catch {
                failed += 1
                fputs("[LibrarySyncService.applyBatch] deleteSampleDrawer failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }

        if removedBatch {
            do {
                try libraryStore.deleteBatchDrawer(batchID: batchId, rootURL: rootURL)
            } catch {
                fputs("[LibrarySyncService.applyBatch] deleteBatchDrawer failed for \(batchId): \(error.localizedDescription)\n", stderr)
            }
        } else if let batch = changedBatch ?? batchesByIDInPreview[batchId], (!newSamples.isEmpty || !changedSamples.isEmpty || !removedSamples.isEmpty || changedBatch != nil) {
            do {
                try libraryStore.updateBatch(batch, rootURL: rootURL)
            } catch {
                fputs("[LibrarySyncService.applyBatch] updateBatch failed for \(batchId): \(error.localizedDescription)\n", stderr)
            }
        }

        var syncedIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        syncedIndex.updatedAt = .now
        syncedIndex.registryInternalPath = settings.registryInternalPath
        syncedIndex.registrySourcePath = settings.registrySourcePath
        syncedIndex.metadataColumnOrder = preview.index.metadataColumnOrder
        libraryStore.saveIndex(syncedIndex, to: rootURL)

        return LibraryApplyBatchResult(
            touchedSamples: touched,
            failedSamples: failed,
            batchAction: removedBatch ? "removed" : "updated"
        )
    }

    func applyAll(preview: LibraryPreview, rootURL: URL, settings: LibrarySettings) {
        let baselineIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        let diff = libraryDiffEngine.diff(current: baselineIndex, updated: preview.index)
        let batchesByIDInPreview = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })
        var touchedBatchIDs: Set<String> = []

        for sample in diff.newSamples {
            guard let batch = batchesByIDInPreview[sample.batchId] else {
                continue
            }
            do {
                try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
                touchedBatchIDs.insert(batch.id)
            } catch {
                fputs("[LibrarySyncService.applyAll] createDrawer failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }

        for change in diff.changedSamples {
            let sample = change.sample
            do {
                try libraryStore.updateSample(sample, rootURL: rootURL)
                touchedBatchIDs.insert(sample.batchId)
            } catch {
                fputs("[LibrarySyncService.applyAll] updateSample failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }

        for removedSample in diff.removedSamples {
            do {
                try libraryStore.deleteSampleDrawer(for: removedSample, rootURL: rootURL)
                touchedBatchIDs.insert(removedSample.batchId)
            } catch {
                fputs("[LibrarySyncService.applyAll] deleteSampleDrawer failed for \(removedSample.id): \(error.localizedDescription)\n", stderr)
            }
        }

        for batchChange in diff.changedBatches {
            touchedBatchIDs.insert(batchChange.batch.id)
        }

        for batchID in touchedBatchIDs {
            guard let batch = batchesByIDInPreview[batchID] else {
                continue
            }
            do {
                try libraryStore.updateBatch(batch, rootURL: rootURL)
            } catch {
                fputs("[LibrarySyncService.applyAll] updateBatch failed for \(batchID): \(error.localizedDescription)\n", stderr)
            }
        }

        for removedBatch in diff.removedBatches {
            do {
                try libraryStore.deleteBatchDrawer(batchID: removedBatch.id, rootURL: rootURL)
            } catch {
                fputs("[LibrarySyncService.applyAll] deleteBatchDrawer failed for \(removedBatch.id): \(error.localizedDescription)\n", stderr)
            }
        }

        var mergedIndex = preview.index
        mergedIndex.updatedAt = .now
        mergedIndex.registryInternalPath = settings.registryInternalPath
        mergedIndex.registrySourcePath = settings.registrySourcePath
        libraryStore.saveIndex(mergedIndex, to: rootURL)
    }
}
