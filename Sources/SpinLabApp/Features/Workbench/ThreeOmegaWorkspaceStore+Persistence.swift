import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Persist to Library

    /// Saves the active tab's chart (+ metrics for scaling) to Library.
    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = activeChartPNG else {
            saveMessage = "No chart to save. Run analysis first."
            return
        }
        guard let payload = activeChartManifestPayload else {
            saveMessage = "No manifest payload available for the active tab."
            return
        }
        let libraryRootPath = lastLibraryRootPath
        let sampleKeys = activeChartSampleKeys
        let metrics = buildActiveChartMetrics()

        let input = SaveActiveChartInput(
            png: png,
            payload: payload,
            sampleKeys: sampleKeys,
            libraryRootPath: libraryRootPath,
            metrics: metrics
        )

        Task { [weak self] in
            guard let self else { return }
            let outcome = await Task.detached(priority: .userInitiated) {
                SaveActiveChartToLibraryUseCase().execute(input: input)
            }.value
            self.persistenceOutcome = outcome
            self.currentRunTrace = outcome.trace
            switch outcome {
            case .success:
                self.saveMessage = "Saved to Library."
                self.refreshRelatedCharts()
            case .partial(_, let err):
                self.saveMessage = "Chart saved; metric error: \(err)"
                self.refreshRelatedCharts()
            case .failure(let err):
                self.saveMessage = "Save failed: \(err)"
            }
            onComplete?()
        }
    }
}
