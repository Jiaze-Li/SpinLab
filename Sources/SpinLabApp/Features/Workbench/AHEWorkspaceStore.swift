import CoreGraphics
import Foundation
import Observation

/// Isolated state and actions for the AHE workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. AHE views bind directly to this store
/// for all selection, plot, and artifact state. No AHE-specific state
/// remains in `WorkbenchFeatureStore` after V3.3.3.
@MainActor
@Observable
final class AHEWorkspaceStore: WorkbenchSaveCoordinating {

    // MARK: - Selection bridge (pack serialization only)

    /// Injected by WorkbenchFeatureStore; typed protocol reference to WorkbenchSelectionRuntime.
    @ObservationIgnored weak var selectionReading: (any SelectionReading)?

    // MARK: - Plot output

    private(set) var isPlotRendering: Bool = false
    var plotMessage: String?
    var currentRunTrace: WorkbenchRunTraceProjection?

    // MARK: - Persistence outcome

    /// Set after each `persistToLibrary()` call.
    /// Nil when no persist has occurred or after `clearPlot()`.
    private(set) var persistenceOutcome: PersistenceOutcome? = nil

    /// Incremented every time a persist completes (success or partial).
    /// Use this for `onChange` observation — avoids requiring `PersistenceOutcome: Equatable`.
    private(set) var persistCount: Int = 0

    /// Save-to-library status message. Written only by `persistToLibrary()`.
    /// Cleared on `clearPlot()` and at analysis start.
    /// Preferred over `plotMessage` (analysis status) for save status display.
    var saveMessage: String?

    // MARK: - Pre-persist metric override (V3.4.1)

    /// A pending manual correction the user has entered before clicking "Save to Library".
    /// When non-nil, `persistToLibrary` wraps the extracted metric value in `WorkbenchMetricOverrideInfo`
    /// and writes `newValue` as the stored value. Cleared after a successful persist.
    var pendingMetricOverride: WorkbenchMetricOverrideCandidate? = nil

    /// Per-series AHE metrics extracted from the most recently rendered plot, keyed by sampleKey.
    /// Updated on every render (including preview renders without persist).
    /// Single-sample: one entry; multi-sample: one entry per curve.
    private(set) var lastExtractedMetrics: [String: AHEExtractedMetric] = [:]

    /// A pending manual correction for the extracted R_AHE value.
    /// Mirrors `pendingMetricOverride` but for the R_AHE metric. Cleared after a successful persist.
    var pendingRAHEOverride: WorkbenchMetricOverrideCandidate? = nil

    /// Convenience: Hc from the first (or only) extracted metric, for single-sample UI binding.
    var lastExtractedHc: Double? { lastExtractedMetrics.values.first?.hc }

    /// Convenience: R_AHE from the first (or only) extracted metric, for single-sample UI binding.
    var lastExtractedRAHE: Double? { lastExtractedMetrics.values.first?.rAHE }

    var sortedExtractedMetrics: [AHEExtractedMetric] {
        lastExtractedMetrics.values.sorted { lhs, rhs in
            if lhs.sampleKey != rhs.sampleKey { return lhs.sampleKey < rhs.sampleKey }
            return lhs.hc < rhs.hc
        }
    }

    // MARK: - Warning log

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()

    // MARK: - Ingestion cache (for style-only re-render)

    private(set) var ingestionResult: AHEIngestionResult?

    // MARK: - Related charts (hover popover)

    private(set) var relatedChartsGrouped: [String: [WorkbenchResultReference]] = [:]
    @ObservationIgnored private var relatedChartsTask: Task<Void, Never>?

    func refreshRelatedCharts() {
        relatedChartsTask?.cancel()
        relatedChartsTask = nil

        let keys = lastRenderedSampleKeys
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

    // MARK: - Multi-tab render state (shell capability)

    var tabs = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe, showPlotGrid: false)
    var globalPlotDefaults: [String: String] = [:]

    // MARK: - Title template

    var titleTemplate: String = "#tab #device #sample"
    /// Cached per-sample numericDisplay from library index, populated by WorkbenchFeatureStore.
    var cachedSampleNumericDisplay: [String: [String: String]] = [:]

    // MARK: - Context set by WorkbenchFeatureStore after search

