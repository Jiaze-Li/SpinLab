import CryptoKit
import Foundation
import Observation

/// Isolated state and actions for the RT workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
@MainActor
@Observable
final class RTWorkspaceStore: WorkbenchSaveCoordinating {

    // MARK: - Search / Selection bridge

    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    /// Injected by WorkbenchFeatureStore; typed protocol reference to WorkbenchSelectionRuntime.
    @ObservationIgnored weak var selectionReading: (any SelectionReading)?

    // MARK: - Analysis output

    /// Parsed RT results from the last analysis run. One entry per selected hit.
    var rtResults: [RTAnalysisResult] = []
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    /// Save-to-library status message. Written only by `persistToLibrary()`.
    var saveMessage: String?

    // MARK: - Tab render state

    var tabs = TabRenderManager<RTWorkbenchTab>(defaultTab: .rtCurve)
    var globalPlotDefaults: [String: String] = [:]

    // MARK: - Plot controls

    var titleTemplate: String = "#tab #device #sample"
    var stackOffsetMultiplier: Double = 0.0
    var minGapFraction: Double = 0.15

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

    // MARK: - Cached data

    var cachedSampleNumericDisplay: [String: [String: String]] = [:]
    @ObservationIgnored private(set) var cachedInputFiles: [String] = []
    @ObservationIgnored private(set) var cachedSampleKeys: [String] = []
    @ObservationIgnored private var _titleTokens: [String: String] = [:]

    // MARK: - Context from WorkbenchFeatureStore

    var lastLibraryRootPath: String = ""

    // MARK: - Persistence

    private(set) var persistenceOutcome: PersistenceOutcome?
    var currentRunTrace: WorkbenchRunTraceProjection?

    // MARK: - Warning log

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()

    // MARK: - Related charts

    private(set) var relatedChartsGrouped: [String: [WorkbenchResultReference]] = [:]
    @ObservationIgnored private var relatedChartsTask: Task<Void, Never>?

    // MARK: - Analysis Pack

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
        guard env.fileManager.fileExists(atPath: rootPath) else {
            relatedChartsGrouped = [:]
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        relatedChartsTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                LoadRelatedChartsUseCase().execute(sampleKeys: keys, libraryRootURL: rootURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.relatedChartsGrouped = result
        }
    }

    // MARK: - Clear

    func clearPlot() {
        analysisTask?.cancel()
        analysisTask = nil
        rtResults = []
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

    // MARK: - Re-render (style-only)

    func rerenderForStyleChange() {
        _rerenderActiveTab()
    }

    // MARK: - Private render helpers

    private func _rendererSnapshot() -> RTPlotRenderer {
        var r = RTPlotRenderer()
        r.workflowID = workflowID
        r.titleTemplate = titleTemplate
        r.titleTokens = _titleTokens
        return r
    }

    private func _rerenderActiveTab() {
        PerfCounters.renderCalls += 1
        print("[PERF][count] render workspace=RT tab=\(tabs.activeTab) count=\(PerfCounters.renderCalls)")
        guard !rtResults.isEmpty else { return }
        let tab = tabs.activeTab
        let renderer = _rendererSnapshot()
        guard let payloads = renderer.makePayloads(results: rtResults) else { return }
        let input = tabs.buildPipelineInput(payload: payloads.displayPayload, globalPlotDefaults: globalPlotDefaults, for: tab)
        let displayPayload = payloads.displayPayload
        let manifestPayload = payloads.manifestPayload

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            let output = try? WorkbenchRenderPipeline.render(input)
            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                guard let output else { return }
                self.tabs.applyPipelineOutput(output, displayPayload: displayPayload, manifestPayload: manifestPayload, for: tab)
            }
        }
    }

    func _rerenderAllTabs(policy: DisplayOverridePolicy = .preserveDisplayOverrides) {
        guard !rtResults.isEmpty else { return }
        let renderer = _rendererSnapshot()

        _renderRevision &+= 1
        let revision = _renderRevision

        for tab in RTWorkbenchTab.allCases {
            guard let payloads = renderer.makePayloads(results: rtResults) else { continue }
            let input = tabs.buildPipelineInput(payload: payloads.displayPayload, globalPlotDefaults: globalPlotDefaults, policy: policy, for: tab)
            let displayPayload = payloads.displayPayload
            let manifestPayload = payloads.manifestPayload
            Task.detached(priority: .userInitiated) { [weak self] in
                let output = try? WorkbenchRenderPipeline.render(input)
                await MainActor.run { [weak self] in
                    guard let self, self._renderRevision == revision else { return }
                    guard let output else { return }
                    self.tabs.applyPipelineOutput(output, displayPayload: displayPayload, manifestPayload: manifestPayload, for: tab, policy: policy)
                }
            }
        }
    }

    // MARK: - Pack helpers (private)

    private func _buildPackConfig() -> RTPackConfig {
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: tabs.chartStyleOverrides)
        return RTPackConfig(
            titleTemplate: titleTemplate,
            showPlotGrid: tabs.showPlotGrid,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            legendAnchor: tabs.legendAnchor,
            seriesRenderMode: tabs.seriesRenderMode,
            chartStyleOverrides: splitOverrides.local,
            tabStates: tabs.snapshotStates(keyFor: { $0.stableKey }),
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectionReading?.selectedIDs(for: workflowID) ?? []),
            searchQueryText: ""   // filled by caller at WorkbenchFeatureStore level
        )
    }

    private func _buildPackResult() -> RTPackResult {
        RTPackResult(rtResults: rtResults)
    }

    private func _autoPackLabel() -> String {
        let sample = cachedSearchResults.first?.sampleBatchAndSubstrate ?? "Unknown"
        let device = rtResults.first?.device ?? ""
        return device.isEmpty ? sample : "\(sample) \(device)"
    }
}

