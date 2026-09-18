import Foundation
import Observation

// MARK: - Pack types (Phase 4D)

struct AFMPackResult: Codable {
    /// The full parsed ingestion result, so restore never re-reads/re-parses the source `.ibw`
    /// file — everything needed to reprocess and rerender comes from here plus
    /// `AFMPackState.processingConfiguration`.
    var canonicalDataset: CanonicalAFMDataset?

    init(canonicalDataset: CanonicalAFMDataset? = nil) {
        self.canonicalDataset = canonicalDataset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canonicalDataset = try c.decodeIfPresent(CanonicalAFMDataset.self, forKey: .canonicalDataset)
    }

    private enum CodingKeys: String, CodingKey {
        case canonicalDataset
    }
}

struct AFMPackConfig: Codable, SearchQueryTextInjectable {
    var packState: AFMPackState
    var displayState: HeatmapTabRenderState
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    var searchQueryText: String = ""
    var selectedSearchResultIDs: [String] = []

    init(
        packState: AFMPackState,
        displayState: HeatmapTabRenderState,
        cachedSearchResults: [WorkflowMeasurementSearchHit] = [],
        searchQueryText: String = "",
        selectedSearchResultIDs: [String] = []
    ) {
        self.packState = packState
        self.displayState = displayState
        self.cachedSearchResults = cachedSearchResults
        self.searchQueryText = searchQueryText
        self.selectedSearchResultIDs = selectedSearchResultIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packState = try c.decode(AFMPackState.self, forKey: .packState)
        displayState = try c.decode(HeatmapTabRenderState.self, forKey: .displayState)
        cachedSearchResults = try c.decodeIfPresent([WorkflowMeasurementSearchHit].self, forKey: .cachedSearchResults) ?? []
        searchQueryText = try c.decodeIfPresent(String.self, forKey: .searchQueryText) ?? ""
        selectedSearchResultIDs = try c.decodeIfPresent([String].self, forKey: .selectedSearchResultIDs) ?? []
    }
}

// MARK: - AFMWorkspaceStore

/// Workspace store for the AFM (single-file heatmap) workflow.
///
/// Wires AFMInputAdapter -> CanonicalAFMDataset -> AFMProcessingPipeline ->
/// AFMHeatmapPayloadBuilder -> HeatmapRenderPipeline -> WorkbenchPlotCanvas. Single-file
/// workflow, following RSMWorkspaceStore's structure. `parsedDataset` is parsed exactly once
/// per Analyze/pack-restore and never mutated; every processing-option or channel change
/// reprocesses from it without re-reading the source file. layout passed to WorkbenchPlotCanvas
/// is always nil — heatmap V1 has no hit-testing.
@MainActor
@Observable
final class AFMWorkspaceStore: WorkbenchSaveCoordinating {

    // MARK: - Search / Selection bridge

    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    @ObservationIgnored weak var selectionReading: (any SelectionReading)?

    // MARK: - Analysis state

    private(set) var parsedDataset: CanonicalAFMDataset?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?
    var saveMessage: String?
    @ObservationIgnored var packRestoreErrorMessage: String? = nil

    // MARK: - AFM processing configuration (Phase 3)

    var processingConfiguration: AFMProcessingConfiguration = AFMProcessingConfiguration(activeChannelID: "")

    // MARK: - Render output

    private(set) var renderedImageData: Data?
    private(set) var renderedPdfData: Data?

    // MARK: - Warnings / trace

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()
    var currentRunTrace: WorkbenchRunTraceProjection?

    // MARK: - Heatmap display state (Plot System-owned, persisted in pack)

    var heatmapDisplayState: HeatmapTabRenderState = .init()
    var globalPlotDefaults: [String: String] = [:]

    // MARK: - Identity

    let workflowID: String

    init(workflowID: String) {
        self.workflowID = workflowID
    }

    // MARK: - Pack / persistence

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

    // MARK: - Channel / processing controls
    //
    // None of these re-read the source file — every one reprocesses `parsedDataset` in place.
    // See AFMProcessingPipeline: it always takes the immutable CanonicalAFMChannel as input.

    var activeChannel: CanonicalAFMChannel? {
        parsedDataset?.channels.first { $0.id == processingConfiguration.activeChannelID }
    }

