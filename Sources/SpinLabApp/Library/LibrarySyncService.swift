import Foundation

struct LibraryApplyBatchResult {
    var touchedSamples: Int
    var failedSamples: Int
    var batchAction: String
    /// Non-nil when the files were changed but the index could not be brought in line with them.
    var indexError: String? = nil
    var failures: [String] = []
    var isPartial: Bool { failedSamples > 0 || indexError != nil }
}

/// Real outcome of `applyAll`: what actually succeeded on disk and what did not.
struct LibraryApplyAllResult {
    var succeeded: Int
    var failures: [String]
    var indexError: String?
    var isPartial: Bool { !failures.isEmpty || indexError != nil }
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

    func syncIndexFromFilesystem(rootURL: URL) throws -> LibraryIndex {
        try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
    }

    // MARK: - Diff & Review

    /// Read-only: never creates, migrates or saves anything.
    func diff(rootURL: URL, previewIndex: LibraryIndex) throws -> (baseline: LibraryIndex, diff: LibraryDiff) {
        let baseline = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL)
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
            // Display-only diff: read-only, and if the Library cannot be read completely
            // (or the root is missing) there is no honest diff to show.
            guard let complete = try? libraryStore.readOnlyCompleteIndex(rootURL: rootURL) else {
                return nil
            }
            effectiveBaseline = complete
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
        let baselineIndex: LibraryIndex
        do {
            baselineIndex = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL)
        } catch {
            return .failure(message: "Sync review stopped: \(error.localizedDescription)")
        }
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
        let diff: LibraryDiff
        do {
            diff = try self.diff(rootURL: rootURL, previewIndex: preview.index).diff
        } catch {
            return .failure(message: "Refresh stopped: \(error.localizedDescription)")
        }
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
    ) throws -> LibraryApplyBatchResult? {
        // 1. Non-destructive preflight validation: verify Library completeness before any mutation
        let preflightIndex = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL)

        // Preflight safety assessment based on read-only diff before ANY mutation (S1, S2, AC2, AC4)
        let preDiff = libraryDiffEngine.diff(current: preflightIndex, updated: preview.index)
        let preNewSamples = preDiff.newSamples.filter { $0.batchId == batchId }
        let preRemovedSamples = preDiff.removedSamples.filter { $0.batchId == batchId }
        let preRemovedBatches = preDiff.removedBatches.filter { $0.id == batchId }

        try LibraryMutationSafetyGuard.validateRegistryDiffSafety(
            removedSamples: preRemovedSamples,
            newSamples: preNewSamples,
            removedBatches: preRemovedBatches,
            baselineIndex: preflightIndex,
            rootURL: rootURL,
            fileManager: libraryStore.fileManager
        )

        // 2. Reconcile any stale sample keys in batch.json (e.g. from previous partial deletion failure)
        let reconciled = try libraryStore.reconcileBatchSampleKeys(rootURL: rootURL, batchID: batchId)
        let reconciledStaleKeys = reconciled[batchId] ?? []

        // 3. Authoritative baseline derived from post-reconciliation filesystem state
        let baselineIndex = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        let diff = libraryDiffEngine.diff(current: baselineIndex, updated: preview.index)
        let batchesByIDInPreview = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })

        let newSamples = diff.newSamples.filter { $0.batchId == batchId }
        let changedSamples = diff.changedSamples.filter { $0.sample.batchId == batchId }.map(\.sample)
        let removedSamples = diff.removedSamples.filter { $0.batchId == batchId }
        let changedBatch = diff.changedBatches.first { $0.batch.id == batchId }?.batch
        let removedBatch = diff.removedBatches.contains { $0.id == batchId }

        guard !newSamples.isEmpty || !changedSamples.isEmpty || !removedSamples.isEmpty || changedBatch != nil || removedBatch || !reconciledStaleKeys.isEmpty else {
            return nil
        }

        var touched = !reconciledStaleKeys.isEmpty ? 1 : 0
        var failed = 0
        var failures: [String] = []
        for sample in newSamples {
            guard let batch = batchesByIDInPreview[sample.batchId] else { continue }
            do {
                try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
                touched += 1
            } catch {
                failed += 1
                failures.append("createDrawer \(sample.id): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyBatch] createDrawer failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }
        for sample in changedSamples {
            do {
                try libraryStore.updateSample(sample, rootURL: rootURL)
                touched += 1
            } catch {
                failed += 1
                failures.append("updateSample \(sample.id): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyBatch] updateSample failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }
        var successfullyDeletedSampleIDs: Set<String> = []
        for sample in removedSamples {
            do {
                try libraryStore.deleteSampleDrawer(for: sample, rootURL: rootURL)
                touched += 1
                successfullyDeletedSampleIDs.insert(sample.id)
            } catch let LibraryDrawerError.batchUpdateFailedAfterSampleDeletion(sampleId, _, underlyingError) {
                failed += 1
                successfullyDeletedSampleIDs.insert(sampleId)
                failures.append("deleteSampleDrawer \(sample.id): Sample deleted but batch.json update failed: \(underlyingError)")
                fputs("[LibrarySyncService.applyBatch] deleteSampleDrawer: Sample \(sample.id) deleted but batch.json update failed: \(underlyingError)\n", stderr)
            } catch {
                failed += 1
                failures.append("deleteSampleDrawer \(sample.id): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyBatch] deleteSampleDrawer failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }

        if removedBatch {
            do {
                try libraryStore.deleteBatchDrawer(batchID: batchId, rootURL: rootURL)
            } catch {
                failed += 1
                failures.append("deleteBatchDrawer \(batchId): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyBatch] deleteBatchDrawer failed for \(batchId): \(error.localizedDescription)\n", stderr)
            }
        } else if let batch = changedBatch ?? batchesByIDInPreview[batchId], (!newSamples.isEmpty || !changedSamples.isEmpty || !removedSamples.isEmpty || changedBatch != nil) {
            do {
                var batchToUpdate = batch
                let existingBatch = baselineIndex.batches.first { $0.id == batchId }
                if batchToUpdate.origin == nil || batchToUpdate.origin?.isEmpty == true {
                    batchToUpdate.origin = existingBatch?.origin
                }
                let nativeKeys = baselineIndex.samples
                    .filter { $0.batchId == batchId && $0.isNativeOrManual }
                    .map(\.id)
                let plannedRemoved = Set(removedSamples.map(\.id))
                let failedDeletions = plannedRemoved.subtracting(successfullyDeletedSampleIDs)
                batchToUpdate.sampleKeys = Set(batch.sampleKeys)
                    .union(nativeKeys)
                    .union(failedDeletions)
                    .subtracting(successfullyDeletedSampleIDs)
                    .sorted()
                try libraryStore.updateBatch(batchToUpdate, rootURL: rootURL)
            } catch {
                failed += 1
                failures.append("updateBatch \(batchId): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyBatch] updateBatch failed for \(batchId): \(error.localizedDescription)\n", stderr)
            }
        }

        // The index must reflect what is actually on disk now. If it cannot be rebuilt or
        // written, report that explicitly (files were already changed) instead of throwing.
        var indexError: String?
        do {
            var syncedIndex = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
            syncedIndex.updatedAt = .now
            syncedIndex.registryInternalPath = settings.registryInternalPath
            syncedIndex.registrySourcePath = settings.registrySourcePath
            syncedIndex.metadataColumnOrder = preview.index.metadataColumnOrder
            if !libraryStore.saveIndex(syncedIndex, to: rootURL) {
                indexError = "the index could not be written"
            }
        } catch {
            indexError = error.localizedDescription
        }

        return LibraryApplyBatchResult(
            touchedSamples: touched,
            failedSamples: failed,
            batchAction: removedBatch ? "removed" : "updated",
            indexError: indexError,
            failures: failures
        )
    }

    @discardableResult
    func applyAll(preview: LibraryPreview, rootURL: URL, settings: LibrarySettings) throws -> LibraryApplyAllResult {
        // 1. Non-destructive preflight validation: verify Library completeness before any mutation
        let preflightIndex = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL)

        // Preflight safety assessment based on read-only diff before ANY mutation (S1, S2, AC2, AC4)
        let preDiff = libraryDiffEngine.diff(current: preflightIndex, updated: preview.index)

        try LibraryMutationSafetyGuard.validateRegistryDiffSafety(
            removedSamples: preDiff.removedSamples,
            newSamples: preDiff.newSamples,
            removedBatches: preDiff.removedBatches,
            baselineIndex: preflightIndex,
            rootURL: rootURL,
            fileManager: libraryStore.fileManager
        )

        var touchedBatchIDs: Set<String> = []
        var succeeded = 0
        var failures: [String] = []

        // 2. Reconcile any stale sample keys across batches from previous partial failures
        let reconciled = try libraryStore.reconcileBatchSampleKeys(rootURL: rootURL)
        for (batchID, staleKeys) in reconciled where !staleKeys.isEmpty {
            touchedBatchIDs.insert(batchID)
            succeeded += 1
        }

        // 3. Authoritative baseline derived from post-reconciliation filesystem state
        let baselineIndex = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        let diff = libraryDiffEngine.diff(current: baselineIndex, updated: preview.index)
        let batchesByIDInPreview = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })

        for sample in diff.newSamples {
            guard let batch = batchesByIDInPreview[sample.batchId] else {
                continue
            }
            do {
                try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
                touchedBatchIDs.insert(batch.id)
                succeeded += 1
            } catch {
                failures.append("createDrawer \(sample.id): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyAll] createDrawer failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }

        for change in diff.changedSamples {
            let sample = change.sample
            do {
                try libraryStore.updateSample(sample, rootURL: rootURL)
                touchedBatchIDs.insert(sample.batchId)
                succeeded += 1
            } catch {
                failures.append("updateSample \(sample.id): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyAll] updateSample failed for \(sample.id): \(error.localizedDescription)\n", stderr)
            }
        }

        var successfullyDeletedSampleIDs: Set<String> = []
        for removedSample in diff.removedSamples {
            do {
                try libraryStore.deleteSampleDrawer(for: removedSample, rootURL: rootURL)
                touchedBatchIDs.insert(removedSample.batchId)
                succeeded += 1
                successfullyDeletedSampleIDs.insert(removedSample.id)
            } catch let LibraryDrawerError.batchUpdateFailedAfterSampleDeletion(sampleId, _, underlyingError) {
                touchedBatchIDs.insert(removedSample.batchId)
                successfullyDeletedSampleIDs.insert(sampleId)
                failures.append("deleteSampleDrawer \(removedSample.id): Sample deleted but batch.json update failed: \(underlyingError)")
                fputs("[LibrarySyncService.applyAll] deleteSampleDrawer: Sample \(removedSample.id) deleted but batch.json update failed: \(underlyingError)\n", stderr)
            } catch {
                failures.append("deleteSampleDrawer \(removedSample.id): \(error.localizedDescription)")
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
                var batchToUpdate = batch
                let existingBatch = baselineIndex.batches.first { $0.id == batchID }
                if batchToUpdate.origin == nil || batchToUpdate.origin?.isEmpty == true {
                    batchToUpdate.origin = existingBatch?.origin
                }
                let nativeKeys = baselineIndex.samples
                    .filter { $0.batchId == batchID && $0.isNativeOrManual }
                    .map(\.id)
                let plannedRemoved = Set(diff.removedSamples.filter { $0.batchId == batchID }.map(\.id))
                let failedDeletions = plannedRemoved.subtracting(successfullyDeletedSampleIDs)
                batchToUpdate.sampleKeys = Set(batch.sampleKeys)
                    .union(nativeKeys)
                    .union(failedDeletions)
                    .subtracting(successfullyDeletedSampleIDs)
                    .sorted()
                try libraryStore.updateBatch(batchToUpdate, rootURL: rootURL)
                succeeded += 1
            } catch {
                failures.append("updateBatch \(batchID): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyAll] updateBatch failed for \(batchID): \(error.localizedDescription)\n", stderr)
            }
        }

        for removedBatch in diff.removedBatches {
            do {
                try libraryStore.deleteBatchDrawer(batchID: removedBatch.id, rootURL: rootURL)
                succeeded += 1
            } catch {
                failures.append("deleteBatchDrawer \(removedBatch.id): \(error.localizedDescription)")
                fputs("[LibrarySyncService.applyAll] deleteBatchDrawer failed for \(removedBatch.id): \(error.localizedDescription)\n", stderr)
            }
        }

        // The saved index must describe what is really on disk, not the planned registry
        // state. If it cannot be rebuilt or written, say so explicitly.
        var indexError: String?
        do {
            var rebuilt = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
            rebuilt.updatedAt = .now
            rebuilt.registryInternalPath = settings.registryInternalPath
            rebuilt.registrySourcePath = settings.registrySourcePath
            rebuilt.metadataColumnOrder = preview.index.metadataColumnOrder
            if !libraryStore.saveIndex(rebuilt, to: rootURL) {
                indexError = "the index could not be written"
            }
        } catch {
            indexError = error.localizedDescription
        }
        return LibraryApplyAllResult(succeeded: succeeded, failures: failures, indexError: indexError)
    }
}
