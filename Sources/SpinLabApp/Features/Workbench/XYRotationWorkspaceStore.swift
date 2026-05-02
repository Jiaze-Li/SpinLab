import CryptoKit
import Foundation
import Observation

/// Isolated state and actions for the XY Rotation workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
@MainActor
@Observable
final class XYRotationWorkspaceStore {

    // MARK: - Search / Selection

    var selectedSearchResultIDs: Set<String> = []
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []

    // MARK: - Analysis output

    private(set) var ingestionResult: XYRotationIngestionResult?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Multi-tab render state (shell capability)

    var tabs = TabRenderManager<XYRotationWorkbenchTab>(defaultTab: .rxxVsPhi)

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
        r.showGrid = tabs.showPlotGrid
        r.legendPoint = tabState.legendPoint?.cgPoint
        r.stackOffsetMultiplier = stackOffsetMultiplier
        r.minGapFraction = minGapFraction
        r.centerBaseline = centerBaseline
        r.linearDetrend = linearDetrend
        r.showAuxiliaryLine180 = showAuxiliaryLine180
        r.seriesRenderMode = tabs.seriesRenderMode
        r.chartStyleOverrides = tabs.chartStyleOverrides
        r.titleTemplate = titleTemplate
        r.titleTokens = _titleTokens
        r.titleOverride = tabState.titleOverride
        r.xLabelOverride = tabState.xLabelOverride
        r.yLabelOverride = tabState.yLabelOverride
        // Both XY Rotation tabs use reverseSeriesForLegend: true, so label indices must be mapped
        // against the post-reversal sweep order (matching what the pipeline sees at step 9).
        let labelMapSeries: [WorkbenchPlotSeries]
        if let ingestion = ingestionResult {
            let baseForTab: [XYRotationAngleSweep]
            switch tab {
            case .rxxVsPhi: baseForTab = ingestion.sweeps
            case .rxyVsPhi: baseForTab = ingestion.sweeps.filter { $0.resistanceXY != nil }
            }
            let ordered = AlignXYSeriesOrderUseCase.applySeriesOrder(tabState.seriesOrder, to: baseForTab)
            labelMapSeries = Array(ordered.reversed()).map { WorkbenchPlotSeries(label: "", x: [], y: [], sampleID: $0.id) }
        } else {
            labelMapSeries = []
        }
        r.seriesLabelOverrides = toIndexedOverrides(tabState.seriesLabelOverrides, series: labelMapSeries)
        r.phiOffsetOverrides = phiOffsetOverrides
        return r
    }

    // MARK: - Analysis

    func runAnalysis() {
        let selectedHits = cachedSearchResults
            .filter { selectedSearchResultIDs.contains($0.id) }
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
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

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        tabs.clearOutputs()
        tabs.clearStates()
        _renderRevision &+= 1  // invalidate any in-flight rerenders

        let capturedNumericDisplay = cachedSampleNumericDisplay

        analysisTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                () -> (XYRotationIngestionResult, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) in
                let result = IngestXYRotationSelectionsUseCase().execute(hits: selectedHits, numericDisplayBySample: capturedNumericDisplay)

                var rxx = rxxRenderer
                let (rxxData, rxxLayout, rxxPayload) = rxx.renderRxxVsPhi(
                    sweeps: AlignXYSeriesOrderUseCase.applySeriesOrder(capturedOrderRxx, to: result.sweeps),
                    device: result.device
                )
                var rxy = rxyRenderer
                let (rxyData, rxyLayout, rxyPayload) = rxy.renderRxyVsPhi(
                    sweeps: AlignXYSeriesOrderUseCase.applySeriesOrder(capturedOrderRxy, to: result.sweeps),
                    device: result.device
                )
                // Deduplicate pipeline warnings from both tabs
                let pipelineWarnings = Array(Set(rxx.collectedWarnings + rxy.collectedWarnings))
                return (result, rxxData, rxxLayout, rxxPayload, rxyData, rxyLayout, rxyPayload, pipelineWarnings)
            }.value

            let (result, rxxData, rxxLayout, rxxPayload, rxyData, rxyLayout, rxyPayload, pipelineWarnings) = rendered
            guard let self, !Task.isCancelled else { return }

            self.ingestionResult = result
            self.tabs.setOutput(TabRenderOutput(imageData: rxxData, layout: rxxLayout, manifestPayload: rxxPayload), for: .rxxVsPhi)
            self.tabs.setOutput(TabRenderOutput(imageData: rxyData, layout: rxyLayout, manifestPayload: rxyPayload), for: .rxyVsPhi)

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
        let capturedOrder = tabs.state(for: tab).seriesOrder
        let orderedSweeps = AlignXYSeriesOrderUseCase.applySeriesOrder(capturedOrder, to: ingestion.sweeps)
        let device = ingestion.device

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            var r = renderer
            let (data, layout, payload): (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?)
            switch tab {
            case .rxxVsPhi:
                (data, layout, payload) = r.renderRxxVsPhi(sweeps: orderedSweeps, device: device)
            case .rxyVsPhi:
                (data, layout, payload) = r.renderRxyVsPhi(sweeps: orderedSweeps, device: device)
            }

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                self.tabs.setOutput(TabRenderOutput(imageData: data, layout: layout, manifestPayload: payload), for: tab)
            }
        }
    }

    // MARK: - Selection helpers

    func toggleSearchHitSelection(_ hitID: String) {
        if selectedSearchResultIDs.contains(hitID) {
            selectedSearchResultIDs.remove(hitID)
        } else {
            selectedSearchResultIDs.insert(hitID)
        }
    }

    var isAllSelected: Bool {
        !cachedSearchResults.isEmpty && selectedSearchResultIDs.count == cachedSearchResults.count
    }

    func selectAll() {
        selectedSearchResultIDs = Set(cachedSearchResults.map(\.id))
    }

    func deselectAll() {
        selectedSearchResultIDs = []
    }

    func clearPlot() {
        analysisTask?.cancel()
        analysisTask = nil
        ingestionResult = nil
        currentRunTrace = nil
        isAnalyzing = false
        analysisMessage = nil
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
        selectedSearchResultIDs = []
        cachedSearchResults = []
        cachedSampleNumericDisplay = [:]
    }

    // MARK: - Related charts

    func refreshRelatedCharts() {
        relatedChartsTask?.cancel()
        relatedChartsTask = nil

        let keys = cachedSampleKeys
        let rootPath = lastLibraryRootPath
        guard !keys.isEmpty, !rootPath.isEmpty else {
            relatedChartsGrouped = [:]
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        guard FileManager.default.fileExists(atPath: rootPath) else {
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

    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = activeChartPNG else {
            analysisMessage = "No chart to save. Run analysis first."
            return
        }
        guard let payload = activeChartManifestPayload else {
            analysisMessage = "No manifest payload available for the active tab."
            return
        }
        let libraryRootPath = lastLibraryRootPath
        let sampleKeys = activeChartSampleKeys
        let metrics = buildActiveChartMetrics()

        let input = SaveActiveChartInput(
            png: png,
            payload: payload,
            sampleKeys: sampleKeys,
            libraryRootPath: libraryRootPath,
            metrics: metrics
        )

        Task { [weak self] in
            guard let self else { return }
            let outcome = await Task.detached(priority: .userInitiated) {
                SaveActiveChartToLibraryUseCase().execute(input: input)
            }.value
            self.persistenceOutcome = outcome
            self.currentRunTrace = outcome.trace
            switch outcome {
            case .success:
                self.analysisMessage = "Saved to Library."
                self.refreshRelatedCharts()
            case .partial(_, let err):
                self.analysisMessage = "Chart saved; metric error: \(err)"
                self.refreshRelatedCharts()
            case .failure(let err):
                self.analysisMessage = "Save failed: \(err)"
            }
            onComplete?()
        }
    }

    // MARK: - Pack helpers (private)

    private func _buildPackConfig() -> XYRotationPackConfig {
        return XYRotationPackConfig(
            phiOffsetOverrides: phiOffsetOverrides,
            centerBaseline: centerBaseline,
            linearDetrend: linearDetrend,
            activeTab: tabs.activeTab.rawValue,
            titleTemplate: titleTemplate,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: tabs.showPlotGrid,
            tabStates: tabs.snapshotStates(keyFor: { $0.rawValue }),
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectedSearchResultIDs),
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
            let orderedSweeps = AlignXYSeriesOrderUseCase.applySeriesOrder(
                tabs.state(for: tab).seriesOrder,
                to: ingestion.sweeps
            )
            Task.detached(priority: .userInitiated) { [weak self] in
                var r = renderer
                let (data, layout, payload): (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?)
                switch tab {
                case .rxxVsPhi:
                    (data, layout, payload) = r.renderRxxVsPhi(sweeps: orderedSweeps, device: device)
                case .rxyVsPhi:
                    (data, layout, payload) = r.renderRxyVsPhi(sweeps: orderedSweeps, device: device)
                }

                await MainActor.run { [weak self] in
                    guard let self, self._renderRevision == revision else { return }
                    self.tabs.setOutput(TabRenderOutput(imageData: data, layout: layout, manifestPayload: payload), for: tab)
                }
            }
        }
    }
}

// MARK: - WorkbenchPlottingStore

extension XYRotationWorkspaceStore: WorkbenchPlottingStore {
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

    func updateSeriesLabel(sampleID: String, newLabel: String) {
        tabs.updateSeriesLabel(sampleID: sampleID, newLabel: newLabel)
        _rerenderActiveTab()
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

    var packWorkflowID: String { "xy" }
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
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void) {
        // Restore analysis params
        phiOffsetOverrides = config.phiOffsetOverrides
        centerBaseline = config.centerBaseline
        linearDetrend = config.linearDetrend

        // Restore display settings
        if let tab = XYRotationWorkbenchTab(rawValue: config.activeTab) {
            tabs.activeTab = tab
        }
        titleTemplate = config.titleTemplate
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        tabs.showPlotGrid = config.showPlotGrid

        // Restore per-tab states from pack
        tabs.restoreStates(config.tabStates) { XYRotationWorkbenchTab(rawValue: $0) }

        // Restore search selection state
        cachedSearchResults = config.cachedSearchResults
        selectedSearchResultIDs = Set(config.selectedSearchResultIDs)

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

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard !cachedInputFiles.isEmpty else { return nil }
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: "xy",
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
}