    func updateActiveChannel(_ channelID: String) {
        guard processingConfiguration.activeChannelID != channelID else { return }
        processingConfiguration.activeChannelID = channelID
        reprocessAndRerender()
    }

    func updatePlaneLevelEnabled(_ enabled: Bool) {
        guard processingConfiguration.planeLevelEnabled != enabled else { return }
        processingConfiguration.planeLevelEnabled = enabled
        reprocessAndRerender()
    }

    func updateLineFlattenOrder(_ order: AFMLineFlattenOrder) {
        guard processingConfiguration.lineFlattenOrder != order else { return }
        processingConfiguration.lineFlattenOrder = order
        reprocessAndRerender()
    }

    func updateZeroReference(_ reference: AFMZeroReference) {
        guard processingConfiguration.zeroReference != reference else { return }
        processingConfiguration.zeroReference = reference
        reprocessAndRerender()
    }

    // MARK: - Heatmap display-only controls (rerender only, never reprocess AFM data)

    func rerenderForStyleChange() {
        reprocessAndRerender()
    }

    func updateHeatmapColorScaleMode(_ mode: HeatmapColorScaleMode) {
        guard heatmapDisplayState.colorScaleMode != mode else { return }
        heatmapDisplayState.colorScaleMode = mode
        rerenderForStyleChange()
    }

    func updateHeatmapInterpolationMode(_ mode: HeatmapInterpolationMode) {
        guard heatmapDisplayState.interpolationMode != mode else { return }
        heatmapDisplayState.interpolationMode = mode
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

    func updateHeatmapShowTitle(_ isShown: Bool) {
        guard heatmapDisplayState.showTitle != isShown else { return }
        heatmapDisplayState.showTitle = isShown
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
        processingConfiguration = AFMProcessingConfiguration(activeChannelID: "")
        renderedImageData = nil
        renderedPdfData = nil
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
        let displayState = heatmapDisplayState
        let channel = activeChannel
        let title = displayState.titleOverride.isEmpty
            ? (parsedDataset?.title ?? "AFM")
            : displayState.titleOverride
        let xLabel = displayState.xLabelOverride.isEmpty ? "X (\(CanonicalAFMDataset.xUnit))" : displayState.xLabelOverride
        let yLabel = displayState.yLabelOverride.isEmpty ? "Y (\(CanonicalAFMDataset.yUnit))" : displayState.yLabelOverride
        let zLabel = displayState.zLabelOverride.isEmpty
            ? (channel.map { "\($0.displayLabel) (\($0.canonicalUnit))" } ?? "")
            : displayState.zLabelOverride
        let projection = AFMSaveProjection(
            workflowID: workflowID,
            title: title,
            activeChannelID: processingConfiguration.activeChannelID,
            channelSemanticType: channel?.semanticTypeRaw,
            xLabel: xLabel,
            yLabel: yLabel,
            zLabel: zLabel,
            sourceFileIdentity: cachedInputFiles.first,
            semanticParams: [
                "planeLevel": String(processingConfiguration.planeLevelEnabled),
                "lineFlatten": processingConfiguration.lineFlattenOrder.rawValue,
                "zeroReference": processingConfiguration.zeroReference.rawValue,
            ]
        )
        executeAFMSave(
            input: SaveAFMChartInput(
                png: png,
                projection: projection,
                sampleKeys: cachedSampleKeys,
                libraryRootPath: lastLibraryRootPath
            ),
            onComplete: onComplete
        )
    }

    // MARK: - Private render

    /// Reprocesses the active channel from the immutable `parsedDataset` with the current
    /// `processingConfiguration` and rerenders. Never re-reads the source file. Safe to call for
    /// both AFM processing-option changes and Heatmap display-only changes.
    private func reprocessAndRerender() {
        guard let dataset = parsedDataset else { return }
        guard let channel = dataset.channels.first(where: { $0.id == processingConfiguration.activeChannelID }) else {
            renderedImageData = nil
            renderedPdfData = nil
            return
        }
        let config = processingConfiguration
        let displayState = heatmapDisplayState
        let styleDefaults = globalPlotDefaults
        let capturedWorkflowID = workflowID
        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) {
            let result: Result<(Data, Data, [String]), Error>
            do {
                let processed = AFMProcessingPipeline.process(
                    channel: channel,
                    xCoordinates: dataset.xCoordinates,
                    yCoordinates: dataset.yCoordinates,
                    configuration: config
                )
                let payload = try Self.buildHeatmapPayload(
                    dataset: dataset, processed: processed, workflowID: capturedWorkflowID, displayState: displayState
                )
                let output = try Self.renderHeatmap(payload: payload, displayState: displayState, globalPlotDefaults: styleDefaults)
                result = .success((output.imageData, output.pdfData, processed.warnings))
            } catch {
                result = .failure(error)
            }

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                switch result {
                case .success(let (data, pdf, warnings)):
                    self.renderedImageData = data
                    self.renderedPdfData = pdf
                    for warning in warnings {
                        self.appendWarning(source: "AFM Processing", message: warning)
                    }
                case .failure(let error):
                    self.appendWarning(source: "Render", message: error.localizedDescription)
                    self.renderedImageData = nil
                    self.renderedPdfData = nil
                }
            }
        }
    }

    nonisolated private static func buildHeatmapPayload(
        dataset: CanonicalAFMDataset,
        processed: ProcessedAFMChannel,
        workflowID: String,
        displayState: HeatmapTabRenderState
    ) throws -> HeatmapPlotPayload {
        var payload = try AFMHeatmapPayloadBuilder.build(
            dataset: dataset,
            processed: processed,
            options: .init(
                workflowID: workflowID,
                title: displayState.titleOverride,
                zLabel: displayState.zLabelOverride
            )
        )
        if !displayState.xLabelOverride.isEmpty { payload.xLabel = displayState.xLabelOverride }
        if !displayState.yLabelOverride.isEmpty { payload.yLabel = displayState.yLabelOverride }
        if let colormapOverride = displayState.colormapKey { payload.colormapKey = colormapOverride }
        return payload
    }

    nonisolated private static func renderHeatmap(
        payload: HeatmapPlotPayload,
        displayState: HeatmapTabRenderState,
        globalPlotDefaults: [String: String]
    ) throws -> HeatmapRenderPipeline.Output {
        try HeatmapRenderPipeline.render(.init(
            payload: payload,
            colorScaleMode: displayState.colorScaleMode,
            zDomainState: displayState.zDomainState,
            chartStyle: WorkbenchChartStyle.from(styleParams: globalPlotDefaults),
            showColorbar: displayState.showColorbar,
            showTitle: displayState.showTitle,
            xTickCount: displayState.xTickCount,
            yTickCount: displayState.yTickCount,
            interpolationMode: displayState.interpolationMode
        ))
    }
}

