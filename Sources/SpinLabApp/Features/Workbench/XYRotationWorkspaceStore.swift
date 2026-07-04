import CryptoKit
import Foundation
import Observation

/// Isolated state and actions for the XY Rotation workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
@MainActor
@Observable
final class XYRotationWorkspaceStore: WorkbenchSaveCoordinating {

    // MARK: - Search / Selection bridge

    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    /// Injected by WorkbenchFeatureStore; typed protocol reference to WorkbenchSelectionRuntime.
    @ObservationIgnored weak var selectionReading: (any SelectionReading)?

    // MARK: - Analysis output

    // Internal setter is kept for boundary-test seeding; production mutation should stay inside analysis lifecycle paths.
    var ingestionResult: XYRotationIngestionResult?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    /// Save-to-library status message. Written only by `persistToLibrary()`.
    /// Cleared on `clearPlot()` and at analysis start.
    /// Preferred over `analysisMessage` (analysis status) for save status display.
    var saveMessage: String?

    // MARK: - Multi-tab render state (shell capability)

    var tabs = TabRenderManager<XYRotationWorkbenchTab>(defaultTab: .rxxVsPhi)
    var globalPlotDefaults: [String: String] = [:]

    // MARK: - Rendered plot (non-tab state)

    var currentRunTrace: WorkbenchRunTraceProjection?

    // MARK: - Warning log

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()

    // MARK: - Plot controls (workflow-specific)

    var stackOffsetMultiplier: Double = 0.0
    var minGapFraction: Double = 0.15
    var centerBaseline: Bool = false
    var linearDetrend: Bool = false
    var showAuxiliaryLine180: Bool = false
    var titleTemplate: String = "#tab #device #sample"
    var phiOffsetOverrides: [String: Double] = [:]

    // MARK: - Cached data for title template + persistence prep

    var cachedSampleNumericDisplay: [String: [String: String]] = [:]
    @ObservationIgnored private(set) var cachedInputFiles: [String] = []
    @ObservationIgnored private(set) var cachedSampleKeys: [String] = []
    @ObservationIgnored private var _titleTokens: [String: String] = [:]

    // MARK: - Context from WorkbenchFeatureStore

    var lastLibraryRootPath: String = ""

    // MARK: - Persistence (Save to Library)

    private(set) var persistenceOutcome: PersistenceOutcome?

    // cachedManifestPayloads now managed by tabs (TabRenderManager)

    // MARK: - Related charts (hover popover)

    private(set) var relatedChartsGrouped: [String: [WorkbenchResultReference]] = [:]
    @ObservationIgnored private var relatedChartsTask: Task<Void, Never>?

    // MARK: - Analysis Pack (vault integration)

    @ObservationIgnored var vault: AnalysisVault?
    var activePackID: AnalysisPack.ID?

    // MARK: - Environment

    let workflowID: String
    @ObservationIgnored private let env: WorkbenchEnvironment

    init(workflowID: String, env: WorkbenchEnvironment = .live) {
        self.workflowID = workflowID
        self.env = env
    }

    // MARK: - Private

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var _renderRevision: UInt64 = 0

    deinit {
        analysisTask?.cancel()
        relatedChartsTask?.cancel()
    }

    // MARK: - Renderer snapshot

    /// Single source of truth for building a renderer from current store state.
    /// Called by both `runAnalysis` and `_rerenderActiveTab` to avoid parameter drift.
    private func _snapshotRenderer(forTab tab: XYRotationWorkbenchTab) -> XYRotationPlotRenderer {
        let tabState = tabs.state(for: tab)
        var r = XYRotationPlotRenderer()
        r.workflowID = workflowID
        r.showGrid = tabs.showPlotGrid
        r.legendPoint = tabState.legendPoint?.cgPoint
        r.stackOffsetMultiplier = stackOffsetMultiplier
        r.minGapFraction = minGapFraction
        r.centerBaseline = centerBaseline
        r.linearDetrend = linearDetrend
        r.showAuxiliaryLine180 = showAuxiliaryLine180
        r.seriesRenderMode = tabs.seriesRenderMode
        r.globalPlotDefaults = globalPlotDefaults
        r.chartStyleOverrides = tabs.chartStyleOverrides
        r.titleTemplate = titleTemplate
        r.titleTokens = _titleTokens
        r.titleOverride = tabState.titleOverride
        r.xLabelOverride = tabState.xLabelOverride
        r.yLabelOverride = tabState.yLabelOverride
        let labelMapSeries: [WorkbenchPlotSeries]
        if let ingestion = ingestionResult {
            let baseForTab: [XYRotationAngleSweep]
            switch tab {
            case .rxxVsPhi: baseForTab = ingestion.sweeps
            case .rxyVsPhi: baseForTab = ingestion.sweeps.filter { $0.resistanceXY != nil }
            }
            labelMapSeries = _orderedXYLabelSeries(from: baseForTab, seriesOrder: tabState.seriesOrder)
        } else {
            labelMapSeries = []
        }
        r.seriesLabelOverrides = toIndexedOverrides(tabState.seriesLabelOverrides, series: labelMapSeries)
        r.phiOffsetOverrides = phiOffsetOverrides
        r.axisRangeOverride = tabState.axisRangeOverride
        return r
    }

