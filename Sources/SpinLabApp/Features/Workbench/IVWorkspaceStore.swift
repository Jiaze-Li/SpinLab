import CryptoKit
import Foundation
import Observation

/// Isolated state and actions for the IV workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
@MainActor
@Observable
final class IVWorkspaceStore: WorkbenchSaveCoordinating {

    // MARK: - Search / Selection bridge

    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    /// Injected by WorkbenchFeatureStore; typed protocol reference to WorkbenchSelectionRuntime.
    @ObservationIgnored weak var selectionReading: (any SelectionReading)?

    // MARK: - Analysis output

    var ingestionResult: IVIngestionResult?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    /// Save-to-library status message. Written only by `persistToLibrary()`.
    var saveMessage: String?

    // MARK: - Tab render state

    var tabs = TabRenderManager<IVWorkbenchTab>(defaultTab: .voltage)
    var globalPlotDefaults: [String: String] = [:]

    // MARK: - Channel mapping (user-overridable; auto-filled after analysis)

    var ch1Component: IVSignalComponent = .x
    var ch2Component: IVSignalComponent = .x
    var xCurrentBasis: IVCurrentBasis = .peak
    /// Display-only confidence ratios, set from ingestion auto-detection.
    private(set) var ch1Confidence: Double = 1.0
    private(set) var ch2Confidence: Double = 1.0

    // MARK: - Power-law fit module state (IV-owned; see IVPowerLawFitAdapter)

    var fitMode: PowerLawFitMode = .none
    var zeroAtCurrentOrigin: Bool = false

    // MARK: - Rendered plot (non-tab state)

    var currentRunTrace: WorkbenchRunTraceProjection?

    // MARK: - Warning log

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()

    // MARK: - Plot controls (workflow-specific)

    var stackOffsetMultiplier: Double = 0.0
    var minGapFraction: Double = 0.15
    var titleTemplate: String = "#tab #device #sample"

    // MARK: - Cached data for title template + persistence prep

    var cachedSampleNumericDisplay: [String: [String: String]] = [:]
    @ObservationIgnored private(set) var cachedInputFiles: [String] = []
    @ObservationIgnored private(set) var cachedSampleKeys: [String] = []
    @ObservationIgnored private var _titleTokens: [String: String] = [:]

    // MARK: - Context from WorkbenchFeatureStore

    var lastLibraryRootPath: String = ""

    // MARK: - Persistence (Save to Library)

    private(set) var persistenceOutcome: PersistenceOutcome?

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

    // MARK: - Analysis

    func runAnalysis() {
        runAnalysis(searchSnapshot: nil)
    }

    // MARK: - Re-render (style-only, no re-parse)

    func rerenderForStyleChange() {
        _rerenderActiveTab()
    }

    func updateXCurrentBasis(_ basis: IVCurrentBasis, previousBasis: IVCurrentBasis? = nil) {
        guard xCurrentBasis != basis else { return }
        let sourceBasis = previousBasis ?? xCurrentBasis
        xCurrentBasis = basis
        _migrateXAxisLabelOverrides(from: sourceBasis, to: basis)
    }

