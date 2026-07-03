import Foundation

// MARK: - ThreeOmegaRendererGlobalSettings

/// Sendable capture of rendering settings shared across all 3ω tabs.
/// Paired with per-tab WorkbenchTabDisplayStateSnapshot and captured on MainActor
/// before entering any detached task.
struct ThreeOmegaRendererGlobalSettings: Sendable {
    let workflowID: String
    let showGrid: Bool
    let seriesRenderMode: SeriesRenderMode
    let chartStyleOverrides: [String: String]
    let globalPlotDefaults: [String: String]
    let legendAnchor: String
    let stackOffsetMultiplier: Double
    let minGapFraction: Double
    let titleTemplate: String
    let titleTokens: [String: String]

    func with(titleTokens: [String: String]) -> ThreeOmegaRendererGlobalSettings {
        ThreeOmegaRendererGlobalSettings(
            workflowID: workflowID,
            showGrid: showGrid,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            globalPlotDefaults: globalPlotDefaults,
            legendAnchor: legendAnchor,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            titleTemplate: titleTemplate,
            titleTokens: titleTokens
        )
    }
}

struct ThreeOmegaTabRenderResult {
    let imageData: Data?
    let layout: WorkbenchPlotLayout?
    let displayPayload: WorkbenchPlotPayload?
    let warnings: [String]
}

@MainActor
extension ThreeOmegaWorkspaceStore {

    /// Returns true when the current MainActor state still permits committing a render result.
    /// Re-evaluate this immediately before every tabs.setOutput call so in-flight detached work
    /// cannot publish stale output after a newer render or analysis change.
    private func _canCommitRenderOutput(revision: UInt64?, analysisRevision: UInt64?) -> Bool {
        guard !Task.isCancelled else { return false }
        if let revision, revision != _renderRevision { return false }
        if let analysisRevision, analysisRevision != _analysisRevision { return false }
        return true
    }