    // MARK: - Analysis

    func runAnalysis() {
        runAnalysis(searchSnapshot: nil)
    }

    // MARK: - Rerender (style-only, no re-parse)

    func rerenderForStyleChange() {
        _rerenderActiveTab()
    }

    func updatePhiOffset(sweepID: String, offset: Double) {
        phiOffsetOverrides[sweepID] = offset
        _rerenderActiveTab()
    }

    private func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }
        let tab = tabs.activeTab
        let renderer = _snapshotRenderer(forTab: tab)
        let tabState = tabs.displayStateSnapshot(for: tab)
        let device = ingestion.device
        let manifestPayload: WorkbenchPlotPayload?
        switch tab {
        case .rxxVsPhi:
            manifestPayload = renderer.makeRxxVsPhiPayload(
                sweeps: ingestion.sweeps,
                device: device,
                seriesOrder: tabState.seriesOrder
            )
        case .rxyVsPhi:
            manifestPayload = renderer.makeRxyVsPhiPayload(
                sweeps: ingestion.sweeps,
                device: device,
                seriesOrder: tabState.seriesOrder
            )
        }
        guard let manifestPayload else { return }

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            var r = renderer
            let result: (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String])
            switch tab {
            case .rxxVsPhi:
                result = r.renderRxxVsPhi(
                    sweeps: ingestion.sweeps,
                    device: device,
                    seriesOrder: tabState.seriesOrder,
                    hiddenSeriesKeys: tabState.hiddenSeriesKeys
                )
            case .rxyVsPhi:
                result = r.renderRxyVsPhi(
                    sweeps: ingestion.sweeps,
                    device: device,
                    seriesOrder: tabState.seriesOrder,
                    hiddenSeriesKeys: tabState.hiddenSeriesKeys
                )
            }
            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                self.tabs.setOutput(
                    TabRenderOutput(
                        imageData: result.0,
                        layout: result.1,
                        manifestPayload: manifestPayload,
                        displayPayload: result.2
                    ),
                    for: tab
                )
                for warning in result.3 {
                    self.appendWarning(source: "Render", message: warning)
                }
            }
        }
    }

    func clearPlot() {
        analysisTask?.cancel()
        analysisTask = nil
        ingestionResult = nil
        currentRunTrace = nil
        isAnalyzing = false
        analysisMessage = nil
        saveMessage = nil
        _titleTokens = [:]
        warningLog.clear()
        activePackID = nil
        persistenceOutcome = nil
        relatedChartsTask?.cancel()
        relatedChartsTask = nil
        relatedChartsGrouped = [:]
        cachedSampleKeys = []
        cachedInputFiles = []
        tabs.clearAll()
    }

    func clearResults() {
        cachedSearchResults = []
        cachedSampleNumericDisplay = [:]
    }

    // MARK: - Related charts

    func refreshRelatedCharts() {
        relatedChartsTask?.cancel()
        relatedChartsTask = nil

        let keys = cachedSampleKeys
        let rootPath = lastLibraryRootPath
        // TODO(boundary): replace raw root-path probing with a shared library-root access helper.
        guard !keys.isEmpty, !rootPath.isEmpty else {
            relatedChartsGrouped = [:]
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard env.fileManager.fileExists(atPath: rootPath) else {
            relatedChartsGrouped = [:]
            return
        }
        relatedChartsTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                LoadRelatedChartsUseCase().execute(sampleKeys: keys, libraryRootURL: rootURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.relatedChartsGrouped = result
        }
    }

    func relatedCharts(for tab: XYRotationWorkbenchTab) -> [WorkbenchResultReference] {
        guard let payload = tabs.output(for: tab).manifestPayload else { return [] }
        let inputFiles = payload.series.compactMap(\.sourceRef)
        guard !inputFiles.isEmpty else { return [] }
        let key = InputFilesCanonicalKey.make(from: inputFiles)
        return relatedChartsGrouped[key] ?? []
    }

    // MARK: - Save to Library

    func applyPersistenceOutcome(_ outcome: PersistenceOutcome) {
        persistenceOutcome = outcome
    }

    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = activeChartPNG else {
            saveMessage = "No chart to save. Run analysis first."
            return
        }
        guard let payload = activeChartManifestPayload else {
            saveMessage = "No manifest payload available for the active tab."
            return
        }
        executeSave(
            input: SaveActiveChartInput(
                png: png,
                payload: payload,
                sampleKeys: activeChartSampleKeys,
                libraryRootPath: lastLibraryRootPath,
                metrics: buildActiveChartMetrics()
            ),
            onComplete: onComplete
        )
    }

    // MARK: - Pack helpers (private)

    private func _buildPackConfig() -> XYRotationPackConfig {
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: tabs.chartStyleOverrides)
        return XYRotationPackConfig(
            phiOffsetOverrides: phiOffsetOverrides,
            centerBaseline: centerBaseline,
            linearDetrend: linearDetrend,
            activeTab: tabs.activeTab.rawValue,
            titleTemplate: titleTemplate,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: tabs.showPlotGrid,
            showAuxiliaryLine180: showAuxiliaryLine180,
            legendAnchor: tabs.legendAnchor,
            seriesRenderMode: tabs.seriesRenderMode,
            chartStyleOverrides: splitOverrides.local,
            tabStates: tabs.snapshotStates(keyFor: { $0.rawValue }),
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectionReading?.selectedIDs(for: workflowID) ?? []),
            searchQueryText: ""   // filled by caller at WorkbenchFeatureStore level
        )
    }

    private func _buildPackResult() -> XYRotationPackResult {
        XYRotationPackResult(
            ingestionResult: ingestionResult!
        )
    }

    private func _autoPackLabel() -> String {
        let sample = cachedSearchResults.first?.sampleBatchAndSubstrate ?? "Unknown"
        let device = ingestionResult?.device ?? ""
        return device.isEmpty ? sample : "\(sample) \(device)"
    }

    /// Re-renders both tabs after loadPack.
    private func _rerenderAllTabs() {
        guard let ingestion = ingestionResult else { return }
        let device = ingestion.device

        _renderRevision &+= 1
        let revision = _renderRevision

        for tab in XYRotationWorkbenchTab.allCases {
            let renderer = _snapshotRenderer(forTab: tab)
            let tabState = tabs.displayStateSnapshot(for: tab)
            let manifestPayload: WorkbenchPlotPayload?
            switch tab {
            case .rxxVsPhi:
                manifestPayload = renderer.makeRxxVsPhiPayload(
                    sweeps: ingestion.sweeps,
                    device: device,
                    seriesOrder: tabState.seriesOrder
                )
            case .rxyVsPhi:
                manifestPayload = renderer.makeRxyVsPhiPayload(
                    sweeps: ingestion.sweeps,
                    device: device,
                    seriesOrder: tabState.seriesOrder
                )
            }
            guard let manifestPayload else { continue }
            Task.detached(priority: .userInitiated) { [weak self] in
                var r = renderer
                let result: (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String])
                switch tab {
                case .rxxVsPhi:
                    result = r.renderRxxVsPhi(
                        sweeps: ingestion.sweeps,
                        device: device,
                        seriesOrder: tabState.seriesOrder,
                        hiddenSeriesKeys: tabState.hiddenSeriesKeys
                    )
                case .rxyVsPhi:
                    result = r.renderRxyVsPhi(
                        sweeps: ingestion.sweeps,
                        device: device,
                        seriesOrder: tabState.seriesOrder,
                        hiddenSeriesKeys: tabState.hiddenSeriesKeys
                    )
                }
                await MainActor.run { [weak self] in
                    guard let self, self._renderRevision == revision else { return }
                    self.tabs.setOutput(
                        TabRenderOutput(
                            imageData: result.0,
                            layout: result.1,
                            manifestPayload: manifestPayload,
                            displayPayload: result.2
                        ),
                        for: tab
                    )
                    for warning in result.3 {
                        self.appendWarning(source: "Render", message: warning)
                    }
                }
            }
        }
    }
}