    /// Updated by WorkbenchFeatureStore when search results change.
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    /// Updated by WorkbenchFeatureStore when a search runs. Required for artifact I/O.
    var lastLibraryRootPath: String = ""

    /// Sample keys snapshot from the render that produced current plot.
    @ObservationIgnored
    private(set) var lastRenderedSampleKeys: [String] = []
    /// Per-sample conditions snapshot from the render.
    @ObservationIgnored
    private(set) var lastRenderedConditionsBySampleKey: [String: [String: String]] = [:]

    // MARK: - Analysis Pack (vault integration)

    @ObservationIgnored var vault: AnalysisVault?
    var activePackID: AnalysisPack.ID?

    // MARK: - Cached input files (for pack fingerprint)

    @ObservationIgnored private(set) var cachedInputFiles: [String] = []

    // MARK: - Environment

    @ObservationIgnored private let env: WorkbenchEnvironment

    init(env: WorkbenchEnvironment = .live) {
        self.env = env
    }

    // MARK: - Private

    @ObservationIgnored
    var plotTask: Task<Void, Never>?
    deinit {
        plotTask?.cancel()
        relatedChartsTask?.cancel()
    }

    // MARK: - Plot

    // MARK: - Rerender (style-only, from cached ingestion)

    private func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }

        let tabState = tabs.activeState
        let resolvedTitle: String = {
            if !tabState.titleOverride.isEmpty { return tabState.titleOverride }
            let hit = cachedSearchResults.first(where: { lastRenderedSampleKeys.contains($0.sampleKey) })
            var tokens: [String: String] = ["sample": hit?.sampleBatchAndSubstrate ?? ""]
            if let key = hit?.sampleKey {
                let nd = cachedSampleNumericDisplay[key] ?? [:]
                for (k, v) in nd { tokens[k] = v }
            }
            tokens["tab"] = "AHE"
            return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
        }()
        let payload = BuildAHEPlotPayloadUseCase().execute(
            ingestion: ingestion,
            title: resolvedTitle,
            styleParams: [:]
        )
        let input = tabs.buildPipelineInput(payload: payload, globalPlotDefaults: globalPlotDefaults)

        plotTask?.cancel()
        plotTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try WorkbenchRenderPipeline.render(input)
                }.value
                guard !Task.isCancelled else { return }
                self.tabs.applyPipelineOutput(output, for: .ahe)
            } catch is CancellationError {
                // cancelled — no-op
            } catch {
                self.plotMessage = "Re-render failed: \(error.localizedDescription)"
            }
        }
    }

    func clearPlot() {
        plotTask?.cancel()
        plotTask = nil
        tabs.clearAll()
        currentRunTrace = nil
        warningLog.clear()
        ingestionResult = nil
        persistenceOutcome = nil
        pendingMetricOverride = nil
        pendingRAHEOverride = nil
        lastExtractedMetrics = [:]
        isPlotRendering = false
        plotMessage = nil
        saveMessage = nil
        cachedInputFiles = []
        activePackID = nil
        relatedChartsTask?.cancel()
        relatedChartsTask = nil
        relatedChartsGrouped = [:]
    }

    func clearResults() {
        cachedSearchResults = []
        cachedSampleNumericDisplay = [:]
    }

    func updateHcCandidate(rawValue: String, rawReason: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { pendingMetricOverride = nil; return }
        guard let parsed = Double(trimmed) else { pendingMetricOverride = nil; return }
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingMetricOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: parsed,
            reason: reason.isEmpty ? "visual check" : reason,
            source: .manual
        )
    }

    func updateRAHECandidate(rawValue: String, rawReason: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { pendingRAHEOverride = nil; return }
        guard let parsed = Double(trimmed) else { pendingRAHEOverride = nil; return }
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingRAHEOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: parsed,
            reason: reason.isEmpty ? "visual check" : reason,
            source: .manual
        )
    }

    // MARK: - Save to Library

    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = activeChartPNG else {
            saveMessage = "No chart to save. Render first."
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

    func applyPersistenceOutcome(_ outcome: PersistenceOutcome) {
        persistenceOutcome = outcome
    }

    func didCompleteSave(outcome: PersistenceOutcome) {
        switch outcome {
        case .success:
            self.pendingMetricOverride = nil
            self.pendingRAHEOverride = nil
            self.persistCount += 1
        case .partial:
            self.persistCount += 1
        case .failure:
            break
        }
    }

    // MARK: - Plot label / position overrides (delegate to TabRenderManager)

    func updateSeriesLabel(identityKey: String, newLabel: String) {
        tabs.updateSeriesLabel(identityKey: identityKey, newLabel: newLabel)
        _rerenderActiveTab()
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

    // MARK: - Private helpers

    private func buildAHESelections(from sourceHits: [WorkflowMeasurementSearchHit]) -> [AHEPlotSelectionItem] {
        let hits: [WorkflowMeasurementSearchHit]
        if let reading = selectionReading {
            let ids = reading.selectedIDs(for: .ahe)
            hits = ids.isEmpty ? [] : sourceHits.filter { ids.contains($0.id) }
        } else {
            hits = sourceHits
        }
        return buildAHESelections(fromSelectedHits: hits)
    }

    private func buildAHESelections(fromSelectedHits hits: [WorkflowMeasurementSearchHit]) -> [AHEPlotSelectionItem] {
        var selections: [AHEPlotSelectionItem] = []
        for hit in hits {
            let channels: [AHEChannel]
            if hit.channels.isEmpty {
                channels = [.ch1]
            } else {
                let mapped = hit.channels.compactMap { AHEChannel(rawValue: $0.lowercased()) }
                channels = mapped.isEmpty ? [.ch1] : mapped
            }
            for ch in channels {
                selections.append(AHEPlotSelectionItem(
                    sampleKey: hit.sampleKey,
                    sourceFilePath: hit.measurementFilePath,
                    channel: ch,
                    conditions: hit.conditions,
                    workflowID: hit.workflowID,
                    sampleSubstrate: hit.sampleSubstrate
                ))
            }
        }
        return selections
    }

}

// MARK: - WorkbenchCartesianXYPlottingStore conformance

extension AHEWorkspaceStore: WorkbenchCartesianXYPlottingStore {
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
}

// MARK: - ActiveChartProviding conformance

extension AHEWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? { tabs.activeImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { tabs.activeManifestPayload }

    var activeChartSampleKeys: [String] { lastRenderedSampleKeys }

    func buildActiveChartMetrics() -> [PendingMetricEntry] {
        let sampleKeys = lastRenderedSampleKeys
        let isSingleSample = sampleKeys.count == 1
        let generatedAt = Date()
        let conditionsBySampleKey = lastRenderedConditionsBySampleKey

        var entries: [PendingMetricEntry] = []
        for key in sampleKeys {
            guard let metric = lastExtractedMetrics[key] else { continue }
            let conditions = conditionsBySampleKey[key] ?? [:]

            // Hc
            let hcValue: Double
            let hcOverride: WorkbenchMetricOverrideInfo?
            if isSingleSample, let override = pendingMetricOverride {
                hcValue = override.proposedValue
                hcOverride = WorkbenchMetricOverrideInfo(
                    oldValue: metric.hc, newValue: override.proposedValue,
                    reason: override.reason, source: override.source, at: generatedAt
                )
            } else {
                hcValue = metric.hc
                hcOverride = nil
            }
            entries.append(PendingMetricEntry(
                sampleKey: key, metric: "Hc", value: hcValue,
                canonicalUnit: "T", conditions: conditions, overrideInfo: hcOverride
            ))

            // R_AHE
            let rAHEValue: Double
            let rAHEOverride: WorkbenchMetricOverrideInfo?
            if isSingleSample, let override = pendingRAHEOverride {
                rAHEValue = override.proposedValue
                rAHEOverride = WorkbenchMetricOverrideInfo(
                    oldValue: metric.rAHE, newValue: override.proposedValue,
                    reason: override.reason, source: override.source, at: generatedAt
                )
            } else {
                rAHEValue = metric.rAHE
                rAHEOverride = nil
            }
            entries.append(PendingMetricEntry(
                sampleKey: key, metric: "R_AHE", value: rAHEValue,
                canonicalUnit: "Ω", conditions: conditions, overrideInfo: rAHEOverride
            ))
        }
        return entries
    }
}

// MARK: - AnalysisPackProviding conformance

extension AHEWorkspaceStore: AnalysisPackProviding {
    typealias PackConfig = AHEPackConfig
    typealias PackResult = AHEPackResult

    var packWorkflowID: String { "ahe" }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { lastRenderedSampleKeys }
    var hasAnalysisResult: Bool { tabs.activeImageData != nil }

    var analysisMessage: String? {
        get { plotMessage }
        set { plotMessage = newValue }
    }

    func buildPackConfig() -> AHEPackConfig {
        AHEPackConfig(
            titleTemplate: titleTemplate,
            showPlotGrid: tabs.showPlotGrid,
            tabStates: tabs.snapshotStates(keyFor: { $0.rawValue }),
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectionReading?.selectedIDs(for: .ahe) ?? []),
            searchQueryText: ""
        )
    }

    func buildPackResult() -> AHEPackResult {
        AHEPackResult(ingestionResult: ingestionResult)
    }

    func autoPackLabel() -> String {
        cachedSearchResults.first?.sampleBatchAndSubstrate ?? "AHE"
    }

    func cancelInflightWork() {
        plotTask?.cancel()
        plotTask = nil
    }

    func restoreFromPack(config: AHEPackConfig, result: AHEPackResult, pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                         seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void) {
        // Restore plot controls
        titleTemplate = config.titleTemplate
        tabs.showPlotGrid = config.showPlotGrid

        // Restore per-tab states
        tabs.restoreStates(config.tabStates) { AHEWorkbenchTab(rawValue: $0) }

        // Restore search selection
        cachedSearchResults = config.cachedSearchResults
        seedSelection(Set(config.selectedSearchResultIDs), config.cachedSearchResults)

        // Restore results
        ingestionResult = result.ingestionResult

        // Restore cached persistence state
        cachedInputFiles = pack.filePaths
        lastRenderedSampleKeys = pack.sampleKeys

        // Restore library root from vault
        if lastLibraryRootPath.isEmpty, let root = vault?.libraryRootPath {
            lastLibraryRootPath = root
        }

        // Bridge search results
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        // Re-render from cached ingestion, or full re-analysis for legacy packs
        if ingestionResult != nil {
            _rerenderActiveTab()
        } else {
            runAnalysis()
        }
    }
}

