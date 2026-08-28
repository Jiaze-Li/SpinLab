import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore: AnalysisPackProviding, PackRestoreFailureReporting {
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

        // Storage-unit compatibility boundary: normalizes to internal-canonical Tesla regardless
        // of how this overlay pack's magnetic-field values were stored (see
        // ThreeOmegaIngestionDomain.swift).
        let ingestionResult = result.ingestionResult.normalizedToInternalTesla()

        // Snapshot content (sweeps, sampleKeys, sourceFiles) stays workflow-owned.
        overlaySnapshots[id] = OverlaySnapshot(
            label: pack.label,
            sweeps: ingestionResult.fieldSweeps,
            sourceFiles: pack.filePaths,
            sampleKeys: pack.sampleKeys
        )

        overlayRuntime?.addEntry(id: id, label: pack.label)
    }


    /// Removes an overlay.
    func removeOverlay(id: AnalysisPack.ID) {
        overlaySnapshots.removeValue(forKey: id)
        overlayRuntime?.removeEntry(id: id)
    }


    func _buildPackConfig() -> ThreeOmegaPackConfig {
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: tabs.chartStyleOverrides)
        let searchContext = AnalysisPackSearchContext(
            cachedSearchResults: cachedSearchResults,
            selectionReading: selectionReading,
            workflowID: workflowID
        )
        return ThreeOmegaPackConfig(
            device: ingestionResult?.device ?? "",
            geometry: geometry,
            fitRanges: fitRanges,
            v3Method: v3Method.rawValue,
            rahe1Method: rahe1omegaMethod.rawValue,
            rahe3Method: rahe3omegaMethod.rawValue,
            rtFilePath: cachedRTFilePath,
            sampleBatchAndSubstrate: cachedSearchResults.first?.sampleBatchAndSubstrate ?? "",
            activeTab: tabs.activeTab.packStableKey,
            titleTemplate: titleTemplate,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: tabs.showPlotGrid,
            plotLegendAnchor: tabs.legendAnchor,
            seriesRenderMode: tabs.seriesRenderMode,
            tabStates: ThreeOmegaWorkbenchTab.visibleTabs.reduce(into: [String: TabRenderState]()) { dict, tab in
                if let state = tabs.tabStates[tab] {
                    dict[tab.stableKey] = state
                }
            },
            chartStyleOverrides: splitOverrides.local,
            temperatureDependenceDisplayState: temperatureDependenceDisplayState.snapshot(),
            cachedSearchResults: searchContext.cachedSearchResults,
            selectedSearchResultIDs: searchContext.selectedSearchResultIDs,
            selectedRTHit: selectedRTHit,
            rtQuery: rtQuery,
            searchQueryText: "",   // filled by caller at WorkbenchFeatureStore level
            scalingAngleCoefficient: scalingAngleCoefficient.rawValue,
            scalingAngleMethod: scalingAngleMethod,
            scalingAngleFitRange: scalingAngleFitRange,
            scalingAngleCandidate: scalingAngleCandidate
        )
    }


    func _buildPackResult() -> ThreeOmegaPackResult {
        // Save-time invariant guard: the in-memory ingestionResult is already canonical Tesla
        // (see ThreeOmegaIngestionDomain.swift normalizedForPackSave()) — this is a defensive
        // no-op in the expected case, not the primary conversion path.
        ThreeOmegaPackResult(
            ingestionResult: ingestionResult!.normalizedForPackSave(),
            scalingResult: scalingResult,
            scalingVsAngleResult: scalingVsAngleResult
        )
    }


    func _autoPackLabel() -> String {
        analysisPackLabel(
            sampleBatchAndSubstrate: cachedSearchResults.first?.sampleBatchAndSubstrate,
            device: ingestionResult?.device,
            fallback: "Unknown"
        )
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
        packRestoreErrorMessage = nil
        if Self.hasLegacyFieldSweepSeriesLabelOverrideKeys(in: config.tabStates) {
            packRestoreErrorMessage = "Unsupported 3ω pack format: legacy Int-keyed seriesLabelOverrides are no longer supported. Re-save this pack with current identity-key overrides."
            return
        }

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

        // Restore results.
        // Storage-unit compatibility boundary: normalizes to internal-canonical Tesla regardless
        // of how this pack's magnetic-field values were stored (see ThreeOmegaIngestionDomain.swift).
        ingestionResult = result.ingestionResult.normalizedToInternalTesla()
        scalingResult = result.scalingResult
        transportDerivedStatus = result.scalingResult == nil ? .idle : .ready

        // Build title tokens from restored search results
        if let hit = config.cachedSearchResults.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            if let testTemp = hit.conditions["temperature"], !testTemp.isEmpty { tokens["测试温度"] = testTemp }
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

        // Normalize field-sweep visual order before any legacy migration reads tab series data.
        // We resolve one visual order here and sync both field-sweep tabs to it so restore
        // never depends on stale manifest/display payload ordering.
        let restoredFieldSweepSeriesOrder = _resolvedRestoredFieldSweepSeriesOrder(
            from: result.ingestionResult.fieldSweeps
        )
        setFieldSweepSeriesOrder(restoredFieldSweepSeriesOrder)

        // Migrate any Int-string-keyed overrides (packs saved before 5.3.6) to sampleID keys.
        for tab in ThreeOmegaWorkbenchTab.allCases {
            if var state = tabs.tabStates[tab] {
                let seriesForTab: [WorkbenchPlotSeries]
                if tab == .fieldSweep1omega || tab == .fieldSweep3omega {
                    seriesForTab = Self._sweepsToFakeSeries(
                        Self.manifestOrderedFieldSweeps(
                            result.ingestionResult.fieldSweeps,
                            seriesOrder: restoredFieldSweepSeriesOrder
                        )
                    )
                } else {
                    seriesForTab = tabs.output(for: tab).manifestPayload?.series ?? []
                }
                migrateStateIfNeeded(&state, series: seriesForTab)
                tabs.tabStates[tab] = state
            }
        }

        // Discard any stale render outputs from the pre-restore session. The restored
        // field-sweep tabs will be repopulated from ingestion below using the normalized order.
        tabs.clearOutputs()

        if let coeffStr = config.scalingAngleCoefficient, let coeff = ThreeOmegaScalingCoefficientKind(rawValue: coeffStr) {
            scalingAngleCoefficient = coeff
        } else {
            scalingAngleCoefficient = .beta
        }
        scalingAngleMethod = config.scalingAngleMethod
        scalingAngleFitRange = config.scalingAngleFitRange
        scalingAngleCandidate = config.scalingAngleCandidate
        if let restoredAngleResult = result.scalingVsAngleResult {
            // Lossless restore of the displayed Scaling vs Angle aggregate: the
            // persisted signed points, provenance, diagnostics, and duplicate
            // candidates are used verbatim — no recomputation, averaging, or
            // normalization.
            scalingVsAngleResult = restoredAngleResult
        } else {
            // Legacy pack (saved before the aggregate was persisted): rebuild from
            // the already-computed per-device scaling artifacts. This does not
            // recompute scaling physics across devices.
            _refreshScalingVsAngleResult()
        }

        // Re-render all tabs respecting restored per-tab state and refreshing library tokens.
        // _rerenderAllTabs() does not apply per-tab overrides (titleOverride, legendPoint, etc.),
        // so we use _rerenderAllTabsFromRestoredState() in the Pack load path instead.
        _rerenderAllTabsFromRestoredState()
        refreshRelatedCharts()
    }

    private func _resolvedRestoredFieldSweepSeriesOrder(from fieldSweeps: [ThreeOmegaFieldSweepResult]) -> [String]? {
        guard !fieldSweeps.isEmpty else { return nil }
        let restoredOrder = fieldSweepSeriesOrder
        return Self.alignSeriesOrder(old: restoredOrder, fieldSweeps: fieldSweeps)
            ?? Self.defaultFieldSweepVisualSeriesOrder(
                from: fieldSweeps,
                workflowID: workflowID,
                tab: .fieldSweep1omega
            )
    }

    private static func hasLegacyFieldSweepSeriesLabelOverrideKeys(in tabStates: [String: TabRenderState]) -> Bool {
        let legacyTabKeys = [
            ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey,
            ThreeOmegaWorkbenchTab.fieldSweep3omega.stableKey
        ]
        return legacyTabKeys.contains { tabKey in
            guard let overrides = tabStates[tabKey]?.seriesLabelOverrides, !overrides.isEmpty else { return false }
            return overrides.keys.contains { Int($0) != nil }
        }
    }
}