    /// Setting Fit back to None also clears "Zero at I=0" — that toggle has no meaning
    /// without an active fit, so its state must not survive a switch back to None.
    func updateFitMode(_ mode: PowerLawFitMode) {
        guard fitMode != mode else { return }
        fitMode = mode
        if mode == .none {
            zeroAtCurrentOrigin = false
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
            saveMessage = "No manifest payload available."
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

    // MARK: - Renderer snapshot

    private func _snapshotRenderer(forTab tab: IVWorkbenchTab) -> IVPlotRenderer {
        var r = IVPlotRenderer()
        r.workflowID = workflowID
        r.titleTemplate = titleTemplate
        r.seriesOrder = tabs.state(for: tab).seriesOrder
        r.ch1Component = ch1Component
        r.ch2Component = ch2Component
        r.xCurrentBasis = xCurrentBasis
        r.fitMode = fitMode
        r.zeroAtCurrentOrigin = zeroAtCurrentOrigin
        r.titleTokens = _titleTokens
        r.stackOffsetMultiplier = stackOffsetMultiplier
        r.minGapFraction = minGapFraction
        return r
    }

    // MARK: - Private render

    private func _rerenderActiveTab() {
        PerfCounters.renderCalls += 1
        print("[PERF][count] render workspace=IV tab=\(tabs.activeTab) count=\(PerfCounters.renderCalls)")
        guard let ingestion = ingestionResult else { return }
        let tab = tabs.activeTab
        var renderer = _snapshotRenderer(forTab: tab)
        let sweeps = ingestion.sweeps
        let device = ingestion.device
        let tabState = tabs.displayStateSnapshot(for: tab)
        let payloads: IVPlotRenderer.StackedIVPayloads?
        switch tab {
        case .voltage:
            payloads = renderer.makeFirstHarmonicPayloads(
                sweeps: sweeps,
                device: device,
                hiddenSeriesKeys: tabState.hiddenSeriesKeys
            )
        case .resistance:
            payloads = renderer.makeSecondHarmonicPayloads(
                sweeps: sweeps,
                device: device,
                hiddenSeriesKeys: tabState.hiddenSeriesKeys
            )
        }
        guard let payloads else { return }
        let displayPayload = payloads.displayPayload
        let manifestPayload = payloads.manifestPayload
        let input = tabs.buildPipelineInput(
            payload: displayPayload,
            globalPlotDefaults: globalPlotDefaults,
            tabState: tabState,
            showPlotGrid: tabs.showPlotGrid,
            seriesRenderMode: tabs.seriesRenderMode,
            chartStyleOverrides: tabs.chartStyleOverrides,
            legendAnchor: tabs.legendAnchor,
            for: tab
        )

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            let renderResult: (Data?, Data?, WorkbenchPlotLayout?, [String]) = {
                do {
                    let output = try WorkbenchRenderPipeline.render(input)
                    return (output.imageData, output.pdfData, output.layout, output.warnings)
                } catch {
                    return (nil, nil, nil, ["pipeline failure: \(error)"])
                }
            }()
            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                let warnings = payloads.warnings + renderResult.3
                self.tabs.setOutput(
                    TabRenderOutput(
                        imageData: renderResult.0,
                        pdfData: renderResult.1,
                        layout: renderResult.2,
                        manifestPayload: manifestPayload,
                        displayPayload: displayPayload
                    ),
                    for: tab
                )
                for warning in warnings {
                    self.appendWarning(source: "Render", message: warning)
                }
            }
        }
    }

