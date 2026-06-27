import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    /// Re-runs only the scaling (cheap). Called when geometry parameters change.
    func runScaling() {
        guard let result = ingestionResult, let rt = result.rtResult else {
            analysisMessage = "Run analysis first before applying geometry."
            return
        }
        guard geometry.isComplete else {
            analysisMessage = "Enter L_xx, L_xy, and d to compute Scaling Law."
            return
        }

        let capturedResult   = result
        let capturedGeometry = geometry
        let capturedGlobalSettings = ThreeOmegaRendererGlobalSettings(
            workflowID: workflowID,
            showGrid: tabs.showPlotGrid,
            seriesRenderMode: tabs.seriesRenderMode,
            chartStyleOverrides: tabs.chartStyleOverrides,
            globalPlotDefaults: globalPlotDefaults,
            legendAnchor: tabs.legendAnchor,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            titleTemplate: titleTemplate,
            titleTokens: _titleTokens
        )
        let capturedScalingSnapshot = tabs.displayStateSnapshot(for: .scaling)
        let capturedRanges   = fitRanges
        let capturedV3Method = v3Method

        _renderRevision &+= 1
        let revision = _renderRevision

        scalingTask?.cancel()
        scalingTask = Task { [weak self] in
            guard let self else { return }
            let scalingRes = await Task.detached(priority: .userInitiated) {
                let scalingUseCase = ThreeOmegaScalingUseCase()
                return scalingUseCase.executeWithIRms(
                    fieldSweeps: capturedResult.fieldSweeps,
                    rtResult: rt,
                    geometry: capturedGeometry,
                    iRmsValues: capturedResult.iRmsValues,
                    fitRanges: capturedRanges,
                    v3Method: capturedV3Method
                )
            }.value

            guard !Task.isCancelled else { return }
            _ = await self.renderThreeOmegaTab(
                .scaling,
                ingestion: capturedResult,
                scalingResult: scalingRes,
                fieldSweepSeriesOrder: nil,
                globalSettings: capturedGlobalSettings,
                tabSnapshot: capturedScalingSnapshot,
                revision: revision,
                policy: .preserveDisplayOverrides
            )
            guard !Task.isCancelled, self._renderRevision == revision else { return }
            self.scalingResult = scalingRes
            // Refresh manifest payloads (v3Method may have changed) using frozen inputFiles
            self._refreshManifestPayloads()

            for w in scalingRes.warnings {
                self.appendWarning(source: "Scaling", message: w)
                print("[SpinLab][3ω Scaling] \(w)")
            }

            // Scaling results are shown in the dedicated ScalingResultPanel below the plot.
            // Do not overwrite analysisMessage — keep the ingestion summary visible.
        }
    }
}
