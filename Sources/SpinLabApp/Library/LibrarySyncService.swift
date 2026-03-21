import Foundation

struct LibraryApplyBatchResult {
    var touchedSamples: Int
    var batchAction: String
}

final class LibrarySyncService {
    private let libraryStore: LibraryStore
    private let libraryDiffEngine: LibraryDiffEngine

    init(libraryStore: LibraryStore, libraryDiffEngine: LibraryDiffEngine) {
        self.libraryStore = libraryStore
        self.libraryDiffEngine = libraryDiffEngine
    }

    func diff(rootURL: URL, previewIndex: LibraryIndex) -> (baseline: LibraryIndex, diff: LibraryDiff) {
        let baseline = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        return (baseline, libraryDiffEngine.diff(current: baseline, updated: previewIndex))
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
        for sample in newSamples {
            if let batch = batchesByIDInPreview[sample.batchId] {
                libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
                touched += 1
            }
        }
        for sample in changedSamples {
            libraryStore.updateSample(sample, rootURL: rootURL)
            touched += 1
        }
        for sample in removedSamples {
            libraryStore.deleteSampleDrawer(for: sample, rootURL: rootURL)
            touched += 1
        }

        if removedBatch {
            libraryStore.deleteBatchDrawer(batchID: batchId, rootURL: rootURL)
        } else if let batch = changedBatch ?? batchesByIDInPreview[batchId], (!newSamples.isEmpty || !changedSamples.isEmpty || !removedSamples.isEmpty || changedBatch != nil) {
            libraryStore.updateBatch(batch, rootURL: rootURL)
        }

        var syncedIndex = libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        syncedIndex.updatedAt = .now
        syncedIndex.registryInternalPath = settings.registryInternalPath
        syncedIndex.registrySourcePath = settings.registrySourcePath
        syncedIndex.metadataColumnOrder = preview.index.metadataColumnOrder
        libraryStore.saveIndex(syncedIndex, to: rootURL)

        return LibraryApplyBatchResult(
            touchedSamples: touched,
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
            libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
            touchedBatchIDs.insert(batch.id)
        }

        for change in diff.changedSamples {
            let sample = change.sample
            libraryStore.updateSample(sample, rootURL: rootURL)
            touchedBatchIDs.insert(sample.batchId)
        }

        for removedSample in diff.removedSamples {
            libraryStore.deleteSampleDrawer(for: removedSample, rootURL: rootURL)
            touchedBatchIDs.insert(removedSample.batchId)
        }

        for batchChange in diff.changedBatches {
            touchedBatchIDs.insert(batchChange.batch.id)
        }

        for batchID in touchedBatchIDs {
            guard let batch = batchesByIDInPreview[batchID] else {
                continue
            }
            libraryStore.updateBatch(batch, rootURL: rootURL)
        }

        for removedBatch in diff.removedBatches {
            libraryStore.deleteBatchDrawer(batchID: removedBatch.id, rootURL: rootURL)
        }

        var mergedIndex = preview.index
        mergedIndex.updatedAt = .now
        mergedIndex.registryInternalPath = settings.registryInternalPath
        mergedIndex.registrySourcePath = settings.registrySourcePath
        libraryStore.saveIndex(mergedIndex, to: rootURL)
    }
}
