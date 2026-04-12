import CryptoKit
import Foundation
import Observation

/// Isolated state and actions for the XY Rotation workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
@MainActor
@Observable
final class XYRotationWorkspaceStore {

    // MARK: - Search / Selection

    var selectedSearchResultIDs: Set<String> = []
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []

    // MARK: - Analysis output

    private(set) var ingestionResult: XYRotationIngestionResult?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Rendered plot data

    private(set) var plotRxxVsPhi: Data?
    private(set) var plotRxyVsPhi: Data?
    private(set) var plotLayouts: [XYRotationWorkbenchTab: WorkbenchPlotLayout] = [:]
    private(set) var currentRunTrace: WorkbenchRunTraceProjection?

    var activePlotImageData: Data? {
        switch activeTab {
        case .rxxVsPhi: return plotRxxVsPhi
        case .rxyVsPhi: return plotRxyVsPhi
        }
    }

    // MARK: - Plot controls

    var activeTab: XYRotationWorkbenchTab = .rxxVsPhi
    var showPlotGrid: Bool = true
    var stackOffsetMultiplier: Double = 0.0
    var minGapFraction: Double = 0.15
    var centerBaseline: Bool = false
    var linearDetrend: Bool = false
    var titleTemplate: String = "#tab #device #sample"
    var phiOffsetOverrides: [String: Double] = [:]

    // MARK: - Display overrides (interactive editing)

    var plotLegendPoints: [XYRotationWorkbenchTab: CGPoint] = [:]
    var plotSeriesLabelOverrides: [Int: String] = [:]
    var plotTitleOverride: String?
    var plotXLabelOverride: String?
    var plotYLabelOverride: String?

    // MARK: - Cached data for title template + persistence prep

    var cachedSampleNumericDisplay: [String: [String: String]] = [:]
    @ObservationIgnored private(set) var cachedInputFiles: [String] = []
    @ObservationIgnored private(set) var cachedSampleKeys: [String] = []
    @ObservationIgnored private var _titleTokens: [String: String] = [:]

    // MARK: - Context from WorkbenchFeatureStore

    var lastLibraryRootPath: String = ""

    // MARK: - Persistence (Save to Library)

    private(set) var persistenceOutcome: PersistenceOutcome?

    /// Cached manifest payloads per tab, built at render time with sourceRef populated.
    @ObservationIgnored private(set) var cachedManifestPayloads: [XYRotationWorkbenchTab: WorkbenchPlotPayload] = [:]

    // MARK: - Related charts (hover popover)

    private(set) var relatedChartsGrouped: [String: [WorkbenchResultReference]] = [:]
    @ObservationIgnored private var relatedChartsTask: Task<Void, Never>?

    // MARK: - Analysis Pack (vault integration)

    @ObservationIgnored var vault: AnalysisVault?
    var activePackID: AnalysisPack.ID?

    // MARK: - Private

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var _renderRevision: UInt64 = 0

    deinit {
        analysisTask?.cancel()
        relatedChartsTask?.cancel()
    }

    // MARK: - Renderer snapshot

    /// Single source of truth for building a renderer from current store state.
    /// Called by both `runAnalysis` and `_rerenderActiveTab` to avoid parameter drift.
    private func _snapshotRenderer(forTab tab: XYRotationWorkbenchTab) -> XYRotationPlotRenderer {
        var r = XYRotationPlotRenderer()
        r.showGrid = showPlotGrid
        r.legendPoint = plotLegendPoints[tab]
        r.stackOffsetMultiplier = stackOffsetMultiplier
        r.minGapFraction = minGapFraction
        r.centerBaseline = centerBaseline
        r.linearDetrend = linearDetrend
        r.titleTemplate = titleTemplate
        r.titleTokens = _titleTokens
        r.titleOverride = plotTitleOverride ?? ""
        r.xLabelOverride = plotXLabelOverride ?? ""
        r.yLabelOverride = plotYLabelOverride ?? ""
        r.seriesLabelOverrides = plotSeriesLabelOverrides
        r.phiOffsetOverrides = phiOffsetOverrides
        return r
    }

