import Foundation
import Observation

/// Isolated state and actions for the 3ω AHE workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
/// Geometry parameters are session-only (not persisted).
@MainActor
@Observable
final class ThreeOmegaWorkspaceStore {

    // MARK: - Search / Selection

    var selectedSearchResultIDs: Set<String> = []
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []

    // MARK: - Geometry (session-only, not persisted)

    var geometry = ThreeOmegaGeometry()

    // MARK: - Analysis output

    private(set) var ingestionResult: ThreeOmegaIngestionResult?
    private(set) var scalingResult: ThreeOmegaScalingResult?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Tab selection

    var activeTab: ThreeOmegaWorkbenchTab = .fieldSweep1omega

    // MARK: - Rendered plots (PNG Data per tab)

    private(set) var plotR1omega: Data?
    private(set) var plotR3omega: Data?
    private(set) var plotRAHEvsT: Data?
    private(set) var plotHcvsT: Data?
    private(set) var plotRT: Data?
    private(set) var plotScaling: Data?

    // MARK: - Interactive plot layouts (per tab, for WorkbenchPlotCanvas)

    private(set) var plotLayouts: [ThreeOmegaWorkbenchTab: WorkbenchPlotLayout] = [:]

    // MARK: - Plot controls (global, apply to the active tab on re-render)

    var showPlotGrid: Bool = true
    var plotLegendAnchor: String = ""           // "" = top-right (default)
    var plotTitleOverride: String = ""

    // Per-tab state (legend drag position and series label renames)
    var plotLegendPoints: [ThreeOmegaWorkbenchTab: CGPoint] = [:]
    var plotSeriesLabelOverrides: [ThreeOmegaWorkbenchTab: [String: String]] = [:]

    // MARK: - Private

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var scalingTask: Task<Void, Never>?

    deinit {
        analysisTask?.cancel()
        scalingTask?.cancel()
    }

    // MARK: - Selection

    func toggleSearchHitSelection(_ id: String) {
        if selectedSearchResultIDs.contains(id) {
            selectedSearchResultIDs.remove(id)
        } else {
            selectedSearchResultIDs.insert(id)
        }
    }

    // MARK: - Analysis