    private func _rerenderAllTabs(policy: DisplayOverridePolicy = .preserveDisplayOverrides) {
        guard let ingestion = ingestionResult else { return }
        let sweeps = ingestion.sweeps
        let device = ingestion.device

        _renderRevision &+= 1
        let revision = _renderRevision

        for tab in IVWorkbenchTab.allCases {
            var renderer = _snapshotRenderer(forTab: tab)
            let tabState = tabs.displayStateSnapshot(for: tab)
            let payloads: IVPlotRenderer.StackedIVPayloads?
            switch tab {
            case .voltage:
                payloads = renderer.makeFirstHarmonicPayloads(
                    sweeps: sweeps,
                    device: device,
                    hiddenSeriesKeys: tabState.hiddenSeriesKeys
                )
            case .resistance:
                payloads = renderer.makeSecondHarmonicPayloads(
                    sweeps: sweeps,
                    device: device,
                    hiddenSeriesKeys: tabState.hiddenSeriesKeys
                )
            }
            guard let payloads else { continue }
            let displayPayload = payloads.displayPayload
            let manifestPayload = payloads.manifestPayload
            // Centralized, policy-aware path (same as AHE/RT full-analysis): preparedState
            // applies `policy` — .clearDisplayOverridesIfSourceChanged from full-analysis,
            // .preserveDisplayOverrides from pack restore — before this Input (and therefore
            // axisRangeOverride) exists, so a stale override can't be baked into the render.
            let input = tabs.buildPipelineInput(
                payload: displayPayload,
                globalPlotDefaults: globalPlotDefaults,
                policy: policy,
                for: tab
            )
            Task.detached(priority: .userInitiated) { [weak self] in
                let renderResult: (Data?, Data?, WorkbenchPlotLayout?, [String]) = {
                    do {
                        let output = try WorkbenchRenderPipeline.render(input)
                        return (output.imageData, output.pdfData, output.layout, output.warnings)
                    } catch {
                        return (nil, nil, nil, ["pipeline failure: \(error)"])
                    }
                }()
                await MainActor.run { [weak self] in
                    guard let self, self._renderRevision == revision else { return }
                    let warnings = payloads.warnings + renderResult.3
                    self.tabs.setOutput(
                        TabRenderOutput(
                            imageData: renderResult.0,
                            pdfData: renderResult.1,
                            layout: renderResult.2,
                            manifestPayload: manifestPayload,
                            displayPayload: displayPayload
                        ),
                        for: tab,
                        policy: policy
                    )
                    for warning in warnings {
                        self.appendWarning(source: "Render", message: warning)
                    }
                }
            }
        }
    }

    // MARK: - Pack helpers (private)

    private func _buildPackConfig() -> IVPackConfig {
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: tabs.chartStyleOverrides)
        return IVPackConfig(
            titleTemplate: titleTemplate,
            activeTab: tabs.activeTab.rawValue,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: tabs.showPlotGrid,
            legendAnchor: tabs.legendAnchor,
            seriesRenderMode: tabs.seriesRenderMode,
            chartStyleOverrides: splitOverrides.local,
            ch1Component: ch1Component.rawValue,
            ch2Component: ch2Component.rawValue,
            xCurrentBasis: xCurrentBasis,
            fitMode: fitMode,
            zeroAtCurrentOrigin: zeroAtCurrentOrigin,
            tabStates: tabs.snapshotStates(keyFor: { $0.rawValue }),
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectionReading?.selectedIDs(for: workflowID) ?? []),
            searchQueryText: ""   // filled by caller at WorkbenchFeatureStore level
        )
    }

    private func _buildPackResult() -> IVPackResult {
        IVPackResult(ingestionResult: ingestionResult!)
    }

    private func _autoPackLabel() -> String {
        let sample = cachedSearchResults.first?.sampleBatchAndSubstrate ?? "Unknown"
        let device = ingestionResult?.device ?? ""
        return device.isEmpty ? sample : "\(sample) \(device)"
    }

    private func _migrateXAxisLabelOverrides(from sourceBasis: IVCurrentBasis, to targetBasis: IVCurrentBasis) {
        let sourceLabels = sourceBasis.autoAxisLabels
        let targetLabel = targetBasis.axisLabel
        let tabsToUpdate = Array(tabs.tabStates.keys)
        for tab in tabsToUpdate {
            guard var state = tabs.tabStates[tab], sourceLabels.contains(state.xLabelOverride) else { continue }
            state.xLabelOverride = targetLabel
            tabs.tabStates[tab] = state
        }
    }

    private func _normalizeXAxisLabelOverridesForCurrentBasis() {
        _migrateXAxisLabelOverrides(from: xCurrentBasis, to: xCurrentBasis)
    }
}

// MARK: - WorkbenchCartesianXYPlottingStore

