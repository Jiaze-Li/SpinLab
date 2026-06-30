import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    /// Internal compatibility entrypoint for the old manual workflow.
    /// The view no longer exposes Run Scaling as a required action.
    func runScaling() {
        refreshTransportDerivedPlots(reason: "manual")
    }

    /// Recomputes the transport-derived Scaling Law tab from the current cached analysis state.
    /// Missing RT/geometry is surfaced locally via `transportDerivedStatus` instead of the global
    /// analysis message.
    func refreshTransportDerivedPlots(reason: String) {
        _ = reason
        scalingTask?.cancel()
        scalingTask = nil

        guard let result = ingestionResult else {
            isRefreshingTransportDerivedPlots = false
            transportDerivedStatus = .idle
            scalingResult = nil
            _clearScalingTabOutput()
            _clearTemperatureDependenceTabOutput()
            return
        }

        let currentRT = result.rtResult
        let missingRequirements = _missingTransportRequirements(rtResult: currentRT)
        guard missingRequirements.isEmpty, let rt = currentRT else {
            isRefreshingTransportDerivedPlots = false
            transportDerivedStatus = .missing(missingRequirements)
            scalingResult = nil
            _clearScalingTabOutput()
            _clearTemperatureDependenceTabOutput()
            return
        }

        let capturedResult = result
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
        let capturedRanges = fitRanges
        let capturedV3Method = v3Method

        _renderRevision &+= 1
        let revision = _renderRevision
        isRefreshingTransportDerivedPlots = true
        transportDerivedStatus = .refreshing

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
            let scalingRenderResult = await self.renderThreeOmegaTab(
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
            self._refreshManifestPayloads()

            if scalingRes.points.count >= 2 {
                if scalingRenderResult.imageData != nil {
                    self.transportDerivedStatus = .ready
                } else {
                    self.transportDerivedStatus = .unavailable("Scaling Law render failed.")
                }
            } else {
                self.transportDerivedStatus = .unavailable("Scaling Law unavailable: fewer than 2 valid points.")
            }

            self.isRefreshingTransportDerivedPlots = false

            for warning in scalingRenderResult.warnings + scalingRes.warnings {
                self.appendWarning(source: "Scaling", message: warning)
                print("[SpinLab][3ω Scaling] \(warning)")
            }

            // Temperature Dependence is a separate DualAxis render path. Keep it out of the
            // Cartesian XY scaling render and re-render it from the committed scaling result plus
            // the DualAxis display-state snapshot.
            self.rerenderTemperatureDependenceForDualAxisControlChange()
        }
    }

    private func _clearScalingTabOutput() {
        tabs.setOutput(
            TabRenderOutput(imageData: nil, layout: nil, manifestPayload: nil, displayPayload: nil),
            for: .scaling
        )
    }

    private func _clearTemperatureDependenceTabOutput() {
        tabs.setOutput(
            TabRenderOutput(
                imageData: nil,
                renderKind: .dualAxis,
                layout: nil,
                manifestPayload: nil,
                displayPayload: nil,
                dualAxisLayout: nil,
                dualAxisPayload: nil
            ),
            for: .temperatureDependence
        )
    }

    private func _missingTransportRequirements(rtResult: ThreeOmegaRTResult?) -> [ThreeOmegaTransportRequirement] {
        var requirements: [ThreeOmegaTransportRequirement] = []
        if let rtResult {
            if rtResult.temperatureK.isEmpty || rtResult.rxx.isEmpty || rtResult.temperatureK.count != rtResult.rxx.count {
                requirements.append(.rt)
            }
        } else {
            requirements.append(.rt)
        }
        if geometry.lxx <= 0 { requirements.append(.lxx) }
        if geometry.lxy <= 0 { requirements.append(.lxy) }
        if geometry.dNm <= 0 { requirements.append(.d) }
        return requirements
    }
}
