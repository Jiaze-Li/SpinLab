import Foundation
import Observation

// MARK: - Pack types (Gate H4: RSM pack/restore runtime integration)

struct RSMPackConfig: Codable, SearchQueryTextInjectable {
    var packState: RSMPackState
    var displayState: HeatmapTabRenderState
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    var searchQueryText: String = ""
}

struct RSMPackResult: Codable {}

// MARK: - RSMWorkspaceStore

/// Workspace store for the RSM (Reciprocal Space Map) workflow.
///
/// Wires RSMDataParser → RSMHeatmapPayloadBuilder → HeatmapRenderPipeline → WorkbenchPlotCanvas.
/// Single-file workflow: the first selected hit is used.
/// layout passed to WorkbenchPlotCanvas is always nil — heatmap V1 has no hit-testing.
@MainActor
@Observable
final class RSMWorkspaceStore: WorkbenchSaveCoordinating {

    // MARK: - Search / Selection bridge

    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    @ObservationIgnored weak var selectionReading: (any SelectionReading)?

    // MARK: - Analysis state

    private(set) var parsedDataset: CanonicalRSMDataset?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?
    var saveMessage: String?

    // MARK: - View selection (HL / KL / HK)

    var activeView: RSMView = .hl

    // MARK: - Render output

    private(set) var renderedImageData: Data?

    // MARK: - Warnings / trace

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()
    var currentRunTrace: WorkbenchRunTraceProjection?

    // MARK: - Heatmap display state (Plot System-owned, persisted in pack)

    var heatmapDisplayState: HeatmapTabRenderState = .init()
    /// Shared font defaults mirrored from the workbench. Not part of pack state.
    var globalPlotDefaults: [String: String] = [:]

    // MARK: - Pack / persistence stubs

    @ObservationIgnored var vault: AnalysisVault?
    var activePackID: AnalysisPack.ID?
    private(set) var persistenceOutcome: PersistenceOutcome?

    // MARK: - Context

    var lastLibraryRootPath: String = ""
    var cachedSampleNumericDisplay: [String: [String: String]] = [:]

    // MARK: - Internal

    @ObservationIgnored private(set) var cachedInputFiles: [String] = []
    @ObservationIgnored private(set) var cachedSampleKeys: [String] = []
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var _renderRevision: UInt64 = 0

    deinit { analysisTask?.cancel() }

    // MARK: - WorkbenchSaveCoordinating

    func refreshRelatedCharts() {}

    func applyPersistenceOutcome(_ outcome: PersistenceOutcome) {
        persistenceOutcome = outcome
    }

    // MARK: - Core

    func runAnalysis() {
        runAnalysis(searchSnapshot: nil)
    }

    func rerenderForStyleChange() {
        guard let dataset = parsedDataset else { return }
        _rerenderHeatmap(dataset: dataset)
    }

    func updateHeatmapColorScaleMode(_ mode: HeatmapColorScaleMode) {
        guard heatmapDisplayState.colorScaleMode != mode else { return }
        heatmapDisplayState.colorScaleMode = mode
        rerenderForStyleChange()
    }

    func updateHeatmapTitle(_ title: String) {
        guard heatmapDisplayState.titleOverride != title else { return }
        heatmapDisplayState.titleOverride = title
        rerenderForStyleChange()
    }

    func updateHeatmapXAxisLabel(_ label: String) {
        guard heatmapDisplayState.xLabelOverride != label else { return }
        heatmapDisplayState.xLabelOverride = label
        rerenderForStyleChange()
    }

    func updateHeatmapYAxisLabel(_ label: String) {
        guard heatmapDisplayState.yLabelOverride != label else { return }
        heatmapDisplayState.yLabelOverride = label
        rerenderForStyleChange()
    }

    func updateHeatmapZLabel(_ label: String) {
        guard heatmapDisplayState.zLabelOverride != label else { return }
        heatmapDisplayState.zLabelOverride = label
        rerenderForStyleChange()
    }

    func updateHeatmapShowColorbar(_ isShown: Bool) {
        guard heatmapDisplayState.showColorbar != isShown else { return }
        heatmapDisplayState.showColorbar = isShown
        rerenderForStyleChange()
    }

    func updateHeatmapXTickCount(_ count: Int) {
        let clamped = PlotTickConfiguration.clamp(count)
        guard heatmapDisplayState.xTickCount != clamped else { return }
        heatmapDisplayState.xTickCount = clamped
        rerenderForStyleChange()
    }

