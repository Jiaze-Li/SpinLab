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

        var resolvedFieldSweepVisualOrder: [String]? = nil
        var effectiveTabSnapshot = tabSnapshot

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
            let visualOrder = fieldSweepSeriesOrder
                ?? tabSnapshot.seriesOrder
                ?? Self.defaultFieldSweepVisualSeriesOrder(
                    from: ingestion.fieldSweeps,
                    workflowID: globalSettings.workflowID,
                    tab: tab
                )
            resolvedFieldSweepVisualOrder = visualOrder
            effectiveTabSnapshot = tabSnapshot.with(seriesOrder: visualOrder)
            guard let manifestPayload = renderer.makeR1omegaPayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: visualOrder
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
                    seriesOrder: visualOrder,
                    hiddenSeriesKeys: effectiveTabSnapshot.hiddenSeriesKeys
                )
            }, manifestPayload: manifestPayload)
        case .fieldSweep3omega:
            let visualOrder = fieldSweepSeriesOrder
                ?? tabSnapshot.seriesOrder
                ?? Self.defaultFieldSweepVisualSeriesOrder(
                    from: ingestion.fieldSweeps,
                    workflowID: globalSettings.workflowID,
                    tab: tab
                )
            resolvedFieldSweepVisualOrder = visualOrder
            effectiveTabSnapshot = tabSnapshot.with(seriesOrder: visualOrder)
            guard let manifestPayload = renderer.makeR3omegaPayload(
                sweeps: ingestion.fieldSweeps,
                device: ingestion.device,
                seriesOrder: visualOrder
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
                    seriesOrder: visualOrder,
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
                let seriesControlModel: SeriesControlModel? = {
                    guard let resolvedFieldSweepVisualOrder,
                          let manifestPayload,
                          tab == .fieldSweep1omega || tab == .fieldSweep3omega else {
                        return nil
                    }
                    return SeriesControlModel.fromPayload(
                        manifestPayload,
                        currentSeriesOrder: resolvedFieldSweepVisualOrder,
                        hiddenSeriesKeys: effectiveTabSnapshot.hiddenSeriesKeys
                    )
                }()
                output = TabRenderOutput(
                    imageData: data,
                    layout: layoutValue,
                    manifestPayload: manifestPayload,
                    displayPayload: payload,
                    seriesControlModel: seriesControlModel
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
        let capturedState1     = tabs.displayStateSnapshot(for: .fieldSweep1omega)
        let capturedState3     = tabs.displayStateSnapshot(for: .fieldSweep3omega)
        let capturedGlobalPlotDefaults = globalPlotDefaults
        let capturedWorkflowID = workflowID
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

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let tabSnapshot1 = capturedState1.with(seriesOrder: capturedFieldSweepSeriesOrder)
            let tabSnapshot3 = capturedState3.with(seriesOrder: capturedFieldSweepSeriesOrder)
            let result1 = await self.renderThreeOmegaTab(
                .fieldSweep1omega,
                ingestion: ingestion,
                scalingResult: nil,
                fieldSweepSeriesOrder: capturedFieldSweepSeriesOrder,
                globalSettings: globalSettings,
                tabSnapshot: tabSnapshot1
            )
            let result3 = await self.renderThreeOmegaTab(
                .fieldSweep3omega,
                ingestion: ingestion,
                scalingResult: nil,
                fieldSweepSeriesOrder: capturedFieldSweepSeriesOrder,
                globalSettings: globalSettings,
                tabSnapshot: tabSnapshot3
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                for warning in result1.warnings + result3.warnings {
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
    /// tag visibility.
    nonisolated static func _buildRenderer(
        for tab: ThreeOmegaWorkbenchTab,
        globalSettings: ThreeOmegaRendererGlobalSettings,
        tabSnap: WorkbenchTabDisplayStateSnapshot,
        fieldSweeps: [ThreeOmegaFieldSweepResult]
    ) -> ThreeOmegaPlotRenderer {
        let orderedSweeps = _applySeriesOrder(rendererSeriesOrder(fromVisualOrder: tabSnap.seriesOrder), to: fieldSweeps)
        let fakeSeries = _sweepsToFakeSeries(orderedSweeps)
        // Field-sweep stacked payloads now stay in visual top-to-bottom order all the way
        // through the renderer, so index-keyed label overrides can be mapped directly.
        let labelMapSeries = fakeSeries
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
        switch tab {
        case .fieldSweep1omega, .fieldSweep3omega:
            r.canonicalVisualSeriesOrder = tabSnap.seriesOrder ?? Self.defaultFieldSweepVisualSeriesOrder(
                from: fieldSweeps,
                workflowID: globalSettings.workflowID,
                tab: tab
            )
        default:
            r.canonicalVisualSeriesOrder = tabSnap.seriesOrder
        }
        return r
    }

    nonisolated static func defaultFieldSweepVisualSeriesOrder(
        from fieldSweeps: [ThreeOmegaFieldSweepResult],
        workflowID: String,
        tab: ThreeOmegaWorkbenchTab
    ) -> [String] {
        guard !fieldSweeps.isEmpty else { return [] }
        return Array(fieldSweeps.map(\.stableSourceRef).reversed())
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
