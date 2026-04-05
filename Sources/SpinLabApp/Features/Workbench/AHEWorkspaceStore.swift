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
    var plotSeriesLabelOverrides: [String: String] = [:]
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
        // Capture pending override before leaving MainActor; cleared after successful persist
        let capturedOverride = pendingMetricOverride

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
                let (imageData, plotLayout, candidates, outcome) = try await Task.detached(priority: .userInitiated) {
                    let ingestion = try IngestAHESelectionsUseCase().execute(
                        selections: selections,
                        xColumnOverride: xOverride.isEmpty ? nil : xOverride,
                        yColumnOverride: yOverride.isEmpty ? nil : yOverride
                    )
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
                    // Apply series label overrides (keyed by original label, stable across re-renders)
                    if !labelOverrides.isEmpty {
                        payload.series = payload.series.map { s in
                            guard let custom = labelOverrides[s.label] else { return s }
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
                            ingestionSeries: ingestion.series,
                            firstSampleKey: firstSampleKey,
                            conditionsBySampleKey: conditionsBySampleKey,
                            pendingOverride: capturedOverride,
                            libraryRootPath: libraryRootPath,
                            sampleKeys: allSampleKeys,
                            runID: runID,
                            generatedAt: generatedAt
                        )
                    } else {
                        outcome = nil
                    }
                    return (png, plotLayout, ingestion.candidateAxisFields, outcome)
                }.value
                guard !Task.isCancelled else { return }
                self.currentPlotImageData = imageData
                self.currentPlotLayout = plotLayout
                self.currentCandidateAxisFields = candidates
                self.isPlotRendering = false
                if let outcome {
                    self.persistenceOutcome = outcome
                    self.currentRunTrace = outcome.trace
                    switch outcome {
                    case .success:
                        self.pendingMetricOverride = nil   // clear after successful persist
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
    func updateSeriesLabel(originalLabel: String, newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == originalLabel {
            plotSeriesLabelOverrides.removeValue(forKey: originalLabel)
        } else {
            plotSeriesLabelOverrides[originalLabel] = trimmed
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
        ingestionSeries: [WorkbenchPlotSeries],
        firstSampleKey: String,
        conditionsBySampleKey: [String: [String: String]],
        pendingOverride: WorkbenchMetricOverrideCandidate?,
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

        // 2. Extract Hc estimate and persist a metric record for every sample key.
        // Conditions are sourced per-sample from conditionsBySampleKey (Fix-1: canonical keys
        // from the rule parser, not alias keys — Adj-8). Each sample gets its own
        // measurement_data.json entry so results_index coverage matches metric coverage.
        let extractedHc = extractHcEstimate(from: ingestionSeries)
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

        let metricUseCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
        var metricErrors: [String] = []
        for sk in sampleKeys {
            let record = WorkbenchMetricRecord(
                recordID: UUID().uuidString,
                sampleKey: sk,
                displayKey: sk,
                workflowID: payload.workflowID,
                metric: "Hc",
                value: storedValue,
                canonicalUnit: "T",
                conditions: conditionsBySampleKey[sk] ?? [:],
                generatedAt: generatedAt,
                runID: runID,
                overrideInfo: overrideInfo
            )
            do {
                try metricUseCase.execute(sampleKey: sk, record: record)
            } catch {
                metricErrors.append("\(sk): \(AppError.from(error, fallback: "Metric persist failed").localizedDescription)")
            }
        }

        if !metricErrors.isEmpty {
            return .partial(trace: trace, metricError: metricErrors.joined(separator: "; "))
        }
        return .success(trace: trace)
    }

    /// Estimates the coercive field Hc from AHE series data.
    ///
    /// Hc is the x-value at which the Hall resistance (y) crosses zero.
    /// Uses linear interpolation between the two adjacent points that straddle the zero crossing.
    /// Falls back to the x-value at minimum |y| if no zero crossing is found.
    /// Returns 0.0 if the series is empty.
    private nonisolated static func extractHcEstimate(from series: [WorkbenchPlotSeries]) -> Double {
        guard let first = series.first, first.x.count > 1 else { return 0.0 }
        let xs = first.x
        let ys = first.y
        for i in 0..<xs.count - 1 {
            let y0 = ys[i], y1 = ys[i + 1]
            if y0 * y1 <= 0, y0 != y1 {
                let t = y0 / (y0 - y1)
                return xs[i] + t * (xs[i + 1] - xs[i])
            }
        }
        // Fallback: x at minimum |y|
        var minAbs = Double.infinity
        var result = 0.0
        for i in 0..<xs.count {
            let a = abs(ys[i])
            if a < minAbs { minAbs = a; result = xs[i] }
        }
        return result
    }
}