// MARK: - WorkbenchCartesianXYPlottingStore

extension RTWorkspaceStore: WorkbenchCartesianXYPlottingStore {

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
    }

    func updateSeriesVisibility(identityKey: String, isVisible: Bool) {
        tabs.updateSeriesVisibility(identityKey: identityKey, isVisible: isVisible)
    }

    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {
        tabs.togglePointLabelVisibility(sampleID: sampleID, pointIndex: pointIndex)
        rerenderForStyleChange()
    }

    func updateSeriesOrder(_ order: [String]) {
        tabs.updateSeriesOrder(order.isEmpty ? nil : order)
    }

    func updateAxisBound(_ bound: AxisRangeBound, value: Double?) {
        guard tabs.updateAxisBound(bound, value: value) else { return }
        rerenderForStyleChange()
    }

    /// Atomically clears all four axis-range bounds for the active tab.
    func resetAxisRanges() {
        guard tabs.resetAxisRangeOverride() else { return }
        rerenderForStyleChange()
    }

    func updateTickCount(axis: PlotTickAxis, count: Int) {
        guard tabs.updateTickCount(axis: axis, count: count) else { return }
        rerenderForStyleChange()
    }
}

// MARK: - ActiveChartProviding

extension RTWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? { tabs.activeImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { tabs.activeManifestPayload }

    var activeChartSampleKeys: [String] { cachedSampleKeys }

    func buildActiveChartMetrics() -> [PendingMetricEntry] { [] }
}

// MARK: - AnalysisPackProviding

extension RTWorkspaceStore: AnalysisPackProviding {
    typealias PackConfig = RTPackConfig
    typealias PackResult = RTPackResult

    var packWorkflowID: String { workflowID }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var hasAnalysisResult: Bool { !rtResults.isEmpty }

    func buildPackConfig() -> RTPackConfig { _buildPackConfig() }
    func buildPackResult() -> RTPackResult { _buildPackResult() }
    func autoPackLabel() -> String { _autoPackLabel() }

    func cancelInflightWork() {
        analysisTask?.cancel(); analysisTask = nil
        isAnalyzing = false
    }