extension IVWorkspaceStore: WorkbenchCartesianXYPlottingStore {
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
        rerenderForStyleChange()
    }

    func updatePlotTitle(_ title: String) {
        tabs.updateTitleOverride(title)
        rerenderForStyleChange()
    }

    func updateXAxisLabel(_ label: String) {
        tabs.updateXLabelOverride(label)
        rerenderForStyleChange()
    }

    func updateYAxisLabel(_ label: String) {
        tabs.updateYLabelOverride(label)
        rerenderForStyleChange()
    }

    func updateSeriesLabel(identityKey: String, newLabel: String) {
        tabs.updateSeriesLabel(identityKey: identityKey, newLabel: newLabel)
        rerenderForStyleChange()
    }

    func updateSeriesVisibility(identityKey: String, isVisible: Bool) {
        tabs.updateSeriesVisibility(identityKey: identityKey, isVisible: isVisible)
        rerenderForStyleChange()
    }

    func updateSeriesOrder(_ order: [String]) {
        tabs.updateSeriesOrder(order.isEmpty ? nil : order)
        rerenderForStyleChange()
    }

    func updateAxisBound(_ bound: AxisRangeBound, value: Double?) {
        guard tabs.updateAxisBound(bound, value: value) else { return }
        rerenderForStyleChange()
    }

    func updateTickCount(axis: PlotTickAxis, count: Int) {
        guard tabs.updateTickCount(axis: axis, count: count) else { return }
        rerenderForStyleChange()
    }
}

// MARK: - ActiveChartProviding

extension IVWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? { tabs.activeImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { tabs.activeManifestPayload }

    var activeChartSampleKeys: [String] { cachedSampleKeys }

    func buildActiveChartMetrics() -> [PendingMetricEntry] { [] }
}

// MARK: - AnalysisPackProviding

extension IVWorkspaceStore: AnalysisPackProviding {
    typealias PackConfig = IVPackConfig
    typealias PackResult = IVPackResult

    var packWorkflowID: String { workflowID }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var hasAnalysisResult: Bool { ingestionResult != nil }

    func buildPackConfig() -> IVPackConfig { _buildPackConfig() }
    func buildPackResult() -> IVPackResult { _buildPackResult() }
    func autoPackLabel() -> String { _autoPackLabel() }

    func cancelInflightWork() {
        analysisTask?.cancel(); analysisTask = nil
        isAnalyzing = false
    }

    func restoreFromPack(config: IVPackConfig, result: IVPackResult,
                         pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                         seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void) {
        if let tab = IVWorkbenchTab(rawValue: config.activeTab) {
            tabs.activeTab = tab
        }
        titleTemplate = config.titleTemplate
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        tabs.showPlotGrid = config.showPlotGrid
        tabs.legendAnchor = config.legendAnchor
        tabs.seriesRenderMode = config.seriesRenderMode
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: config.chartStyleOverrides)
        if !splitOverrides.global.isEmpty {
            globalPlotDefaults = splitOverrides.global
        }
        tabs.chartStyleOverrides = splitOverrides.local
        ch1Component = IVSignalComponent(rawValue: config.ch1Component) ?? .x
        ch2Component = IVSignalComponent(rawValue: config.ch2Component) ?? .x
        xCurrentBasis = config.xCurrentBasis
        fitMode = config.fitMode
        zeroAtCurrentOrigin = config.fitMode == .none ? false : config.zeroAtCurrentOrigin

        tabs.restoreStates(config.tabStates) { IVWorkbenchTab(rawValue: $0) }
        _normalizeXAxisLabelOverridesForCurrentBasis()

        cachedSearchResults = config.cachedSearchResults
        seedSelection(Set(config.selectedSearchResultIDs), config.cachedSearchResults)

        ingestionResult = result.ingestionResult

        if let hit = config.cachedSearchResults.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        } else {
            _titleTokens = [:]
        }

        cachedInputFiles = pack.filePaths
        cachedSampleKeys = pack.sampleKeys

        if lastLibraryRootPath.isEmpty, let root = vault?.libraryRootPath {
            lastLibraryRootPath = root
        }

        restoreSearchState(config.cachedSearchResults, config.searchQueryText)
        _rerenderAllTabs()
    }
}

