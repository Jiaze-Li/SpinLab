import Foundation

struct LibraryPreviewComputationService {
    func buildPreviewGroups(from index: LibraryIndex) -> [String: [LibraryPreviewBatchGroup]] {
        var groups: [String: [LibraryPreviewBatchGroup]] = [:]
        let samplesByBatch = Dictionary(grouping: index.samples) { $0.batchId }
        for (batchId, samples) in samplesByBatch {
            let prefix = LibrarySort.batchSortKey(batchId).prefix
            let sortedSamples = samples.sorted { $0.substrateDisplay < $1.substrateDisplay }
            let group = LibraryPreviewBatchGroup(batchId: batchId, samples: sortedSamples)
            groups[prefix, default: []].append(group)
        }
        for prefix in groups.keys {
            groups[prefix] = groups[prefix]?.sorted { LibrarySort.compareBatch($0.batchId, $1.batchId) }
        }
        return groups
    }

    func actionablePreviewIndex(
        from previewIndex: LibraryIndex,
        diff: LibraryDiff?,
        hasLibraryRoot: Bool
    ) -> LibraryIndex {
        guard hasLibraryRoot, let diff else {
            return previewIndex
        }

        var actionableByID: [String: LibrarySample] = [:]
        for sample in diff.newSamples {
            actionableByID[sample.id] = sample
        }
        for change in diff.changedSamples {
            actionableByID[change.sample.id] = change.sample
        }

        let actionableSamples = Array(actionableByID.values).sorted { $0.displayName < $1.displayName }
        let actionableBatchIDs = Set(actionableSamples.map(\.batchId))
        let actionableBatches = previewIndex.batches
            .filter { actionableBatchIDs.contains($0.id) }
            .map { batch in
                var next = batch
                next.sampleKeys = batch.sampleKeys.filter { actionableByID[$0] != nil }
                return next
            }
            .sorted { $0.id < $1.id }

        return LibraryIndex(
            version: previewIndex.version,
            createdAt: previewIndex.createdAt,
            updatedAt: previewIndex.updatedAt,
            registryInternalPath: previewIndex.registryInternalPath,
            registrySourcePath: previewIndex.registrySourcePath,
            metadataColumnOrder: previewIndex.metadataColumnOrder,
            batches: actionableBatches,
            samples: actionableSamples
        )
    }
}