// MARK: - WorkbenchWorkspaceProviding

extension AFMWorkspaceStore: WorkbenchWorkspaceProviding {

    func runAnalysis(selectedHitsSnapshot: WorkbenchSelectedHitsSnapshot) {
        _runAnalysis(hits: selectedHitsSnapshot.selectedHits)
    }

    /// AFM is a single-file workflow: the selection basket is structurally capped to at most
    /// one hit by `WorkbenchFeatureStore`'s single-selection mode, so this guard rejecting
    /// >1 is a defensive check against malformed/legacy state, not a `.first`-style fallback.
    private func _runAnalysis(hits: [WorkflowMeasurementSearchHit]) {
        guard hits.count <= 1 else {
            analysisMessage = "AFM analyzes exactly one file; multiple selected hits are not supported."
            appendWarning(source: "Selection", message: "AFM received \(hits.count) selected hits; expected at most 1.")
            return
        }
        guard let hit = hits.first else {
            analysisMessage = "No files selected."
            return
        }

        let filePath = hit.measurementFilePath
        let displayState = heatmapDisplayState
        let styleDefaults = globalPlotDefaults
        let capturedWorkflowID = workflowID

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        saveMessage = nil
        renderedImageData = nil
        renderedPdfData = nil
        _renderRevision &+= 1
        let revision = _renderRevision
        warningLog.clear()

        analysisTask = Task { [weak self] in
            let parsed = await Task.detached(priority: .userInitiated) {
                () -> Result<(CanonicalAFMDataset, [String], ProcessedAFMChannel, Data, Data), Error> in
                do {
                    let output = try AFMInputAdapter.load(fileURL: URL(fileURLWithPath: filePath))
                    let dataset = output.dataset
                    let resolution = AFMChannelResolver.resolveDefaultChannel(in: dataset.channels)
                    guard let defaultChannel = resolution.channel else {
                        throw AFMHeatmapPayloadBuilderError.dimensionMismatch(expectedX: 0, expectedY: 0, foundY: 0, foundX: nil)
                    }
                    let config = AFMProcessingConfiguration(activeChannelID: defaultChannel.id)
                    let processed = AFMProcessingPipeline.process(
                        channel: defaultChannel,
                        xCoordinates: dataset.xCoordinates,
                        yCoordinates: dataset.yCoordinates,
                        configuration: config
                    )
                    let payload = try Self.buildHeatmapPayload(
                        dataset: dataset, processed: processed, workflowID: capturedWorkflowID, displayState: displayState
                    )
                    let renderOutput = try Self.renderHeatmap(payload: payload, displayState: displayState, globalPlotDefaults: styleDefaults)
                    var warnings = resolution.warning.map { [$0] } ?? []
                    warnings.append(contentsOf: output.warnings)
                    warnings.append(contentsOf: processed.warnings)
                    return .success((dataset, warnings, processed, renderOutput.imageData, renderOutput.pdfData))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled, self._renderRevision == revision else { return }

            switch parsed {
            case .success(let (dataset, warnings, processed, imageData, pdfData)):
                self.parsedDataset = dataset
                self.processingConfiguration = AFMProcessingConfiguration(activeChannelID: processed.sourceChannelID)
                self.renderedImageData = imageData
                self.renderedPdfData = pdfData
                self.cachedInputFiles = [filePath]
                self.cachedSampleKeys = [hit.sampleKey]
                for warning in warnings {
                    self.appendWarning(source: "AFM", message: warning)
                }
                self.analysisMessage = "Rendered \(processed.displayLabel)."
                self.commitRunTrace()

            case .failure(let error):
                self.parsedDataset = nil
                self.renderedImageData = nil
                self.renderedPdfData = nil
                let msg: String
                if let e = error as? IBWReadError {
                    msg = e.description
                } else if let e = error as? AFMHeatmapPayloadBuilderError {
                    msg = e.errorDescription ?? e.localizedDescription
                } else {
                    msg = error.localizedDescription
                }
                self.appendWarning(source: "AFM", message: msg)
                self.analysisMessage = "AFM render failed."
            }

            self.isAnalyzing = false
        }
    }

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard !cachedInputFiles.isEmpty else { return nil }
        var semanticParams: [String: String] = [
            "channelID": processingConfiguration.activeChannelID,
            "planeLevel": String(processingConfiguration.planeLevelEnabled),
            "lineFlatten": processingConfiguration.lineFlattenOrder.rawValue,
            "zeroReference": processingConfiguration.zeroReference.rawValue,
        ]
        if let channel = activeChannel {
            semanticParams["sourceLabel"] = channel.sourceLabel
            if let semanticType = channel.semanticTypeRaw { semanticParams["semanticType"] = semanticType }
            if let planefit = channel.provenance.planefit { semanticParams["sourcePlanefit"] = planefit }
        }
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: workflowID,
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(xField: "X (\(CanonicalAFMDataset.xUnit))", yField: "Y (\(CanonicalAFMDataset.yUnit))"),
            semanticParams: semanticParams,
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }

    var activeImageData: Data? { renderedImageData }
    var activePdfData: Data? { renderedPdfData }
    var activeLayout: WorkbenchPlotLayout? { nil }
    var seriesLabelOverrides: [String: String] { [:] }
    var relatedCharts: [WorkbenchResultReference]? { nil }
    var libraryRootURL: URL? {
        lastLibraryRootPath.isEmpty ? nil : URL(fileURLWithPath: lastLibraryRootPath)
    }
}

// MARK: - ActiveChartProviding

extension AFMWorkspaceStore: ActiveChartProviding {
    var activeChartPNG: Data? { renderedImageData }
    var activeChartManifestPayload: WorkbenchPlotPayload? { nil }
    var activeChartSampleKeys: [String] { cachedSampleKeys }
    func buildActiveChartMetrics() -> [PendingMetricEntry] { [] }
}

// MARK: - AnalysisPackProviding

extension AFMWorkspaceStore: AnalysisPackProviding, PackRestoreFailureReporting {
    typealias PackConfig = AFMPackConfig
    typealias PackResult = AFMPackResult

