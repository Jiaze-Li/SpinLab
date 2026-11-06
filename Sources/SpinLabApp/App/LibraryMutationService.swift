import Foundation

enum LibraryRefreshIncrementalMutationOutcome {
    case failure(message: String)
    case success(rootURL: URL, previewIndex: LibraryIndex, message: String)
    /// Some changes were applied and some were not (or the index could not be brought in
    /// line). Files DID change, so callers must refresh, but must not report success.
    case partial(rootURL: URL, previewIndex: LibraryIndex, message: String)
}

enum LibraryCreateDrawersMutationOutcome {
    case failure(message: String)
    case success(rootURL: URL, previewIndex: LibraryIndex, createdCount: Int, message: String)
    case partial(rootURL: URL, previewIndex: LibraryIndex, createdCount: Int, message: String)
}

enum LibraryDeleteDrawerMutationOutcome {
    case failure(message: String)
    case success(rootURL: URL, previewIndex: LibraryIndex?, message: String)
}

struct LibraryCommitMutationOutcome {
    var syncedIndex: LibraryIndex
    var plan: CommitLibraryMutationPlan
}

struct LibrarySyncChangeIndicators {
    var batchStatusByID: [String: LibrarySyncBatchStatus]
    var sampleChangesByID: [String: [LibraryFieldChange]]
    var batchChangesByID: [String: [LibraryFieldChange]]
}

enum LibraryPrepareSyncReviewMutationOutcome {
    case failure(message: String)
    case success(
        review: LibraryRefreshReview,
        diff: LibraryDiff,
        baselineIndex: LibraryIndex,
        message: String,
        indicators: LibrarySyncChangeIndicators
    )
}

enum LibraryConfirmNumericRefreshOutcome {
    case failure(message: String)
    case success(updatedReview: LibraryRefreshReview, appliedCount: Int, lastRefreshAt: Date)
}

struct LibraryMutationService {
    func refreshIncremental(
        librarySyncService: LibrarySyncService,
        preview: LibraryPreview?,
        rootPath: String?,
        settings: LibrarySettings
    ) -> LibraryRefreshIncrementalMutationOutcome {
        let planResult = librarySyncService.planIncrementalRefresh(
            preview: preview,
            rootPath: rootPath
        )
        let plan: RefreshLibraryIncrementalPlan
        switch planResult {
        case let .failure(message):
            return .failure(message: message)
        case let .success(value):
            plan = value
        }

        let result: LibraryApplyAllResult
        do {
            result = try librarySyncService.applyAll(preview: plan.preview, rootURL: plan.rootURL, settings: settings)
        } catch {
            return .failure(message: "Refresh stopped: \(error.localizedDescription)")
        }
        guard result.isPartial else {
            return .success(rootURL: plan.rootURL, previewIndex: plan.preview.index, message: plan.message)
        }
        var message = "PARTIAL: \(result.succeeded) change(s) applied, \(result.failures.count) failed"
        if let first = result.failures.first { message += " (first: \(first))" }
        if let indexError = result.indexError { message += "; the index may not match the files: \(indexError)" }
        message += ". Files were changed and nothing was rolled back; fix the cause and run Sync from files, then Refresh again."
        return .partial(rootURL: plan.rootURL, previewIndex: plan.preview.index, message: message)
    }

    /// Rebuilds the index from what is really on disk and saves it. Returns an error text, or nil.
    private func rebuildIndexFromDisk(
        libraryStore: LibraryStore,
        rootURL: URL,
        settings: LibrarySettings,
        metadataColumnOrder: [String]
    ) -> String? {
        do {
            var index = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
            index.updatedAt = .now
            index.registryInternalPath = settings.registryInternalPath
            index.registrySourcePath = settings.registrySourcePath
            index.metadataColumnOrder = metadataColumnOrder
            return libraryStore.saveIndex(index, to: rootURL) ? nil : "the index could not be written"
        } catch {
            return error.localizedDescription
        }
    }

    private func createOutcome(
        rootURL: URL,
        preview: LibraryPreview,
        created: Int,
        planned: Int,
        failure: String?,
        indexError: String?
    ) -> LibraryCreateDrawersMutationOutcome {
        guard failure != nil || indexError != nil else {
            return .success(rootURL: rootURL, previewIndex: preview.index, createdCount: created,
                            message: "Created \(created) sample drawers.")
        }
        var message = "PARTIAL: created \(created) of \(planned) drawers"
        if let failure { message += "; stopped at \(failure)" }
        if let indexError { message += "; the index may not match the files: \(indexError)" }
        message += ". Created drawers were kept; fix the cause and run Sync from files."
        return .partial(rootURL: rootURL, previewIndex: preview.index, createdCount: created, message: message)
    }

