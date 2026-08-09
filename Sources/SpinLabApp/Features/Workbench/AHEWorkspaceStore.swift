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
    @ObservationIgnored var packRestoreErrorMessage: String? = nil
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

    /// The magnetic-field display unit for the current chart, selected by magnitude from
    /// `ingestionResult.series.x` (always canonical Tesla — see `IngestAHESelectionsUseCase`).
    /// Transient/derived, not persisted; matches what `BuildAHEPlotPayloadUseCase` renders.
    var fieldDisplayUnit: MagneticFieldUnit {
        guard let ingestion = ingestionResult else { return .tesla }
        return WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: ingestion.series.flatMap(\.x))
    }

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
    /// Vertical stack offset multiplier for series display (0 = no stacking).
    /// Matches RT/IV/XYRotation naming and default — see `ThreeOmegaStackOffsetUseCase`.
    var stackOffsetMultiplier: Double = 0.0
    /// Minimum gap floor as a fraction of max peak-to-peak amplitude.
    var minGapFraction: Double = 0.15
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

    let workflowID: String
    @ObservationIgnored private let env: WorkbenchEnvironment

    init(workflowID: String, env: WorkbenchEnvironment = .live) {
        self.workflowID = workflowID
        self.env = env
    }

    // MARK: - Private

    @ObservationIgnored
    var plotTask: Task<Void, Never>?

    @ObservationIgnored private var _renderRevision: UInt64 = 0
    deinit {
        plotTask?.cancel()
        relatedChartsTask?.cancel()
    }

    // MARK: - Rerender (style-only, from cached ingestion)

    private func _rerenderActiveTab() {
        PerfCounters.renderCalls += 1
        print("[PERF][count] render workspace=AHE tab=\(tabs.activeTab) count=\(PerfCounters.renderCalls)")
        guard let ingestion = ingestionResult else { return }

        let tabState = tabs.activeState
        let capturedGlobalPlotDefaults = globalPlotDefaults
        let capturedShowPlotGrid = tabs.showPlotGrid
        let capturedSeriesRenderMode = tabs.seriesRenderMode
        let capturedChartStyleOverrides = tabs.chartStyleOverrides
        let capturedLegendAnchor = tabs.legendAnchor
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
        let payloads = BuildAHEPlotPayloadUseCase().executePayloads(
            ingestion: ingestion,
            title: resolvedTitle,
            styleParams: [:],
            seriesOrder: tabState.seriesOrder,
            hiddenSeriesKeys: tabState.hiddenSeriesKeys,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        let input = tabs.buildPipelineInput(
            payload: payloads.displayPayload,
            globalPlotDefaults: capturedGlobalPlotDefaults,
            tabState: WorkbenchTabDisplayStateSnapshot(
                titleOverride: tabState.titleOverride,
                xLabelOverride: tabState.xLabelOverride,
                yLabelOverride: tabState.yLabelOverride,
                seriesLabelOverrides: tabState.seriesLabelOverrides,
                legendPoint: tabState.legendPoint?.cgPoint,
                hiddenSeriesKeys: tabState.hiddenSeriesKeys,
                hiddenPointLabelsBySeries: tabState.hiddenPointLabelIndicesBySeries,
                seriesOrder: tabState.seriesOrder,
                axisRangeOverride: tabState.axisRangeOverride,
                tickOverride: tabState.tickOverride,
                showPointTags: tabState.showPointTags
            ),
            showPlotGrid: capturedShowPlotGrid,
            seriesRenderMode: capturedSeriesRenderMode,
            chartStyleOverrides: capturedChartStyleOverrides,
            legendAnchor: capturedLegendAnchor,
            for: .ahe
        )

        plotTask?.cancel()
        _renderRevision &+= 1
        let revision = _renderRevision
        plotTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try WorkbenchRenderPipeline.render(input)
                }.value
                guard !Task.isCancelled, self._renderRevision == revision else { return }
                self.tabs.applyPipelineOutput(
                    output,
                    displayPayload: payloads.displayPayload,
                    manifestPayload: payloads.manifestPayload,
                    for: .ahe
                )
            } catch is CancellationError {
                // cancelled — no-op
            } catch {
                guard self._renderRevision == revision else { return }
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
    }

    func updateSeriesVisibility(identityKey: String, isVisible: Bool) {
        tabs.updateSeriesVisibility(identityKey: identityKey, isVisible: isVisible)
    }

    func updateSeriesOrder(_ order: [String]) {
        tabs.updateSeriesOrder(order)
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

    func updateAxisBound(_ bound: AxisRangeBound, value: Double?) {
        guard tabs.updateAxisBound(bound, value: value) else { return }
        _rerenderActiveTab()
    }

    /// Atomically clears all four axis-range bounds for the active tab.
    func resetAxisRanges() {
        guard tabs.resetAxisRangeOverride() else { return }
        _rerenderActiveTab()
    }

    func updateTickCount(axis: PlotTickAxis, count: Int) {
        guard tabs.updateTickCount(axis: axis, count: count) else { return }
        _rerenderActiveTab()
    }

    // MARK: - Private helpers

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
                    sampleSubstrate: hit.sampleSubstrate,
                    batchID: hit.batchID,
                    hitID: hit.id
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
                sampleKey: key, metric: AHEDataFieldKey.hc.rawValue, value: hcValue,
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
                sampleKey: key, metric: AHEDataFieldKey.rAHE.rawValue, value: rAHEValue,
                canonicalUnit: "Ω", conditions: conditions, overrideInfo: rAHEOverride
            ))
        }
        return entries
    }
}

