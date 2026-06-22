import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Analysis

    func runAnalysis() {
        runAnalysis(searchSnapshot: nil)
    }

    /// Parse all selected files, fit RAHE/Hc, render tabs 1–5.
    /// When searchSnapshot is provided it is the canonical source of hits for this run;
    /// nil falls back to cachedSearchResults (pack restore, direct calls).
    func runAnalysis(searchSnapshot: WorkbenchSearchSnapshot?) {
        let sourceHits = searchSnapshot?.results ?? cachedSearchResults
        let selectedHits: [WorkflowMeasurementSearchHit]
        if let reading = selectionReading {
            let ids = reading.selectedIDs(for: .threeOmega)
            selectedHits = _sortedSelectedHits(sourceHits.filter { ids.contains($0.id) })
        } else {
            selectedHits = _sortedSelectedHits(sourceHits)
        }
        _runAnalysis(selectedHits: selectedHits)
    }

    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot?) {
        if let selectedHitsSnapshot {
            _runAnalysis(selectedHits: _sortedSelectedHits(selectedHitsSnapshot.selectedHits))
        } else {
            let ids = selectionReading?.selectedIDs(for: .threeOmega) ?? []
            let selectedHits = _sortedSelectedHits(
                cachedSearchResults.filter { ids.contains($0.id) }
            )
            _runAnalysis(selectedHits: selectedHits)
        }
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
        isAnalyzing = true
        analysisMessage = nil
        saveMessage = nil
        activePackID = nil
        _clearPlots()

        let capturedGrid       = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor     = tabs.legendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedRAHE1MethodForPlots = rahe1omegaMethod
        let capturedRAHE3MethodForPlots = rahe3omegaMethod
        let capturedRAHE1DevMethodForPlots = rahe1omegaVsDeviceMethod
        let capturedRAHE3DevMethodForPlots = rahe3omegaVsDeviceMethod
        let capturedGlobalPlotDefaults = globalPlotDefaults

        let capturedRTHit = selectedRTHit
        let capturedNumericDisplay: [String: [String: String]] = cachedSampleNumericDisplay
        let capturedFieldSweepSeriesOrder = fieldSweepSeriesOrder

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let (result, plots, alignedSeriesOrder) = await Task.detached(priority: .userInitiated) { [selectedHits] in
                let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                let result = ingestUseCase.execute(hits: selectedHits, rtHit: capturedRTHit, numericDisplayBySample: capturedNumericDisplay)
                let alignedSeriesOrder = ThreeOmegaWorkspaceStore.alignSeriesOrder(old: capturedFieldSweepSeriesOrder, fieldSweeps: result.fieldSweeps)
                var renderer = ThreeOmegaPlotRenderer()
                renderer.showGrid              = capturedGrid
                renderer.seriesRenderMode      = capturedRenderMode
                renderer.chartStyleOverrides   = capturedStyleOverrides
                renderer.globalPlotDefaults    = capturedGlobalPlotDefaults
                renderer.legendAnchor          = capturedAnchor
                renderer.stackOffsetMultiplier = capturedMultiplier
                renderer.minGapFraction        = capturedMinGap
                renderer.titleTemplate          = capturedTemplate
                renderer.titleTokens            = capturedTokens
                let plots = renderer.renderAllTabs(result: result, seriesOrder1omega: alignedSeriesOrder, seriesOrder3omega: alignedSeriesOrder, rahe1Method: capturedRAHE1MethodForPlots, rahe3Method: capturedRAHE3MethodForPlots, rahe1DevMethod: capturedRAHE1DevMethodForPlots, rahe3DevMethod: capturedRAHE3DevMethodForPlots)
                return (result, plots, alignedSeriesOrder)
            }.value

            guard !Task.isCancelled else { return }
            self.ingestionResult = result
            self._applyPlots(plots)
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
            self.isAnalyzing = false
            self.refreshRelatedCharts()
        }
    }


    private func _clearPlots() {
        tabs.clearOutputs()
        cachedSampleKeys = []
        cachedConditionsBySampleKey = [:]
        cachedInputFiles = []
        cachedRTFilePath = nil
    }
}
