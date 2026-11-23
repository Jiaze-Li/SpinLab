import Foundation

extension SpinLabAppState {
    /// Result service bound to the open Library, or nil when no Library Root is configured.
    func libraryResultContext() -> (service: LibraryResultService, rootURL: URL)? {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath, !rootPath.isEmpty else { return nil }
        return (LibraryResultService(libraryStore: libraryFeatureStore.libraryStore), URL(fileURLWithPath: rootPath))
    }

    /// Reloads the Library index after a Result write so every screen shows the on-disk values.
    func refreshLibraryAfterResultChange() {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath, !rootPath.isEmpty else { return }
        let rootURL = URL(fileURLWithPath: rootPath)
        do {
            let index = try libraryFeatureStore.libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
            applyExistingIndex(index)
        } catch {
            libraryFeatureStore.libraryDrawerError = "Result saved, but refreshing the Library index failed: \(error.localizedDescription)"
        }
    }
}