    func updateHeatmapYTickCount(_ count: Int) {
        let clamped = PlotTickConfiguration.clamp(count)
        guard heatmapDisplayState.yTickCount != clamped else { return }
        heatmapDisplayState.yTickCount = clamped
        rerenderForStyleChange()
    }

    func updateHeatmapZDomainState(_ state: HeatmapZDomainState) {
        guard heatmapDisplayState.zDomainState != state else { return }
        heatmapDisplayState.zDomainState = state
        rerenderForStyleChange()
    }

    func clearPlot() {
        analysisTask?.cancel()
        analysisTask = nil
        parsedDataset = nil
        renderedImageData = nil
        currentRunTrace = nil
        isAnalyzing = false
        analysisMessage = nil
        saveMessage = nil
        warningLog.clear()
        activePackID = nil
        persistenceOutcome = nil
        cachedInputFiles = []
        cachedSampleKeys = []
    }

    func clearResults() {
        cachedSearchResults = []
        cachedSampleNumericDisplay = [:]
    }

    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = renderedImageData else {
            saveMessage = "No chart to save. Run analysis first."
            return
        }
        guard !cachedSampleKeys.isEmpty else {
            saveMessage = "No sample keys. Run analysis first."
            return
        }
        let view = activeView
        let displayState = heatmapDisplayState
        let title = displayState.titleOverride.isEmpty
            ? (parsedDataset?.title ?? view.rawValue.uppercased())
            : displayState.titleOverride
        let xLabel = displayState.xLabelOverride.isEmpty ? view.xLabel : displayState.xLabelOverride
        let yLabel = displayState.yLabelOverride.isEmpty ? view.yLabel : displayState.yLabelOverride
        let zLabel = displayState.zLabelOverride.isEmpty
            ? Self.publicationZLabel(for: parsedDataset?.detectorColumnName ?? "")
            : displayState.zLabelOverride
        let projection = RSMSaveProjection(
            workflowID: "rsm",
            title: title,
            activeView: view,
            detectorColumnName: parsedDataset?.detectorColumnName ?? "",
            xLabel: xLabel,
            yLabel: yLabel,
            zLabel: zLabel,
            sourceFileIdentity: cachedInputFiles.first,
            semanticParams: ["view": view.rawValue]
        )
        executeRSMSave(
            input: SaveRSMChartInput(
                png: png,
                projection: projection,
                sampleKeys: cachedSampleKeys,
                libraryRootPath: lastLibraryRootPath
            ),
            onComplete: onComplete
        )
    }

    // MARK: - Private render

    private func _rerenderHeatmap(dataset: CanonicalRSMDataset) {
        let view = activeView
        let displayState = heatmapDisplayState
        let styleDefaults = globalPlotDefaults
        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) {
            let result: Result<Data, Error>
            do {
                let payload = try Self.buildHeatmapPayload(
                    from: dataset,
                    view: view,
                    displayState: displayState,
                    title: dataset.title
                )
                let output = try Self.renderHeatmap(
                    payload: payload,
                    displayState: displayState,
                    globalPlotDefaults: styleDefaults
                )
                result = .success(output.imageData)
            } catch {
                result = .failure(error)
            }

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                switch result {
                case .success(let data):
                    self.renderedImageData = data
                case .failure(let error):
                    self.appendWarning(source: "Render", message: error.localizedDescription)
                    self.renderedImageData = nil
                }
            }
        }
    }
}

// MARK: - WorkbenchWorkspaceProviding

extension RSMWorkspaceStore: WorkbenchWorkspaceProviding {