// MARK: - WorkbenchCartesianXYPlottingStore

extension XYRotationWorkspaceStore: WorkbenchCartesianXYPlottingStore {
    var showPlotGrid: Bool {
        get { tabs.showPlotGrid }
        set { tabs.showPlotGrid = newValue }
    }
    var seriesRenderMode: SeriesRenderMode {
        get { tabs.seriesRenderMode }
        set { tabs.seriesRenderMode = newValue }
    }
    var chartStyleOverrides: [String: String] {
        get { tabs.chartStyleOverrides }
        set { tabs.chartStyleOverrides = newValue }
    }

    func updateLegendPoint(_ point: CGPoint) {
        tabs.updateLegendPoint(point)
        _rerenderActiveTab()
    }

    func updatePlotTitle(_ title: String) {
        tabs.updateTitleOverride(title)
        _rerenderActiveTab()
    }

    func updateXAxisLabel(_ label: String) {
        tabs.updateXLabelOverride(label)
        _rerenderActiveTab()
    }

    func updateYAxisLabel(_ label: String) {
        tabs.updateYLabelOverride(label)
        _rerenderActiveTab()
    }

    func updateSeriesLabel(identityKey: String, newLabel: String) {
        tabs.updateSeriesLabel(identityKey: identityKey, newLabel: newLabel)
        _rerenderActiveTab()
    }

