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

    /// Set after each `renderAHEPlot(persistArtifact: true)` call.
    /// Nil when no persist has occurred or after `clearPlot()`.
    private(set) var persistenceOutcome: PersistenceOutcome? = nil

    /// Incremented every time a persist completes (success or partial).
    /// Use this for `onChange` observation — avoids requiring `PersistenceOutcome: Equatable`.
    private(set) var persistCount: Int = 0

    // MARK: - Pre-persist metric override (V3.4.1)

    /// A pending manual correction the user has entered before clicking "Save to Library".
    /// When non-nil, `attemptPersist` wraps the extracted metric value in `WorkbenchMetricOverrideInfo`
    /// and writes `newValue` as the stored value. Cleared after a successful persist.
    var pendingMetricOverride: WorkbenchMetricOverrideCandidate? = nil

    /// The Hc value auto-extracted from the most recently rendered series.
    /// Updated on every render (including preview renders without persist).
    /// Displayed in the override panel so the user can see the algorithm result before deciding to correct it.
    private(set) var lastExtractedHc: Double? = nil

    /// A pending manual correction for the extracted R_AHE value.
    /// Mirrors `pendingMetricOverride` but for the R_AHE metric. Cleared after a successful persist.
    var pendingRAHEOverride: WorkbenchMetricOverrideCandidate? = nil

    /// The R_AHE value auto-extracted from the most recently rendered series.
    /// Updated on every render alongside `lastExtractedHc`.
    private(set) var lastExtractedRAHE: Double? = nil

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

    // MARK: - Context set by WorkbenchFeatureStore after search

    /// Updated by WorkbenchFeatureStore when search results change.
    /// Used by renderAHEPlot to build selections without coupling back to WFS.
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    /// Updated by WorkbenchFeatureStore when a search runs. Required for artifact I/O.
    var lastLibraryRootPath: String = ""

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

    func renderAHEPlot(persistArtifact: Bool = true) {
        let selections = buildAHESelections()
        guard !selections.isEmpty else {
            plotMessage = "Select at least one AHE measurement to plot."
            return
        }
        // Capture overrides and context before leaving MainActor
        let xOverride = plotAxisXOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let yOverride = plotAxisYOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleOverride = plotTitleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let grid = showPlotGrid
        let legendAnchor = plotLegendAnchor
        let legendPoint = plotLegendPoint
        let labelOverrides = plotSeriesLabelOverrides
        let xLabelOverride = plotXLabelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let yLabelOverride = plotYLabelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryRootPath = lastLibraryRootPath
        let savedTrace = currentRunTrace  // preserved when not persisting
        let allSampleKeys: [String] = {
            var seen = Set<String>()
            return selections.compactMap { seen.insert($0.sampleKey).inserted ? $0.sampleKey : nil }
        }()
        // Capture per-sample conditions for metric records (Fix-1: each sample uses its own conditions,
        // not firstConditions which caused wrong condition data for non-first samples).
        // First selection for each sampleKey wins (canonical keys from rule parser, Adj-8).
        let firstSampleKey = allSampleKeys.first ?? "unknown"
        let conditionsBySampleKey: [String: [String: String]] = {
            var map: [String: [String: String]] = [:]
            for sel in selections where map[sel.sampleKey] == nil {
                map[sel.sampleKey] = sel.conditions
            }
            return map
        }()
        // Generate runID once; passed into both chart and metric persistence (Adj-2)
        let runID = UUID().uuidString
        let generatedAt = Date()
        // Capture pending overrides before leaving MainActor; cleared after successful persist
        let capturedOverride = pendingMetricOverride
        let capturedRAHEOverride = pendingRAHEOverride

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
                let (imageData, plotLayout, candidates, outcome, extractedHc, extractedRAHE) = try await Task.detached(priority: .userInitiated) {
                    let ingestion = try IngestAHESelectionsUseCase().execute(
                        selections: selections,
                        xColumnOverride: xOverride.isEmpty ? nil : xOverride,
                        yColumnOverride: yOverride.isEmpty ? nil : yOverride
                    )
                    let (extractedHc, extractedRAHE) = AHEWorkspaceStore.extractAHEMetrics(from: ingestion.series)
                    let resolvedTitle = titleOverride.isEmpty ? "AHE" : titleOverride
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
                    let outcome: PersistenceOutcome?
                    if persistArtifact {
                        // Restore data-column axisMapping so the manifest records the actual
                        // data columns used, not the display-only label overrides.
                        var manifestPayload = payload
                        manifestPayload.axisMapping = manifestAxisMapping
                        outcome = AHEWorkspaceStore.attemptPersist(
                            png: png,
                            payload: manifestPayload,
                            extractedHc: extractedHc,
                            extractedRAHE: extractedRAHE,
                            firstSampleKey: firstSampleKey,
                            conditionsBySampleKey: conditionsBySampleKey,
                            pendingOverride: capturedOverride,
                            pendingRAHEOverride: capturedRAHEOverride,
                            libraryRootPath: libraryRootPath,
                            sampleKeys: allSampleKeys,
                            runID: runID,
                            generatedAt: generatedAt
                        )
                    } else {
                        outcome = nil
                    }
                    return (png, plotLayout, ingestion.candidateAxisFields, outcome, extractedHc, extractedRAHE)
                }.value
                guard !Task.isCancelled else { return }
                self.currentPlotImageData = imageData
                self.currentPlotLayout = plotLayout
                self.currentCandidateAxisFields = candidates
                self.lastExtractedHc = extractedHc
                self.lastExtractedRAHE = extractedRAHE
                self.isPlotRendering = false
                if let outcome {
                    self.persistenceOutcome = outcome
                    self.currentRunTrace = outcome.trace
                    switch outcome {
                    case .success:
                        self.pendingMetricOverride = nil   // clear after successful persist
                        self.pendingRAHEOverride = nil
                        self.persistCount += 1
                        self.plotMessage = "Rendered \(seriesCount) series."
                    case .partial(_, let metricError):
                        self.persistCount += 1
                        self.plotMessage = "Rendered \(seriesCount) series (metric write failed: \(metricError))."
                    case .failure(let msg):
                        self.plotMessage = "Persist failed: \(msg)."
                    }
                } else {
                    self.currentRunTrace = savedTrace
                    self.plotMessage = "Rendered \(seriesCount) series."
                }
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
        lastExtractedHc = nil
        lastExtractedRAHE = nil
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
        renderAHEPlot(persistArtifact: false)
    }

    /// Updates the legend position and re-renders without persisting.
    /// `point` is normalized: (0,0) = bottom-left, (1,1) = top-right of the plot area.
    func updateLegendPoint(_ point: CGPoint) {
        plotLegendPoint = point
        renderAHEPlot(persistArtifact: false)
    }

    /// Overrides the chart title displayed on the chart. Pass empty string to revert to default.
    func updatePlotTitle(_ title: String) {
        plotTitleOverride = title
        renderAHEPlot(persistArtifact: false)
    }

    /// Overrides the X-axis display label without changing the data column.
    func updateXAxisLabel(_ label: String) {
        plotXLabelOverride = label
        renderAHEPlot(persistArtifact: false)
    }

    /// Overrides the Y-axis display label without changing the data column.
    func updateYAxisLabel(_ label: String) {
        plotYLabelOverride = label
        renderAHEPlot(persistArtifact: false)
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
    private nonisolated static func attemptPersist(
        png: Data,
        payload: WorkbenchPlotPayload,
        extractedHc: Double,
        extractedRAHE: Double,
        firstSampleKey: String,
        conditionsBySampleKey: [String: [String: String]],
        pendingOverride: WorkbenchMetricOverrideCandidate?,
        pendingRAHEOverride: WorkbenchMetricOverrideCandidate?,
        libraryRootPath: String,
        sampleKeys: [String],
        runID: String,
        generatedAt: Date
    ) -> PersistenceOutcome {
        guard !libraryRootPath.isEmpty else {
            return .failure("Library root path not set")
        }
        let resolver = LibraryPathResolver(libraryRootURL: URL(filePath: libraryRootPath))
        let writer = AtomicFileWriter()

        // 1. Persist chart + manifest + results_index
        let chartResult: ChartArtifactPersistenceResult
        do {
            chartResult = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
                .execute(
                    sampleKeys: sampleKeys,
                    payload: payload,
                    imageData: png,
                    runID: runID,
                    generatedAt: generatedAt
                )
        } catch {
            return .failure(AppError.from(error, fallback: "Chart persist failed").localizedDescription)
        }

        let trace = BuildRunTraceProjectionUseCase().execute(
            manifest: chartResult.manifest,
            manifestPath: chartResult.manifestPath
        )

        // 2. Persist a metric record for single-sample renders only.
        //
        // Multi-sample renders are intentionally skipped: extractHcEstimate operates on
        // series.first, which belongs to one specific sample's curve. Writing that value into
        // every sample's measurement_data.json would record incorrect Hc for non-first samples.
        // Per-sample Hc extraction for multi-sample renders is deferred to a future iteration.
        guard sampleKeys.count == 1, let singleKey = sampleKeys.first else {
            return .success(trace: trace)
        }

        // Conditions are sourced per-sample from conditionsBySampleKey (Fix-1: canonical keys
        // from the rule parser, not alias keys — Adj-8).
        // If the user entered a manual correction, use the proposed value and record override info.
        let storedValue: Double
        let overrideInfo: WorkbenchMetricOverrideInfo?
        if let override = pendingOverride {
            storedValue = override.proposedValue
            overrideInfo = WorkbenchMetricOverrideInfo(
                oldValue: extractedHc,
                newValue: override.proposedValue,
                reason: override.reason,
                source: override.source,
                at: generatedAt
            )
        } else {
            storedValue = extractedHc
            overrideInfo = nil
        }

        let record = WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: singleKey,
            displayKey: singleKey,
            workflowID: payload.workflowID,
            metric: "Hc",
            value: storedValue,
            canonicalUnit: "T",
            conditions: conditionsBySampleKey[singleKey] ?? [:],
            generatedAt: generatedAt,
            runID: runID,
            overrideInfo: overrideInfo
        )
        do {
            try PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
                .execute(sampleKey: singleKey, record: record)
        } catch {
            return .partial(
                trace: trace,
                metricError: AppError.from(error, fallback: "Metric persist failed").localizedDescription
            )
        }

        // 3. Persist R_AHE metric record.
        let rAHEStoredValue: Double
        let rAHEOverrideInfo: WorkbenchMetricOverrideInfo?
        if let rOverride = pendingRAHEOverride {
            rAHEStoredValue = rOverride.proposedValue
            rAHEOverrideInfo = WorkbenchMetricOverrideInfo(
                oldValue: extractedRAHE,
                newValue: rOverride.proposedValue,
                reason: rOverride.reason,
                source: rOverride.source,
                at: generatedAt
            )
        } else {
            rAHEStoredValue = extractedRAHE
            rAHEOverrideInfo = nil
        }

        let rAHERecord = WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: singleKey,
            displayKey: singleKey,
            workflowID: payload.workflowID,
            metric: "R_AHE",
            value: rAHEStoredValue,
            canonicalUnit: "Ω",
            conditions: conditionsBySampleKey[singleKey] ?? [:],
            generatedAt: generatedAt,
            runID: runID,
            overrideInfo: rAHEOverrideInfo
        )
        do {
            try PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
                .execute(sampleKey: singleKey, record: rAHERecord)
        } catch {
            return .partial(
                trace: trace,
                metricError: AppError.from(error, fallback: "R_AHE metric persist failed").localizedDescription
            )
        }
        return .success(trace: trace)
    }

    /// Extracts both Hc and R_AHE from AHE series data in a single pass.
    ///
    /// **Shared background removal:**
    /// AHE measurements from PPMS carry a large ordinary-Hall background. Both metrics are
    /// derived from the background-corrected curve:
    ///
    ///   threshold = (ymin + ymax) / 2
    ///   y_shifted = y − threshold
    ///
    /// **Hc** — coercive field:
    /// Zero crossings on y_shifted found via linear interpolation. Full loop:
    /// Hc = (|Hc+| + |Hc-|) / 2. Partial loop: average of absolute crossings.
    /// Fallback: x at minimum |y_shifted|. Returns 0.0 for empty/single-point series.
    ///
    /// **R_AHE** — saturated Hall resistance amplitude:
    /// R_AHE = (plateau_top − plateau_bottom) / 2, where plateau regions are defined as
    /// |H| > 80 % of H_max on the shifted curve. Each plateau value is the median of all
    /// points in that region. Falls back to (ymax − ymin) / 2 if either plateau is empty.
    private nonisolated static func extractAHEMetrics(
        from series: [WorkbenchPlotSeries]
    ) -> (hc: Double, rAHE: Double) {
        guard let first = series.first, first.x.count > 1 else { return (0.0, 0.0) }
        let xs = first.x
        let rawYs = first.y

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
