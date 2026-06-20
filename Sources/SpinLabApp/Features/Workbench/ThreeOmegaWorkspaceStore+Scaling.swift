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
        let capturedGrid     = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor   = tabs.legendAnchor
        let capturedScalingState = tabs.state(for: .scaling)
        let capturedLegend   = capturedScalingState.legendPoint?.cgPoint
        let capturedRanges   = fitRanges
        let capturedTemplate = titleTemplate
        let capturedTokens   = _titleTokens
        let capturedDevice   = result.device
        let capturedV3Method = v3Method
        let capturedGlobalPlotDefaults = globalPlotDefaults

        scalingTask?.cancel()
        scalingTask = Task { [weak self] in
            guard let self else { return }
            let (scalingRes, scalingData, scalingLayout) = await Task.detached(priority: .userInitiated) {
                let scalingUseCase = ThreeOmegaScalingUseCase()
                let res = scalingUseCase.executeWithIRms(
                    fieldSweeps: capturedResult.fieldSweeps,
                    rtResult: rt,
                    geometry: capturedGeometry,
                    iRmsValues: capturedResult.iRmsValues,
                    fitRanges: capturedRanges,
                    v3Method: capturedV3Method
                )
                var renderer = ThreeOmegaPlotRenderer()
                renderer.showGrid     = capturedGrid
                renderer.seriesRenderMode = capturedRenderMode
                renderer.chartStyleOverrides = capturedStyleOverrides
                renderer.globalPlotDefaults = capturedGlobalPlotDefaults
                renderer.legendAnchor = capturedAnchor
                renderer.legendPoint    = capturedLegend
                renderer.titleOverride  = capturedScalingState.titleOverride
                renderer.xLabelOverride = capturedScalingState.xLabelOverride
                renderer.yLabelOverride = capturedScalingState.yLabelOverride
                renderer.titleTemplate  = capturedTemplate
                renderer.titleTokens   = capturedTokens
                let method = capturedV3Method == .highField ? "(HFE)" : "(WA)"
                let (data, layout, _) = renderer.renderScaling(result: res, device: capturedDevice, method: method)
                return (res, data, layout)
            }.value

            guard !Task.isCancelled else { return }
            self.scalingResult = scalingRes
            self.tabs.setOutput(TabRenderOutput(imageData: scalingData, layout: scalingLayout, manifestPayload: nil), for: .scaling)
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
