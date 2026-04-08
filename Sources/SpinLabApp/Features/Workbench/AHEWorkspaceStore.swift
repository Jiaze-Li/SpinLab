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

    private(set) var currentPlotImageData: Data?
    private(set) var isPlotRendering: Bool = false
    var plotMessage: String?
    private(set) var currentCandidateAxisFields: [String] = []
    private(set) var currentRunTrace: WorkbenchRunTraceProjection?
    private(set) var currentPlotLayout: WorkbenchPlotLayout? = nil

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

    // MARK: - Artifact loading

    private(set) var isLoadingArtifact: Bool = false
    var artifactLoadMessage: String?

    // MARK: - Plot controls (bound by AHEPlotControlsPanel)

    var plotAxisXOverride: String = ""
    var plotAxisYOverride: String = ""
    var plotTitleOverride: String = ""
    var showPlotGrid: Bool = false
    var plotLegendAnchor: String = ""
    var plotLegendPoint: CGPoint? = nil
    /// Keyed by the series' original label (pre-override). Stable across sort/filter changes.
    var plotSeriesLabelOverrides: [Int: String] = [:]
    /// Display-only label override for the X axis (does not affect which data column is used).
    var plotXLabelOverride: String = ""
    /// Display-only label override for the Y axis (does not affect which data column is used).
    var plotYLabelOverride: String = ""

    // MARK: - Title template

    var titleTemplate: String = "#tab #device #sample"
    /// Cached per-sample numericDisplay from library index, populated by WorkbenchFeatureStore.
    var cachedSampleNumericDisplay: [String: [String: String]] = [:]

    // MARK: - Context set by WorkbenchFeatureStore after search

    /// Updated by WorkbenchFeatureStore when search results change.
    /// Used by renderAHEPlot to build selections without coupling back to WFS.
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    /// Updated by WorkbenchFeatureStore when a search runs. Required for artifact I/O.
    var lastLibraryRootPath: String = ""

    /// Manifest payload captured at render time for stable Save to Library identity.
    @ObservationIgnored
    private(set) var lastRenderedManifestPayload: WorkbenchPlotPayload?
    /// Sample keys snapshot from the render that produced currentPlotImageData.
    @ObservationIgnored
    private(set) var lastRenderedSampleKeys: [String] = []
    /// Per-sample conditions snapshot from the render.
    @ObservationIgnored
    private(set) var lastRenderedConditionsBySampleKey: [String: [String: String]] = [:]

    // MARK: - Private

    @ObservationIgnored
    private var plotTask: Task<Void, Never>?
    @ObservationIgnored
    private var artifactLoadTask: Task<Void, Never>?

    deinit {
        plotTask?.cancel()
        artifactLoadTask?.cancel()
    }

    // MARK: - Selection

    func toggleSearchHitSelection(_ id: String) {
        if selectedSearchResultIDs.contains(id) {
            selectedSearchResultIDs.remove(id)
        } else {
            selectedSearchResultIDs.insert(id)
        }
    }

    // MARK: - Plot

    func renderAHEPlot() {
        let selections = buildAHESelections()
        guard !selections.isEmpty else {
            plotMessage = "Select at least one AHE measurement to plot."
            return
        }
        // Capture overrides and context before leaving MainActor
        let xOverride = plotAxisXOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let yOverride = plotAxisYOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleOverride = plotTitleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedTemplate = titleTemplate
        // Build title tokens from representative hit
        let capturedTitleTokens: [String: String] = {
            let sortedHits = selections.sorted(by: { $0.sampleKey < $1.sampleKey })
            guard let hit = sortedHits.first,
                  let searchHit = cachedSearchResults.first(where: { $0.sampleKey == hit.sampleKey }) else { return [:] }
            var tokens: [String: String] = ["sample": searchHit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[searchHit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            return tokens
        }()
        let grid = showPlotGrid
        let legendAnchor = plotLegendAnchor
        let legendPoint = plotLegendPoint
        let labelOverrides = plotSeriesLabelOverrides
        let xLabelOverride = plotXLabelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let yLabelOverride = plotYLabelOverride.trimmingCharacters(in: .whitespacesAndNewlines)

        // Snapshot sampleKeys and conditions at render time (not at save time)
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

        plotTask?.cancel()
        isPlotRendering = true
        plotMessage = nil
        currentPlotImageData = nil
        currentRunTrace = nil
        persistenceOutcome = nil

        let seriesCount = selections.count
        plotTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (imageData, plotLayout, candidates, manifestPayload, extractedMetrics) = try await Task.detached(priority: .userInitiated) {
                    let ingestion = try IngestAHESelectionsUseCase().execute(
                        selections: selections,
                        xColumnOverride: xOverride.isEmpty ? nil : xOverride,
                        yColumnOverride: yOverride.isEmpty ? nil : yOverride
                    )
                    let extractedMetrics = try AHEWorkspaceStore.extractAHEMetricsPerSeries(from: ingestion.series).get()
                    let resolvedTitle: String = {
                        if !titleOverride.isEmpty { return titleOverride }
                        var tokens = capturedTitleTokens
                        tokens["tab"] = "AHE"
                        return WorkbenchTitleResolver.resolve(template: capturedTemplate, tokens: tokens)
                    }()
                    let xField = xOverride.isEmpty ? ingestion.defaultAxisMapping.xField : xOverride
                    let yField = yOverride.isEmpty ? ingestion.defaultAxisMapping.yField : yOverride
                    var style: [String: String] = [:]
                    if grid { style["showGrid"] = "true" }
                    if let lp = legendPoint {
                        style["legendX"] = String(format: "%.4f", lp.x)
                        style["legendY"] = String(format: "%.4f", lp.y)
                    } else if !legendAnchor.isEmpty {
                        style["legendAnchor"] = legendAnchor
                    }
                    var payload = BuildAHEPlotPayloadUseCase().execute(
                        ingestion: ingestion,
                        title: resolvedTitle,
                        axisMappingOverride: WorkbenchAxisMapping(xField: xField, yField: yField),
                        styleParams: style
                    )
                    // Preserve data-column axisMapping for manifest; label overrides are display-only.
                    let manifestAxisMapping = payload.axisMapping
                    // Apply display-only axis label overrides to payload before layout computation
                    if !xLabelOverride.isEmpty { payload.axisMapping.xField = xLabelOverride }
                    if !yLabelOverride.isEmpty { payload.axisMapping.yField = yLabelOverride }
                    // Compute layout BEFORE series label overrides so legendRow.originalLabel
                    // is the stable pre-override key used by plotSeriesLabelOverrides.
                    let rendererOptions = WorkbenchChartRenderer.Options()
                    let plotLayout = WorkbenchPlotLayout.compute(
                        options: rendererOptions, payload: payload, legendPoint: legendPoint
                    )
                    // Apply series label overrides (keyed by series index for per-row isolation)
                    if !labelOverrides.isEmpty {
                        payload.series = payload.series.enumerated().map { i, s in
                            guard let custom = labelOverrides[i] else { return s }
                            var copy = s; copy.label = custom; return copy
                        }
                    }
                    let png = try WorkbenchChartRenderer().renderPNG(payload: payload, options: rendererOptions)
                    // Build manifest payload with data-column axisMapping (not display overrides)
                    var manifestPayload = payload
                    manifestPayload.axisMapping = manifestAxisMapping
                    return (png, plotLayout, ingestion.candidateAxisFields, manifestPayload, extractedMetrics)
                }.value
                guard !Task.isCancelled else { return }
                self.currentPlotImageData = imageData
                self.currentPlotLayout = plotLayout
                self.currentCandidateAxisFields = candidates
                self.lastExtractedMetrics = extractedMetrics
                self.lastRenderedManifestPayload = manifestPayload
                self.lastRenderedSampleKeys = snapshotSampleKeys
                self.lastRenderedConditionsBySampleKey = snapshotConditions
                self.isPlotRendering = false
                self.plotMessage = "Rendered \(seriesCount) series."
            } catch is CancellationError {
                self.isPlotRendering = false
            } catch {
                self.currentPlotImageData = nil
                self.isPlotRendering = false
                self.plotMessage = "Plot failed: \(error.localizedDescription)"
            }
        }
    }

    func clearPlot() {
        plotTask?.cancel()
        plotTask = nil
        currentPlotImageData = nil
        currentRunTrace = nil
        persistenceOutcome = nil
        pendingMetricOverride = nil
        pendingRAHEOverride = nil
        lastExtractedMetrics = [:]
        isPlotRendering = false
        plotMessage = nil
        selectedSearchResultIDs = []
        currentCandidateAxisFields = []
        plotAxisXOverride = ""
        plotAxisYOverride = ""
        plotTitleOverride = ""
        showPlotGrid = false
        plotLegendAnchor = ""
        plotLegendPoint = nil
        plotSeriesLabelOverrides = [:]
        plotXLabelOverride = ""
        plotYLabelOverride = ""
        currentPlotLayout = nil
    }

    func loadPersistedArtifact(sampleKey: String) {
        guard !lastLibraryRootPath.isEmpty else { return }
        let libraryRootPath = lastLibraryRootPath

        artifactLoadTask?.cancel()
        isLoadingArtifact = true
        artifactLoadMessage = nil

        artifactLoadTask = Task { [weak self] in
            guard let self else { return }
            let artifact = await Task.detached(priority: .userInitiated) {
                let resolver = LibraryPathResolver(libraryRootURL: URL(filePath: libraryRootPath))
                return LoadLatestChartArtifactUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
            }.value
            guard !Task.isCancelled else { return }
            if let artifact {
                self.currentPlotImageData = artifact.imageData
                self.currentRunTrace = BuildRunTraceProjectionUseCase().execute(
                    manifest: artifact.manifest,
                    manifestPath: artifact.manifestPath
                )
                self.artifactLoadMessage = "Loaded saved chart for \(sampleKey)."
            } else {
                self.artifactLoadMessage = nil
            }
            self.isLoadingArtifact = false
        }
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

    // MARK: - Plot label / position overrides

    /// Overrides the display label for a series identified by its original label.
    /// Pass an empty or whitespace-only string to remove the override.
    func updateSeriesLabel(index: Int, newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            plotSeriesLabelOverrides.removeValue(forKey: index)
        } else {
            plotSeriesLabelOverrides[index] = trimmed
        }
        renderAHEPlot()
    }

    /// Updates the legend position and re-renders without persisting.
    /// `point` is normalized: (0,0) = bottom-left, (1,1) = top-right of the plot area.
    func updateLegendPoint(_ point: CGPoint) {
        plotLegendPoint = point
        renderAHEPlot()
    }

    /// Overrides the chart title displayed on the chart. Pass empty string to revert to default.
    func updatePlotTitle(_ title: String) {
        plotTitleOverride = title
        renderAHEPlot()
    }

    /// Overrides the X-axis display label without changing the data column.
    func updateXAxisLabel(_ label: String) {
        plotXLabelOverride = label
        renderAHEPlot()
    }

    /// Overrides the Y-axis display label without changing the data column.
    func updateYAxisLabel(_ label: String) {
        plotYLabelOverride = label
        renderAHEPlot()
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
                    workflowID: hit.workflowID
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

extension AHEWorkspaceStore: WorkbenchPlottingStore {}

// MARK: - ActiveChartProviding conformance

extension AHEWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? { currentPlotImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { lastRenderedManifestPayload }

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