    func updateSeriesVisibility(identityKey: String, isVisible: Bool) {
        tabs.updateSeriesVisibility(identityKey: identityKey, isVisible: isVisible)
        _rerenderActiveTab()
    }

    func renderPNGAtScale(_ scale: CGFloat) -> Data? {
        let snapshot = tabs.exportSnapshot(for: tabs.activeTab, globalPlotDefaults: globalPlotDefaults)
        return WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: scale)
    }
}

// MARK: - ActiveChartProviding conformance

extension XYRotationWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? { tabs.activeImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { tabs.activeManifestPayload }

    var activeChartSampleKeys: [String] { cachedSampleKeys }

    func buildActiveChartMetrics() -> [PendingMetricEntry] {
        // Deferred to 4.2.5 — Fourier fit will provide AMR/PHE metrics
        []
    }
}

// MARK: - AnalysisPackProviding conformance

extension XYRotationWorkspaceStore: AnalysisPackProviding {
    typealias PackConfig = XYRotationPackConfig
    typealias PackResult = XYRotationPackResult

    var packWorkflowID: String { workflowID }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var hasAnalysisResult: Bool { ingestionResult != nil }

    func buildPackConfig() -> XYRotationPackConfig { _buildPackConfig() }
    func buildPackResult() -> XYRotationPackResult { _buildPackResult() }
    func autoPackLabel() -> String { _autoPackLabel() }

    func cancelInflightWork() {
        analysisTask?.cancel(); analysisTask = nil
        isAnalyzing = false
    }

    func restoreFromPack(config: XYRotationPackConfig, result: XYRotationPackResult,
                         pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                         seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void) {
        // Restore analysis params
        phiOffsetOverrides = config.phiOffsetOverrides
        centerBaseline = config.centerBaseline
        linearDetrend = config.linearDetrend
        showAuxiliaryLine180 = config.showAuxiliaryLine180

        // Restore display settings
        if let tab = XYRotationWorkbenchTab(rawValue: config.activeTab) {
            tabs.activeTab = tab
        }
        titleTemplate = config.titleTemplate
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        tabs.showPlotGrid = config.showPlotGrid
        tabs.legendAnchor = config.legendAnchor
        tabs.seriesRenderMode = config.seriesRenderMode
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: config.chartStyleOverrides)
        if !splitOverrides.global.isEmpty { globalPlotDefaults = splitOverrides.global }
        tabs.chartStyleOverrides = splitOverrides.local

