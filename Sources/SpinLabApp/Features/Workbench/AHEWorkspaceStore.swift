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
final class AHEWorkspaceStore {

    // MARK: - Selection

    var selectedSearchResultIDs: Set<String> = []

    // MARK: - Plot output

    private(set) var isPlotRendering: Bool = false
    var plotMessage: String?
    private(set) var currentCandidateAxisFields: [String] = []
    var currentRunTrace: WorkbenchRunTraceProjection?

    // MARK: - Persistence outcome

    /// Set after each `persistToLibrary()` call.
    /// Nil when no persist has occurred or after `clearPlot()`.
    private(set) var persistenceOutcome: PersistenceOutcome? = nil

    /// Incremented every time a persist completes (success or partial).
    /// Use this for `onChange` observation — avoids requiring `PersistenceOutcome: Equatable`.
    private(set) var persistCount: Int = 0

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

    // MARK: - Multi-tab render state (shell capability)

    var tabs = TabRenderManager<AHEWorkbenchTab>(defaultTab: .ahe, showPlotGrid: false)

    // MARK: - Plot controls (bound by AHEPlotControlsPanel)

    var plotAxisXOverride: String = ""
    var plotAxisYOverride: String = ""

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

    // MARK: - Private

    @ObservationIgnored
    var plotTask: Task<Void, Never>?
    deinit {
        plotTask?.cancel()
        relatedChartsTask?.cancel()
    }

    // MARK: - Selection

    var isAllSelected: Bool {
        !cachedSearchResults.isEmpty && selectedSearchResultIDs.count == cachedSearchResults.count
    }

    func selectAll() {
        selectedSearchResultIDs = Set(cachedSearchResults.map(\.id))
    }

    func deselectAll() {
        selectedSearchResultIDs = []
    }

    func toggleSearchHitSelection(_ id: String) {
        if selectedSearchResultIDs.contains(id) {
            selectedSearchResultIDs.remove(id)
        } else {
            selectedSearchResultIDs.insert(id)
        }
    }

    // MARK: - Plot

    // MARK: - Rerender (style-only, from cached ingestion)

