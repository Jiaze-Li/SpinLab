import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {
    /// Re-render the Temperature Dependence tab from the current 3ω scaling result
    /// and the DualAxis display-state snapshot. This is the bridge from workflow-owned
    /// physics payload construction into PlotSystem-owned DualAxis controls.
    func rerenderTemperatureDependenceForDualAxisControlChange() {
        guard let scalingResult else { return }

        let displaySnapshot = temperatureDependenceDisplayState.snapshot()
        let capturedWorkflowID = workflowID
        let capturedShowGrid = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedGlobalPlotDefaults = globalPlotDefaults
        let capturedLegendAnchor = tabs.legendAnchor
        let capturedLegendPoint = tabs.activeState.legendPoint?.cgPoint
        let capturedStackOffset = stackOffsetMultiplier
        let capturedMinGap = minGapFraction
        let capturedTemplate = titleTemplate
        let capturedTokens = _titleTokens

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            var renderer = ThreeOmegaPlotRenderer()
            renderer.workflowID = capturedWorkflowID
            renderer.showGrid = capturedShowGrid
            renderer.seriesRenderMode = capturedRenderMode
            renderer.chartStyleOverrides = capturedStyleOverrides
            renderer.globalPlotDefaults = capturedGlobalPlotDefaults
            renderer.legendAnchor = capturedLegendAnchor
            renderer.stackOffsetMultiplier = capturedStackOffset
            renderer.minGapFraction = capturedMinGap
            renderer.titleTemplate = capturedTemplate
            renderer.titleTokens = capturedTokens

            let (imageData, layout, payload, warnings) = renderer.renderTemperatureDependence(
                result: scalingResult,
                displayState: displaySnapshot,
                legendPoint: capturedLegendPoint
            )

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                self.tabs.setOutput(
                    TabRenderOutput(
                        imageData: imageData,
                        renderKind: .dualAxis,
                        layout: nil,
                        manifestPayload: nil,
                        displayPayload: nil,
                        dualAxisLayout: layout,
                        dualAxisPayload: payload
                    ),
                    for: .temperatureDependence,
                    policy: .preserveDisplayOverrides
                )
                for warning in warnings {
                    self.appendWarning(source: "Temperature Dependence", message: warning)
                }
            }
        }
    }
}