        // Restore per-tab states from pack
        tabs.restoreStates(config.tabStates) { XYRotationWorkbenchTab(rawValue: $0) }

        // Restore search selection state
        cachedSearchResults = config.cachedSearchResults
        seedSelection(Set(config.selectedSearchResultIDs), config.cachedSearchResults)

        // Restore results
        ingestionResult = result.ingestionResult

        // Build title tokens from restored search results
        if let hit = config.cachedSearchResults.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        } else {
            _titleTokens = [:]
        }

        // Restore cached persistence state from pack
        cachedInputFiles = pack.filePaths
        cachedSampleKeys = pack.sampleKeys

        // Restore library root from vault so persistToLibrary works without a prior search
        if lastLibraryRootPath.isEmpty, let root = vault?.libraryRootPath {
            lastLibraryRootPath = root
        }

        // Bridge: restore search results into WorkbenchFeatureStore
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        // Re-render all tabs
        _rerenderAllTabs()
        refreshRelatedCharts()
    }
}

// MARK: - WorkbenchWorkspaceProviding conformance

extension XYRotationWorkspaceStore: WorkbenchWorkspaceProviding {

    func runAnalysis(searchSnapshot: WorkbenchSearchSnapshot?) {
        let sourceHits = searchSnapshot?.results ?? cachedSearchResults
        let selectedHits: [WorkflowMeasurementSearchHit]
        if let reading = selectionReading {
            selectedHits = _selectedHits(from: sourceHits, selectedIDs: reading.selectedIDs(for: workflowID))
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
            let selectedHits = _selectedHits(from: cachedSearchResults, selectedIDs: ids)
            _runAnalysis(selectedHits: selectedHits)
        }
    }

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard !cachedInputFiles.isEmpty else { return nil }
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: workflowID,
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(xField: "φ (deg)", yField: "R (Ω)"),
            semanticParams: ["sweeps": "\(ingestionResult?.sweeps.count ?? 0)"],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }

    var activeImageData: Data? { tabs.activeImageData }
    var activeLayout: WorkbenchPlotLayout? { tabs.activeLayout }
    var seriesLabelOverrides: [String: String] { tabs.activeSeriesLabelOverrides }

    var relatedCharts: [WorkbenchResultReference]? {
        let charts = relatedCharts(for: tabs.activeTab)
        return charts.isEmpty ? nil : charts
    }

    var libraryRootURL: URL? {
        lastLibraryRootPath.isEmpty ? nil : URL(fileURLWithPath: lastLibraryRootPath)
    }

    var canReorderSeries: Bool { tabs.activeOutput.manifestPayload?.seriesReorderable ?? false }
    var activeSeriesOrder: [String]? { tabs.activeState.seriesOrder }

    func updateSeriesOrder(_ order: [String]) {
        tabs.updateSeriesOrder(order)
        _rerenderActiveTab()
    }

    func resetSeriesOrder() {
        tabs.resetSeriesOrder()
        _rerenderActiveTab()
    }

    private func _selectedHits(from sourceHits: [WorkflowMeasurementSearchHit], selectedIDs: Set<String>) -> [WorkflowMeasurementSearchHit] {
        _sortedSelectedHits(sourceHits.filter { selectedIDs.contains($0.id) })
    }

    private func _sortedSelectedHits(_ selectedHits: [WorkflowMeasurementSearchHit]) -> [WorkflowMeasurementSearchHit] {
        selectedHits.sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
    }

    private func _runAnalysis(selectedHits: [WorkflowMeasurementSearchHit]) {
        guard !selectedHits.isEmpty else {
            analysisMessage = "No files selected."
            return
        }

        // Build title tokens from representative hit
        if let hit = selectedHits.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        }

        // Snapshot renderers for both tabs (each gets its own legend position)
        let rxxRenderer = _snapshotRenderer(forTab: .rxxVsPhi)
        let rxyRenderer = _snapshotRenderer(forTab: .rxyVsPhi)
        let capturedOrderRxx = tabs.state(for: .rxxVsPhi).seriesOrder
        let capturedOrderRxy = tabs.state(for: .rxyVsPhi).seriesOrder
        let capturedHiddenRxx = tabs.state(for: .rxxVsPhi).hiddenSeriesKeys
        let capturedHiddenRxy = tabs.state(for: .rxyVsPhi).hiddenSeriesKeys

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        saveMessage = nil
        tabs.clearOutputs()
        _renderRevision &+= 1  // invalidate any in-flight rerenders

        let capturedNumericDisplay = cachedSampleNumericDisplay

        analysisTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                () -> (XYRotationIngestionResult, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) in
                let result = IngestXYRotationSelectionsUseCase().execute(hits: selectedHits, numericDisplayBySample: capturedNumericDisplay)

                var rxx = rxxRenderer
                let rxxOrder = AlignXYSeriesOrderUseCase.applySeriesOrder(capturedOrderRxx, to: result.sweeps)
                let rxxManifest = rxx.makeRxxVsPhiPayload(sweeps: rxxOrder, device: result.device)
                let (rxxData, rxxLayout, rxxDisplayPayload, rxxWarnings) = rxx.renderRxxVsPhi(
                    sweeps: AlignXYSeriesOrderUseCase.applySeriesOrder(capturedOrderRxx, to: result.sweeps),
                    device: result.device,
                    hiddenSeriesKeys: capturedHiddenRxx
                )
                var rxy = rxyRenderer
                let rxyManifest = rxy.makeRxyVsPhiPayload(
                    sweeps: result.sweeps,
                    device: result.device,
                    seriesOrder: capturedOrderRxy
                )
                let (rxyData, rxyLayout, rxyDisplayPayload, rxyWarnings) = rxy.renderRxyVsPhi(
                    sweeps: result.sweeps,
                    device: result.device,
                    seriesOrder: capturedOrderRxy,
                    hiddenSeriesKeys: capturedHiddenRxy
                )
                // Deduplicate pipeline warnings from both tabs
                let pipelineWarnings = Array(Set(rxxWarnings + rxyWarnings))
                return (result, rxxData, rxxLayout, rxxManifest ?? rxxDisplayPayload!, rxyData, rxyLayout, rxyManifest ?? rxyDisplayPayload!, pipelineWarnings)
            }.value

            let (result, rxxData, rxxLayout, rxxPayload, rxyData, rxyLayout, rxyPayload, pipelineWarnings) = rendered
            guard let self, !Task.isCancelled else { return }

            self.ingestionResult = result
            self.tabs.setOutput(TabRenderOutput(imageData: rxxData, layout: rxxLayout, manifestPayload: rxxPayload, displayPayload: rxxPayload), for: .rxxVsPhi, policy: .clearDisplayOverridesIfSourceChanged)
            self.tabs.setOutput(TabRenderOutput(imageData: rxyData, layout: rxyLayout, manifestPayload: rxyPayload, displayPayload: rxyPayload), for: .rxyVsPhi, policy: .clearDisplayOverridesIfSourceChanged)

            let sweepCount = result.sweeps.count
            self.analysisMessage = "Analyzed \(sweepCount) angle-sweep file(s)."

            for w in result.warnings {
                self.appendWarning(source: "Ingestion", message: w)
            }

            for w in pipelineWarnings {
                self.appendWarning(source: "Legend", message: w)
            }

            // Snapshot for persistence
            self.cachedInputFiles = selectedHits.map(\.measurementFilePath)
            self.cachedSampleKeys = Array(Set(selectedHits.map(\.sampleKey))).sorted()

            self.commitRunTrace()

            self.isAnalyzing = false
            self.refreshRelatedCharts()
        }
    }

    private func _orderedXYLabelSeries(
        from sweeps: [XYRotationAngleSweep],
        seriesOrder: [String]?
    ) -> [WorkbenchPlotSeries] {
        let rawSeries = sweeps.map { sweep in
            WorkbenchPlotSeries(
                label: "",
                x: [],
                y: [],
                sourceRef: sweep.measurementFilePath,
                sampleID: sweep.stem
            )
        }
        let orderedKeys = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(seriesOrder, series: rawSeries)
        let keyedSeries = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: rawSeries)
        let lookup = Dictionary(uniqueKeysWithValues: zip(keyedSeries, rawSeries).map { identity, series in
            (identity.identityKey, series)
        })
        return orderedKeys.compactMap { lookup[$0] }
    }
}