    private func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }

        let xOverride = plotAxisXOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let yOverride = plotAxisYOverride.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let xField = xOverride.isEmpty ? ingestion.defaultAxisMapping.xField : xOverride
        let yField = yOverride.isEmpty ? ingestion.defaultAxisMapping.yField : yOverride
        let payload = BuildAHEPlotPayloadUseCase().execute(
            ingestion: ingestion,
            title: resolvedTitle,
            axisMappingOverride: WorkbenchAxisMapping(xField: xField, yField: yField),
            styleParams: [:]
        )
        let input = tabs.buildPipelineInput(payload: payload)

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
        currentCandidateAxisFields = []
        plotAxisXOverride = ""
        plotAxisYOverride = ""
        cachedInputFiles = []
        activePackID = nil
        relatedChartsTask?.cancel()
        relatedChartsTask = nil
        relatedChartsGrouped = [:]
    }

    func clearResults() {
        selectedSearchResultIDs = []
        cachedSearchResults = []
        cachedSampleNumericDisplay = [:]
    }

    // MARK: - Save to Library

    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = activeChartPNG else {
            plotMessage = "No chart to save. Render first."
            return
        }
        guard let payload = activeChartManifestPayload else {
            plotMessage = "No manifest payload available."
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
                self.pendingMetricOverride = nil
                self.pendingRAHEOverride = nil
                self.persistCount += 1
                self.plotMessage = "Saved to Library."
            case .partial(_, let metricError):
                self.persistCount += 1
                self.plotMessage = "Chart saved; metric error: \(metricError)"
            case .failure(let msg):
                self.plotMessage = "Save failed: \(msg)"
            }
            onComplete?()
        }
    }

    // MARK: - Plot label / position overrides (delegate to TabRenderManager)

    func updateSeriesLabel(index: Int, newLabel: String) {
        tabs.updateSeriesLabel(index: index, newLabel: newLabel)
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

    private func buildAHESelections() -> [AHEPlotSelectionItem] {
        let hits = cachedSearchResults.filter { selectedSearchResultIDs.contains($0.id) }
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

    /// Persists chart + metric artifacts for a completed render.
    ///
    /// `runID` is generated once by the caller and passed into both
    /// `PersistChartArtifactUseCase` and `PersistMeasurementDataUseCase` so that
    /// the run manifest and the metric record share the same identifier (Adj-2).
    ///
    /// Returns `PersistenceOutcome` — never throws or returns nil — so partial
    /// failures (chart OK, metric failed) are surfaced to the store (Adj-3).
    ///
    /// Extracts Hc and R_AHE for every series, keyed by sampleKey parsed from the series label.
    ///
    /// Series label format (from IngestAHESelectionsUseCase):
    ///   "sampleKey | channel" or "sampleKey | channel | temperature"
    /// The sampleKey is the first segment before " | ".
    ///
    /// When multiple series share the same sampleKey (e.g. different channels), only the
    /// first series for that key is used for metric extraction (consistent with single-file-per-sample semantics).
    ///
    /// If any series label cannot be parsed to extract a sampleKey, returns
    /// `.failure(.unparseableLabels([...]))` with the full list of unparseable labels.
    nonisolated static func extractAHEMetricsPerSeries(
        from series: [WorkbenchPlotSeries]
    ) -> Result<[String: AHEExtractedMetric], AHEMetricExtractionError> {
        var result: [String: AHEExtractedMetric] = [:]
        var failedLabels: [String] = []
        for s in series {
            guard let key = parseSampleKey(from: s.label) else {
                failedLabels.append(s.label.isEmpty ? "<empty>" : s.label)
                continue
            }
            guard result[key] == nil else { continue }
            let (hc, rAHE) = extractSingleSeriesMetrics(s)
            result[key] = AHEExtractedMetric(sampleKey: key, hc: hc, rAHE: rAHE)
        }
        guard failedLabels.isEmpty else {
            return .failure(.unparseableLabels(failedLabels))
        }
        return .success(result)
    }

    /// Parses the sampleKey from an AHE series label.
    /// Label format: "sampleKey | channel | temperature" or "sampleKey | channel".
    /// Returns nil if the label is empty or has no " | " separator.
    nonisolated static func parseSampleKey(from label: String) -> String? {
        let segment = label.components(separatedBy: " | ").first?.trimmingCharacters(in: .whitespaces)
        guard let key = segment, !key.isEmpty else { return nil }
        return key
    }

    /// Extracts Hc and R_AHE from a single series.
    ///
    /// **Background removal:**
    ///   threshold = (ymin + ymax) / 2;  y_shifted = y − threshold
    ///
    /// **Hc** — coercive field via zero-crossing interpolation.
    /// **R_AHE** — saturation plateau method (|H| > 80% H_max).
    nonisolated static func extractSingleSeriesMetrics(
        _ series: WorkbenchPlotSeries
    ) -> (hc: Double, rAHE: Double) {
        guard series.x.count > 1 else { return (0.0, 0.0) }
        let xs = series.x
        let rawYs = series.y

        let yMin = rawYs.min()!
        let yMax = rawYs.max()!
        let threshold = (yMin + yMax) / 2.0
        let ys = rawYs.map { $0 - threshold }

        // --- Hc ---
        var crossings: [Double] = []
        for i in 0..<xs.count - 1 {
            let y0 = ys[i], y1 = ys[i + 1]
            if y0 * y1 <= 0, y0 != y1 {
                let t = y0 / (y0 - y1)
                crossings.append(xs[i] + t * (xs[i + 1] - xs[i]))
            }
        }

        let hc: Double
        if crossings.isEmpty {
            var minAbs = Double.infinity
            var result = 0.0
            for i in 0..<xs.count {
                let a = abs(ys[i])
                if a < minAbs { minAbs = a; result = xs[i] }
            }
            hc = abs(result)
        } else {
            let posCrossings = crossings.filter { $0 > 0 }
            let negCrossings = crossings.filter { $0 < 0 }
            if !posCrossings.isEmpty && !negCrossings.isEmpty {
                hc = (posCrossings.max()! + abs(negCrossings.min()!)) / 2.0
            } else {
                hc = crossings.map { abs($0) }.reduce(0, +) / Double(crossings.count)
            }
        }

        // --- R_AHE ---
        let hMax = xs.map { abs($0) }.max() ?? 0.0
        let rAHE: Double
        if hMax > 0 {
            let satThreshold = 0.8 * hMax
            let topPlateau = zip(xs, ys).compactMap { $0.0 > satThreshold ? $0.1 : nil }
            let bottomPlateau = zip(xs, ys).compactMap { $0.0 < -satThreshold ? $0.1 : nil }
            if !topPlateau.isEmpty && !bottomPlateau.isEmpty {
                rAHE = (AHEWorkspaceStore.median(topPlateau) - AHEWorkspaceStore.median(bottomPlateau)) / 2.0
            } else {
                rAHE = (yMax - yMin) / 2.0
            }
        } else {
            rAHE = (yMax - yMin) / 2.0
        }

        return (hc, rAHE)
    }

    private nonisolated static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }
}

