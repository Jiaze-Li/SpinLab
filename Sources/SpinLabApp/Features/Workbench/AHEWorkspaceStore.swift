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

        plotTask?.cancel()
        isPlotRendering = true
        plotMessage = nil
        currentPlotImageData = nil
        currentRunTrace = nil

        let seriesCount = selections.count
        plotTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (imageData, plotLayout, candidates, trace) = try await Task.detached(priority: .userInitiated) {
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
                    let trace: WorkbenchRunTraceProjection?
                    if persistArtifact {
                        trace = AHEWorkspaceStore.attemptPersistAndTrace(
                            png: png, payload: payload,
                            libraryRootPath: libraryRootPath, sampleKeys: allSampleKeys
                        )
                    } else {
                        trace = savedTrace  // legend reposition: preserve existing trace
                    }
                    return (png, plotLayout, ingestion.candidateAxisFields, trace)
                }.value
                guard !Task.isCancelled else { return }
                self.currentPlotImageData = imageData
                self.currentPlotLayout = plotLayout
                self.currentCandidateAxisFields = candidates
                self.currentRunTrace = trace
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

    private nonisolated static func attemptPersistAndTrace(
        png: Data,
        payload: WorkbenchPlotPayload,
        libraryRootPath: String,
        sampleKeys: [String]
    ) -> WorkbenchRunTraceProjection? {
        guard !libraryRootPath.isEmpty else { return nil }
        let resolver = LibraryPathResolver(libraryRootURL: URL(filePath: libraryRootPath))
        let useCase = PersistChartArtifactUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
        guard let result = try? useCase.execute(sampleKeys: sampleKeys, payload: payload, imageData: png) else {
            return nil
        }
        return BuildRunTraceProjectionUseCase().execute(
            manifest: result.manifest,
            manifestPath: result.manifestPath
        )
    }
}
