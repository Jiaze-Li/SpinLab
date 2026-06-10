import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore: WorkbenchSaveCoordinating {

    // MARK: - Persist to Library

    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = activeChartPNG else {
            saveMessage = "No chart to save. Run analysis first."
            return
        }
        guard let payload = activeChartManifestPayload else {
            saveMessage = "No manifest payload available for the active tab."
            return
        }
        executeSave(
            input: SaveActiveChartInput(
                png: png,
                payload: payload,
                sampleKeys: activeChartSampleKeys,
                libraryRootPath: lastLibraryRootPath,
                metrics: buildActiveChartMetrics()
            ),
            onComplete: onComplete
        )
    }
}