    // MARK: - Analysis

    func runAnalysis() {
        let selectedHits = cachedSearchResults
            .filter { selectedSearchResultIDs.contains($0.id) }
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
        guard !selectedHits.isEmpty else {
            analysisMessage = "No files selected."
            return
        }

        // Build title tokens from representative hit
        if let hit = selectedHits.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        }

        // Snapshot renderers for both tabs (each gets its own legend position)
        let rxxRenderer = _snapshotRenderer(forTab: .rxxVsPhi)
        let rxyRenderer = _snapshotRenderer(forTab: .rxyVsPhi)

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        clearPlot()
        _renderRevision &+= 1  // invalidate any in-flight rerenders

        analysisTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                () -> (XYRotationIngestionResult, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?) in
                let result = IngestXYRotationSelectionsUseCase().execute(hits: selectedHits)

                var rxx = rxxRenderer
                let (rxxData, rxxLayout, rxxPayload) = rxx.renderRxxVsPhi(
                    sweeps: result.sweeps, device: result.device
                )
                var rxy = rxyRenderer
                let (rxyData, rxyLayout, rxyPayload) = rxy.renderRxyVsPhi(
                    sweeps: result.sweeps, device: result.device
                )
                return (result, rxxData, rxxLayout, rxxPayload, rxyData, rxyLayout, rxyPayload)
            }.value

            let (result, rxxData, rxxLayout, rxxPayload, rxyData, rxyLayout, rxyPayload) = rendered
            guard let self, !Task.isCancelled else { return }

            self.ingestionResult = result
            self.plotRxxVsPhi = rxxData
            self.plotRxyVsPhi = rxyData
            if let l = rxxLayout { self.plotLayouts[.rxxVsPhi] = l }
            if let l = rxyLayout { self.plotLayouts[.rxyVsPhi] = l }

            // Cache manifest payloads for Save to Library + related charts
            if let p = rxxPayload { self.cachedManifestPayloads[.rxxVsPhi] = p }
            if let p = rxyPayload { self.cachedManifestPayloads[.rxyVsPhi] = p }

            let sweepCount = result.sweeps.count
            var msg = "Analyzed \(sweepCount) angle-sweep file(s)."
            if !result.warnings.isEmpty {
                msg += " Warnings: " + result.warnings.joined(separator: "; ")
            }
            self.analysisMessage = msg

            // Snapshot for persistence
            self.cachedInputFiles = selectedHits.map(\.measurementFilePath)
            self.cachedSampleKeys = Array(Set(selectedHits.map(\.sampleKey))).sorted()

            self.isAnalyzing = false
            self.refreshRelatedCharts()
        }
    }

    // MARK: - Rerender (style-only, no re-parse)

    func rerenderForStyleChange() {
        _rerenderActiveTab()
    }

    func updatePhiOffset(sweepID: String, offset: Double) {
        phiOffsetOverrides[sweepID] = offset
        _rerenderActiveTab()
    }

    private func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }
        let tab = activeTab
        let renderer = _snapshotRenderer(forTab: tab)
        let sweeps = ingestion.sweeps
        let device = ingestion.device

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            var r = renderer
            let (data, layout, payload): (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?)
            switch tab {
            case .rxxVsPhi:
                (data, layout, payload) = r.renderRxxVsPhi(sweeps: sweeps, device: device)
            case .rxyVsPhi:
                (data, layout, payload) = r.renderRxyVsPhi(sweeps: sweeps, device: device)
            }

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                switch tab {
                case .rxxVsPhi: self.plotRxxVsPhi = data
                case .rxyVsPhi: self.plotRxyVsPhi = data
                }
                if let l = layout { self.plotLayouts[tab] = l }
                if let p = payload { self.cachedManifestPayloads[tab] = p }
            }
        }
    }

    // MARK: - Selection helpers

    func toggleSearchHitSelection(_ hitID: String) {
        if selectedSearchResultIDs.contains(hitID) {
            selectedSearchResultIDs.remove(hitID)
        } else {
            selectedSearchResultIDs.insert(hitID)
        }
    }

    func selectAll() {
        selectedSearchResultIDs = Set(cachedSearchResults.map(\.id))
    }

    func clearPlot() {
        plotRxxVsPhi = nil
        plotRxyVsPhi = nil
        plotLayouts = [:]
        plotSeriesLabelOverrides = [:]
        plotTitleOverride = nil
        plotXLabelOverride = nil
        plotYLabelOverride = nil
        plotLegendPoints = [:]
    }

    func clearAll() {
        selectedSearchResultIDs = []
        currentRunTrace = nil
        isAnalyzing = false
        analysisMessage = nil
        ingestionResult = nil
        cachedSampleNumericDisplay = [:]
        cachedInputFiles = []
        cachedSampleKeys = []
        _titleTokens = [:]
        phiOffsetOverrides = [:]
        analysisTask?.cancel()
        analysisTask = nil
        activePackID = nil
        persistenceOutcome = nil
        cachedManifestPayloads = [:]
        relatedChartsTask?.cancel()
        relatedChartsTask = nil
        relatedChartsGrouped = [:]
        clearPlot()
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

    func relatedCharts(for tab: XYRotationWorkbenchTab) -> [WorkbenchResultReference] {
        guard let payload = cachedManifestPayloads[tab] else { return [] }
        let inputFiles = payload.series.compactMap(\.sourceRef)
        guard !inputFiles.isEmpty else { return [] }
        let key = InputFilesCanonicalKey.make(from: inputFiles)
        return relatedChartsGrouped[key] ?? []
    }

    // MARK: - Save to Library

    func persistToLibrary(onComplete: (() -> Void)? = nil) {
        guard let png = activeChartPNG else {
            analysisMessage = "No chart to save. Run analysis first."
            return
        }
        guard let payload = activeChartManifestPayload else {
            analysisMessage = "No manifest payload available for the active tab."
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
                self.analysisMessage = "Saved to Library."
                self.refreshRelatedCharts()
            case .partial(_, let err):
                self.analysisMessage = "Chart saved; metric error: \(err)"
                self.refreshRelatedCharts()
            case .failure(let err):
                self.analysisMessage = "Save failed: \(err)"
            }
            onComplete?()
        }
    }

    // MARK: - Analysis Pack save / load

    var matchingVaultPack: AnalysisPack? {
        guard ingestionResult != nil, let vault else { return nil }
        let fingerprint = AnalysisPack.makeFingerprint(inputFiles: cachedInputFiles, rtFilePath: nil)
        return vault.pack(forWorkflow: "xy", fingerprint: fingerprint)
            ?? activePackID.flatMap { vault.get(id: $0) }
    }

    var hasUnsavedAnalysis: Bool {
        guard ingestionResult != nil else { return false }
        guard let packID = activePackID, let vault, let pack = vault.get(id: packID) else {
            return ingestionResult != nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let currentConfig = try? encoder.encode(_buildPackConfig()),
              let currentResult = try? encoder.encode(_buildPackResult()) else { return true }
        var currentData = currentConfig
        currentData.append(currentResult)
        var storedData = pack.config
        storedData.append(pack.result)
        let currentHash = SHA256.hash(data: currentData)
        let storedHash = SHA256.hash(data: storedData)
        return currentHash != storedHash
    }

    func saveAnalysis(searchQueryText: String = "") {
        guard let vault else {
            analysisMessage = "Vault not available."
            return
        }
        guard ingestionResult != nil else {
            analysisMessage = "No analysis to save. Run analysis first."
            return
        }
        var config = _buildPackConfig()
        config.searchQueryText = searchQueryText
        let result = _buildPackResult()
        let fingerprint = AnalysisPack.makeFingerprint(inputFiles: cachedInputFiles, rtFilePath: nil)

        let existingPack = vault.pack(forWorkflow: "xy", fingerprint: fingerprint)
            ?? activePackID.flatMap { vault.get(id: $0) }

        if let existing = existingPack {
            do {
                var pack = existing
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                pack.config = try encoder.encode(config)
                pack.result = try encoder.encode(result)
                pack.filePaths = cachedInputFiles
                pack.sampleKeys = cachedSampleKeys
                pack.sourceFingerprint = fingerprint
                vault.update(pack)
                activePackID = pack.id
                analysisMessage = "Updated: \(pack.label)"
            } catch {
                analysisMessage = "Save failed: \(error.localizedDescription)"
            }
        } else {
            let label = _autoPackLabel()
            do {
                let pack = try AnalysisPack(
                    label: label,
                    workflowID: "xy",
                    filePaths: cachedInputFiles,
                    sampleKeys: cachedSampleKeys,
                    sourceFingerprint: fingerprint,
                    config: config,
                    result: result
                )
                vault.add(pack)
                activePackID = pack.id
                analysisMessage = "Analysis saved: \(label)"
            } catch {
                analysisMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    func loadPack(id: AnalysisPack.ID, restoreSearchState: (([WorkflowMeasurementSearchHit], String) -> Void)) {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false

        guard let vault, let pack = vault.get(id: id) else {
            analysisMessage = "Pack not found."
            return
        }
        guard let config = try? pack.decodeConfig(XYRotationPackConfig.self),
              let result = try? pack.decodeResult(XYRotationPackResult.self) else {
            analysisMessage = "Failed to decode pack data."
            return
        }

        // Restore analysis params
        phiOffsetOverrides = config.phiOffsetOverrides
        centerBaseline = config.centerBaseline
        linearDetrend = config.linearDetrend

        // Restore display settings
        if let tab = XYRotationWorkbenchTab(rawValue: config.activeTab) {
            activeTab = tab
        }
        titleTemplate = config.titleTemplate
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        showPlotGrid = config.showPlotGrid
        plotTitleOverride = config.plotTitleOverride
        plotXLabelOverride = config.plotXLabelOverride
        plotYLabelOverride = config.plotYLabelOverride
        plotSeriesLabelOverrides = config.plotSeriesLabelOverrides

        // Restore per-tab legend points
        plotLegendPoints = [:]
        for (key, val) in config.plotLegendPoints {
            if let tab = XYRotationWorkbenchTab(rawValue: key) {
                plotLegendPoints[tab] = val.cgPoint
            }
        }

        // Restore search selection state
        cachedSearchResults = config.cachedSearchResults
        selectedSearchResultIDs = Set(config.selectedSearchResultIDs)

        // Restore results
        ingestionResult = result.ingestionResult

        // Build title tokens from restored search results
        if let hit = config.cachedSearchResults.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        } else {
            _titleTokens = [:]
        }

        // Restore cached persistence state from pack
        cachedInputFiles = pack.filePaths
        cachedSampleKeys = pack.sampleKeys

        // Restore library root from vault so persistToLibrary works without a prior search
        if lastLibraryRootPath.isEmpty, let root = vault.libraryRootPath {
            lastLibraryRootPath = root
        }

        // Set active pack
        activePackID = id

        // Bridge: restore search results into WorkbenchFeatureStore
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        // Re-render all tabs
        _rerenderAllTabs()
        refreshRelatedCharts()

        analysisMessage = "Loaded: \(pack.label)"
    }

    // MARK: - Pack helpers (private)

    private func _buildPackConfig() -> XYRotationPackConfig {
        let legendPts: [String: CGPointCodable] = plotLegendPoints.reduce(into: [:]) { d, kv in
            d[kv.key.rawValue] = CGPointCodable(kv.value)
        }
        return XYRotationPackConfig(
            phiOffsetOverrides: phiOffsetOverrides,
            centerBaseline: centerBaseline,
            linearDetrend: linearDetrend,
            activeTab: activeTab.rawValue,
            titleTemplate: titleTemplate,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: showPlotGrid,
            plotTitleOverride: plotTitleOverride,
            plotXLabelOverride: plotXLabelOverride,
            plotYLabelOverride: plotYLabelOverride,
            plotLegendPoints: legendPts,
            plotSeriesLabelOverrides: plotSeriesLabelOverrides,
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectedSearchResultIDs),
            searchQueryText: ""   // filled by caller at WorkbenchFeatureStore level
        )
    }

    private func _buildPackResult() -> XYRotationPackResult {
        XYRotationPackResult(
            ingestionResult: ingestionResult!
        )
    }

    private func _autoPackLabel() -> String {
        let sample = cachedSearchResults.first?.sampleBatchAndSubstrate ?? "Unknown"
        let device = ingestionResult?.device ?? ""
        return device.isEmpty ? sample : "\(sample) \(device)"
    }

    /// Re-renders both tabs after loadPack.
    private func _rerenderAllTabs() {
        guard let ingestion = ingestionResult else { return }
        let sweeps = ingestion.sweeps
        let device = ingestion.device

        _renderRevision &+= 1
        let revision = _renderRevision

        for tab in XYRotationWorkbenchTab.allCases {
            let renderer = _snapshotRenderer(forTab: tab)
            Task.detached(priority: .userInitiated) { [weak self] in
                var r = renderer
                let (data, layout, payload): (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?)
                switch tab {
                case .rxxVsPhi:
                    (data, layout, payload) = r.renderRxxVsPhi(sweeps: sweeps, device: device)
                case .rxyVsPhi:
                    (data, layout, payload) = r.renderRxyVsPhi(sweeps: sweeps, device: device)
                }

                await MainActor.run { [weak self] in
                    guard let self, self._renderRevision == revision else { return }
                    switch tab {
                    case .rxxVsPhi: self.plotRxxVsPhi = data
                    case .rxyVsPhi: self.plotRxyVsPhi = data
                    }
                    if let l = layout { self.plotLayouts[tab] = l }
                    if let p = payload { self.cachedManifestPayloads[tab] = p }
                }
            }
        }
    }
}

// MARK: - WorkbenchPlottingStore

extension XYRotationWorkspaceStore: WorkbenchPlottingStore {
    func updateLegendPoint(_ point: CGPoint) {
        plotLegendPoints[activeTab] = point
        _rerenderActiveTab()
    }

    func updatePlotTitle(_ title: String) {
        plotTitleOverride = title
        _rerenderActiveTab()
    }

    func updateXAxisLabel(_ label: String) {
        plotXLabelOverride = label
        _rerenderActiveTab()
    }

    func updateYAxisLabel(_ label: String) {
        plotYLabelOverride = label
        _rerenderActiveTab()
    }

    func updateSeriesLabel(index: Int, newLabel: String) {
        plotSeriesLabelOverrides[index] = newLabel
        _rerenderActiveTab()
    }
}

// MARK: - ActiveChartProviding conformance

extension XYRotationWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? {
        switch activeTab {
        case .rxxVsPhi: return plotRxxVsPhi
        case .rxyVsPhi: return plotRxyVsPhi
        }
    }

    var activeChartManifestPayload: WorkbenchPlotPayload? {
        cachedManifestPayloads[activeTab]
    }

    var activeChartSampleKeys: [String] { cachedSampleKeys }

    func buildActiveChartMetrics() -> [PendingMetricEntry] {
        // Deferred to 4.2.5 — Fourier fit will provide AMR/PHE metrics
        []
    }
}