// MARK: - AnalysisPackProviding conformance

extension AHEWorkspaceStore: AnalysisPackProviding, PackRestoreFailureReporting {
    typealias PackConfig = AHEPackConfig
    typealias PackResult = AHEPackResult

    var packWorkflowID: String { workflowID }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { lastRenderedSampleKeys }
    var hasAnalysisResult: Bool { tabs.activeImageData != nil }

    var analysisMessage: String? {
        get { plotMessage }
        set { plotMessage = newValue }
    }

    func buildPackConfig() -> AHEPackConfig {
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: tabs.chartStyleOverrides)
        let searchContext = AnalysisPackSearchContext(
            cachedSearchResults: cachedSearchResults,
            selectionReading: selectionReading,
            workflowID: workflowID
        )
        return AHEPackConfig(
            titleTemplate: titleTemplate,
            showPlotGrid: tabs.showPlotGrid,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            legendAnchor: tabs.legendAnchor,
            seriesRenderMode: tabs.seriesRenderMode,
            chartStyleOverrides: splitOverrides.local,
            tabStates: tabs.snapshotStates(keyFor: { $0.rawValue }),
            cachedSearchResults: searchContext.cachedSearchResults,
            selectedSearchResultIDs: searchContext.selectedSearchResultIDs,
            searchQueryText: ""
        )
    }

    func buildPackResult() -> AHEPackResult {
        AHEPackResult(ingestionResult: ingestionResult)
    }

    func autoPackLabel() -> String {
        analysisPackLabel(
            sampleBatchAndSubstrate: cachedSearchResults.first?.sampleBatchAndSubstrate,
            device: nil,
            fallback: "AHE"
        )
    }

    func cancelInflightWork() {
        plotTask?.cancel()
        plotTask = nil
    }

    func restoreFromPack(config: AHEPackConfig, result: AHEPackResult, pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
                         seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void) {
        packRestoreErrorMessage = nil
        // Restore plot controls
        titleTemplate = config.titleTemplate
        tabs.showPlotGrid = config.showPlotGrid
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        tabs.legendAnchor = config.legendAnchor
        tabs.seriesRenderMode = config.seriesRenderMode
        let splitOverrides = WorkbenchChartStyle.splitGlobalPlotDefaults(from: config.chartStyleOverrides)
        if !splitOverrides.global.isEmpty { globalPlotDefaults = splitOverrides.global }
        tabs.chartStyleOverrides = splitOverrides.local

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
            // Legacy pack with no cached ingestion result: build a snapshot from the
            // just-restored (and already reconciled) selection/search state and run once,
            // synchronously, at restore time — not a live re-read during an in-flight run.
            let ids = selectionReading?.selectedIDs(for: workflowID) ?? []
            let hits = cachedSearchResults.filter { ids.contains($0.id) }
            runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot(
                workflowID: workflowID,
                queryText: config.searchQueryText,
                selectedIDs: ids,
                selectedHits: hits,
                sourceHitCount: cachedSearchResults.count,
                selectionSource: .canonicalSnapshot
            ))
        }
    }
}

// MARK: - WorkbenchWorkspaceProviding conformance

extension AHEWorkspaceStore: WorkbenchWorkspaceProviding {