// MARK: - WorkbenchWorkspaceProviding conformance

extension AHEWorkspaceStore: WorkbenchWorkspaceProviding {

    var isAnalyzing: Bool { isPlotRendering }

    func runAnalysis() {
        runAnalysis(searchSnapshot: nil)
    }

    func runAnalysis(searchSnapshot: WorkbenchSearchSnapshot?) {
        let sourceHits = searchSnapshot?.results ?? cachedSearchResults
        let selections = buildAHESelections(from: sourceHits)
        _runAnalysisWithPreparedSelections(selections, sourceHits: sourceHits)
    }

    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot?) {
        let sourceHits: [WorkflowMeasurementSearchHit]
        let selections: [AHEPlotSelectionItem]
        if let selectedHitsSnapshot {
            sourceHits = selectedHitsSnapshot.selectedHits
            selections = buildAHESelections(fromSelectedHits: selectedHitsSnapshot.selectedHits)
        } else {
            sourceHits = cachedSearchResults
            selections = buildAHESelections(from: sourceHits)
        }
        _runAnalysisWithPreparedSelections(selections, sourceHits: sourceHits)
    }

    private func _runAnalysisWithPreparedSelections(
        _ selections: [AHEPlotSelectionItem],
        sourceHits: [WorkflowMeasurementSearchHit]
    ) {
        guard !selections.isEmpty else {
            plotMessage = "Select at least one AHE measurement to plot."
            return
        }
        let capturedTemplate = titleTemplate
        let capturedTitleTokens: [String: String] = {
            let sortedHits = selections.sorted(by: { $0.sampleKey < $1.sampleKey })
            guard let hit = sortedHits.first,
                  let searchHit = sourceHits.first(where: { $0.sampleKey == hit.sampleKey }) else { return [:] }
            var tokens: [String: String] = ["sample": searchHit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[searchHit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            return tokens
        }()
        let capturedTabState = tabs.activeState
        let capturedGlobalPlotDefaults = globalPlotDefaults
        let capturedPipelineInput: (WorkbenchPlotPayload) -> WorkbenchRenderPipeline.Input = { [tabs] payload in
            tabs.buildPipelineInput(payload: payload, globalPlotDefaults: capturedGlobalPlotDefaults)
        }

        let snapshotSampleKeys: [String] = {
            var seen = Set<String>()
            return selections.compactMap { seen.insert($0.sampleKey).inserted ? $0.sampleKey : nil }
        }()
        let snapshotConditions: [String: [String: String]] = {
            var map: [String: [String: String]] = [:]
            for sel in selections where map[sel.sampleKey] == nil {
                map[sel.sampleKey] = sel.conditions
            }
            return map
        }()

        let capturedNumericDisplay = cachedSampleNumericDisplay

        plotTask?.cancel()
        isPlotRendering = true
        plotMessage = nil
        saveMessage = nil
        tabs.clearOutputs()
        currentRunTrace = nil
        persistenceOutcome = nil

        let seriesCount = selections.count
        plotTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (ingestion, pipelineOutput, extractedMetrics) = try await Task.detached(priority: .userInitiated) {
                    let ingestion = try IngestAHESelectionsUseCase().execute(
                        selections: selections,
                        numericDisplayBySample: capturedNumericDisplay
                    )
                    let extractedMetrics = try ExtractAHEMetricsUseCase.extractAHEMetricsPerSeries(from: ingestion.series).get()
                    let resolvedTitle: String = {
                        if !capturedTabState.titleOverride.isEmpty { return capturedTabState.titleOverride }
                        var tokens = capturedTitleTokens
                        tokens["tab"] = "AHE"
                        return WorkbenchTitleResolver.resolve(template: capturedTemplate, tokens: tokens)
                    }()
                    let payload = BuildAHEPlotPayloadUseCase().execute(
                        ingestion: ingestion,
                        title: resolvedTitle,
                        styleParams: [:]
                    )
                    let input = capturedPipelineInput(payload)
                    let output = try WorkbenchRenderPipeline.render(input)
                    return (ingestion, output, extractedMetrics)
                }.value
                guard !Task.isCancelled else { return }
                self.ingestionResult = ingestion
                self.tabs.applyPipelineOutput(pipelineOutput, for: .ahe)
                for w in pipelineOutput.warnings {
                    self.appendWarning(source: "Legend", message: w)
                }
                for w in ingestion.warnings {
                    self.appendWarning(source: "Ingestion", message: w)
                }
                self.lastExtractedMetrics = extractedMetrics
                self.lastRenderedSampleKeys = snapshotSampleKeys
                self.lastRenderedConditionsBySampleKey = snapshotConditions
                self.cachedInputFiles = selections.map(\.sourceFilePath)
                self.commitRunTrace()
                self.isPlotRendering = false
                self.plotMessage = "Rendered \(seriesCount) series."
                self.refreshRelatedCharts()
            } catch is CancellationError {
                self.isPlotRendering = false
            } catch {
                self.tabs.clearOutputs()
                self.isPlotRendering = false
                self.plotMessage = "Plot failed: \(error.localizedDescription)"
            }
        }
    }

    func rerenderForStyleChange() { _rerenderActiveTab() }

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard !cachedInputFiles.isEmpty else { return nil }
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: "ahe",
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(
                xField: AHEAxisDetector.semanticXField,
                yField: AHEAxisDetector.semanticYField
            ),
            semanticParams: ["series": "\(lastRenderedSampleKeys.count)"],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }

    var activeImageData: Data? { tabs.activeImageData }
    var activeLayout: WorkbenchPlotLayout? { tabs.activeLayout }
    var seriesLabelOverrides: [String: String] { tabs.activeSeriesLabelOverrides }
    var relatedCharts: [WorkbenchResultReference]? {
        guard let payload = tabs.activeManifestPayload else { return nil }
        let inputFiles = payload.series.compactMap(\.sourceRef)
        guard !inputFiles.isEmpty else { return nil }
        let key = InputFilesCanonicalKey.make(from: inputFiles)
        let charts = relatedChartsGrouped[key] ?? []
        return charts.isEmpty ? nil : charts
    }
    var libraryRootURL: URL? {
        lastLibraryRootPath.isEmpty ? nil : URL(fileURLWithPath: lastLibraryRootPath)
    }
}
