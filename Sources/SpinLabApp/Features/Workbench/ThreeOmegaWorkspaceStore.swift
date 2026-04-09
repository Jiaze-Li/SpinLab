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

    private static let rtQueryDefaultsKey = "workbench.searchQuery.3w.rt"

    var rtQuery: String = "" {
        didSet { UserDefaults.standard.set(rtQuery, forKey: Self.rtQueryDefaultsKey) }
    }
    var rtSearchResults: [WorkflowMeasurementSearchHit] = []
    var rtSearchMessage: String?
    var isRTSearching: Bool = false
    var showRTPopover: Bool = false
    private(set) var selectedRTHit: WorkflowMeasurementSearchHit?

    init() {
        self.rtQuery = UserDefaults.standard.string(forKey: Self.rtQueryDefaultsKey) ?? ""
    }

    func selectRTHit(_ hit: WorkflowMeasurementSearchHit) {
        selectedRTHit = hit
        rtSearchResults = []
        showRTPopover = false
    }

    func clearRTSelection() {
        selectedRTHit = nil
    }

    /// Set during restore; consumed on first 3w search to rebuild selectedRTHit.
    var pendingRTSidecarPath: String?

    /// Applies a pre-built hit from background restoration. Called by WorkbenchFeatureStore.
    func applyRestoredRTHit(_ hit: WorkflowMeasurementSearchHit) {
        selectRTHit(hit)
        pendingRTSidecarPath = nil
    }

    /// Clears pending restore (called when restore fails).
    func clearPendingRTRestore() {
        pendingRTSidecarPath = nil
    }

    /// Parses a sidecar file and rebuilds a lightweight hit. Runs off MainActor.
    nonisolated static func rebuildRTHit(fromSidecarPath sidecarPath: String) -> WorkflowMeasurementSearchHit? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sidecarPath) else { return nil }

        let suffix = ".spinlab.json"
        guard sidecarPath.hasSuffix(suffix) else { return nil }
        let baseName = String(sidecarPath.dropLast(suffix.count))
        guard fm.fileExists(atPath: baseName) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sidecarPath)),
              let sidecar = try? decoder.decode(SpinLabFileSidecar.self, from: data) else { return nil }

        let wfID = sidecar.workflow.lowercased()
        guard wfID == "3w" || wfID == "rt" else { return nil }

        return WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: baseName,
            sourceFilePath: sidecar.sourceFilePath,
            workflowID: sidecar.workflow,
            workflowDisplayName: sidecar.workflowDisplayName,
            workflowCanonicalID: wfID,
            batchID: "",
            sampleKey: "",
            sampleSubstrate: "",
            conditions: sidecar.conditions,
            channels: sidecar.channels,
            appliedAt: sidecar.appliedAt
        )
    }

    // MARK: - Geometry (session-only, not persisted)

    var geometry = ThreeOmegaGeometry()
    var v3Method: ThreeOmegaV3Method = .highField

    // MARK: - Per-tab RAHE method (independent of v3Method used by Scaling Law)

    var rahe1omegaMethod: ThreeOmegaV3Method = .highField
    var rahe3omegaMethod: ThreeOmegaV3Method = .highField

    /// The RAHE method for the currently active RAHE tab (nil if not on RAHE tab).
    var activeRAHEMethod: ThreeOmegaV3Method? {
        switch activeTab {
        case .rahe1omegaVsT: return rahe1omegaMethod
        case .rahe3omegaVsT: return rahe3omegaMethod
        default: return nil
        }
    }

    /// Explicit RAHE method switch — re-renders active tab and refreshes manifests.
    func updateRAHEMethod(_ method: ThreeOmegaV3Method) {
        switch activeTab {
        case .rahe1omegaVsT:
            guard method != rahe1omegaMethod else { return }
            rahe1omegaMethod = method
        case .rahe3omegaVsT:
            guard method != rahe3omegaMethod else { return }
            rahe3omegaMethod = method
        default: return
        }
        _rerenderActiveTab()
        _refreshManifestPayloads()
    }

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
    private(set) var plotRAHE1omegaVsT: Data?
    private(set) var plotRAHE3omegaVsT: Data?
    private(set) var plotHcvsT: Data?
    private(set) var plotRT: Data?
    private(set) var plotScaling: Data?

    // MARK: - Interactive plot layouts (per tab, for WorkbenchPlotCanvas)

    private(set) var plotLayouts: [ThreeOmegaWorkbenchTab: WorkbenchPlotLayout] = [:]

    // MARK: - Plot controls (global, apply to the active tab on re-render)

    var showPlotGrid: Bool = true
    var plotLegendAnchor: String = ""           // "" = top-right (default)
    var plotTitleOverride: String = ""
    var titleTemplate: String = "#tab #method #device #sample #氧压 #能量"
    var stackOffsetMultiplier: Double = 1.2     // 0 = no stacking; >0 = curve spacing
    var minGapFraction: Double = 0.15            // minimum gap as fraction of max peak-to-peak

    // Per-tab state (legend drag position, axis label overrides, and series label renames)
    var plotLegendPoints: [ThreeOmegaWorkbenchTab: CGPoint] = [:]
    var plotSeriesLabelOverrides: [ThreeOmegaWorkbenchTab: [Int: String]] = [:]
    /// Display-only x-axis label overrides per tab (does not affect data).
    var plotXLabelOverrides: [ThreeOmegaWorkbenchTab: String] = [:]
    /// Display-only y-axis label overrides per tab (does not affect data).
    var plotYLabelOverrides: [ThreeOmegaWorkbenchTab: String] = [:]

    /// Cached per-sample numericDisplay from library index, populated by WorkbenchFeatureStore after search.
    var cachedSampleNumericDisplay: [String: [String: String]] = [:]
    /// Title tokens resolved from selected hit (sample + numericDisplay). Tab/device added by renderer.
    private(set) var _titleTokens: [String: String] = [:]

    // MARK: - Persistence

    /// Set by WorkbenchFeatureStore during search; required for artifact I/O.
    var lastLibraryRootPath: String = ""
    private(set) var persistenceOutcome: PersistenceOutcome?

    /// Cached manifest payloads per tab, built at render time with sourceRef populated.
    /// Used by SaveActiveChartToLibraryUseCase for stable identity keys.
    @ObservationIgnored private(set) var cachedManifestPayloads: [ThreeOmegaWorkbenchTab: WorkbenchPlotPayload] = [:]
    /// Sample keys snapshot from the analysis run that produced current plots.
    @ObservationIgnored private(set) var cachedSampleKeys: [String] = []
    /// Per-sample conditions snapshot from the analysis run.
    @ObservationIgnored private(set) var cachedConditionsBySampleKey: [String: [String: String]] = [:]
    /// Input file paths snapshot from the analysis run.
    @ObservationIgnored private(set) var cachedInputFiles: [String] = []
    /// RT file path snapshot from the analysis run.
    @ObservationIgnored private(set) var cachedRTFilePath: String? = nil

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

        // Build title token dictionary from representative hit (stable: sorted by path)
        if let hit = selectedHits.first {
            var tokens: [String: String] = ["sample": hit.sampleBatchAndSubstrate]
            let numericDisplay = cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
            for (k, v) in numericDisplay { tokens[k] = v }
            _titleTokens = tokens
        } else {
            _titleTokens = [:]
        }

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        _clearPlots()

        let capturedGrid       = showPlotGrid
        let capturedAnchor     = plotLegendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedRAHE1MethodForPlots = rahe1omegaMethod
        let capturedRAHE3MethodForPlots = rahe3omegaMethod

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
                renderer.minGapFraction        = capturedMinGap
                renderer.titleTemplate          = capturedTemplate
                renderer.titleTokens            = capturedTokens
                let plots = renderer.renderAllTabs(result: result, rahe1Method: capturedRAHE1MethodForPlots, rahe3Method: capturedRAHE3MethodForPlots)
                return (result, plots)
            }.value

            guard !Task.isCancelled else { return }
            self.ingestionResult = result
            self._applyPlots(plots)

            let sweepCount = result.fieldSweeps.count
            let rtNote     = result.rtResult != nil ? ", RT curve loaded" : ""
            self.analysisMessage = "Analyzed \(sweepCount) field-sweep file(s)\(rtNote)."

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
            self._snapshotAndCacheManifestPayloads()
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
        let capturedTemplate = titleTemplate
        let capturedTokens   = _titleTokens
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
                renderer.titleTemplate = capturedTemplate
                renderer.titleTokens   = capturedTokens
                let method = capturedV3Method == .highField ? "(HFE)" : "(WA)"
                let (data, layout) = renderer.renderScaling(result: res, device: capturedDevice, method: method)
                return (res, data, layout)
            }.value

            guard !Task.isCancelled else { return }
            self.scalingResult = scalingRes
            self.plotScaling   = scalingData
            if let l = scalingLayout { self.plotLayouts[.scaling] = l }
            // Refresh manifest payloads (v3Method may have changed) using frozen inputFiles
            self._refreshManifestPayloads()

            for w in scalingRes.warnings {
                self.warningLog.append(ThreeOmegaWarningEntry(source: "Scaling", message: w))
                print("[SpinLab][3ω Scaling] \(w)")
            }

            // Scaling results are shown in the dedicated ScalingResultPanel below the plot.
            // Do not overwrite analysisMessage — keep the ingestion summary visible.
        }
    }

    // MARK: - Persist to Library

    /// Saves the active tab's chart (+ metrics for scaling) to Library.
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
            switch outcome {
            case .success:
                self.analysisMessage = "Saved to Library."
            case .partial(_, let err):
                self.analysisMessage = "Chart saved; metric error: \(err)"
            case .failure(let err):
                self.analysisMessage = "Save failed: \(err)"
            }
            onComplete?()
        }
    }

    // MARK: - Manifest payload helpers

    /// Builds a manifest payload for the given tab with sourceRef properly filled.
    private func _buildManifestPayload(
        tab: ThreeOmegaWorkbenchTab,
        device: String,
        inputFiles: [String],
        rtFilePath: String?,
        titleTemplate: String,
        titleTokens: [String: String],
        v3Method: ThreeOmegaV3Method
    ) -> WorkbenchPlotPayload? {
        let methodTag = v3Method == .highField ? "HFE" : "WA"

        func resolveTitle(_ tabName: String) -> String {
            var tokens = titleTokens
            tokens["tab"] = tabName
            tokens["device"] = device
            var result = titleTemplate
            for (key, value) in tokens {
                result = result.replacingOccurrences(of: "#\(key)", with: value)
            }
            result = result.replacingOccurrences(of: "#\\S+", with: "", options: .regularExpression)
            return result.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        func makePayload(title: String, xField: String, yField: String, files: [String], extraParams: [String: String] = [:]) -> WorkbenchPlotPayload {
            var params: [String: String] = ["device": device]
            for (k, v) in extraParams { params[k] = v }
            return WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: title,
                axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
                series: files.map { WorkbenchPlotSeries(label: URL(fileURLWithPath: $0).lastPathComponent, x: [], y: [], sourceRef: $0) },
                semanticParams: params
            )
        }

        switch tab {
        case .fieldSweep1omega:
            return makePayload(title: resolveTitle("R(1ω)"), xField: "H (T)", yField: "R(1ω) (Ω)", files: inputFiles)
        case .fieldSweep3omega:
            return makePayload(title: resolveTitle("R(3ω)"), xField: "H (T)", yField: "R(3ω) (Ω)", files: inputFiles)
        case .rahe1omegaVsT:
            let tag = rahe1omegaMethod == .highField ? "HFE" : "WA"
            return makePayload(
                title: resolveTitle("RAHE(1ω)") + " (\(tag))",
                xField: "T (K)", yField: "RAHE(1ω) (Ω)", files: inputFiles,
                extraParams: ["v3method": tag]
            )
        case .rahe3omegaVsT:
            let tag = rahe3omegaMethod == .highField ? "HFE" : "WA"
            return makePayload(
                title: resolveTitle("RAHE(3ω)") + " (\(tag))",
                xField: "T (K)", yField: "RAHE(3ω) (Ω)", files: inputFiles,
                extraParams: ["v3method": tag]
            )
        case .hcVsT:
            return makePayload(title: resolveTitle("Hc"), xField: "T (K)", yField: "Hc (T)", files: inputFiles)
        case .rtCurve:
            guard let rtPath = rtFilePath else { return nil }
            return makePayload(title: resolveTitle("RT"), xField: "T (K)", yField: "Rxx (Ω)", files: [rtPath])
        case .scaling:
            let rangeSig = fitRanges
                .sorted { ($0.tLo ?? 0) < ($1.tLo ?? 0) }
                .map { "\(Int(($0.tLo ?? 0).rounded()))K-\(Int(($0.tHi ?? 9999).rounded()))K" }
                .joined(separator: ",")
            return makePayload(
                title: resolveTitle("Scaling Law") + " (\(methodTag))",
                xField: "σ²_xx (S²/m²)", yField: "E(3ω)_AHE / (E³_xx · σ_xx)",
                files: inputFiles,
                extraParams: ["v3method": methodTag, "fitRanges": rangeSig]
            )
        }
    }

    /// Caches manifest payloads for all tabs after analysis completes.
    /// Snapshots sampleKeys, conditions, inputFiles from the current selection.
    /// Called once after runAnalysis completes; scaling re-runs call `_refreshManifestPayloads()` instead.
    private func _snapshotAndCacheManifestPayloads() {
        let selectedHits = cachedSearchResults.filter { selectedSearchResultIDs.contains($0.id) }
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })

        // Snapshot from current selection — frozen for the lifetime of this analysis run
        cachedInputFiles = selectedHits.map { $0.measurementFilePath }
        cachedRTFilePath = selectedRTHit?.measurementFilePath
        var seen = Set<String>()
        cachedSampleKeys = selectedHits.compactMap { seen.insert($0.sampleKey).inserted ? $0.sampleKey : nil }
        var condMap: [String: [String: String]] = [:]
        for hit in selectedHits where condMap[hit.sampleKey] == nil {
            condMap[hit.sampleKey] = hit.conditions
        }
        cachedConditionsBySampleKey = condMap

        _refreshManifestPayloads()
    }

    /// Rebuilds manifest payloads from cached (frozen) inputFiles/sampleKeys.
    /// Safe to call after scaling reruns — does NOT re-read UI selection.
    private func _refreshManifestPayloads() {
        let device = ingestionResult?.device ?? ""

        cachedManifestPayloads = [:]
        for tab in ThreeOmegaWorkbenchTab.allCases {
            cachedManifestPayloads[tab] = _buildManifestPayload(
                tab: tab,
                device: device,
                inputFiles: cachedInputFiles,
                rtFilePath: cachedRTFilePath,
                titleTemplate: titleTemplate,
                titleTokens: _titleTokens,
                v3Method: v3Method
            )
        }
    }

    // MARK: - Stack offset

    /// Re-renders Tab 1 and Tab 2 after stack offset multiplier changes.
    func rerenderFieldSweepTabs() {
        guard let ingestion = ingestionResult else { return }
        let capturedGrid       = showPlotGrid
        let capturedAnchor     = plotLegendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.legendAnchor          = capturedAnchor
            r.stackOffsetMultiplier = capturedMultiplier
            r.minGapFraction        = capturedMinGap
            r.titleTemplate         = capturedTemplate
            r.titleTokens           = capturedTokens
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
        _titleTokens             = [:]
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
        plotR1omega        = plots.r1omega
        plotR3omega        = plots.r3omega
        plotRAHE1omegaVsT  = plots.rahe1omegaVsT
        plotRAHE3omegaVsT  = plots.rahe3omegaVsT
        plotHcvsT          = plots.hcVsT
        plotRT             = plots.rtCurve
        plotScaling        = plots.scaling
        if let l = plots.layoutR1omega         { plotLayouts[.fieldSweep1omega] = l }
        if let l = plots.layoutR3omega         { plotLayouts[.fieldSweep3omega] = l }
        if let l = plots.layoutRAHE1omegaVsT   { plotLayouts[.rahe1omegaVsT]   = l }
        if let l = plots.layoutRAHE3omegaVsT   { plotLayouts[.rahe3omegaVsT]   = l }
        if let l = plots.layoutHcVsT           { plotLayouts[.hcVsT]           = l }
        if let l = plots.layoutRTCurve         { plotLayouts[.rtCurve]         = l }
    }

    /// Re-renders only the active tab using cached ingestion/scaling result.
    private func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }

        let tab            = activeTab
        let capturedGrid   = showPlotGrid
        let capturedAnchor = plotLegendAnchor
        let capturedLegend = plotLegendPoints[tab]
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let titleOverride  = plotTitleOverride
        let xLabelOverride = plotXLabelOverrides[tab] ?? ""
        let yLabelOverride = plotYLabelOverrides[tab] ?? ""
        let labelOverrides = plotSeriesLabelOverrides[tab] ?? [:]
        let capturedScaling = scalingResult
        let capturedGeometry = geometry
        let capturedTemplate = titleTemplate
        let capturedTokens  = _titleTokens
        let capturedDevice  = ingestion.device
        let capturedV3Method = v3Method
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.legendAnchor          = capturedAnchor
            r.legendPoint           = capturedLegend
            r.stackOffsetMultiplier = capturedMultiplier
            r.minGapFraction        = capturedMinGap
            r.titleOverride         = titleOverride
            r.xLabelOverride        = xLabelOverride
            r.yLabelOverride        = yLabelOverride
            r.seriesLabelOverrides  = labelOverrides
            r.titleTemplate         = capturedTemplate
            r.titleTokens           = capturedTokens

            let rendered: (Data?, WorkbenchPlotLayout?)
            switch tab {
            case .fieldSweep1omega:
                rendered = r.renderR1omega(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .fieldSweep3omega:
                rendered = r.renderR3omega(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .rahe1omegaVsT:
                rendered = r.renderRAHE1omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE1Method)
            case .rahe3omegaVsT:
                rendered = r.renderRAHE3omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE3Method)
            case .hcVsT:
                rendered = r.renderHcVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            case .rtCurve:
                rendered = ingestion.rtResult.map { r.renderRT(rt: $0) } ?? (nil, nil)
            case .scaling:
                if let sr = capturedScaling, capturedGeometry.isComplete {
                    let method = capturedV3Method == .highField ? "(HFE)" : "(WA)"
                    rendered = r.renderScaling(result: sr, device: capturedDevice, method: method)
                } else {
                    rendered = (nil, nil)
                }
            }

            let plotData   = rendered.0
            let plotLayout = rendered.1
            await MainActor.run { [weak self] in
                guard let self, self.activeTab == tab else { return }
                switch tab {
                case .fieldSweep1omega: self.plotR1omega        = plotData
                case .fieldSweep3omega: self.plotR3omega        = plotData
                case .rahe1omegaVsT:    self.plotRAHE1omegaVsT  = plotData
                case .rahe3omegaVsT:    self.plotRAHE3omegaVsT  = plotData
                case .hcVsT:            self.plotHcvsT          = plotData
                case .rtCurve:          self.plotRT             = plotData
                case .scaling:          self.plotScaling        = plotData
                }
                if let l = plotLayout { self.plotLayouts[tab] = l }
            }
        }
    }

    private func _clearPlots() {
        plotR1omega        = nil
        plotR3omega        = nil
        plotRAHE1omegaVsT  = nil
        plotRAHE3omegaVsT  = nil
        plotHcvsT          = nil
        plotRT      = nil
        plotScaling = nil
        plotLayouts = [:]
        cachedManifestPayloads = [:]
        cachedSampleKeys = []
        cachedConditionsBySampleKey = [:]
        cachedInputFiles = []
        cachedRTFilePath = nil
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

// MARK: - ActiveChartProviding conformance

extension ThreeOmegaWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? {
        switch activeTab {
        case .fieldSweep1omega: return plotR1omega
        case .fieldSweep3omega: return plotR3omega
        case .rahe1omegaVsT:    return plotRAHE1omegaVsT
        case .rahe3omegaVsT:    return plotRAHE3omegaVsT
        case .hcVsT:            return plotHcvsT
        case .rtCurve:          return plotRT
        case .scaling:          return plotScaling
        }
    }

    var activeChartManifestPayload: WorkbenchPlotPayload? {
        cachedManifestPayloads[activeTab]
    }

    var activeChartSampleKeys: [String] { cachedSampleKeys }

    func buildActiveChartMetrics() -> [PendingMetricEntry] {
        guard activeTab == .scaling,
              let scaling = scalingResult, !scaling.segments.isEmpty else {
            return []
        }
        guard let sampleKey = cachedSampleKeys.first else { return [] }
        let methodTag = v3Method == .highField ? "HFE" : "WA"
        let device = ingestionResult?.device ?? ""

        var entries: [PendingMetricEntry] = []
        for seg in scaling.segments {
            var segConditions: [String: String] = [
                "range": "\(Int(seg.tLo.rounded()))K–\(Int(seg.tHi.rounded()))K",
                "v3method": methodTag
            ]
            if !device.isEmpty { segConditions["device"] = device }

            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "alpha", value: seg.alpha * 1e31, canonicalUnit: "Ω·μm³·cm²·V⁻²·S⁻²", conditions: segConditions))
            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "beta", value: seg.beta * 1e20, canonicalUnit: "Ω·μm³·V⁻²", conditions: segConditions))
            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "r_squared", value: seg.rSquared, canonicalUnit: "", conditions: segConditions))
        }
        return entries
    }
}

// MARK: - Rendered plot bundle

struct ThreeOmegaRenderedPlots: Sendable {
    var r1omega:        Data?
    var r3omega:        Data?
    var rahe1omegaVsT:  Data?
    var rahe3omegaVsT:  Data?
    var hcVsT:          Data?
    var rtCurve:        Data?
    var scaling:        Data?
    // Layouts for interactive WorkbenchPlotCanvas
    var layoutR1omega:         WorkbenchPlotLayout?
    var layoutR3omega:         WorkbenchPlotLayout?
    var layoutRAHE1omegaVsT:   WorkbenchPlotLayout?
    var layoutRAHE3omegaVsT:   WorkbenchPlotLayout?
    var layoutHcVsT:           WorkbenchPlotLayout?
    var layoutRTCurve:         WorkbenchPlotLayout?
    var layoutScaling:         WorkbenchPlotLayout?
}