    var packWorkflowID: String { workflowID }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var hasAnalysisResult: Bool { renderedImageData != nil }

    func buildPackConfig() -> AFMPackConfig {
        let searchContext = AnalysisPackSearchContext(
            cachedSearchResults: cachedSearchResults,
            selectionReading: selectionReading,
            workflowID: workflowID
        )
        return AFMPackConfig(
            packState: AFMPackState(
                sourceFileIdentity: cachedInputFiles.first,
                processingConfiguration: processingConfiguration
            ),
            displayState: heatmapDisplayState,
            cachedSearchResults: searchContext.cachedSearchResults,
            selectedSearchResultIDs: searchContext.selectedSearchResultIDs
        )
    }

    func buildPackResult() -> AFMPackResult {
        AFMPackResult(canonicalDataset: parsedDataset)
    }

    func autoPackLabel() -> String {
        analysisPackLabel(
            sampleBatchAndSubstrate: cachedSearchResults.first?.sampleBatchAndSubstrate,
            device: nil,
            fallback: "AFM"
        )
    }

    func restoreFromPack(
        config: AFMPackConfig,
        result: AFMPackResult,
        pack: AnalysisPack,
        restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void,
        seedSelection: @escaping (Set<String>, [WorkflowMeasurementSearchHit]) -> Void
    ) {
        packRestoreErrorMessage = nil
        heatmapDisplayState = config.displayState
        processingConfiguration = config.packState.processingConfiguration
        cachedSearchResults = config.cachedSearchResults
        cachedInputFiles = pack.filePaths
        cachedSampleKeys = pack.sampleKeys

        if lastLibraryRootPath.isEmpty, let vaultRoot = vault?.libraryRootPath, !vaultRoot.isEmpty {
            lastLibraryRootPath = vaultRoot
        }

        seedSelection(Set(config.selectedSearchResultIDs), config.cachedSearchResults)
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        // Restore rerenders from the pack's own carried ingestion result — it never re-reads or
        // re-parses the source `.ibw` file (Phase 4D).
        guard let dataset = result.canonicalDataset else {
            packRestoreErrorMessage = "Pack has no saved AFM dataset to restore."
            return
        }
        guard let channel = dataset.channels.first(where: { $0.id == processingConfiguration.activeChannelID }) else {
            packRestoreErrorMessage = "Pack's saved channel selection no longer matches its dataset."
            return
        }

        let config = processingConfiguration
        let displayState = heatmapDisplayState
        let styleDefaults = globalPlotDefaults
        let capturedWorkflowID = workflowID

        analysisTask?.cancel()
        isAnalyzing = true
        renderedImageData = nil
        renderedPdfData = nil
        _renderRevision &+= 1
        let revision = _renderRevision
        warningLog.clear()

        analysisTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                () -> Result<(Data, Data, [String]), Error> in
                do {
                    let processed = AFMProcessingPipeline.process(
                        channel: channel, xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates, configuration: config
                    )
                    let payload = try Self.buildHeatmapPayload(
                        dataset: dataset, processed: processed, workflowID: capturedWorkflowID, displayState: displayState
                    )
                    let output = try Self.renderHeatmap(payload: payload, displayState: displayState, globalPlotDefaults: styleDefaults)
                    return .success((output.imageData, output.pdfData, processed.warnings))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled, self._renderRevision == revision else { return }

            switch rendered {
            case .success(let (imageData, pdfData, warnings)):
                self.parsedDataset = dataset
                self.renderedImageData = imageData
                self.renderedPdfData = pdfData
                for warning in warnings { self.appendWarning(source: "AFM Processing", message: warning) }
                self.isAnalyzing = false
                self.commitRunTrace()
            case .failure(let error):
                self.parsedDataset = dataset
                self.renderedImageData = nil
                self.renderedPdfData = nil
                self.appendWarning(source: "AFM Restore", message: error.localizedDescription)
                self.packRestoreErrorMessage = error.localizedDescription
                self.activePackID = nil
                self.analysisMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
}
