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

    // MARK: - RT file search (independent of main 3w search)

    var rtQuery: String = ""
    var rtSearchResults: [WorkflowMeasurementSearchHit] = []
    var rtSearchMessage: String?
    var isRTSearching: Bool = false
    var showRTPopover: Bool = false
    private(set) var selectedRTHit: WorkflowMeasurementSearchHit?

    func selectRTHit(_ hit: WorkflowMeasurementSearchHit) {
        selectedRTHit = hit
        rtQuery = hit.measurementFilePath.components(separatedBy: "/").last ?? hit.id
        rtSearchResults = []
        showRTPopover = false
    }

    func clearRTSelection() {
        selectedRTHit = nil
    }

    // MARK: - Geometry (session-only, not persisted)

    var geometry = ThreeOmegaGeometry()
    var v3Method: ThreeOmegaV3Method = .highField

    // MARK: - Fit ranges (session-only, not persisted)

    var fitRanges: [ThreeOmegaFitRange] = [ThreeOmegaFitRange()]

    // MARK: - Analysis output

    private(set) var ingestionResult: ThreeOmegaIngestionResult?
    private(set) var scalingResult: ThreeOmegaScalingResult?
    private(set) var currentRunTrace: WorkbenchRunTraceProjection?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Warning log (persists across runs within the session)

    private(set) var warningLog: [ThreeOmegaWarningEntry] = []

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
    var plotTitleSuffix: String = ""            // e.g., "PN69 o STO111 20 mT 100 mJ"
    var stackOffsetMultiplier: Double = 1.2     // 0 = no stacking; >0 = curve spacing

    // Per-tab state (legend drag position, axis label overrides, and series label renames)
    var plotLegendPoints: [ThreeOmegaWorkbenchTab: CGPoint] = [:]
    var plotSeriesLabelOverrides: [ThreeOmegaWorkbenchTab: [Int: String]] = [:]
    /// Display-only x-axis label overrides per tab (does not affect data).
    var plotXLabelOverrides: [ThreeOmegaWorkbenchTab: String] = [:]
    /// Display-only y-axis label overrides per tab (does not affect data).
    var plotYLabelOverrides: [ThreeOmegaWorkbenchTab: String] = [:]

    /// Cached per-sample numericDisplay from library index, populated by WorkbenchFeatureStore after search.
    var cachedSampleNumericDisplay: [String: [String: String]] = [:]

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

    var isAllSelected: Bool {
        !cachedSearchResults.isEmpty && selectedSearchResultIDs.count == cachedSearchResults.count
    }

    func selectAll() {
        selectedSearchResultIDs = Set(cachedSearchResults.map { $0.id })
    }

    func deselectAll() {
        selectedSearchResultIDs = []
    }

    // MARK: - Fit range management

    func addFitRange() {
        fitRanges.append(ThreeOmegaFitRange())
    }

    func removeFitRange(id: UUID) {
        guard fitRanges.count > 1 else { return }
        fitRanges.removeAll { $0.id == id }
    }

    func updateFitRange(id: UUID, tLo: Double?, tHi: Double?) {
        guard let idx = fitRanges.firstIndex(where: { $0.id == id }) else { return }
        fitRanges[idx].tLo = tLo
        fitRanges[idx].tHi = tHi
    }

    // MARK: - Analysis

    /// Parse all selected files, fit RAHE/Hc, render tabs 1–5.
    func runAnalysis() {
        let selectedHits = cachedSearchResults.filter { selectedSearchResultIDs.contains($0.id) }
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
        guard !selectedHits.isEmpty else {
            analysisMessage = "Select at least one 3w measurement file."
            return
        }

        // Compute title suffix from representative hit (stable: sorted by path)
        if let hit = selectedHits.first {
            let sampleLabel = hit.sampleBatchAndSubstrate
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            let numericParts = ["氧压", "能量"].compactMap { numericDisplay[$0] }
            plotTitleSuffix = ([sampleLabel] + numericParts)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else {
            plotTitleSuffix = ""
        }

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        _clearPlots()

        let capturedGrid       = showPlotGrid
        let capturedAnchor     = plotLegendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedSuffix     = plotTitleSuffix

        let capturedRTHit = selectedRTHit

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let (result, plots) = await Task.detached(priority: .userInitiated) { [selectedHits] in
                let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                let result = ingestUseCase.execute(hits: selectedHits, rtHit: capturedRTHit)
                var renderer = ThreeOmegaPlotRenderer()
                renderer.showGrid              = capturedGrid
                renderer.legendAnchor          = capturedAnchor
                renderer.stackOffsetMultiplier = capturedMultiplier
                renderer.titleSuffix           = capturedSuffix
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

            for w in result.warnings {
                self.warningLog.append(ThreeOmegaWarningEntry(source: "Ingestion", message: w))
                print("[SpinLab][3ω Ingestion] \(w)")
            }

            self.currentRunTrace = WorkbenchRunTraceProjection(
                runID: UUID().uuidString,
                workflowID: "3w",
                inputFiles: selectedHits.map { $0.measurementFilePath },
                axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R (Ω)"),
                semanticParams: [
                    "device":       result.device.isEmpty ? "unknown" : result.device,
                    "fieldSweeps":  "\(sweepCount)",
                    "rtLoaded":     result.rtResult != nil ? "yes" : "no"
                ],
                outputImagePath: "",
                manifestPath: "",
                generatedAt: Date()
            )
            self.isAnalyzing = false
        }
    }

    /// Re-runs only the scaling (cheap). Called when geometry parameters change.
    func runScaling() {
        guard let result = ingestionResult, let rt = result.rtResult else {
            analysisMessage = "Run analysis first before applying geometry."
            return
        }
        guard geometry.isComplete else {
            analysisMessage = "Enter L_xx, L_xy, and d to compute Scaling Law."
            return
        }

        let capturedResult   = result
        let capturedGeometry = geometry
        let capturedGrid     = showPlotGrid
        let capturedAnchor   = plotLegendAnchor
        let capturedLegend   = plotLegendPoints[.scaling]
        let capturedRanges   = fitRanges
        let capturedSuffix   = plotTitleSuffix
        let capturedDevice   = result.device
        let capturedV3Method = v3Method

        scalingTask?.cancel()
        scalingTask = Task { [weak self] in
            guard let self else { return }
            let (scalingRes, scalingData, scalingLayout) = await Task.detached(priority: .userInitiated) {
                let scalingUseCase = ThreeOmegaScalingUseCase()
                let res = scalingUseCase.executeWithIRms(
                    fieldSweeps: capturedResult.fieldSweeps,
                    rtResult: rt,
                    geometry: capturedGeometry,
                    iRmsValues: capturedResult.iRmsValues,
                    fitRanges: capturedRanges,
                    v3Method: capturedV3Method
                )
                var renderer = ThreeOmegaPlotRenderer()
                renderer.showGrid     = capturedGrid
                renderer.legendAnchor = capturedAnchor
                renderer.legendPoint  = capturedLegend
                renderer.titleSuffix  = capturedSuffix
                let (data, layout) = renderer.renderScaling(result: res, device: capturedDevice)
                return (res, data, layout)
            }.value

            guard !Task.isCancelled else { return }
            self.scalingResult = scalingRes
            self.plotScaling   = scalingData
            if let l = scalingLayout { self.plotLayouts[.scaling] = l }

            for w in scalingRes.warnings {
                self.warningLog.append(ThreeOmegaWarningEntry(source: "Scaling", message: w))
                print("[SpinLab][3ω Scaling] \(w)")
            }

            if scalingRes.isSingleFullRange(), let seg = scalingRes.segments.first {
                self.analysisMessage = String(format: "Scaling: β = %.4e, R² = %.4f", seg.beta, seg.rSquared)
            } else if !scalingRes.segments.isEmpty {
                self.analysisMessage = "Scaling: \(scalingRes.segments.count) segment(s) fitted."
            } else if !scalingRes.warnings.isEmpty {
                self.analysisMessage = scalingRes.warnings.first
            }
        }
    }

    // MARK: - Stack offset

    /// Re-renders Tab 1 and Tab 2 after stack offset multiplier changes.
    func rerenderFieldSweepTabs() {
        guard let ingestion = ingestionResult else { return }
        let capturedGrid       = showPlotGrid
        let capturedAnchor     = plotLegendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedSuffix     = plotTitleSuffix

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.legendAnchor          = capturedAnchor
            r.stackOffsetMultiplier = capturedMultiplier
            r.titleSuffix           = capturedSuffix
            let r1 = r.renderR1omega(sweeps: ingestion.fieldSweeps, device: ingestion.device)
            let r3 = r.renderR3omega(sweeps: ingestion.fieldSweeps, device: ingestion.device)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.plotR1omega = r1.0
                self.plotR3omega = r3.0
                if let l = r1.1 { self.plotLayouts[.fieldSweep1omega] = l }
                if let l = r3.1 { self.plotLayouts[.fieldSweep3omega] = l }
            }
        }
    }

    // MARK: - Interactive callbacks (mirror AHEWorkspaceStore pattern)

    func updateLegendPoint(_ point: CGPoint) {
        plotLegendPoints[activeTab] = point
        plotLegendAnchor = ""           // free position overrides anchor
        _rerenderActiveTab()
    }

    /// Re-renders the active tab for style-only changes (grid, etc.)
    /// without mutating legend position or anchor state.
    func rerenderForStyleChange() {
        _rerenderActiveTab()
    }

    func updatePlotTitle(_ title: String) {
        plotTitleOverride = title
        _rerenderActiveTab()
    }

    func updateXAxisLabel(_ label: String) {
        plotXLabelOverrides[activeTab] = label.isEmpty ? nil : label
        _rerenderActiveTab()
    }

    func updateYAxisLabel(_ label: String) {
        plotYLabelOverrides[activeTab] = label.isEmpty ? nil : label
        _rerenderActiveTab()
    }

    func updateSeriesLabel(index: Int, newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            plotSeriesLabelOverrides[activeTab]?.removeValue(forKey: index)
        } else {
            if plotSeriesLabelOverrides[activeTab] == nil {
                plotSeriesLabelOverrides[activeTab] = [:]
            }
            plotSeriesLabelOverrides[activeTab]![index] = trimmed
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
        currentRunTrace          = nil
        isAnalyzing              = false
        analysisMessage          = nil
        geometry                 = ThreeOmegaGeometry()
        v3Method                 = .highField
        fitRanges                = [ThreeOmegaFitRange()]
        activeTab                = .fieldSweep1omega
        showPlotGrid             = true
        plotLegendAnchor         = ""
        plotTitleOverride        = ""
        plotTitleSuffix          = ""
        plotLegendPoints         = [:]
        plotSeriesLabelOverrides = [:]
        plotXLabelOverrides      = [:]
        plotYLabelOverrides      = [:]
        rtQuery                  = ""
        rtSearchResults          = []
        rtSearchMessage          = nil
        isRTSearching            = false
        showRTPopover            = false
        selectedRTHit            = nil
        warningLog               = []
        cachedSampleNumericDisplay = [:]
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
    private func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }

        let tab            = activeTab
        let capturedGrid   = showPlotGrid
        let capturedAnchor = plotLegendAnchor
        let capturedLegend = plotLegendPoints[tab]
        let titleOverride  = plotTitleOverride
        let xLabelOverride = plotXLabelOverrides[tab] ?? ""
        let yLabelOverride = plotYLabelOverrides[tab] ?? ""
        let labelOverrides = plotSeriesLabelOverrides[tab] ?? [:]
        let capturedScaling = scalingResult
        let capturedGeometry = geometry
        let capturedSuffix  = plotTitleSuffix
        let capturedDevice  = ingestion.device

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.legendAnchor          = capturedAnchor
            r.legendPoint           = capturedLegend
            r.titleOverride         = titleOverride
            r.xLabelOverride        = xLabelOverride
            r.yLabelOverride        = yLabelOverride
            r.seriesLabelOverrides  = labelOverrides
            r.titleSuffix           = capturedSuffix

            let rendered: (Data?, WorkbenchPlotLayout?)
            switch tab {
            case .fieldSweep1omega:
                rendered = r.renderR1omega(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .fieldSweep3omega:
                rendered = r.renderR3omega(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .raheVsT:
                rendered = r.renderRAHEvsT(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .hcVsT:
                rendered = r.renderHcVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .rtCurve:
                rendered = ingestion.rtResult.map { r.renderRT(rt: $0) } ?? (nil, nil)
            case .scaling:
                if let sr = capturedScaling, capturedGeometry.isComplete {
                    rendered = r.renderScaling(result: sr, device: capturedDevice)
                } else {
                    rendered = (nil, nil)
                }
            }

            let plotData   = rendered.0
            let plotLayout = rendered.1
            await MainActor.run { [weak self] in
                guard let self, self.activeTab == tab else { return }
                switch tab {
                case .fieldSweep1omega: self.plotR1omega = plotData
                case .fieldSweep3omega: self.plotR3omega = plotData
                case .raheVsT:          self.plotRAHEvsT = plotData
                case .hcVsT:            self.plotHcvsT   = plotData
                case .rtCurve:          self.plotRT      = plotData
                case .scaling:          self.plotScaling = plotData
                }
                if let l = plotLayout { self.plotLayouts[tab] = l }
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

// MARK: - Warning log entry

struct ThreeOmegaWarningEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let source: String   // "Ingestion" or "Scaling"
    let message: String

    init(source: String, message: String) {
        self.timestamp = Date()
        self.source = source
        self.message = message
    }
}

// MARK: - WorkbenchPlottingStore conformance

extension ThreeOmegaWorkspaceStore: WorkbenchPlottingStore {}

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