    func restoreFromPack(config: RTPackConfig, result: RTPackResult,
                         pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                         seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void) {
        // Restore display settings
        tabs.activeTab = .rtCurve
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

        tabs.restoreStates(config.tabStates) { key in RTWorkbenchTab.allCases.first { $0.stableKey == key } }

        // Restore search and selection state
        cachedSearchResults = config.cachedSearchResults
        seedSelection(Set(config.selectedSearchResultIDs), config.cachedSearchResults)

        // Restore results
        rtResults = result.rtResults

        // Build title tokens from restored search results
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

extension RTWorkspaceStore: WorkbenchWorkspaceProviding {

    func runAnalysis() {
        runAnalysis(searchSnapshot: nil)
    }

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
                xField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .temperature),
                yField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .rxx)
            ),
            semanticParams: ["curves": "\(rtResults.filter { !$0.temperatureK.isEmpty }.count)"],
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
        hits.sorted { $0.measurementFilePath < $1.measurementFilePath }
    }

    private func _runAnalysis(selectedHits: [WorkflowMeasurementSearchHit]) {
        guard !selectedHits.isEmpty else {
            analysisMessage = "Select at least one RT measurement file."
            return
        }

        if let hit = selectedHits.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        }

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        saveMessage = nil
        warningLog.clear()
        activePackID = nil

        let capturedTitleTokens = _titleTokens
        let capturedTemplate = titleTemplate
        let capturedGlobalDefaults = globalPlotDefaults
        let capturedNumericDisplay = cachedSampleNumericDisplay
        let capturedWorkflowID = workflowID

        analysisTask = Task { [weak self] in
            guard let self else { return }

            let results: [RTAnalysisResult] = await Task.detached(priority: .userInitiated) { [selectedHits, capturedNumericDisplay, capturedWorkflowID] in
                let useCase = AnalyzeRTWorkflowUseCase()
                return selectedHits.map { hit in
                    useCase.execute(
                        hit: hit,
                        workflowID: capturedWorkflowID,
                        numericDisplay: capturedNumericDisplay[hit.sampleKey] ?? [:]
                    )
                }
            }.value

            guard !Task.isCancelled else { return }

            // Surface per-result warnings
            for result in results where !result.warnings.isEmpty {
                for w in result.warnings {
                    self.appendWarning(source: "RT", message: w)
                }
            }

            let nonEmpty = results.filter { !$0.temperatureK.isEmpty && !$0.rxx.isEmpty }
            let emptyCount = results.count - nonEmpty.count

            self.rtResults = results
            self.cachedInputFiles = selectedHits.map { $0.measurementFilePath }
            var seen = Set<String>()
            self.cachedSampleKeys = selectedHits.compactMap { seen.insert($0.sampleKey).inserted ? $0.sampleKey : nil }

            if nonEmpty.isEmpty {
                self.analysisMessage = "No data found in selected RT files."
                self.isAnalyzing = false
                return
            }

            let succeeded = nonEmpty.count
            let summary: String
            if emptyCount == 0 {
                summary = "Analyzed \(succeeded) RT file(s)."
            } else {
                summary = "Analyzed \(succeeded) RT file(s); \(emptyCount) empty/failed."
            }
            self.analysisMessage = summary

            // Build and render
            var renderer = RTPlotRenderer()
            renderer.workflowID = capturedWorkflowID
            renderer.titleTemplate = capturedTemplate
            renderer.titleTokens = capturedTitleTokens

            guard let payloads = renderer.makePayloads(results: results) else {
                self.isAnalyzing = false
                return
            }

            let tab = RTWorkbenchTab.rtCurve
            let input = self.tabs.buildPipelineInput(
                payload: payloads.displayPayload,
                globalPlotDefaults: capturedGlobalDefaults,
                policy: .clearDisplayOverridesIfSourceChanged,
                for: tab
            )
            let displayPayload = payloads.displayPayload
            let manifestPayload = payloads.manifestPayload

            self._renderRevision &+= 1
            let revision = self._renderRevision

            let pipelineOutput = await Task.detached(priority: .userInitiated) {
                try? WorkbenchRenderPipeline.render(input)
            }.value

            guard !Task.isCancelled, self._renderRevision == revision else { return }
            if let output = pipelineOutput {
                self.tabs.applyPipelineOutput(output, displayPayload: displayPayload, manifestPayload: manifestPayload, for: tab,
                                              policy: .clearDisplayOverridesIfSourceChanged)
            }

            self.commitRunTrace()
            self.isAnalyzing = false
            self.refreshRelatedCharts()
        }
    }
}