    func runAnalysis(searchSnapshot: WorkbenchSearchSnapshot?) {
        let sourceHits = searchSnapshot?.results ?? cachedSearchResults
        let selectedHits: [WorkflowMeasurementSearchHit]
        if let reading = selectionReading {
            let ids = reading.selectedIDs(for: .rsm)
            selectedHits = sourceHits
                .filter { ids.contains($0.id) }
                .sorted { $0.measurementFilePath < $1.measurementFilePath }
        } else {
            selectedHits = sourceHits.sorted { $0.measurementFilePath < $1.measurementFilePath }
        }
        _runAnalysis(hits: selectedHits)
    }

    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot?) {
        let hits = (selectedHitsSnapshot?.selectedHits ?? [])
            .sorted { $0.measurementFilePath < $1.measurementFilePath }
        _runAnalysis(hits: hits)
    }

    private func _runAnalysis(hits: [WorkflowMeasurementSearchHit]) {
        guard let hit = hits.first else {
            analysisMessage = "No files selected."
            return
        }

        let filePath = hit.measurementFilePath
        let title = hit.sampleBatchAndSubstrate
        let view = activeView
        let displayState = heatmapDisplayState
        let styleDefaults = globalPlotDefaults

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        saveMessage = nil
        renderedImageData = nil
        _renderRevision &+= 1
        let revision = _renderRevision
        warningLog.clear()

        analysisTask = Task { [weak self] in
            let parsed = await Task.detached(priority: .userInitiated) {
                () -> Result<(CanonicalRSMDataset, Data, RSMView), Error> in
                do {
                    let text = try String(contentsOfFile: filePath, encoding: .utf8)
                    let dataset = try RSMDataParser.parse(text: text, title: title, sourceRef: filePath)
                    // Auto-correct view if the data's fixed axis conflicts with the chosen view.
                    let effectiveView = dataset.isViewCompatible(view) ? view : dataset.recommendedView
                    let payload = try Self.buildHeatmapPayload(
                        from: dataset,
                        view: effectiveView,
                        displayState: displayState,
                        title: title
                    )
                    let output = try Self.renderHeatmap(
                        payload: payload,
                        displayState: displayState,
                        globalPlotDefaults: styleDefaults
                    )
                    return .success((dataset, output.imageData, effectiveView))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled, self._renderRevision == revision else { return }

            switch parsed {
            case .success(let (dataset, imageData, usedView)):
                self.parsedDataset = dataset
                self.renderedImageData = imageData
                if usedView != view {
                    self.activeView = usedView
                    self.analysisMessage = "Auto-selected \(usedView.rawValue.uppercased()) view (data is a \(usedView.rawValue.uppercased())-plane scan)."
                } else {
                    self.analysisMessage = "Rendered \(view.rawValue.uppercased()) heatmap."
                }
                self.cachedInputFiles = [filePath]
                self.cachedSampleKeys = [hit.sampleKey]
                self.commitRunTrace()

            case .failure(let error):
                self.parsedDataset = nil
                self.renderedImageData = nil
                let msg: String
                if let e = error as? RSMDataParser.ParseError {
                    msg = e.errorDescription ?? e.localizedDescription
                } else if let e = error as? RSMHeatmapPayloadBuilderError {
                    msg = e.errorDescription ?? e.localizedDescription
                } else {
                    msg = error.localizedDescription
                }
                self.appendWarning(source: "RSM", message: msg)
                self.analysisMessage = "RSM render failed."
            }

            self.isAnalyzing = false
        }
    }

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard !cachedInputFiles.isEmpty else { return nil }
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: "rsm",
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(xField: activeView.xLabel, yField: activeView.yLabel),
            semanticParams: ["view": activeView.rawValue],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }

    var activeImageData: Data? { renderedImageData }
    var activeLayout: WorkbenchPlotLayout? { nil }
    var seriesLabelOverrides: [String: String] { [:] }
    var relatedCharts: [WorkbenchResultReference]? { nil }
    var libraryRootURL: URL? {
        lastLibraryRootPath.isEmpty ? nil : URL(fileURLWithPath: lastLibraryRootPath)
    }
}

// MARK: - ActiveChartProviding

extension RSMWorkspaceStore: ActiveChartProviding {
    var activeChartPNG: Data? { renderedImageData }
    var activeChartManifestPayload: WorkbenchPlotPayload? { nil }
    var activeChartSampleKeys: [String] { cachedSampleKeys }
    func buildActiveChartMetrics() -> [PendingMetricEntry] { [] }
}

// MARK: - AnalysisPackProviding

extension RSMWorkspaceStore: AnalysisPackProviding {
    typealias PackConfig = RSMPackConfig
    typealias PackResult = RSMPackResult

    var packWorkflowID: String { "rsm" }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var hasAnalysisResult: Bool { renderedImageData != nil }

    func buildPackConfig() -> RSMPackConfig {
        RSMPackConfig(
            packState: RSMPackState(
                sourceFileIdentity: cachedInputFiles.first,
                detectorColumnName: parsedDataset?.detectorColumnName ?? "",
                activeView: activeView
            ),
            displayState: heatmapDisplayState,
            cachedSearchResults: cachedSearchResults
        )
    }

