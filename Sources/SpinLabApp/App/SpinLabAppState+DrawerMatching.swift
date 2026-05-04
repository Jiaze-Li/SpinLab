import Foundation

extension SpinLabAppState {

    func hasExistingLibraryDrawer(sampleKey: String) -> Bool {
        matchedExistingLibraryDrawer(sampleInput: sampleKey) != nil
    }

    func matchedExistingLibraryDrawer(sampleInput: String) -> String? {
        inboxFeatureStore.matchedExistingLibraryDrawer(sampleInput: sampleInput)
    }

    func refreshPendingDrawerMatches(for pendingIDs: [UUID]? = nil) {
        inboxFeatureStore.refreshPendingDrawerMatches(for: pendingIDs)
    }

    func pendingRoutingSnapshot(for pending: SpinLabDomain.PendingImport) -> SpinLabDomain.PendingRoutingSnapshot {
        inboxFeatureStore.pendingRoutingSnapshot(for: pending)
    }

    func cachedPendingRoutingSnapshot(for pendingID: UUID) -> SpinLabDomain.PendingRoutingSnapshot? {
        inboxFeatureStore.cachedPendingRoutingSnapshot(for: pendingID)
    }

    func wireNameConflictChecker() {
        inboxFeatureStore.inboxRoutingState.nameExistsInLibraryDrawer = { [weak self] fileName, matchedSampleID, workflowID in
            guard let self,
                  let rootPath = self.libraryFeatureStore.librarySettings.rootPath else {
                return false
            }
            let sample = self.libraryFeatureStore.libraryExistingGroups.values
                .flatMap { $0 }
                .flatMap { $0.samples }
                .first { $0.id == matchedSampleID }
            guard let sample else { return false }
            let rootURL = URL(fileURLWithPath: rootPath)
            let drawerRoot = self.libraryFeatureStore.libraryStore.drawerRootURL(for: sample, rootURL: rootURL)
            let subpath = LibraryDestinationSubpath.subpath(workflowName: workflowID)
            let destinationURL = drawerRoot
                .appending(path: subpath, directoryHint: .isDirectory)
                .appending(path: fileName, directoryHint: .notDirectory)
            return FileManager.default.fileExists(atPath: destinationURL.path)
        }
    }
}