// MARK: - WorkbenchWorkspaceProviding

extension IVWorkspaceStore: WorkbenchWorkspaceProviding {

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
        if let snapshot = selectedHitsSnapshot {
            _runAnalysis(selectedHits: _sortedSelectedHits(snapshot.selectedHits))
        } else {
            let ids = selectionReading?.selectedIDs(for: workflowID) ?? []
            let selectedHits = _sortedSelectedHits(cachedSearchResults.filter { ids.contains($0.id) })
            _runAnalysis(selectedHits: selectedHits)
        }
    }

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard !cachedInputFiles.isEmpty else { return nil }
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: workflowID,
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.plainTextLabel(
                    for: .current,
                    currentBasis: xCurrentBasis.workbenchCurrentBasis
                ),
                yField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .voltage)
            ),
            semanticParams: ["sweeps": "\(ingestionResult?.sweeps.count ?? 0)"],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }

    var activeImageData: Data? { tabs.activeImageData }
    var activePdfData: Data? { tabs.activePdfData }
    var activeLayout: WorkbenchPlotLayout? { tabs.activeLayout }
    var activeSeriesOrder: [String]? { tabs.activeState.seriesOrder }
    var seriesLabelOverrides: [String: String] { tabs.activeSeriesLabelOverrides }
    var canReorderSeries: Bool { tabs.activeOutput.manifestPayload?.seriesReorderable ?? false }

    var relatedCharts: [WorkbenchResultReference]? {
        guard let payload = tabs.activeOutput.manifestPayload else { return nil }
        let inputFiles = payload.series.compactMap(\.sourceRef)
        guard !inputFiles.isEmpty else { return nil }
        let key = InputFilesCanonicalKey.make(from: inputFiles)
        let charts = relatedChartsGrouped[key] ?? []
        return charts.isEmpty ? nil : charts
    }

    var libraryRootURL: URL? {
        lastLibraryRootPath.isEmpty ? nil : URL(fileURLWithPath: lastLibraryRootPath)
    }

    // MARK: - Private helpers

    private func _sortedSelectedHits(_ hits: [WorkflowMeasurementSearchHit]) -> [WorkflowMeasurementSearchHit] {
        hits.sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
    }

    private func _runAnalysis(selectedHits: [WorkflowMeasurementSearchHit]) {
        guard !selectedHits.isEmpty else {
            analysisMessage = "No files selected."
            return
        }

        if let hit = selectedHits.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        }

        isAnalyzing = true
        analysisMessage = nil
        saveMessage = nil
        warningLog.clear()
        activePackID = nil

        let snapshot = cachedSampleNumericDisplay
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }

            let result = await Task.detached(priority: .userInitiated) {
                IngestIVSelectionsUseCase().execute(
                    hits: selectedHits,
                    numericDisplayBySample: snapshot
                )
            }.value

            guard !Task.isCancelled else { return }

            self.ingestionResult = result
            self.cachedInputFiles = result.sweeps.compactMap { $0.measurementFilePath }
            self.cachedSampleKeys = selectedHits.map { $0.sampleKey }

            // Auto-fill channel mapping from ingestion result.
            self.ch1Component = result.ch1State.autoComponent
            self.ch1Confidence = result.ch1State.confidence
            self.ch2Component = result.ch2State.autoComponent
            self.ch2Confidence = result.ch2State.confidence
            self._normalizeXAxisLabelOverridesForCurrentBasis()

            for warning in result.warnings {
                self.appendWarning(source: "ingestion", message: warning)
            }

            self.isAnalyzing = false
            self.analysisMessage = result.sweeps.isEmpty
                ? "No data found in selected files."
                : "Analysis complete. \(result.sweeps.count) sweep(s) loaded."

            self.commitRunTrace()
            self._rerenderAllTabs(policy: .clearDisplayOverridesIfSourceChanged)
            self.refreshRelatedCharts()
        }
    }
}