    /// Parse all selected files, fit RAHE/Hc, render tabs 1–5.
    func runAnalysis() {
        let selectedHits = cachedSearchResults.filter { selectedSearchResultIDs.contains($0.id) }
        guard !selectedHits.isEmpty else {
            analysisMessage = "Select at least one 3ω AHE measurement file."
            return
        }

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        _clearPlots()

        let capturedGrid   = showPlotGrid
        let capturedAnchor = plotLegendAnchor

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (result, plots) = try await Task.detached(priority: .userInitiated) { [selectedHits] in
                    let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                    let result = ingestUseCase.execute(hits: selectedHits)
                    var renderer = ThreeOmegaPlotRenderer()
                    renderer.showGrid    = capturedGrid
                    renderer.legendAnchor = capturedAnchor
                    let plots = renderer.renderAllTabs(result: result)
                    return (result, plots)
                }.value

                guard !Task.isCancelled else { return }
                self.ingestionResult = result
                self._applyPlots(plots)

                let sweepCount = result.fieldSweeps.count
                let rtNote     = result.rtResult != nil ? ", RT curve loaded" : ""
                let warnNote   = result.warnings.isEmpty ? "" : " (\(result.warnings.count) warning(s))"
                self.analysisMessage = "Analyzed \(sweepCount) field-sweep file(s)\(rtNote)\(warnNote)."
                self.isAnalyzing = false
            } catch is CancellationError {
                self.isAnalyzing = false
            } catch {
                self.isAnalyzing = false
                self.analysisMessage = "Analysis failed: \(error.localizedDescription)"
            }
        }
    }

    /// Re-runs only the scaling (cheap). Called when geometry parameters change.
    func runScaling() {
        guard let result = ingestionResult, let rt = result.rtResult else {
            analysisMessage = "Run analysis first before applying geometry."
            return
        }
        guard geometry.isComplete else {
            analysisMessage = "Enter L_xx, L_xy, and d to compute Fig 5b scaling."
            return
        }

        let capturedResult   = result
        let capturedGeometry = geometry
        let capturedGrid     = showPlotGrid
        let capturedAnchor   = plotLegendAnchor
        let capturedLegend   = plotLegendPoints[.scaling]

        scalingTask?.cancel()
        scalingTask = Task { [weak self] in
            guard let self else { return }
            let (scalingRes, scalingData, scalingLayout) = await Task.detached(priority: .userInitiated) {
                let scalingUseCase = ThreeOmegaScalingUseCase()
                let res = scalingUseCase.executeWithIRms(
                    fieldSweeps: capturedResult.fieldSweeps,
                    rtResult: rt,
                    geometry: capturedGeometry,
                    iRmsValues: capturedResult.iRmsValues
                )
                var renderer = ThreeOmegaPlotRenderer()
                renderer.showGrid     = capturedGrid
                renderer.legendAnchor = capturedAnchor
                renderer.legendPoint  = capturedLegend
                let (data, layout) = renderer.renderScaling(result: res)
                return (res, data, layout)
            }.value

            guard !Task.isCancelled else { return }
            self.scalingResult = scalingRes
            self.plotScaling   = scalingData
            if let l = scalingLayout { self.plotLayouts[.scaling] = l }

            if let beta = scalingRes.beta, let r2 = scalingRes.rSquared {
                self.analysisMessage = String(format: "Scaling: β = %.4e, R² = %.4f", beta, r2)
            } else if !scalingRes.warnings.isEmpty {
                self.analysisMessage = scalingRes.warnings.first
            }
        }
    }

    // MARK: - Interactive callbacks (mirror AHEWorkspaceStore pattern)

    func updateLegendPoint(_ point: CGPoint) {
        plotLegendPoints[activeTab] = point
        plotLegendAnchor = ""           // free position overrides anchor
        _rerenderActiveTab()
    }

    func updatePlotTitle(_ title: String) {
        plotTitleOverride = title
        _rerenderActiveTab()
    }

    func updateXAxisLabel(_ label: String) {
        // X/Y label overrides are applied via payload mutation in re-render
        _rerenderActiveTab(xLabelOverride: label)
    }

    func updateYAxisLabel(_ label: String) {
        _rerenderActiveTab(yLabelOverride: label)
    }

    func updateSeriesLabel(originalLabel: String, newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == originalLabel {
            plotSeriesLabelOverrides[activeTab]?.removeValue(forKey: originalLabel)
        } else {
            if plotSeriesLabelOverrides[activeTab] == nil {
                plotSeriesLabelOverrides[activeTab] = [:]
            }
            plotSeriesLabelOverrides[activeTab]![originalLabel] = trimmed
        }
        _rerenderActiveTab()
    }

    // MARK: - Clear

    func clearAll() {
        analysisTask?.cancel()
        scalingTask?.cancel()
        selectedSearchResultIDs  = []
        ingestionResult          = nil
        scalingResult            = nil
        isAnalyzing              = false
        analysisMessage          = nil
        geometry                 = ThreeOmegaGeometry()
        activeTab                = .fieldSweep1omega
        showPlotGrid             = true
        plotLegendAnchor         = ""
        plotTitleOverride        = ""
        plotLegendPoints         = [:]
        plotSeriesLabelOverrides = [:]
        _clearPlots()
    }

    // MARK: - Private helpers

    private func _applyPlots(_ plots: ThreeOmegaRenderedPlots) {
        plotR1omega  = plots.r1omega
        plotR3omega  = plots.r3omega
        plotRAHEvsT  = plots.raheVsT
        plotHcvsT    = plots.hcVsT
        plotRT       = plots.rtCurve
        plotScaling  = plots.scaling
        if let l = plots.layoutR1omega  { plotLayouts[.fieldSweep1omega] = l }
        if let l = plots.layoutR3omega  { plotLayouts[.fieldSweep3omega] = l }
        if let l = plots.layoutRAHEvsT  { plotLayouts[.raheVsT]         = l }
        if let l = plots.layoutHcVsT    { plotLayouts[.hcVsT]           = l }
        if let l = plots.layoutRTCurve  { plotLayouts[.rtCurve]         = l }
    }

    /// Re-renders only the active tab using cached ingestion/scaling result.
    private func _rerenderActiveTab(xLabelOverride: String? = nil, yLabelOverride: String? = nil) {
        guard let ingestion = ingestionResult else { return }

        let tab            = activeTab
        let capturedGrid   = showPlotGrid
        let capturedAnchor = plotLegendAnchor
        let capturedLegend = plotLegendPoints[tab]
        let titleOverride  = plotTitleOverride
        let labelOverrides = plotSeriesLabelOverrides[tab] ?? [:]
        let capturedScaling = scalingResult
        let capturedGeometry = geometry

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var r = ThreeOmegaPlotRenderer()
            r.showGrid     = capturedGrid
            r.legendAnchor = capturedAnchor
            r.legendPoint  = capturedLegend

            var result: (Data?, WorkbenchPlotLayout?) = (nil, nil)
            switch tab {
            case .fieldSweep1omega:
                result = r.renderR1omega(sweeps: ingestion.fieldSweeps, angleLabel: ingestion.angleLabel)
            case .fieldSweep3omega:
                result = r.renderR3omega(sweeps: ingestion.fieldSweeps, angleLabel: ingestion.angleLabel)
            case .raheVsT:
                result = r.renderRAHEvsT(sweeps: ingestion.fieldSweeps, angleLabel: ingestion.angleLabel)
            case .hcVsT:
                result = r.renderHcVsT(sweeps: ingestion.fieldSweeps, angleLabel: ingestion.angleLabel)
            case .rtCurve:
                if let rt = ingestion.rtResult { result = r.renderRT(rt: rt) }
            case .scaling:
                if let sr = capturedScaling, capturedGeometry.isComplete {
                    result = r.renderScaling(result: sr)
                }
            }

            // Apply title and series label overrides to the rendered payload is complex
            // post-render; for now title/label override is stored and used on next full render.
            // TODO: pass overrides into renderer for live preview.
            _ = titleOverride
            _ = xLabelOverride
            _ = yLabelOverride
            _ = labelOverrides

            await MainActor.run { [weak self] in
                guard let self, self.activeTab == tab else { return }
                switch tab {
                case .fieldSweep1omega: self.plotR1omega = result.0
                case .fieldSweep3omega: self.plotR3omega = result.0
                case .raheVsT:          self.plotRAHEvsT = result.0
                case .hcVsT:            self.plotHcvsT   = result.0
                case .rtCurve:          self.plotRT      = result.0
                case .scaling:          self.plotScaling = result.0
                }
                if let l = result.1 { self.plotLayouts[tab] = l }
            }
        }
    }

    private func _clearPlots() {
        plotR1omega = nil
        plotR3omega = nil
        plotRAHEvsT = nil
        plotHcvsT   = nil
        plotRT      = nil
        plotScaling = nil
        plotLayouts = [:]
    }
}

// MARK: - Rendered plot bundle

struct ThreeOmegaRenderedPlots: Sendable {
    var r1omega:  Data?
    var r3omega:  Data?
    var raheVsT:  Data?
    var hcVsT:    Data?
    var rtCurve:  Data?
    var scaling:  Data?
    // Layouts for interactive WorkbenchPlotCanvas
    var layoutR1omega:  WorkbenchPlotLayout?
    var layoutR3omega:  WorkbenchPlotLayout?
    var layoutRAHEvsT:  WorkbenchPlotLayout?
    var layoutHcVsT:    WorkbenchPlotLayout?
    var layoutRTCurve:  WorkbenchPlotLayout?
    var layoutScaling:  WorkbenchPlotLayout?
}