    func createDrawersFromPreview(
        preview: LibraryPreview?,
        rootPath: String?,
        libraryStore: LibraryStore,
        settings: LibrarySettings
    ) -> LibraryCreateDrawersMutationOutcome {
        guard let preview else {
            return .failure(message: "Load the registry preview first.")
        }
        guard let rootPath else {
            return .failure(message: "Select a Library Root first.")
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)
        // An unreadable existing Library must never be treated as an empty one.
        do { _ = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL) } catch {
            return .failure(message: "Create stopped: \(error.localizedDescription)")
        }

        let batchesById = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })
        var created = 0
        var planned = 0
        var failure: String?
        for sample in preview.index.samples {
            guard let batch = batchesById[sample.batchId] else {
                continue
            }
            planned += 1
            do {
                try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
                created += 1
            } catch {
                failure = "\(sample.id): \(error.localizedDescription)"
                break
            }
        }
        if failure != nil, created == 0 {
            return .failure(message: "Failed to create drawer for \(failure ?? "")")
        }

        // The saved index describes the files that now exist (existing content is kept).
        let indexError = rebuildIndexFromDisk(
            libraryStore: libraryStore, rootURL: rootURL, settings: settings,
            metadataColumnOrder: preview.index.metadataColumnOrder)
        return createOutcome(rootURL: rootURL, preview: preview, created: created, planned: planned,
                             failure: failure, indexError: indexError)
    }

    func createDrawersForSelection(
        preview: LibraryPreview?,
        rootPath: String?,
        batchId: String?,
        sampleId: String?,
        libraryStore: LibraryStore,
        settings: LibrarySettings
    ) -> LibraryCreateDrawersMutationOutcome {
        guard let preview else {
            return .failure(message: "Load the registry preview first.")
        }
        guard let rootPath else {
            return .failure(message: "Select a Library Root first.")
        }
        guard let batchId else {
            return .failure(message: "Select a batch or sample.")
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)
        do { _ = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL) } catch {
            return .failure(message: "Create stopped: \(error.localizedDescription)")
        }

        let batchesById = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })
        guard let batch = batchesById[batchId] else {
            return .failure(message: "Selected batch not found.")
        }

        let samples = preview.index.samples.filter { $0.batchId == batchId }
        let targetSamples: [LibrarySample]
        if let sampleId, let sample = samples.first(where: { $0.id == sampleId }) {
            targetSamples = [sample]
        } else {
            targetSamples = samples
        }
        guard !targetSamples.isEmpty else {
            return .failure(message: "No samples found for selection.")
        }

        var createdSamples: [LibrarySample] = []
        var failure: String?
        for sample in targetSamples {
            do {
                try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
                createdSamples.append(sample)
            } catch {
                failure = "\(sample.id): \(error.localizedDescription)"
                break
            }
        }
        if failure != nil, createdSamples.isEmpty {
            return .failure(message: "Failed to create drawer for \(failure ?? "")")
        }

        // Baseline was verified complete above, so merging into it cannot drop unread content.
        let baselineIndex = libraryStore.loadIndex(from: rootURL)
            ?? LibraryIndex(
                createdAt: .now,
                updatedAt: .now,
                registryInternalPath: settings.registryInternalPath,
                registrySourcePath: settings.registrySourcePath,
                metadataColumnOrder: [],
                batches: [],
                samples: []
            )
        var samplesByID = Dictionary(uniqueKeysWithValues: baselineIndex.samples.map { ($0.id, $0) })
        for sample in createdSamples {
            samplesByID[sample.id] = sample
        }

        var batchesByID = Dictionary(uniqueKeysWithValues: baselineIndex.batches.map { ($0.id, $0) })
        var mergedBatch = batchesByID[batch.id] ?? batch
        let mergedSampleKeys = Set(mergedBatch.sampleKeys).union(createdSamples.map(\.id))
        mergedBatch.sampleKeys = mergedSampleKeys.sorted()
        mergedBatch.metadata = batch.metadata
        mergedBatch.numericTags = batch.numericTags
        mergedBatch.numericDisplay = batch.numericDisplay
        mergedBatch.sheetName = batch.sheetName
        mergedBatch.updatedAt = .now
        batchesByID[batch.id] = mergedBatch

        var index = baselineIndex
        index.updatedAt = .now
        index.registryInternalPath = settings.registryInternalPath
        index.registrySourcePath = settings.registrySourcePath
        index.metadataColumnOrder = preview.index.metadataColumnOrder
        index.samples = Array(samplesByID.values).sorted { $0.displayName < $1.displayName }
        index.batches = Array(batchesByID.values).sorted { $0.id < $1.id }
        let indexError: String? = libraryStore.saveIndex(index, to: rootURL) ? nil : "the index could not be written"

        return createOutcome(rootURL: rootURL, preview: preview, created: createdSamples.count,
                             planned: targetSamples.count, failure: failure, indexError: indexError)
    }

    func deleteExistingDrawer(
        batchId: String,
        rootPath: String?,
        previewIndex: LibraryIndex?,
        libraryStore: LibraryStore
    ) -> LibraryDeleteDrawerMutationOutcome {
        guard let rootPath else {
            return .failure(message: "Select a Library Root first.")
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        // Validate completeness BEFORE deleting anything: an unreadable batch or sample must
        // never look like "not there" and must never be dropped from the saved index.
        let baselineIndex: LibraryIndex
        do {
            baselineIndex = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        } catch {
            return .failure(message: "Delete stopped: \(error.localizedDescription)")
        }
        let targetSamples = baselineIndex.samples.filter { $0.batchId == batchId }
        let targetBatch = baselineIndex.batches.first { $0.id == batchId }
        guard targetBatch != nil || !targetSamples.isEmpty else {
            return .failure(message: "Drawer \(batchId) not found.")
        }

        for sample in targetSamples {
            do {
                try libraryStore.deleteSampleDrawer(for: sample, rootURL: rootURL)
            } catch {
                return .failure(message: "Failed to delete drawer for \(sample.id): \(error.localizedDescription)")
            }
        }
        do {
            try libraryStore.deleteBatchDrawer(batchID: batchId, rootURL: rootURL)
        } catch {
            return .failure(message: "Failed to delete batch drawer \(batchId): \(error.localizedDescription)")
        }

        var index = baselineIndex
        index.updatedAt = .now
        index.samples.removeAll { $0.batchId == batchId }
        index.batches.removeAll { $0.id == batchId }
        guard libraryStore.saveIndex(index, to: rootURL) else {
            return .failure(message: "Deleted drawer \(batchId) but the index could not be updated; run Sync from files.")
        }

        return .success(
            rootURL: rootURL,
            previewIndex: previewIndex,
            message: "Deleted drawer \(batchId) (\(targetSamples.count) samples)."
        )
    }

    func commitMutation(
        rootURL: URL,
        previewIndex: LibraryIndex?,
        precomputedDiff: LibraryDiff?,
        precomputedReview: LibraryRefreshReview?,
        librarySyncService: LibrarySyncService
    ) throws -> LibraryCommitMutationOutcome {
        let syncedIndex = try librarySyncService.syncIndexFromFilesystem(rootURL: rootURL)
        let plan = librarySyncService.makeCommitPlan(
            syncedIndex: syncedIndex,
            previewIndex: previewIndex,
            precomputedDiff: precomputedDiff,
            precomputedReview: precomputedReview
        )
        return LibraryCommitMutationOutcome(syncedIndex: syncedIndex, plan: plan)
    }

    func prepareSyncReview(
        preview: LibraryPreview?,
        rootPath: String?,
        precomputedDiff: LibraryDiff?,
        librarySyncService: LibrarySyncService
    ) -> LibraryPrepareSyncReviewMutationOutcome {
        let result = librarySyncService.prepareLibrarySyncReview(
            preview: preview,
            rootPath: rootPath,
            precomputedDiff: precomputedDiff
        )
        switch result {
        case let .failure(message):
            return .failure(message: message)
        case let .success(plan):
            return .success(
                review: plan.review,
                diff: plan.diff,
                baselineIndex: plan.baselineIndex,
                message: plan.message,
                indicators: makeSyncChangeIndicators(review: plan.review)
            )
        }
    }

    func confirmNumericRefreshChanges(
        review: LibraryRefreshReview?,
        preview: LibraryPreview?,
        rootPath: String?,
        settings: LibrarySettings,
        libraryStore: LibraryStore
    ) -> LibraryConfirmNumericRefreshOutcome {
        guard let review else {
            return .failure(message: "No refresh review available.")
        }
        guard !review.deferredNumericChanges.isEmpty else {
            return .failure(message: "No numeric changes pending confirmation.")
        }
        guard let preview else {
            return .failure(message: "Load the registry preview first.")
        }
        guard let rootPath else {
            return .failure(message: "Select a Library Root first.")
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let baselineIndex = libraryStore.loadIndex(from: rootURL)
            ?? LibraryIndex(
                createdAt: .now,
                updatedAt: .now,
                registryInternalPath: settings.registryInternalPath,
                registrySourcePath: settings.registrySourcePath,
                metadataColumnOrder: [],
                batches: [],
                samples: []
            )
        var mergedSamplesByID = Dictionary(uniqueKeysWithValues: baselineIndex.samples.map { ($0.id, $0) })
        var mergedBatchesByID = Dictionary(uniqueKeysWithValues: baselineIndex.batches.map { ($0.id, $0) })
        let batchesByIDInPreview = Dictionary(uniqueKeysWithValues: preview.index.batches.map { ($0.id, $0) })
        var touchedBatchIDs: Set<String> = []

        for change in review.deferredNumericChanges {
            let sample = change.sample
            mergedSamplesByID[sample.id] = sample
            do {
                try libraryStore.updateSample(sample, rootURL: rootURL)
            } catch {
                return .failure(message: "Failed to update sample \(sample.id): \(error.localizedDescription)")
            }
            touchedBatchIDs.insert(sample.batchId)
        }

        for batchID in touchedBatchIDs {
            guard let batch = batchesByIDInPreview[batchID] else {
                continue
            }
            mergedBatchesByID[batchID] = batch
            do {
                try libraryStore.updateBatch(batch, rootURL: rootURL)
            } catch {
                return .failure(message: "Failed to update batch \(batchID): \(error.localizedDescription)")
            }
        }

        var mergedIndex = baselineIndex
        mergedIndex.updatedAt = .now
        mergedIndex.registryInternalPath = settings.registryInternalPath
        mergedIndex.registrySourcePath = settings.registrySourcePath
        mergedIndex.metadataColumnOrder = preview.index.metadataColumnOrder
        mergedIndex.samples = Array(mergedSamplesByID.values).sorted { $0.displayName < $1.displayName }
        mergedIndex.batches = Array(mergedBatchesByID.values).sorted { $0.id < $1.id }
        libraryStore.saveIndex(mergedIndex, to: rootURL)

        let updatedReview = LibraryRefreshReview(
            generatedAt: review.generatedAt,
            newSamples: review.newSamples,
            changedSamples: review.changedSamples,
            removedSamples: review.removedSamples,
            changedBatches: review.changedBatches,
            removedBatches: review.removedBatches,
            autoAppliedChanges: review.autoAppliedChanges + review.deferredNumericChanges,
            deferredNumericChanges: []
        )

        return .success(
            updatedReview: updatedReview,
            appliedCount: review.deferredNumericChanges.count,
            lastRefreshAt: Date()
        )
    }

    func makeSyncChangeIndicators(review: LibraryRefreshReview?) -> LibrarySyncChangeIndicators {
        guard let review else {
            return LibrarySyncChangeIndicators(
                batchStatusByID: [:],
                sampleChangesByID: [:],
                batchChangesByID: [:]
            )
        }

        var batchStatus: [String: LibrarySyncBatchStatus] = [:]
        for sample in review.newSamples {
            batchStatus[sample.batchId] = .added
        }
        for change in review.changedSamples where batchStatus[change.sample.batchId] != .added {
            batchStatus[change.sample.batchId] = .changed
        }
        for sample in review.removedSamples where batchStatus[sample.batchId] != .added {
            batchStatus[sample.batchId] = .changed
        }
        for change in review.changedBatches where batchStatus[change.batch.id] != .added {
            batchStatus[change.batch.id] = .changed
        }
        for batch in review.removedBatches {
            batchStatus[batch.id] = .removed
        }

        return LibrarySyncChangeIndicators(
            batchStatusByID: batchStatus,
            sampleChangesByID: Dictionary(uniqueKeysWithValues: review.changedSamples.map { ($0.sample.id, $0.fieldChanges) }),
            batchChangesByID: Dictionary(uniqueKeysWithValues: review.changedBatches.map { ($0.batch.id, $0.fieldChanges) })
        )
    }
}
