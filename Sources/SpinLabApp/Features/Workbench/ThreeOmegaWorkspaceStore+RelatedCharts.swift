import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    /// Refreshes the related charts cache from library indices.
    /// Cancels any in-flight load and guards against stale results.
    func refreshRelatedCharts() {
        relatedChartsTask?.cancel()
        relatedChartsTask = nil

        let keys = cachedSampleKeys
        let rootPath = lastLibraryRootPath
        // TODO(boundary): replace raw root-path probing with a shared library-root access helper.
        guard !keys.isEmpty, !rootPath.isEmpty else {
            relatedChartsGrouped = [:]
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard env.fileManager.fileExists(atPath: rootPath) else {
            relatedChartsGrouped = [:]
            return
        }
        relatedChartsTask?.cancel()
        relatedChartsTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                LoadRelatedChartsUseCase().execute(sampleKeys: keys, libraryRootURL: rootURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.relatedChartsGrouped = result
        }
    }


    /// Returns related charts for a specific tab based on that tab's inputFiles.
    func relatedCharts(for tab: ThreeOmegaWorkbenchTab) -> [WorkbenchResultReference] {
        guard let payload = tabs.output(for: tab).manifestPayload else { return [] }
        let inputFiles = payload.series.compactMap(\.sourceRef)
        guard !inputFiles.isEmpty else { return [] }
        let key = InputFilesCanonicalKey.make(from: inputFiles)
        return relatedChartsGrouped[key] ?? []
    }
}