// MARK: - WorkbenchPlottingStore conformance

extension AHEWorkspaceStore: WorkbenchPlottingStore {
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
            plotAxisXOverride: plotAxisXOverride,
            plotAxisYOverride: plotAxisYOverride,
            titleTemplate: titleTemplate,
            showPlotGrid: tabs.showPlotGrid,
            tabStates: tabs.snapshotStates(keyFor: { $0.rawValue }),
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectedSearchResultIDs),
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
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void) {
        // Restore plot controls
        plotAxisXOverride = config.plotAxisXOverride
        plotAxisYOverride = config.plotAxisYOverride
        titleTemplate = config.titleTemplate
        tabs.showPlotGrid = config.showPlotGrid

        // Restore per-tab states
        tabs.restoreStates(config.tabStates) { AHEWorkbenchTab(rawValue: $0) }

        // Restore search selection
        cachedSearchResults = config.cachedSearchResults
        selectedSearchResultIDs = Set(config.selectedSearchResultIDs)

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
        let selections = buildAHESelections()
        guard !selections.isEmpty else {
            plotMessage = "Select at least one AHE measurement to plot."
            return
        }
        // Capture overrides and context before leaving MainActor
        let xOverride = plotAxisXOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let yOverride = plotAxisYOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedTemplate = titleTemplate
        let capturedTitleTokens: [String: String] = {
            let sortedHits = selections.sorted(by: { $0.sampleKey < $1.sampleKey })
            guard let hit = sortedHits.first,
                  let searchHit = cachedSearchResults.first(where: { $0.sampleKey == hit.sampleKey }) else { return [:] }
            var tokens: [String: String] = ["sample": searchHit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[searchHit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            return tokens
        }()
        let capturedTabState = tabs.activeState
        let capturedPipelineInput: (WorkbenchPlotPayload) -> WorkbenchRenderPipeline.Input = { [tabs] payload in
            tabs.buildPipelineInput(payload: payload)
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
                        xColumnOverride: xOverride.isEmpty ? nil : xOverride,
                        yColumnOverride: yOverride.isEmpty ? nil : yOverride,
                        numericDisplayBySample: capturedNumericDisplay
                    )
                    let extractedMetrics = try AHEWorkspaceStore.extractAHEMetricsPerSeries(from: ingestion.series).get()
                    let resolvedTitle: String = {
                        if !capturedTabState.titleOverride.isEmpty { return capturedTabState.titleOverride }
                        var tokens = capturedTitleTokens
                        tokens["tab"] = "AHE"
                        return WorkbenchTitleResolver.resolve(template: capturedTemplate, tokens: tokens)
                    }()
                    let xField = xOverride.isEmpty ? ingestion.defaultAxisMapping.xField : xOverride
                    let yField = yOverride.isEmpty ? ingestion.defaultAxisMapping.yField : yOverride
                    let payload = BuildAHEPlotPayloadUseCase().execute(
                        ingestion: ingestion,
                        title: resolvedTitle,
                        axisMappingOverride: WorkbenchAxisMapping(xField: xField, yField: yField),
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
                self.currentCandidateAxisFields = ingestion.candidateAxisFields
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
        let xField = plotAxisXOverride.isEmpty ? "Magnetic Field" : plotAxisXOverride
        let yField = plotAxisYOverride.isEmpty ? "R_H" : plotAxisYOverride
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: "ahe",
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
            semanticParams: ["series": "\(lastRenderedSampleKeys.count)"],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }

    var activeImageData: Data? { tabs.activeImageData }
    var activeLayout: WorkbenchPlotLayout? { tabs.activeLayout }
    var seriesLabelOverrides: [Int: String] { tabs.activeSeriesLabelOverrides }
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
