import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Analysis

    /// Parse all selected files, fit RAHE/Hc, render tabs 1–5.
    func runAnalysis() {
        let selectedHits = cachedSearchResults.filter { selectedSearchResultIDs.contains($0.id) }
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
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

        let capturedRTHit = selectedRTHit
        let capturedNumericDisplay: [String: [String: String]] = cachedSampleNumericDisplay
        let capturedOrder1 = tabs.state(for: .fieldSweep1omega).seriesOrder
        let capturedOrder3 = tabs.state(for: .fieldSweep3omega).seriesOrder

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let (result, plots, aligned1, aligned3) = await Task.detached(priority: .userInitiated) { [selectedHits] in
                let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                let result = ingestUseCase.execute(hits: selectedHits, rtHit: capturedRTHit, numericDisplayBySample: capturedNumericDisplay)
                let defaultIDs = result.fieldSweeps.compactMap(\.sampleID)
                let aligned1 = ThreeOmegaWorkspaceStore.alignSeriesOrder(old: capturedOrder1, defaultIDs: defaultIDs)
                let aligned3 = ThreeOmegaWorkspaceStore.alignSeriesOrder(old: capturedOrder3, defaultIDs: defaultIDs)
                var renderer = ThreeOmegaPlotRenderer()
                renderer.showGrid              = capturedGrid
                renderer.seriesRenderMode      = capturedRenderMode
                renderer.chartStyleOverrides   = capturedStyleOverrides
                renderer.legendAnchor          = capturedAnchor
                renderer.stackOffsetMultiplier = capturedMultiplier
                renderer.minGapFraction        = capturedMinGap
                renderer.titleTemplate          = capturedTemplate
                renderer.titleTokens            = capturedTokens
                let plots = renderer.renderAllTabs(result: result, seriesOrder1omega: aligned1, seriesOrder3omega: aligned3, rahe1Method: capturedRAHE1MethodForPlots, rahe3Method: capturedRAHE3MethodForPlots)
                return (result, plots, aligned1, aligned3)
            }.value

            guard !Task.isCancelled else { return }
            self.ingestionResult = result
            self._applyPlots(plots)
            self.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].seriesOrder = aligned1
            self.tabs.tabStates[.fieldSweep3omega, default: TabRenderState()].seriesOrder = aligned3

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

            self._snapshotAndCacheManifestPayloads()
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
