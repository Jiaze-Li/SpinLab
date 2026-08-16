import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Analysis

    /// Parse all selected files, fit RAHE/Hc, render tabs 1–5. `selectedHitsSnapshot` is
    /// captured once by the caller before this run starts (see `WorkbenchWorkspaceProviding`'s
    /// `runAnalysis(selectedHitsSnapshot:)` doc) and used as-is for the whole run.
    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot) {
        _runAnalysis(selectedHits: _sortedSelectedHits(selectedHitsSnapshot.selectedHits))
    }

    private func _sortedSelectedHits(_ selectedHits: [WorkflowMeasurementSearchHit]) -> [WorkflowMeasurementSearchHit] {
        selectedHits.sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
    }

    private func _runAnalysis(selectedHits: [WorkflowMeasurementSearchHit]) {
        guard !selectedHits.isEmpty else {
            analysisMessage = "Select at least one 3w measurement file."
            return
        }

        // Build title token dictionary from representative hit (stable: sorted by path)
        if let hit = selectedHits.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        } else {
            _titleTokens = [:]
        }

        analysisTask?.cancel()
        scalingTask?.cancel()
        scalingTask = nil
        _analysisRevision &+= 1
        let capturedAnalysisRevision = _analysisRevision
        isAnalyzing = true
        analysisMessage = nil
        saveMessage = nil
        activePackID = nil
        isRefreshingTransportDerivedPlots = false
        transportDerivedStatus = .idle
        _clearPlots()

        // Capture global renderer settings and per-tab display state BEFORE going detached
        // so that re-analysis respects current title/axis/legend/series-label overrides.
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
        let capturedTabSnaps: [ThreeOmegaWorkbenchTab: WorkbenchTabDisplayStateSnapshot] =
            Dictionary(uniqueKeysWithValues: ThreeOmegaWorkbenchTab.allCases.map { ($0, tabs.displayStateSnapshot(for: $0)) })

        let capturedScaling = scalingResult
        let capturedFieldSweepSeriesOrder = fieldSweepSeriesOrder
        let capturedRTResult = cachedRTResult
        let capturedNumericDisplay: [String: [String: String]] = cachedSampleNumericDisplay

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) { [selectedHits] in
                let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                return ingestUseCase.execute(hits: selectedHits, rtAnalysisResult: capturedRTResult, numericDisplayBySample: capturedNumericDisplay)
            }.value

            guard !Task.isCancelled else { return }
            let alignedSeriesOrder = ThreeOmegaWorkspaceStore.alignSeriesOrder(old: capturedFieldSweepSeriesOrder, fieldSweeps: result.fieldSweeps)
            let snap1 = capturedTabSnaps[.fieldSweep1omega]!.with(seriesOrder: alignedSeriesOrder)
            let snap3 = capturedTabSnaps[.fieldSweep3omega]!.with(seriesOrder: alignedSeriesOrder)
            let renderSettings = capturedGlobalSettings
            let plots = await self.renderAllThreeOmegaTabs(
                ingestion: result,
                scalingResult: capturedScaling,
                globalSettings: renderSettings,
                tabSnaps: [
                    .rahe: capturedTabSnaps[.rahe]!,
                    .fieldSweep1omega: snap1,
                    .fieldSweep3omega: snap3,
                    .rahe1omegaVsDevice: capturedTabSnaps[.rahe1omegaVsDevice]!,
                    .rahe3omegaVsDevice: capturedTabSnaps[.rahe3omegaVsDevice]!,
                    .hcVsT: capturedTabSnaps[.hcVsT]!,
                    .rtCurve: capturedTabSnaps[.rtCurve]!,
                    .scaling: capturedTabSnaps[.scaling]!
                ],
                fieldSweepSeriesOrder: alignedSeriesOrder,
                analysisRevision: capturedAnalysisRevision,
                policy: .clearDisplayOverridesIfSourceChanged
            )

            // Guard against publishing stale results: if this task was cancelled while
            // rendering (a newer analysis started), discard the output without writing
            // to tabs, manifestCache, analysisMessage, or ingestionResult.
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                // Final cancellation check on MainActor before committing any state.
                // Prevents a race where cancel arrives between the async render completing
                // and the MainActor block being scheduled.
                guard !Task.isCancelled else { return }
                self.ingestionResult = result
                self.setFieldSweepSeriesOrder(alignedSeriesOrder)

                // Pipeline warnings (legend resolver)
                for w in plots.pipelineWarnings {
                    self.appendWarning(source: "Legend", message: w)
                }

                let sweepCount = result.fieldSweeps.count
                let rtNote     = result.rtResult != nil ? ", RT curve loaded" : ""
                self.analysisMessage = "Analyzed \(sweepCount) field-sweep file(s)\(rtNote)."

                for w in result.warnings {
                    self.appendWarning(source: "Ingestion", message: w)
                }

                self._snapshotAndCacheManifestPayloads(from: selectedHits)
                self.commitRunTrace()
                self.refreshTransportDerivedPlots(reason: "analysis completed")
                self.isAnalyzing = false
                self.refreshRelatedCharts()
            }
        }
    }


    private func _clearPlots() {
        // Not tabs.clearOutputs(): that also wipes the source-identity tracker
        // preparedDisplayState (called from renderThreeOmegaTab) relies on to detect a
        // source change — wiping it here would make every full-analysis render look
        // unattributable and silently skip .clearDisplayOverridesIfSourceChanged.
        for tab in ThreeOmegaWorkbenchTab.allCases {
            tabs.clearOutputPreservingSourceIdentity(for: tab)
        }
        cachedSampleKeys = []
        cachedConditionsBySampleKey = [:]
        cachedInputFiles = []
        cachedRTFilePath = nil
    }
}
