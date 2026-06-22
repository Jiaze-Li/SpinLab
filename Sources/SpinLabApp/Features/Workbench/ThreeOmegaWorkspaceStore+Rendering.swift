import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    /// Explicit RAHE method switch — re-renders active tab and refreshes manifests.
    func updateRAHEMethod(_ method: ThreeOmegaV3Method) {
        switch tabs.activeTab {
        case .rahe1omegaVsT:
            guard method != rahe1omegaMethod else { return }
            rahe1omegaMethod = method
        case .rahe3omegaVsT:
            guard method != rahe3omegaMethod else { return }
            rahe3omegaMethod = method
        default: return
        }
        _rerenderActiveTab()
        _refreshManifestPayloads()
    }


    // MARK: - Stack offset

    /// Re-renders Tab 1 and Tab 2 after stack offset multiplier changes.
    func rerenderFieldSweepTabs() {
        guard let ingestion = ingestionResult else { return }
        let capturedGrid       = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor     = tabs.legendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedFieldSweepSeriesOrder = fieldSweepSeriesOrder
        let capturedState1     = tabs.state(for: .fieldSweep1omega)
        let capturedState3     = tabs.state(for: .fieldSweep3omega)
        let capturedGlobalPlotDefaults = globalPlotDefaults

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let orderedSweeps  = ThreeOmegaWorkspaceStore._applySeriesOrder(capturedFieldSweepSeriesOrder, to: ingestion.fieldSweeps)
            let fakeSeries     = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(orderedSweeps)
            // R1ω and R3ω use reverseSeriesForLegend: true; map label overrides against reversed order.
            let labelMapSeries = Array(fakeSeries.reversed())

            var renderer1 = ThreeOmegaPlotRenderer()
            renderer1.showGrid              = capturedGrid
            renderer1.seriesRenderMode      = capturedRenderMode
            renderer1.chartStyleOverrides   = capturedStyleOverrides
            renderer1.globalPlotDefaults    = capturedGlobalPlotDefaults
            renderer1.legendAnchor          = capturedAnchor
            renderer1.stackOffsetMultiplier = capturedMultiplier
            renderer1.minGapFraction        = capturedMinGap
            renderer1.titleTemplate         = capturedTemplate
            renderer1.titleTokens           = capturedTokens
            renderer1.legendPoint           = capturedState1.legendPoint?.cgPoint
            renderer1.titleOverride         = capturedState1.titleOverride
            renderer1.xLabelOverride        = capturedState1.xLabelOverride
            renderer1.yLabelOverride        = capturedState1.yLabelOverride
            renderer1.seriesLabelOverrides  = toIndexedOverrides(capturedState1.seriesLabelOverrides, series: labelMapSeries)
            let result1 = renderer1.renderR1omega(sweeps: ingestion.fieldSweeps, device: ingestion.device, seriesOrder: capturedFieldSweepSeriesOrder)

            var renderer3 = ThreeOmegaPlotRenderer()
            renderer3.showGrid              = capturedGrid
            renderer3.seriesRenderMode      = capturedRenderMode
            renderer3.chartStyleOverrides   = capturedStyleOverrides
            renderer3.globalPlotDefaults    = capturedGlobalPlotDefaults
            renderer3.legendAnchor          = capturedAnchor
            renderer3.stackOffsetMultiplier = capturedMultiplier
            renderer3.minGapFraction        = capturedMinGap
            renderer3.titleTemplate         = capturedTemplate
            renderer3.titleTokens           = capturedTokens
            renderer3.legendPoint           = capturedState3.legendPoint?.cgPoint
            renderer3.titleOverride         = capturedState3.titleOverride
            renderer3.xLabelOverride        = capturedState3.xLabelOverride
            renderer3.yLabelOverride        = capturedState3.yLabelOverride
            renderer3.seriesLabelOverrides  = toIndexedOverrides(capturedState3.seriesLabelOverrides, series: labelMapSeries)
            let result3 = renderer3.renderR3omega(sweeps: ingestion.fieldSweeps, device: ingestion.device, seriesOrder: capturedFieldSweepSeriesOrder)

            await MainActor.run { [weak self] in
                guard let self else { return }
                let s1 = self.tabs.state(for: .fieldSweep1omega)
                let m1: WorkbenchPlotPayload? = {
                    guard var p = self.tabs.output(for: .fieldSweep1omega).manifestPayload else { return nil }
                    if !s1.titleOverride.isEmpty { p.title = s1.titleOverride }
                    if !s1.xLabelOverride.isEmpty { p.axisMapping.xField = s1.xLabelOverride }
                    if !s1.yLabelOverride.isEmpty { p.axisMapping.yField = s1.yLabelOverride }
                    if !s1.seriesLabelOverrides.isEmpty {
                        p.series = applySeriesLabelOverrides(s1.seriesLabelOverrides, to: p.series)
                    }
                    return p
                }()
                self.tabs.setOutput(TabRenderOutput(imageData: result1.0, layout: result1.1, manifestPayload: m1), for: .fieldSweep1omega)
                let s3 = self.tabs.state(for: .fieldSweep3omega)
                let m3: WorkbenchPlotPayload? = {
                    guard var p = self.tabs.output(for: .fieldSweep3omega).manifestPayload else { return nil }
                    if !s3.titleOverride.isEmpty { p.title = s3.titleOverride }
                    if !s3.xLabelOverride.isEmpty { p.axisMapping.xField = s3.xLabelOverride }
                    if !s3.yLabelOverride.isEmpty { p.axisMapping.yField = s3.yLabelOverride }
                    if !s3.seriesLabelOverrides.isEmpty {
                        p.series = applySeriesLabelOverrides(s3.seriesLabelOverrides, to: p.series)
                    }
                    return p
                }()
                self.tabs.setOutput(TabRenderOutput(imageData: result3.0, layout: result3.1, manifestPayload: m3), for: .fieldSweep3omega)
            }
        }
    }


    // MARK: - Interactive callbacks (delegated to TabRenderManager)

    /// Re-renders the active tab for style-only changes (grid, etc.)
    /// without mutating legend position or anchor state.
    func rerenderForStyleChange() {
        _rerenderActiveTab()
    }


    // MARK: - Private helpers

    func _applyPlots(_ plots: ThreeOmegaRenderedPlots) {
        tabs.setOutput(TabRenderOutput(imageData: plots.r1omega, layout: plots.layoutR1omega, manifestPayload: nil), for: .fieldSweep1omega)
        tabs.setOutput(TabRenderOutput(imageData: plots.r3omega, layout: plots.layoutR3omega, manifestPayload: nil), for: .fieldSweep3omega)
        tabs.setOutput(TabRenderOutput(imageData: plots.rahe1omegaVsT, layout: plots.layoutRAHE1omegaVsT, manifestPayload: nil), for: .rahe1omegaVsT)
        tabs.setOutput(TabRenderOutput(imageData: plots.rahe3omegaVsT, layout: plots.layoutRAHE3omegaVsT, manifestPayload: nil), for: .rahe3omegaVsT)
        tabs.setOutput(TabRenderOutput(imageData: plots.hcVsT, layout: plots.layoutHcVsT, manifestPayload: nil), for: .hcVsT)
        tabs.setOutput(TabRenderOutput(imageData: plots.rtCurve, layout: plots.layoutRTCurve, manifestPayload: nil), for: .rtCurve)
        if plots.scaling != nil {
            tabs.setOutput(TabRenderOutput(imageData: plots.scaling, layout: nil, manifestPayload: nil), for: .scaling)
        }
    }


    /// Re-renders only the active tab using cached ingestion/scaling result.
    func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }

        // For RAHE tabs with overlays, delegate to overlay renderer
        let tab = tabs.activeTab
        if !overlayPackIDs.isEmpty,
           (tab == .rahe1omegaVsT || tab == .rahe3omegaVsT) {
            _renderRAHEWithOverlays()
            return
        }

        let tabState       = tabs.state(for: tab)
        let capturedGrid   = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor = tabs.legendAnchor
        let capturedLegend = tabState.legendPoint?.cgPoint
        let capturedHiddenLabels = tabs.hiddenPointLabelsBySampleID(for: tab)
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let titleOverride  = tabState.titleOverride
        let xLabelOverride = tabState.xLabelOverride
        let yLabelOverride = tabState.yLabelOverride
        let capturedLabelOverrides = tabState.seriesLabelOverrides
        let capturedSeriesOrder = (tab == .fieldSweep1omega || tab == .fieldSweep3omega) ? fieldSweepSeriesOrder : tabState.seriesOrder
        let capturedFieldSweeps = ingestion.fieldSweeps
        let capturedScaling = scalingResult
        let capturedGeometry = geometry
        let capturedTemplate = titleTemplate
        let capturedTokens  = _titleTokens
        let capturedDevice  = ingestion.device
        let capturedV3Method = v3Method
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod
        let capturedGlobalPlotDefaults = globalPlotDefaults

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let orderedSweeps = ThreeOmegaWorkspaceStore._applySeriesOrder(capturedSeriesOrder, to: capturedFieldSweeps)
            let fakeSeries = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(orderedSweeps)
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.seriesRenderMode      = capturedRenderMode
            r.chartStyleOverrides   = capturedStyleOverrides
            r.globalPlotDefaults    = capturedGlobalPlotDefaults
            r.legendAnchor          = capturedAnchor
            r.legendPoint           = capturedLegend
            r.hiddenPointLabelsBySeries = toIndexedOverrides(capturedHiddenLabels, series: fakeSeries).mapValues { Set($0) }
            r.stackOffsetMultiplier = capturedMultiplier
            r.minGapFraction        = capturedMinGap
            r.titleOverride         = titleOverride
            r.xLabelOverride        = xLabelOverride
            r.yLabelOverride        = yLabelOverride
            // R1omega and R3omega use reverseSeriesForLegend: true; the pipeline reverses before step 9,
            // so label indices must be mapped against the post-reversal order.
            let labelMapSeries: [WorkbenchPlotSeries]
            switch tab {
            case .fieldSweep1omega, .fieldSweep3omega:
                labelMapSeries = Array(fakeSeries.reversed())
            default:
                labelMapSeries = fakeSeries
            }
            r.seriesLabelOverrides  = toIndexedOverrides(capturedLabelOverrides, series: labelMapSeries)
            r.titleTemplate         = capturedTemplate
            r.titleTokens           = capturedTokens

            let rendered: (Data?, WorkbenchPlotLayout?, [String])
            switch tab {
            case .fieldSweep1omega:
                rendered = r.renderR1omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: capturedSeriesOrder)
            case .fieldSweep3omega:
                rendered = r.renderR3omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: capturedSeriesOrder)
            case .rahe1omegaVsT:
                rendered = r.renderRAHE1omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE1Method)
            case .rahe3omegaVsT:
                rendered = r.renderRAHE3omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE3Method)
            case .hcVsT:
                rendered = r.renderHcVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .rtCurve:
                rendered = ingestion.rtResult.map { r.renderRT(rt: $0) } ?? (nil, nil, [])
            case .scaling:
                if let sr = capturedScaling, capturedGeometry.isComplete {
                    let method = capturedV3Method == .highField ? "(HFE)" : "(WA)"
                    rendered = r.renderScaling(result: sr, device: capturedDevice, method: method)
                } else {
                    rendered = (nil, nil, [])
                }
            }

            let plotData   = rendered.0
            let plotLayout = rendered.1
            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                let existingManifest = self.tabs.output(for: tab).manifestPayload
                let updatedManifest: WorkbenchPlotPayload? = {
                    guard var payload = existingManifest else { return nil }
                    if !titleOverride.isEmpty { payload.title = titleOverride }
                    if !xLabelOverride.isEmpty { payload.axisMapping.xField = xLabelOverride }
                    if !yLabelOverride.isEmpty { payload.axisMapping.yField = yLabelOverride }
                    if !capturedLabelOverrides.isEmpty {
                        payload.series = payload.series.map { series in
                            guard let sampleID = series.sampleID,
                                  let renamed = capturedLabelOverrides[sampleID] else {
                                return series
                            }
                            var copy = series
                            copy.label = renamed
                            return copy
                        }
                    }
                    return payload
                }()
                self.tabs.setOutput(TabRenderOutput(imageData: plotData, layout: plotLayout, manifestPayload: updatedManifest), for: tab)
            }
        }
    }


    /// Re-renders RAHE tabs with overlays merged, then updates manifest payloads.
    func _renderRAHEWithOverlays() {
        guard let ingestion = ingestionResult else { return }

        // Build groups: first = active analysis, rest = overlays
        var groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])] = []
        let activeLabel = _autoPackLabel()
        groups.append((label: activeLabel, sweeps: ingestion.fieldSweeps, sourceFiles: cachedInputFiles))
        for oid in overlayPackIDs {
            if let snap = overlaySnapshots[oid] {
                groups.append((label: snap.label, sweeps: snap.sweeps, sourceFiles: snap.sourceFiles))
            }
        }

        let capturedGrid = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor = tabs.legendAnchor
        let state1 = tabs.state(for: .rahe1omegaVsT)
        let state3 = tabs.state(for: .rahe3omegaVsT)
        let capturedLegend1 = state1.legendPoint?.cgPoint
        let capturedLegend3 = state3.legendPoint?.cgPoint
        let titleOverride1 = state1.titleOverride
        let titleOverride3 = state3.titleOverride
        let capturedTemplate = titleTemplate
        let capturedTokens = _titleTokens
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod
        let capturedXLabel1 = state1.xLabelOverride
        let capturedYLabel1 = state1.yLabelOverride
        let capturedXLabel3 = state3.xLabelOverride
        let capturedYLabel3 = state3.yLabelOverride
        let capturedSeriesOverrides1 = state1.seriesLabelOverrides
        let capturedSeriesOverrides3 = state3.seriesLabelOverrides
        let capturedRAHEFieldSweeps = ingestion.fieldSweeps
        let capturedGlobalPlotDefaults = globalPlotDefaults

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self, groups] in
            let fakeSeries = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(capturedRAHEFieldSweeps)
            var r1 = ThreeOmegaPlotRenderer()
            r1.showGrid = capturedGrid
            r1.seriesRenderMode = capturedRenderMode
            r1.chartStyleOverrides = capturedStyleOverrides
            r1.globalPlotDefaults = capturedGlobalPlotDefaults
            r1.legendAnchor = capturedAnchor
            r1.legendPoint = capturedLegend1
            r1.titleOverride = titleOverride1
            r1.xLabelOverride = capturedXLabel1
            r1.yLabelOverride = capturedYLabel1
            r1.seriesLabelOverrides = toIndexedOverrides(capturedSeriesOverrides1, series: fakeSeries)
            r1.titleTemplate = capturedTemplate
            r1.titleTokens = capturedTokens
            let rahe1 = r1.renderRAHE1omegaVsTMulti(groups: groups, method: capturedRAHE1Method)

            var r3 = ThreeOmegaPlotRenderer()
            r3.showGrid = capturedGrid
            r3.seriesRenderMode = capturedRenderMode
            r3.chartStyleOverrides = capturedStyleOverrides
            r3.globalPlotDefaults = capturedGlobalPlotDefaults
            r3.legendAnchor = capturedAnchor
            r3.legendPoint = capturedLegend3
            r3.titleOverride = titleOverride3
            r3.xLabelOverride = capturedXLabel3
            r3.yLabelOverride = capturedYLabel3
            r3.seriesLabelOverrides = toIndexedOverrides(capturedSeriesOverrides3, series: fakeSeries)
            r3.titleTemplate = capturedTemplate
            r3.titleTokens = capturedTokens
            let rahe3 = r3.renderRAHE3omegaVsTMulti(groups: groups, method: capturedRAHE3Method)

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                let mR1 = self.tabs.output(for: .rahe1omegaVsT).manifestPayload
                self.tabs.setOutput(TabRenderOutput(imageData: rahe1.0, layout: rahe1.1, manifestPayload: mR1), for: .rahe1omegaVsT)
                let mR3 = self.tabs.output(for: .rahe3omegaVsT).manifestPayload
                self.tabs.setOutput(TabRenderOutput(imageData: rahe3.0, layout: rahe3.1, manifestPayload: mR3), for: .rahe3omegaVsT)

                // Rebuild manifest payloads with individual sourceRef per file (not ;-joined)
                self._rebuildOverlayManifestPayloads(groups: groups)
            }
        }
    }


    /// Re-renders all tabs from cached ingestion/scaling results (used after pack load).
    func _rerenderAllTabs() {
        guard let ingestion = ingestionResult else { return }

        let capturedGrid       = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor     = tabs.legendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod
        let capturedGlobalPlotDefaults = globalPlotDefaults
        Task.detached(priority: .userInitiated) { [weak self, ingestion] in
            var renderer = ThreeOmegaPlotRenderer()
            renderer.showGrid              = capturedGrid
            renderer.seriesRenderMode      = capturedRenderMode
            renderer.chartStyleOverrides   = capturedStyleOverrides
            renderer.globalPlotDefaults    = capturedGlobalPlotDefaults
            renderer.legendAnchor          = capturedAnchor
            renderer.stackOffsetMultiplier = capturedMultiplier
            renderer.minGapFraction        = capturedMinGap
            renderer.titleTemplate         = capturedTemplate
            renderer.titleTokens           = capturedTokens
            let plots = renderer.renderAllTabs(result: ingestion, rahe1Method: capturedRAHE1Method, rahe3Method: capturedRAHE3Method)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self._applyPlots(plots)
            }
        }

        // Also re-run scaling if geometry is complete
        if scalingResult != nil, geometry.isComplete {
            runScaling()
        }
    }


    /// Re-renders all tabs using the current per-tab TabRenderState overrides.
    /// Also refreshes numeric display tokens from the library index so that
    /// title tokens like #氧压 / #能量 resolve correctly after Pack load.
    /// Used exclusively in the Pack restore path.
    func _rerenderAllTabsFromRestoredState() {
        guard let ingestion = ingestionResult else { return }

        _renderRevision &+= 1
        let revision = _renderRevision

        let capturedGrid          = tabs.showPlotGrid
        let capturedRenderMode    = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor        = tabs.legendAnchor
        let capturedMultiplier    = stackOffsetMultiplier
        let capturedMinGap        = minGapFraction
        let capturedTemplate      = titleTemplate
        let capturedRAHE1Method   = rahe1omegaMethod
        let capturedRAHE3Method   = rahe3omegaMethod
        let capturedScaling       = scalingResult
        let capturedGeometry      = geometry
        let capturedV3Method      = v3Method
        let capturedDevice        = ingestion.device
        let capturedFieldSweepSeriesOrder = fieldSweepSeriesOrder
        let capturedGlobalPlotDefaults = globalPlotDefaults

        struct PerTabSnap: Sendable {
            let titleOverride: String
            let xLabelOverride: String
            let yLabelOverride: String
            let seriesLabelOverrides: [String: String]
            let legendPoint: CGPoint?
            let hiddenPointLabelsBySeries: [String: [Int]]
            let seriesOrder: [String]?
        }
        let tabSnaps: [ThreeOmegaWorkbenchTab: PerTabSnap] = Dictionary(
            uniqueKeysWithValues: ThreeOmegaWorkbenchTab.allCases.map { tab in
                let s = tabs.state(for: tab)
                return (tab, PerTabSnap(
                    titleOverride: s.titleOverride,
                    xLabelOverride: s.xLabelOverride,
                    yLabelOverride: s.yLabelOverride,
                    seriesLabelOverrides: s.seriesLabelOverrides,
                    legendPoint: s.legendPoint?.cgPoint,
                    hiddenPointLabelsBySeries: tabs.hiddenPointLabelsBySampleID(for: tab),
                    seriesOrder: (tab == .fieldSweep1omega || tab == .fieldSweep3omega) ? capturedFieldSweepSeriesOrder : s.seriesOrder
                ))
            }
        )
        let capturedRestoredFieldSweeps = ingestion.fieldSweeps

        let lookupHit              = cachedSearchResults.first
        let lookupLibraryRoot      = lastLibraryRootPath
        let fallbackTokens         = _titleTokens
        let capturedLibraryAccess  = env.libraryAccess

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Refresh numeric display tokens from library index.
            // cachedSampleNumericDisplay may be empty after Pack load (no search was run),
            // so we reload directly from disk here.
            var tokens = fallbackTokens
            if let hit = lookupHit, !lookupLibraryRoot.isEmpty {
                let rootURL = URL(fileURLWithPath: lookupLibraryRoot, isDirectory: true)
                if let nd = capturedLibraryAccess.loadIndex(from: rootURL)?
                    .sample(matchingDiskKey: hit.sampleKey)?.numericDisplay,
                   !nd.isEmpty {
                    tokens = ["sample": hit.sampleBatchAndSubstrate]
                    for (k, v) in nd { tokens[k] = v }
                }
            }

            func makeRenderer(for tab: ThreeOmegaWorkbenchTab) -> ThreeOmegaPlotRenderer {
                let s = tabSnaps[tab]!
                let orderedSweeps = ThreeOmegaWorkspaceStore._applySeriesOrder(s.seriesOrder, to: capturedRestoredFieldSweeps)
                let fakeSeries = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(orderedSweeps)
                var r = ThreeOmegaPlotRenderer()
                r.showGrid                   = capturedGrid
                r.seriesRenderMode           = capturedRenderMode
                r.chartStyleOverrides        = capturedStyleOverrides
                r.globalPlotDefaults         = capturedGlobalPlotDefaults
                r.legendAnchor               = capturedAnchor
                r.legendPoint                = s.legendPoint
                r.hiddenPointLabelsBySeries  = toIndexedOverrides(s.hiddenPointLabelsBySeries, series: fakeSeries).mapValues { Set($0) }
                r.stackOffsetMultiplier      = capturedMultiplier
                r.minGapFraction             = capturedMinGap
                r.titleTemplate              = capturedTemplate
                r.titleTokens               = tokens
                r.titleOverride              = s.titleOverride
                r.xLabelOverride             = s.xLabelOverride
                r.yLabelOverride             = s.yLabelOverride
                // R1omega and R3omega use reverseSeriesForLegend: true; the pipeline reverses before
                // applying index-keyed label overrides, so map against the post-reversal order.
                let labelMapSeries: [WorkbenchPlotSeries]
                switch tab {
                case .fieldSweep1omega, .fieldSweep3omega:
                    labelMapSeries = Array(fakeSeries.reversed())
                default:
                    labelMapSeries = fakeSeries
                }
                r.seriesLabelOverrides       = toIndexedOverrides(s.seriesLabelOverrides, series: labelMapSeries)
                return r
            }

            var plots = ThreeOmegaRenderedPlots()
            var r1 = makeRenderer(for: .fieldSweep1omega)
            (plots.r1omega, plots.layoutR1omega, _) = r1.renderR1omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: capturedFieldSweepSeriesOrder)
            var r3 = makeRenderer(for: .fieldSweep3omega)
            (plots.r3omega, plots.layoutR3omega, _) = r3.renderR3omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: capturedFieldSweepSeriesOrder)
            var rahe1 = makeRenderer(for: .rahe1omegaVsT)
            (plots.rahe1omegaVsT, plots.layoutRAHE1omegaVsT, _) = rahe1.renderRAHE1omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE1Method)
            var rahe3 = makeRenderer(for: .rahe3omegaVsT)
            (plots.rahe3omegaVsT, plots.layoutRAHE3omegaVsT, _) = rahe3.renderRAHE3omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE3Method)
            var hc = makeRenderer(for: .hcVsT)
            (plots.hcVsT, plots.layoutHcVsT, _) = hc.renderHcVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            if let rt = ingestion.rtResult {
                var rtR = makeRenderer(for: .rtCurve)
                (plots.rtCurve, plots.layoutRTCurve, _) = rtR.renderRT(rt: rt)
            }
            if let sr = capturedScaling, capturedGeometry.isComplete {
                let method = capturedV3Method == .highField ? "(HFE)" : "(WA)"
                var scR = makeRenderer(for: .scaling)
                (plots.scaling, _, _) = scR.renderScaling(result: sr, device: capturedDevice, method: method)
            }

            let titleTokens = tokens
            let renderedPlots = plots
            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                self._titleTokens = titleTokens
                self._applyPlots(renderedPlots)
            }
        }
    }
}