    var isAnalyzing: Bool { isPlotRendering }

    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot) {
        let sourceHits = selectedHitsSnapshot.selectedHits
        let selections = buildAHESelections(fromSelectedHits: selectedHitsSnapshot.selectedHits)
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
        let capturedStackOffsetMultiplier = stackOffsetMultiplier
        let capturedMinGapFraction = minGapFraction
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
        _renderRevision &+= 1
        let revision = _renderRevision
        isPlotRendering = true
        plotMessage = nil
        saveMessage = nil
        // Clear the stale rendered output (not the full tabs.clearOutputs(), which also wipes
        // the source-identity tracking key) so preparedState can still detect a source change
        // and clear axisRangeOverride via the centralized path below.
        tabs.clearOutputPreservingSourceIdentity(for: .ahe)
        currentRunTrace = nil
        persistenceOutcome = nil

        let seriesCount = selections.count
        plotTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Stage 1 (detached, off the main actor): ingestion + payload assembly.
                // I/O- and CPU-heavy; does not touch `tabs` and needs no display-override state.
                let (ingestion, payload, extractedMetrics) = try await Task.detached(priority: .userInitiated) {
                    let ingestion = try IngestAHESelectionsUseCase().execute(
                        selections: selections,
                        numericDisplayBySample: capturedNumericDisplay
                    )
                    // Metrics must come from the ordinary-Hall-background-corrected series,
                    // never the raw or stacked/display-offset one — see
                    // AHEBackgroundCorrectionUseCase and BuildAHEPlotPayloadUseCase.
                    let correctedSeries = AHEBackgroundCorrectionUseCase().correctedSeries(ingestion.series)
                    let extractedMetrics = try ExtractAHEMetricsUseCase.extractAHEMetricsPerSeries(from: correctedSeries).get()
                    let resolvedTitle: String = {
                        if !capturedTabState.titleOverride.isEmpty { return capturedTabState.titleOverride }
                        var tokens = capturedTitleTokens
                        tokens["tab"] = "AHE"
                        return WorkbenchTitleResolver.resolve(template: capturedTemplate, tokens: tokens)
                    }()
                    let payloads = BuildAHEPlotPayloadUseCase().executePayloads(
                        ingestion: ingestion,
                        title: resolvedTitle,
                        styleParams: [:],
                        seriesOrder: capturedTabState.seriesOrder,
                        hiddenSeriesKeys: capturedTabState.hiddenSeriesKeys,
                        stackOffsetMultiplier: capturedStackOffsetMultiplier,
                        minGapFraction: capturedMinGapFraction
                    )
                    return (ingestion, payloads, extractedMetrics)
                }.value
                guard !Task.isCancelled, self._renderRevision == revision else { return }

                // Stage 2 (main actor): build the render Input through the same centralized,
                // policy-aware TabRenderManager.buildPipelineInput/preparedState path RT uses.
                // .clearDisplayOverridesIfSourceChanged is applied here — before the Input (and
                // therefore before axisRangeOverride) exists — so a stale override from the
                // previous source can never be baked into the first render of new data.
                let input = self.tabs.buildPipelineInput(
                    payload: payload.displayPayload,
                    globalPlotDefaults: self.globalPlotDefaults,
                    policy: .clearDisplayOverridesIfSourceChanged,
                    for: .ahe
                )

                // Stage 3 (detached): pixel rendering — CPU-heavy, kept off the main actor.
                let pipelineOutput = try await Task.detached(priority: .userInitiated) {
                    try WorkbenchRenderPipeline.render(input)
                }.value
                guard !Task.isCancelled, self._renderRevision == revision else { return }
                self.ingestionResult = ingestion
                self.tabs.applyPipelineOutput(
                    pipelineOutput,
                    displayPayload: payload.displayPayload,
                    manifestPayload: payload.manifestPayload,
                    for: .ahe,
                    policy: .clearDisplayOverridesIfSourceChanged
                )
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
                guard self._renderRevision == revision else { return }
                self.isPlotRendering = false
            } catch {
                guard self._renderRevision == revision else { return }
                self.tabs.clearOutputs()
                self.isPlotRendering = false
                self.plotMessage = "Plot failed: \(error.localizedDescription)"
            }
        }
    }

    func rerenderForStyleChange() { _rerenderActiveTab() }

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard !cachedInputFiles.isEmpty else { return nil }
        // Reuse the axis mapping BuildAHEPlotPayloadUseCase actually produced for the
        // rendered chart, rather than independently reconstructing it here — avoids the two
        // call sites drifting apart. Falls back to the same vocabulary call only if a
        // manifest payload isn't available yet (defensive; shouldn't happen once
        // cachedInputFiles is non-empty).
        let axisMapping = activeChartManifestPayload?.axisMapping ?? WorkbenchAxisMapping(
            xField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .externalMagneticField, unit: fieldDisplayUnit),
            yField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .raheCombined)
        )
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: workflowID,
            inputFiles: cachedInputFiles,
            axisMapping: axisMapping,
            semanticParams: ["series": "\(lastRenderedSampleKeys.count)"],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }

    var activeImageData: Data? { tabs.activeImageData }
    var activePdfData: Data? { tabs.activePdfData }
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