    func buildPackResult() -> RSMPackResult { RSMPackResult() }
    func autoPackLabel() -> String { cachedSearchResults.first?.sampleBatchAndSubstrate ?? "RSM" }

    func restoreFromPack(
        config: RSMPackConfig,
        result: RSMPackResult,
        pack: AnalysisPack,
        restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
        seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void
    ) {
        activeView = config.packState.activeView
        heatmapDisplayState = config.displayState
        cachedSearchResults = config.cachedSearchResults
        cachedInputFiles = pack.filePaths
        cachedSampleKeys = pack.sampleKeys

        seedSelection([], config.cachedSearchResults)
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        guard let sourceIdentity = config.packState.sourceFileIdentity, !sourceIdentity.isEmpty else {
            return
        }

        let packState = config.packState
        let displayState = config.displayState
        let styleDefaults = globalPlotDefaults
        let title = config.cachedSearchResults.first?.sampleBatchAndSubstrate ?? pack.label

        analysisTask?.cancel()
        isAnalyzing = true
        renderedImageData = nil
        _renderRevision &+= 1
        let revision = _renderRevision
        warningLog.clear()

        analysisTask = Task { [weak self] in
            let parsed = await Task.detached(priority: .userInitiated) {
                () -> Result<(CanonicalRSMDataset, Data), Error> in
                do {
                    let text = try String(contentsOfFile: sourceIdentity, encoding: .utf8)
                    let dataset = try RSMDataParser.parse(text: text, title: title, sourceRef: sourceIdentity)
                    let payload = try Self.buildHeatmapPayload(
                        from: dataset,
                        view: packState.activeView,
                        displayState: displayState,
                        title: title
                    )
                    let output = try Self.renderHeatmap(
                        payload: payload,
                        displayState: displayState,
                        globalPlotDefaults: styleDefaults
                    )
                    return .success((dataset, output.imageData))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled, self._renderRevision == revision else { return }

            switch parsed {
            case .success(let (dataset, imageData)):
                self.parsedDataset = dataset
                self.renderedImageData = imageData
                self.isAnalyzing = false
                self.commitRunTrace()
            case .failure(let error):
                self.parsedDataset = nil
                self.renderedImageData = nil
                self.appendWarning(source: "RSM Restore", message: error.localizedDescription)
                self.isAnalyzing = false
            }
        }
    }

    /// Maps a raw detector column name to a publication-standard default label.
    /// "Detector" (case-insensitive) and empty strings map to "Intensity (counts)";
    /// all other names are preserved as-is.
    nonisolated static func publicationZLabel(for detectorColumnName: String) -> String {
        let lower = detectorColumnName.lowercased()
        if lower == "detector" || lower.isEmpty {
            return "Intensity (counts)"
        }
        return detectorColumnName
    }

    nonisolated private static func buildHeatmapPayload(
        from dataset: CanonicalRSMDataset,
        view: RSMView,
        displayState: HeatmapTabRenderState,
        title: String
    ) throws -> HeatmapPlotPayload {
        let baseZLabel = displayState.zLabelOverride.isEmpty
            ? Self.publicationZLabel(for: dataset.detectorColumnName)
            : displayState.zLabelOverride
        var payload = try RSMHeatmapPayloadBuilder.build(
            from: dataset,
            options: .init(
                view: view,
                title: displayState.titleOverride.isEmpty ? title : displayState.titleOverride,
                zLabel: baseZLabel
            )
        )

        if !displayState.xLabelOverride.isEmpty { payload.xLabel = displayState.xLabelOverride }
        if !displayState.yLabelOverride.isEmpty { payload.yLabel = displayState.yLabelOverride }
        if !displayState.colormapKey.isEmpty { payload.colormapKey = displayState.colormapKey }

        return payload
    }

    nonisolated private static func renderHeatmap(
        payload: HeatmapPlotPayload,
        displayState: HeatmapTabRenderState,
        globalPlotDefaults: [String: String]
    ) throws -> HeatmapRenderPipeline.Output {
        return try HeatmapRenderPipeline.render(.init(
            payload: payload,
            colorScaleMode: displayState.colorScaleMode,
            zDomainState: displayState.zDomainState,
            chartStyle: WorkbenchChartStyle.from(styleParams: globalPlotDefaults),
            showColorbar: displayState.showColorbar,
            xTickCount: displayState.xTickCount,
            yTickCount: displayState.yTickCount
        ))
    }
}
