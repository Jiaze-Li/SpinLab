import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore: AnalysisPackProviding {
    typealias PackConfig = ThreeOmegaPackConfig
    typealias PackResult = ThreeOmegaPackResult


    func availableOverlayPacks(in vault: AnalysisVault) -> [AnalysisPack] {
        let excludeIDs: Set<AnalysisPack.ID> = Set(overlayPackIDs).union(activePackID.map { [$0] } ?? [])
        return vault.packs(forWorkflow: "3w").filter { !excludeIDs.contains($0.id) }
    }


    // MARK: - Analysis Pack (overlay support)

    /// Adds an overlay from a vault pack onto the current RAHE plots.
    func addOverlay(id: AnalysisPack.ID) {
        guard let vault, let pack = vault.get(id: id) else { return }
        guard let result = try? pack.decodeResult(ThreeOmegaPackResult.self) else { return }
        guard !overlayPackIDs.contains(id) else { return }

        // Snapshot content (sweeps, sampleKeys, sourceFiles) stays workflow-owned.
        overlaySnapshots[id] = OverlaySnapshot(
            label: pack.label,
            sweeps: result.ingestionResult.fieldSweeps,
            sourceFiles: pack.filePaths,
            sampleKeys: pack.sampleKeys
        )

        overlayRuntime?.addEntry(id: id, label: pack.label)

        _renderRAHEWithOverlays()
    }


    /// Removes an overlay.
    func removeOverlay(id: AnalysisPack.ID) {
        overlaySnapshots.removeValue(forKey: id)
        overlayRuntime?.removeEntry(id: id)
        _renderRAHEWithOverlays()
    }


    func _buildPackConfig() -> ThreeOmegaPackConfig {
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: tabs.chartStyleOverrides)
        return ThreeOmegaPackConfig(
            device: ingestionResult?.device ?? "",
            geometry: geometry,
            fitRanges: fitRanges,
            v3Method: v3Method.rawValue,
            rahe1Method: rahe1omegaMethod.rawValue,
            rahe3Method: rahe3omegaMethod.rawValue,
            rtFilePath: cachedRTFilePath,
            sampleBatchAndSubstrate: cachedSearchResults.first?.sampleBatchAndSubstrate ?? "",
            activeTab: tabs.activeTab.stableKey,
            titleTemplate: titleTemplate,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: tabs.showPlotGrid,
            plotLegendAnchor: tabs.legendAnchor,
            seriesRenderMode: tabs.seriesRenderMode,
            tabStates: tabs.snapshotStates(keyFor: { $0.stableKey }),
            chartStyleOverrides: splitOverrides.local,
            temperatureDependenceDisplayState: temperatureDependenceDisplayState.snapshot(),
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectionReading?.selectedIDs(for: workflowID) ?? []),
            selectedRTHit: selectedRTHit,
            rtQuery: rtQuery,
            searchQueryText: ""   // filled by caller at WorkbenchFeatureStore level
        )
    }


    func _buildPackResult() -> ThreeOmegaPackResult {
        ThreeOmegaPackResult(
            ingestionResult: ingestionResult!,
            scalingResult: scalingResult
        )
    }


    func _autoPackLabel() -> String {
        let sample = cachedSearchResults.first?.sampleBatchAndSubstrate ?? "Unknown"
        let device = ingestionResult?.device ?? ""
        return device.isEmpty ? sample : "\(sample) \(device)"
    }


        func buildPackConfig() -> ThreeOmegaPackConfig { _buildPackConfig() }

    func buildPackResult() -> ThreeOmegaPackResult { _buildPackResult() }

    func autoPackLabel() -> String { _autoPackLabel() }


    func cancelInflightWork() {
        analysisTask?.cancel(); analysisTask = nil
        scalingTask?.cancel(); scalingTask = nil
        isAnalyzing = false
        isRefreshingTransportDerivedPlots = false
        transportDerivedStatus = .idle
    }


    func restoreFromPack(config: ThreeOmegaPackConfig, result: ThreeOmegaPackResult,
                         pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                         seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void) {
        // Restore analysis params
        geometry = config.geometry
        fitRanges = config.fitRanges
        v3Method = ThreeOmegaV3Method(rawValue: config.v3Method) ?? .highField
        rahe1omegaMethod = ThreeOmegaV3Method(rawValue: config.rahe1Method) ?? .highField
        rahe3omegaMethod = ThreeOmegaV3Method(rawValue: config.rahe3Method) ?? .highField
        rtQuery = config.rtQuery
        persistRTQuery()
        selectedRTHit = config.selectedRTHit
        if let rtHit = config.selectedRTHit {
            launchRTAnalysis(for: rtHit)
        }

        // Restore display settings
        if let tab = ThreeOmegaWorkbenchTab.tab(forStableKey: config.activeTab, includeLegacyAliases: true) {
            tabs.activeTab = tab
        }
        titleTemplate = config.titleTemplate
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        tabs.showPlotGrid = config.showPlotGrid
        tabs.legendAnchor = config.plotLegendAnchor
        tabs.seriesRenderMode = config.seriesRenderMode
        temperatureDependenceDisplayState = config.temperatureDependenceDisplayState
            .map(DualAxisDisplayState.init) ?? DualAxisDisplayState()

        // Restore per-tab states
        tabs.restoreStates(config.tabStates) { key in
            ThreeOmegaWorkbenchTab.visibleTabs.first { $0.stableKey == key }
        }
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: config.chartStyleOverrides)
        if !splitOverrides.global.isEmpty {
            globalPlotDefaults = splitOverrides.global
        }
        tabs.chartStyleOverrides = splitOverrides.local

        // Restore search selection state
        cachedSearchResults = config.cachedSearchResults
        seedSelection(Set(config.selectedSearchResultIDs), config.cachedSearchResults)

        // Restore results
        ingestionResult = result.ingestionResult
        scalingResult = result.scalingResult
        transportDerivedStatus = result.scalingResult == nil ? .idle : .ready

        // Build title tokens from restored search results
        if let hit = config.cachedSearchResults.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        } else {
            _titleTokens = [:]
        }

        // Restore cached persistence state from pack.
        // config.rtFilePath is retained in the pack schema for fingerprint context only —
        // it is NOT a standalone restore input. selectedRTHit is the canonical RT restore source.
        // cachedRTFilePath is derived output: _snapshotAndCacheManifestPayloads() below sets it
        // from selectedRTHit?.measurementFilePath and must not be pre-empted here.
        cachedInputFiles = pack.filePaths
        cachedSampleKeys = pack.sampleKeys

        // Restore library root from vault so persistToLibrary works without a prior search
        if lastLibraryRootPath.isEmpty, let root = vault?.libraryRootPath {
            lastLibraryRootPath = root
        }

        overlayRuntime?.clear()
        overlaySnapshots = [:]

        // Bridge: restore search results into WorkbenchFeatureStore
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        // Migrate any Int-string-keyed overrides (packs saved before 5.3.6) to sampleID keys.
        for tab in ThreeOmegaWorkbenchTab.allCases {
            if var state = tabs.tabStates[tab] {
                let seriesForTab = tabs.output(for: tab).manifestPayload?.series ?? []
                migrateStateIfNeeded(&state, series: seriesForTab)
                tabs.tabStates[tab] = state
            }
        }

        // Re-render all tabs respecting restored per-tab state and refreshing library tokens.
        // _rerenderAllTabs() does not apply per-tab overrides (titleOverride, legendPoint, etc.),
        // so we use _rerenderAllTabsFromRestoredState() in the Pack load path instead.
        _rerenderAllTabsFromRestoredState()
        refreshRelatedCharts()
    }
}