    func renderThreeOmegaTab(
        _ tab: ThreeOmegaWorkbenchTab,
        ingestion: ThreeOmegaIngestionResult,
        scalingResult: ThreeOmegaScalingResult?,
        fieldSweepSeriesOrder: [String]?,
        globalSettings: ThreeOmegaRendererGlobalSettings,
        tabSnapshot: WorkbenchTabDisplayStateSnapshot,
        revision: UInt64? = nil,
        analysisRevision: UInt64? = nil,
        policy: DisplayOverridePolicy = .preserveDisplayOverrides
    ) async -> ThreeOmegaTabRenderResult {
        let baseOptions: WorkbenchChartRenderer.Options = {
            switch tab {
            case .fieldSweep1omega, .fieldSweep3omega:
                var opts = WorkbenchChartRenderer.Options()
                opts.height = max(opts.height, opts.height + (ingestion.fieldSweeps.count - 6) * 40)
                return opts
            default:
                return .init()
            }
        }()

        _ = tab == .temperatureDependence ? nil : tabs.output(for: tab).manifestPayload
        let dualAxisDisplaySnapshot = temperatureDependenceDisplayState.snapshot()

        func emptyResult() -> ThreeOmegaTabRenderResult {
            ThreeOmegaTabRenderResult(imageData: nil, layout: nil, displayPayload: nil, warnings: [])
        }

        if tab == .scaling {
            guard scalingResult != nil, geometry.isComplete else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
        }

        if tab == .temperatureDependence {
            guard scalingResult != nil, geometry.isComplete else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(
                        TabRenderOutput(
                            renderKind: .dualAxis,
                            manifestPayload: nil,
                            displayPayload: nil
                        ),
                        for: tab,
                        policy: policy
                    )
                }
                return emptyResult()
            }
        }

        var renderer = ThreeOmegaPlotRenderer()
        renderer.workflowID = globalSettings.workflowID
        renderer.showGrid = globalSettings.showGrid
        renderer.seriesRenderMode = globalSettings.seriesRenderMode
        renderer.chartStyleOverrides = globalSettings.chartStyleOverrides
        renderer.globalPlotDefaults = globalSettings.globalPlotDefaults
        renderer.legendAnchor = globalSettings.legendAnchor
        renderer.stackOffsetMultiplier = globalSettings.stackOffsetMultiplier
        renderer.minGapFraction = globalSettings.minGapFraction
        renderer.titleTemplate = globalSettings.titleTemplate
        renderer.titleTokens = globalSettings.titleTokens

        enum PreparedRender {
            case xy(WorkbenchRenderPipeline.Input, manifestPayload: WorkbenchPlotPayload, displayPayload: WorkbenchPlotPayload)
            case rendered(render: @Sendable () -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]), manifestPayload: WorkbenchPlotPayload)
            case dualAxis(ThreeOmegaScalingResult)
        }

        let preparedRender: PreparedRender
        switch tab {
        case .rahe:
            guard let payload = renderer.makeRAHEPayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: tabSnapshot.seriesOrder,
                rahe1Method: rahe1omegaMethod,
                rahe3Method: rahe3omegaMethod
            ) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            let input = tabs.buildPipelineInput(
                payload: payload,
                baseOptions: baseOptions,
                globalPlotDefaults: globalSettings.globalPlotDefaults,
                tabState: tabSnapshot,
                showPlotGrid: globalSettings.showGrid,
                seriesRenderMode: globalSettings.seriesRenderMode,
                chartStyleOverrides: globalSettings.chartStyleOverrides,
                legendAnchor: globalSettings.legendAnchor,
                for: tab
            )
            preparedRender = .xy(input, manifestPayload: payload, displayPayload: payload)
        case .fieldSweep1omega:
            let renderSeriesOrder = Self.rendererSeriesOrder(fromVisualOrder: fieldSweepSeriesOrder ?? tabSnapshot.seriesOrder)
            let effectiveTabSnapshot = tabSnapshot.with(seriesOrder: fieldSweepSeriesOrder ?? tabSnapshot.seriesOrder)
            guard let manifestPayload = renderer.makeR1omegaPayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: renderSeriesOrder
            ) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            preparedRender = .rendered(render: { [globalSettings, effectiveTabSnapshot, ingestion, tab] in
                var r = Self._buildRenderer(
                    for: tab,
                    globalSettings: globalSettings,
                    tabSnap: effectiveTabSnapshot,
                    fieldSweeps: ingestion.fieldSweeps
                )
                return r.renderR1omega(
                    sweeps: ingestion.fieldSweeps,
                    device: ingestion.device,
                    seriesOrder: renderSeriesOrder,
                    hiddenSeriesKeys: effectiveTabSnapshot.hiddenSeriesKeys
                )
            }, manifestPayload: manifestPayload)
        case .fieldSweep3omega:
            let renderSeriesOrder = Self.rendererSeriesOrder(fromVisualOrder: fieldSweepSeriesOrder ?? tabSnapshot.seriesOrder)
            let effectiveTabSnapshot = tabSnapshot.with(seriesOrder: fieldSweepSeriesOrder ?? tabSnapshot.seriesOrder)
            guard let manifestPayload = renderer.makeR3omegaPayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: renderSeriesOrder
            ) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            preparedRender = .rendered(render: { [globalSettings, effectiveTabSnapshot, ingestion, tab] in
                var r = Self._buildRenderer(
                    for: tab,
                    globalSettings: globalSettings,
                    tabSnap: effectiveTabSnapshot,
                    fieldSweeps: ingestion.fieldSweeps
                )
                return r.renderR3omega(
                    sweeps: ingestion.fieldSweeps,
                    device: ingestion.device,
                    seriesOrder: renderSeriesOrder,
                    hiddenSeriesKeys: effectiveTabSnapshot.hiddenSeriesKeys
                )
            }, manifestPayload: manifestPayload)
        case .rahe1omegaVsT, .rahe3omegaVsT:
            if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
            }
            return emptyResult()
        case .rahe1omegaVsDevice:
            guard let payload = renderer.makeRAHE1omegaVsDevicePayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                method: rahe1omegaVsDeviceMethod
            ) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            let input = tabs.buildPipelineInput(
                payload: payload,
                baseOptions: baseOptions,
                globalPlotDefaults: globalSettings.globalPlotDefaults,
                tabState: tabSnapshot,
                showPlotGrid: globalSettings.showGrid,
                seriesRenderMode: globalSettings.seriesRenderMode,
                chartStyleOverrides: globalSettings.chartStyleOverrides,
                legendAnchor: globalSettings.legendAnchor,
                for: tab
            )
            preparedRender = .xy(input, manifestPayload: payload, displayPayload: payload)
        case .rahe3omegaVsDevice:
            guard let payload = renderer.makeRAHE3omegaVsDevicePayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                method: rahe3omegaVsDeviceMethod
            ) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            let input = tabs.buildPipelineInput(
                payload: payload,
                baseOptions: baseOptions,
                globalPlotDefaults: globalSettings.globalPlotDefaults,
                tabState: tabSnapshot,
                showPlotGrid: globalSettings.showGrid,
                seriesRenderMode: globalSettings.seriesRenderMode,
                chartStyleOverrides: globalSettings.chartStyleOverrides,
                legendAnchor: globalSettings.legendAnchor,
                for: tab
            )
            preparedRender = .xy(input, manifestPayload: payload, displayPayload: payload)
        case .hcVsT:
            guard let payload = renderer.makeHcPayload(sweeps: ingestion.fieldSweeps, device: ingestion.device) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            let input = tabs.buildPipelineInput(
                payload: payload,
                baseOptions: baseOptions,
                globalPlotDefaults: globalSettings.globalPlotDefaults,
                tabState: tabSnapshot,
                showPlotGrid: globalSettings.showGrid,
                seriesRenderMode: globalSettings.seriesRenderMode,
                chartStyleOverrides: globalSettings.chartStyleOverrides,
                legendAnchor: globalSettings.legendAnchor,
                for: tab
            )
            preparedRender = .xy(input, manifestPayload: payload, displayPayload: payload)
        case .rtCurve:
            guard let payload = ingestion.rtResult.flatMap({ renderer.makeRTPayload(rt: $0) }) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            let input = tabs.buildPipelineInput(
                payload: payload,
                baseOptions: baseOptions,
                globalPlotDefaults: globalSettings.globalPlotDefaults,
                tabState: tabSnapshot,
                showPlotGrid: globalSettings.showGrid,
                seriesRenderMode: globalSettings.seriesRenderMode,
                chartStyleOverrides: globalSettings.chartStyleOverrides,
                legendAnchor: globalSettings.legendAnchor,
                for: tab
            )
            preparedRender = .xy(input, manifestPayload: payload, displayPayload: payload)
        case .scaling:
            guard let scalingResult, geometry.isComplete else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            let method = v3Method == .highField ? "(HFE)" : "(WA)"
            guard let payload = renderer.makeScalingPayload(result: scalingResult, device: ingestion.device, method: method) else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
                return emptyResult()
            }
            let input = tabs.buildPipelineInput(
                payload: payload,
                baseOptions: baseOptions,
                globalPlotDefaults: globalSettings.globalPlotDefaults,
                tabState: tabSnapshot,
                showPlotGrid: globalSettings.showGrid,
                seriesRenderMode: globalSettings.seriesRenderMode,
                chartStyleOverrides: globalSettings.chartStyleOverrides,
                legendAnchor: globalSettings.legendAnchor,
                for: tab
            )
            preparedRender = .xy(input, manifestPayload: payload, displayPayload: payload)
        case .temperatureDependence:
            guard let scalingResult else {
                if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                    tabs.setOutput(
                        TabRenderOutput(
                            renderKind: .dualAxis,
                            manifestPayload: nil,
                            displayPayload: nil
                        ),
                        for: tab,
                        policy: policy
                    )
                }
                return emptyResult()
            }
            preparedRender = .dualAxis(scalingResult)
        }

        do {
            enum RenderedTab {
                case xy(Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, WorkbenchPlotPayload?, [String])
                case rendered(Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, WorkbenchPlotPayload?, [String])
                case dualAxis(Data?, DualAxisPlotLayout?, DualAxisPlotPayload?, [String])
            }

            let rendered: RenderedTab = try await Task.detached(priority: .userInitiated) {
                switch preparedRender {
                case let .xy(input, manifestPayload, displayPayload):
                    let output = try WorkbenchRenderPipeline.render(input)
                    return .xy(output.imageData, output.layout, manifestPayload, displayPayload, output.warnings)
                case let .rendered(render, manifestPayload):
                    let result = render()
                    return .rendered(result.0, result.1, manifestPayload, result.2, result.3)
                case let .dualAxis(scalingResult):
                    var renderer = ThreeOmegaPlotRenderer()
                    renderer.workflowID = globalSettings.workflowID
                    renderer.showGrid = globalSettings.showGrid
                    renderer.seriesRenderMode = globalSettings.seriesRenderMode
                    renderer.chartStyleOverrides = globalSettings.chartStyleOverrides
                    renderer.globalPlotDefaults = globalSettings.globalPlotDefaults
                    renderer.legendAnchor = globalSettings.legendAnchor
                    renderer.stackOffsetMultiplier = globalSettings.stackOffsetMultiplier
                    renderer.minGapFraction = globalSettings.minGapFraction
                    renderer.titleTemplate = globalSettings.titleTemplate
                    renderer.titleTokens = globalSettings.titleTokens
                    let (imageData, layout, payload, warnings) = renderer.renderTemperatureDependence(
                        result: scalingResult,
                        displayState: dualAxisDisplaySnapshot,
                        legendPoint: tabSnapshot.legendPoint
                    )
                    return .dualAxis(imageData, layout, payload, warnings)
                }
            }.value

            let output: TabRenderOutput
            let imageData: Data?
            let layout: WorkbenchPlotLayout?
            let displayPayload: WorkbenchPlotPayload?
            let warnings: [String]

            switch rendered {
            case let .xy(data, layoutValue, manifestPayload, payload, renderWarnings):
                imageData = data
                layout = layoutValue
                displayPayload = payload
                warnings = renderWarnings
                output = TabRenderOutput(
                    imageData: data,
                    layout: layoutValue,
                    manifestPayload: manifestPayload,
                    displayPayload: payload
                )
            case let .rendered(data, layoutValue, manifestPayload, payload, renderWarnings):
                imageData = data
                layout = layoutValue
                displayPayload = payload
                warnings = renderWarnings
                output = TabRenderOutput(
                    imageData: data,
                    layout: layoutValue,
                    manifestPayload: manifestPayload,
                    displayPayload: payload
                )
            case let .dualAxis(data, layoutValue, payload, renderWarnings):
                imageData = data
                layout = nil
                displayPayload = nil
                warnings = renderWarnings
                output = TabRenderOutput(
                    imageData: data,
                    renderKind: .dualAxis,
                    layout: nil,
                    manifestPayload: nil,
                    displayPayload: nil,
                    dualAxisLayout: layoutValue,
                    dualAxisPayload: payload
                )
            }

            guard _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) else {
                return ThreeOmegaTabRenderResult(
                    imageData: imageData,
                    layout: layout,
                    displayPayload: displayPayload,
                    warnings: warnings
                )
            }

            tabs.setOutput(output, for: tab, policy: policy)
            return ThreeOmegaTabRenderResult(
                imageData: imageData,
                layout: layout,
                displayPayload: displayPayload,
                warnings: warnings
            )
        } catch {
            if _canCommitRenderOutput(revision: revision, analysisRevision: analysisRevision) {
                if tab == .temperatureDependence {
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
                        for: tab,
                        policy: policy
                    )
                } else {
                    tabs.setOutput(TabRenderOutput(), for: tab, policy: policy)
                }
            }
            return ThreeOmegaTabRenderResult(
                imageData: nil,
                layout: nil,
                displayPayload: nil,
                warnings: ["pipeline failure: \(error)"]
            )
        }
    }

    /// Explicit RAHE method switch — re-renders active tab and refreshes manifests.
    func updateRAHEMethod(_ method: ThreeOmegaV3Method) {
        switch tabs.activeTab {
        case .rahe1omegaVsDevice:
            guard method != rahe1omegaVsDeviceMethod else { return }
            rahe1omegaVsDeviceMethod = method
        case .rahe3omegaVsDevice:
            guard method != rahe3omegaVsDeviceMethod else { return }
            rahe3omegaVsDeviceMethod = method
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
        let capturedWorkflowID = workflowID

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let renderSeriesOrder = ThreeOmegaWorkspaceStore.rendererSeriesOrder(fromVisualOrder: capturedFieldSweepSeriesOrder)
            let orderedSweeps  = ThreeOmegaWorkspaceStore._applySeriesOrder(renderSeriesOrder, to: ingestion.fieldSweeps)
            let fakeSeries     = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(orderedSweeps)
            // R1ω and R3ω use reverseSeriesForLegend: true; map label overrides against reversed order.
            let labelMapSeries = Array(fakeSeries.reversed())

            var renderer1 = ThreeOmegaPlotRenderer()
            renderer1.workflowID            = capturedWorkflowID
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
            renderer1.hiddenPointLabelsBySeries = toIndexedOverrides(capturedState1.hiddenPointLabelIndicesBySeries, series: labelMapSeries).mapValues { Set($0) }
            renderer1.axisRangeOverride     = capturedState1.axisRangeOverride
            renderer1.showPointTags         = capturedState1.pointTags.showPointTags
            let result1 = renderer1.renderR1omega(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: renderSeriesOrder,
                hiddenSeriesKeys: capturedState1.hiddenSeriesKeys
            )

            var renderer3 = ThreeOmegaPlotRenderer()
            renderer3.workflowID            = capturedWorkflowID
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
            renderer3.hiddenPointLabelsBySeries = toIndexedOverrides(capturedState3.hiddenPointLabelIndicesBySeries, series: labelMapSeries).mapValues { Set($0) }
            renderer3.axisRangeOverride     = capturedState3.axisRangeOverride
            renderer3.showPointTags         = capturedState3.pointTags.showPointTags
            let result3 = renderer3.renderR3omega(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: renderSeriesOrder,
                hiddenSeriesKeys: capturedState3.hiddenSeriesKeys
            )
            let m1 = renderer1.makeR1omegaPayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: renderSeriesOrder
            )
            let m3 = renderer3.makeR3omegaPayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: renderSeriesOrder
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.tabs.setOutput(TabRenderOutput(imageData: result1.0, layout: result1.1, manifestPayload: m1, displayPayload: result1.2), for: .fieldSweep1omega)
                self.tabs.setOutput(TabRenderOutput(imageData: result3.0, layout: result3.1, manifestPayload: m3, displayPayload: result3.2), for: .fieldSweep3omega)
                for warning in result1.3 + result3.3 {
                    self.appendWarning(source: "Render", message: warning)
                }
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

    func _applyPlots(_ plots: ThreeOmegaRenderedPlots, policy: DisplayOverridePolicy = .preserveDisplayOverrides) {
        tabs.setOutput(TabRenderOutput(imageData: plots.rahe, layout: plots.layoutRAHE, manifestPayload: nil, displayPayload: plots.displayRAHE), for: .rahe, policy: policy)
        tabs.setOutput(TabRenderOutput(imageData: plots.r1omega, layout: plots.layoutR1omega, manifestPayload: nil, displayPayload: plots.displayR1omega), for: .fieldSweep1omega, policy: policy)
        tabs.setOutput(TabRenderOutput(imageData: plots.r3omega, layout: plots.layoutR3omega, manifestPayload: nil, displayPayload: plots.displayR3omega), for: .fieldSweep3omega, policy: policy)
        tabs.setOutput(TabRenderOutput(imageData: plots.rahe1omegaVsDevice, layout: plots.layoutRAHE1omegaVsDevice, manifestPayload: nil, displayPayload: plots.displayRAHE1omegaVsDevice), for: .rahe1omegaVsDevice, policy: policy)
        tabs.setOutput(TabRenderOutput(imageData: plots.rahe3omegaVsDevice, layout: plots.layoutRAHE3omegaVsDevice, manifestPayload: nil, displayPayload: plots.displayRAHE3omegaVsDevice), for: .rahe3omegaVsDevice, policy: policy)
        tabs.setOutput(TabRenderOutput(imageData: plots.hcVsT, layout: plots.layoutHcVsT, manifestPayload: nil, displayPayload: plots.displayHcVsT), for: .hcVsT, policy: policy)
        tabs.setOutput(TabRenderOutput(imageData: plots.rtCurve, layout: plots.layoutRTCurve, manifestPayload: nil, displayPayload: plots.displayRTCurve), for: .rtCurve, policy: policy)
        if plots.scaling != nil {
            tabs.setOutput(TabRenderOutput(imageData: plots.scaling, layout: plots.layoutScaling, manifestPayload: nil, displayPayload: plots.displayScaling), for: .scaling, policy: policy)
        }
    }


    /// Re-renders only the active tab using cached ingestion/scaling result.
    func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }

        // For RAHE tabs with overlays, delegate to overlay renderer
        let tab = tabs.activeTab
        if tab == .scaling {
            scalingTask?.cancel()
            scalingTask = nil
            isRefreshingTransportDerivedPlots = false
            if case .refreshing = transportDerivedStatus {
                if let scalingResult {
                    transportDerivedStatus = scalingResult.points.count >= 2
                        ? .ready
                        : .unavailable("Scaling Law unavailable: fewer than 2 valid points.")
                } else {
                    transportDerivedStatus = .idle
                }
            }
        }
        let tabState       = tabs.state(for: tab)
        let capturedGrid   = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor = tabs.legendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedAxisRangeOverride = tabState.axisRangeOverride
        AxisRangeDebug.log("ThreeOmegaWorkspaceStore._rerenderActiveTab | activeTab=\(tab) capturedAxisRangeOverride=\(String(describing: capturedAxisRangeOverride))")
        let capturedSeriesOrder = (tab == .fieldSweep1omega || tab == .fieldSweep3omega) ? fieldSweepSeriesOrder : tabState.seriesOrder
        let capturedScaling = scalingResult
        let capturedTemplate = titleTemplate
        let capturedTokens  = _titleTokens
        let capturedGlobalPlotDefaults = globalPlotDefaults
        let capturedWorkflowID = workflowID
        let tabSnapshot = tabs.displayStateSnapshot(for: tab)

        _renderRevision &+= 1
        let revision = _renderRevision

        Task { [weak self] in
            guard let self else { return }
            let renderResult = await self.renderThreeOmegaTab(
                tab,
                ingestion: ingestion,
                scalingResult: capturedScaling,
                fieldSweepSeriesOrder: capturedSeriesOrder,
                globalSettings: ThreeOmegaRendererGlobalSettings(
                    workflowID: capturedWorkflowID,
                    showGrid: capturedGrid,
                    seriesRenderMode: capturedRenderMode,
                    chartStyleOverrides: capturedStyleOverrides,
                    globalPlotDefaults: capturedGlobalPlotDefaults,
                    legendAnchor: capturedAnchor,
                    stackOffsetMultiplier: capturedMultiplier,
                    minGapFraction: capturedMinGap,
                    titleTemplate: capturedTemplate,
                    titleTokens: capturedTokens
                ),
                tabSnapshot: tabSnapshot,
                revision: revision,
                policy: .preserveDisplayOverrides
            )

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                for warning in renderResult.warnings {
                    self.appendWarning(source: "Render", message: warning)
                }
            }
        }
    }


    // MARK: - Shared renderer builder

    /// Builds a configured ThreeOmegaPlotRenderer for a single tab.
    ///
    /// Applies both global settings and per-tab display state so that the rendered PNG
    /// reflects title/axis/series label overrides, legend position, axis range, and point
    /// tag visibility. Handles the R1ω/R3ω reversed legend mapping internally.
    nonisolated static func _buildRenderer(
        for tab: ThreeOmegaWorkbenchTab,
        globalSettings: ThreeOmegaRendererGlobalSettings,
        tabSnap: WorkbenchTabDisplayStateSnapshot,
        fieldSweeps: [ThreeOmegaFieldSweepResult]
    ) -> ThreeOmegaPlotRenderer {
        let orderedSweeps = _applySeriesOrder(rendererSeriesOrder(fromVisualOrder: tabSnap.seriesOrder), to: fieldSweeps)
        let fakeSeries = _sweepsToFakeSeries(orderedSweeps)
        // R1ω and R3ω use reverseSeriesForLegend: true; the pipeline reverses series before
        // applying index-keyed label overrides, so map overrides against post-reversal order.
        let labelMapSeries: [WorkbenchPlotSeries]
        switch tab {
        case .fieldSweep1omega, .fieldSweep3omega:
            labelMapSeries = Array(fakeSeries.reversed())
        default:
            labelMapSeries = fakeSeries
        }
        var r = ThreeOmegaPlotRenderer()
        r.workflowID            = globalSettings.workflowID
        r.showGrid              = globalSettings.showGrid
        r.seriesRenderMode      = globalSettings.seriesRenderMode
        r.chartStyleOverrides   = globalSettings.chartStyleOverrides
        r.globalPlotDefaults    = globalSettings.globalPlotDefaults
        r.legendAnchor          = globalSettings.legendAnchor
        r.stackOffsetMultiplier = globalSettings.stackOffsetMultiplier
        r.minGapFraction        = globalSettings.minGapFraction
        r.titleTemplate         = globalSettings.titleTemplate
        r.titleTokens           = globalSettings.titleTokens
        r.legendPoint           = tabSnap.legendPoint
        r.hiddenPointLabelsBySeries = toIndexedOverrides(tabSnap.hiddenPointLabelsBySeries, series: fakeSeries).mapValues { Set($0) }
        r.showPointTags         = tabSnap.showPointTags
        r.titleOverride         = tabSnap.titleOverride
        r.xLabelOverride        = tabSnap.xLabelOverride
        r.yLabelOverride        = tabSnap.yLabelOverride
        r.seriesLabelOverrides  = toIndexedOverrides(tabSnap.seriesLabelOverrides, series: labelMapSeries)
        r.axisRangeOverride     = tabSnap.axisRangeOverride
        r.canonicalVisualSeriesOrder = tabSnap.seriesOrder
        return r
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
        let capturedScaling = scalingResult
        let capturedGlobalPlotDefaults = globalPlotDefaults
        let capturedWorkflowID = workflowID
        _renderRevision &+= 1
        let revision = _renderRevision
        Task { [weak self, ingestion] in
            guard let self else { return }
            let globalSettings = ThreeOmegaRendererGlobalSettings(
                workflowID: capturedWorkflowID,
                showGrid: capturedGrid,
                seriesRenderMode: capturedRenderMode,
                chartStyleOverrides: capturedStyleOverrides,
                globalPlotDefaults: capturedGlobalPlotDefaults,
                legendAnchor: capturedAnchor,
                stackOffsetMultiplier: capturedMultiplier,
                minGapFraction: capturedMinGap,
                titleTemplate: capturedTemplate,
                titleTokens: capturedTokens
            )
            let plots = await self.renderAllThreeOmegaTabs(
                ingestion: ingestion,
                scalingResult: capturedScaling,
                globalSettings: globalSettings,
            )
            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                for warning in plots.pipelineWarnings {
                    self.appendWarning(source: "Render", message: warning)
                }
            }
        }

        // Also refresh transport-derived plots when the cached analysis state is available.
        if ingestionResult != nil {
            refreshTransportDerivedPlots(reason: "rerender all tabs")
        }
    }


    /// Re-renders all tabs using the current per-tab TabRenderState overrides.
    /// Also refreshes numeric display tokens from the library index so that
    /// title tokens like #氧压 / #能量 resolve correctly after Pack load.
    /// Used exclusively in the Pack restore path.
    func _rerenderAllTabsFromRestoredState() {
        guard let ingestion = ingestionResult else { return }

        let capturedScaling        = scalingResult
        let capturedFieldSweepSeriesOrder = fieldSweepSeriesOrder

        let baseGlobalSettings = ThreeOmegaRendererGlobalSettings(
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
        let tabSnaps: [ThreeOmegaWorkbenchTab: WorkbenchTabDisplayStateSnapshot] =
            Dictionary(uniqueKeysWithValues: ThreeOmegaWorkbenchTab.allCases.map { tab in
                var snap = tabs.displayStateSnapshot(for: tab)
                if tab == .fieldSweep1omega || tab == .fieldSweep3omega {
                    snap = snap.with(seriesOrder: capturedFieldSweepSeriesOrder)
                }
                return (tab, snap)
            })
        let lookupHit             = cachedSearchResults.first
        let lookupLibraryRoot     = lastLibraryRootPath
        let fallbackTokens        = _titleTokens
        let capturedLibraryAccess = env.libraryAccess

        _renderRevision &+= 1
        let revision = _renderRevision

        Task { [weak self] in
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
            await MainActor.run { [weak self] in
                self?._titleTokens = tokens
            }
            let gs = baseGlobalSettings.with(titleTokens: tokens)

            let plots = await self.renderAllThreeOmegaTabs(
                ingestion: ingestion,
                scalingResult: capturedScaling,
                globalSettings: gs,
                tabSnaps: tabSnaps,
                fieldSweepSeriesOrder: capturedFieldSweepSeriesOrder
            )

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                self._titleTokens = tokens
                self._snapshotAndCacheManifestPayloads()
                for warning in plots.pipelineWarnings {
                    self.appendWarning(source: "Render", message: warning)
                }
            }
        }

        if ingestionResult != nil {
            refreshTransportDerivedPlots(reason: "rerender all tabs from restored state")
        }
    }

    func renderAllThreeOmegaTabs(
        ingestion: ThreeOmegaIngestionResult,
        scalingResult: ThreeOmegaScalingResult?,
        globalSettings: ThreeOmegaRendererGlobalSettings,
        tabSnaps: [ThreeOmegaWorkbenchTab: WorkbenchTabDisplayStateSnapshot]? = nil,
        fieldSweepSeriesOrder: [String]? = nil,
        analysisRevision: UInt64? = nil
    ) async -> ThreeOmegaRenderedPlots {
        var plots = ThreeOmegaRenderedPlots()
        let snaps = tabSnaps ?? Dictionary(uniqueKeysWithValues: ThreeOmegaWorkbenchTab.allCases.map { tab in
            let snap = tabs.displayStateSnapshot(for: tab)
            return (tab, snap)
        })
        let tabsToRender: [ThreeOmegaWorkbenchTab] = [
            .rahe,
            .fieldSweep1omega,
            .fieldSweep3omega,
            .rahe1omegaVsDevice,
            .rahe3omegaVsDevice,
            .hcVsT,
            .rtCurve,
            .scaling
        ]
        for tab in tabsToRender {
            let snap = snaps[tab] ?? tabs.displayStateSnapshot(for: tab)
            let result = await renderThreeOmegaTab(
                tab,
                ingestion: ingestion,
                scalingResult: scalingResult,
                fieldSweepSeriesOrder: fieldSweepSeriesOrder,
                globalSettings: globalSettings,
                tabSnapshot: snap,
                analysisRevision: analysisRevision,
                policy: .preserveDisplayOverrides
            )
            switch tab {
            case .rahe:
                plots.rahe = result.imageData
                plots.layoutRAHE = result.layout
                plots.displayRAHE = result.displayPayload
            case .rahe1omegaVsT, .rahe3omegaVsT:
                break
            case .fieldSweep1omega:
                plots.r1omega = result.imageData
                plots.layoutR1omega = result.layout
                plots.displayR1omega = result.displayPayload
            case .fieldSweep3omega:
                plots.r3omega = result.imageData
                plots.layoutR3omega = result.layout
                plots.displayR3omega = result.displayPayload
            case .rahe1omegaVsDevice:
                plots.rahe1omegaVsDevice = result.imageData
                plots.layoutRAHE1omegaVsDevice = result.layout
                plots.displayRAHE1omegaVsDevice = result.displayPayload
            case .rahe3omegaVsDevice:
                plots.rahe3omegaVsDevice = result.imageData
                plots.layoutRAHE3omegaVsDevice = result.layout
                plots.displayRAHE3omegaVsDevice = result.displayPayload
            case .hcVsT:
                plots.hcVsT = result.imageData
                plots.layoutHcVsT = result.layout
                plots.displayHcVsT = result.displayPayload
            case .rtCurve:
                plots.rtCurve = result.imageData
                plots.layoutRTCurve = result.layout
                plots.displayRTCurve = result.displayPayload
            case .scaling:
                plots.scaling = result.imageData
                plots.layoutScaling = result.layout
                plots.displayScaling = result.displayPayload
            case .temperatureDependence:
                break
            }
            plots.pipelineWarnings.append(contentsOf: result.warnings)
        }
        plots.pipelineWarnings = Array(Set(plots.pipelineWarnings))
        return plots
    }
}
