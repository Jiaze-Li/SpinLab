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
            let ids = reading.selectedIDs(for: workflowID)
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
            let ids = selectionReading?.selectedIDs(for: workflowID) ?? []
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

        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod
        let capturedRAHE1DevMethod = rahe1omegaVsDeviceMethod
        let capturedRAHE3DevMethod = rahe3omegaVsDeviceMethod
        let capturedFieldSweepSeriesOrder = fieldSweepSeriesOrder
        let capturedRTResult = cachedRTResult
        let capturedNumericDisplay: [String: [String: String]] = cachedSampleNumericDisplay

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let (result, plots, alignedSeriesOrder) = await Task.detached(priority: .userInitiated) { [selectedHits] in
                let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                let result = ingestUseCase.execute(hits: selectedHits, rtAnalysisResult: capturedRTResult, numericDisplayBySample: capturedNumericDisplay)
                let alignedSeriesOrder = ThreeOmegaWorkspaceStore.alignSeriesOrder(old: capturedFieldSweepSeriesOrder, fieldSweeps: result.fieldSweeps)

                // Field sweep tabs use the newly-aligned series order (known only post-ingestion).
                let snap1 = capturedTabSnaps[.fieldSweep1omega]!.with(seriesOrder: alignedSeriesOrder)
                let snap3 = capturedTabSnaps[.fieldSweep3omega]!.with(seriesOrder: alignedSeriesOrder)

                var allWarnings: [String] = []
                var plots = ThreeOmegaRenderedPlots()

                var r1 = ThreeOmegaWorkspaceStore._buildRenderer(for: .fieldSweep1omega, globalSettings: capturedGlobalSettings, tabSnap: snap1, fieldSweeps: result.fieldSweeps)
                let res1 = r1.renderR1omega(sweeps: result.fieldSweeps, device: result.device, seriesOrder: alignedSeriesOrder)
                plots.r1omega = res1.0; plots.layoutR1omega = res1.1; plots.displayR1omega = res1.2; allWarnings.append(contentsOf: res1.3)

                var r3 = ThreeOmegaWorkspaceStore._buildRenderer(for: .fieldSweep3omega, globalSettings: capturedGlobalSettings, tabSnap: snap3, fieldSweeps: result.fieldSweeps)
                let res3 = r3.renderR3omega(sweeps: result.fieldSweeps, device: result.device, seriesOrder: alignedSeriesOrder)
                plots.r3omega = res3.0; plots.layoutR3omega = res3.1; plots.displayR3omega = res3.2; allWarnings.append(contentsOf: res3.3)

                var rahe1 = ThreeOmegaWorkspaceStore._buildRenderer(for: .rahe1omegaVsT, globalSettings: capturedGlobalSettings, tabSnap: capturedTabSnaps[.rahe1omegaVsT]!, fieldSweeps: result.fieldSweeps)
                let resRAHE1 = rahe1.renderRAHE1omegaVsT(sweeps: result.fieldSweeps, device: result.device, method: capturedRAHE1Method)
                plots.rahe1omegaVsT = resRAHE1.0; plots.layoutRAHE1omegaVsT = resRAHE1.1; plots.displayRAHE1omegaVsT = resRAHE1.2; allWarnings.append(contentsOf: resRAHE1.3)

                var rahe3 = ThreeOmegaWorkspaceStore._buildRenderer(for: .rahe3omegaVsT, globalSettings: capturedGlobalSettings, tabSnap: capturedTabSnaps[.rahe3omegaVsT]!, fieldSweeps: result.fieldSweeps)
                let resRAHE3 = rahe3.renderRAHE3omegaVsT(sweeps: result.fieldSweeps, device: result.device, method: capturedRAHE3Method)
                plots.rahe3omegaVsT = resRAHE3.0; plots.layoutRAHE3omegaVsT = resRAHE3.1; plots.displayRAHE3omegaVsT = resRAHE3.2; allWarnings.append(contentsOf: resRAHE3.3)

                var rahe1d = ThreeOmegaWorkspaceStore._buildRenderer(for: .rahe1omegaVsDevice, globalSettings: capturedGlobalSettings, tabSnap: capturedTabSnaps[.rahe1omegaVsDevice]!, fieldSweeps: result.fieldSweeps)
                let resRAHE1d = rahe1d.renderRAHE1omegaVsDevice(sweeps: result.fieldSweeps, device: result.device, method: capturedRAHE1DevMethod)
                plots.rahe1omegaVsDevice = resRAHE1d.0; plots.layoutRAHE1omegaVsDevice = resRAHE1d.1; plots.displayRAHE1omegaVsDevice = resRAHE1d.2; allWarnings.append(contentsOf: resRAHE1d.3)

                var rahe3d = ThreeOmegaWorkspaceStore._buildRenderer(for: .rahe3omegaVsDevice, globalSettings: capturedGlobalSettings, tabSnap: capturedTabSnaps[.rahe3omegaVsDevice]!, fieldSweeps: result.fieldSweeps)
                let resRAHE3d = rahe3d.renderRAHE3omegaVsDevice(sweeps: result.fieldSweeps, device: result.device, method: capturedRAHE3DevMethod)
                plots.rahe3omegaVsDevice = resRAHE3d.0; plots.layoutRAHE3omegaVsDevice = resRAHE3d.1; plots.displayRAHE3omegaVsDevice = resRAHE3d.2; allWarnings.append(contentsOf: resRAHE3d.3)

                var hc = ThreeOmegaWorkspaceStore._buildRenderer(for: .hcVsT, globalSettings: capturedGlobalSettings, tabSnap: capturedTabSnaps[.hcVsT]!, fieldSweeps: result.fieldSweeps)
                let resHc = hc.renderHcVsT(sweeps: result.fieldSweeps, device: result.device)
                plots.hcVsT = resHc.0; plots.layoutHcVsT = resHc.1; plots.displayHcVsT = resHc.2; allWarnings.append(contentsOf: resHc.3)

                if let rt = result.rtResult {
                    var rtR = ThreeOmegaWorkspaceStore._buildRenderer(for: .rtCurve, globalSettings: capturedGlobalSettings, tabSnap: capturedTabSnaps[.rtCurve]!, fieldSweeps: result.fieldSweeps)
                    let resRT = rtR.renderRT(rt: rt)
                    plots.rtCurve = resRT.0; plots.layoutRTCurve = resRT.1; plots.displayRTCurve = resRT.2; allWarnings.append(contentsOf: resRT.3)
                }

                plots.pipelineWarnings = Array(Set(allWarnings))
                return (result, plots, alignedSeriesOrder)
            }.value

            guard !Task.isCancelled else { return }
            self.ingestionResult = result
            self._applyPlots(plots, policy: .clearDisplayOverridesIfSourceChanged)
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
