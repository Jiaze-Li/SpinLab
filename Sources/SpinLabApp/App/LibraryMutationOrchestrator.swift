import Foundation

struct LibraryActionablePreviewState {
    var groups: [String: [LibraryPreviewBatchGroup]]
    var message: String
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
}
