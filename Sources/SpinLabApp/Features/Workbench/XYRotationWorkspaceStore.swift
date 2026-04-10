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

    var lastLibraryRootPath: String?

    // MARK: - Private

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var _renderRevision: UInt64 = 0

    deinit { analysisTask?.cancel() }

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
                () -> (XYRotationIngestionResult, Data?, WorkbenchPlotLayout?, Data?, WorkbenchPlotLayout?) in
                let result = IngestXYRotationSelectionsUseCase().execute(hits: selectedHits)

                var rxx = rxxRenderer
                let (rxxData, rxxLayout, _) = rxx.renderRxxVsPhi(
                    sweeps: result.sweeps, device: result.device
                )
                var rxy = rxyRenderer
                let (rxyData, rxyLayout, _) = rxy.renderRxyVsPhi(
                    sweeps: result.sweeps, device: result.device
                )
                return (result, rxxData, rxxLayout, rxyData, rxyLayout)
            }.value

            let (result, rxxData, rxxLayout, rxyData, rxyLayout) = rendered
            guard let self, !Task.isCancelled else { return }

            self.ingestionResult = result
            self.plotRxxVsPhi = rxxData
            self.plotRxyVsPhi = rxyData
            if let l = rxxLayout { self.plotLayouts[.rxxVsPhi] = l }
            if let l = rxyLayout { self.plotLayouts[.rxyVsPhi] = l }

            let sweepCount = result.sweeps.count
            var msg = "Analyzed \(sweepCount) angle-sweep file(s)."
            if !result.warnings.isEmpty {
                msg += " Warnings: " + result.warnings.joined(separator: "; ")
            }
            self.analysisMessage = msg

            // Snapshot for persistence prep (used in 4.2.4)
            self.cachedInputFiles = selectedHits.map(\.measurementFilePath)
            self.cachedSampleKeys = Array(Set(selectedHits.map(\.sampleKey))).sorted()

            self.isAnalyzing = false
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
            let (data, layout, _): (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?)
            switch tab {
            case .rxxVsPhi:
                (data, layout, _) = r.renderRxxVsPhi(sweeps: sweeps, device: device)
            case .rxyVsPhi:
                (data, layout, _) = r.renderRxyVsPhi(sweeps: sweeps, device: device)
            }

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                switch tab {
                case .rxxVsPhi: self.plotRxxVsPhi = data
                case .rxyVsPhi: self.plotRxyVsPhi = data
                }
                if let l = layout { self.plotLayouts[tab] = l }
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
        clearPlot()
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
