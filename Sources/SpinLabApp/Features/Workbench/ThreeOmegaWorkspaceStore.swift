import CryptoKit
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

    // MARK: - Analysis Pack (vault integration)

    /// Vault reference, set by WorkbenchFeatureStore after init.
    @ObservationIgnored var vault: AnalysisVault?

    /// ID of the pack that was last saved or loaded. nil = fresh (unsaved) analysis.
    var activePackID: AnalysisPack.ID?

    /// IDs of packs currently overlaid on RAHE tabs.
    var overlayPackIDs: [AnalysisPack.ID] = []

    /// Decoupled snapshots of overlay data — survive vault deletion.
    @ObservationIgnored var overlaySnapshots: [AnalysisPack.ID: OverlaySnapshot] = [:]

    // MARK: - Private

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var _renderRevision: UInt64 = 0
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
        activePackID = nil
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
            var params: [String: String] = ["device": device, "tabKey": tab.stableKey]
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
                .map { "\($0.tLo ?? 0)K-\($0.tHi ?? 9999)K" }
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
        let capturedLegend1    = plotLegendPoints[.fieldSweep1omega]
        let capturedLegend3    = plotLegendPoints[.fieldSweep3omega]

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.legendAnchor          = capturedAnchor
            r.stackOffsetMultiplier = capturedMultiplier
            r.minGapFraction        = capturedMinGap
            r.titleTemplate         = capturedTemplate
            r.titleTokens           = capturedTokens
            r.legendPoint           = capturedLegend1
            let r1 = r.renderR1omega(sweeps: ingestion.fieldSweeps, device: ingestion.device)
            r.legendPoint           = capturedLegend3
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

    // MARK: - Analysis Pack save / load / overlay

    /// Returns the existing pack that matches the current source files, if any.
    /// Used by the View to show "Save to X" vs "Update to X".
    var matchingVaultPack: AnalysisPack? {
        guard ingestionResult != nil, let vault else { return nil }
        let fingerprint = AnalysisPack.makeFingerprint(inputFiles: cachedInputFiles, rtFilePath: cachedRTFilePath)
        return vault.pack(forWorkflow: "3w", fingerprint: fingerprint)
            ?? activePackID.flatMap { vault.get(id: $0) }
    }

    /// Whether the current analysis has unsaved changes relative to the active pack.
    var hasUnsavedAnalysis: Bool {
        guard ingestionResult != nil else { return false }
        guard let packID = activePackID, let vault, let pack = vault.get(id: packID) else {
            // No active pack → any ingestion result is "unsaved"
            return ingestionResult != nil
        }
        // Compare config+result hash against stored pack
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

    /// Saves the current analysis state into the vault.
    /// `searchQueryText` is passed from WorkbenchFeatureStore (owns search query state).
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
        let fingerprint = AnalysisPack.makeFingerprint(inputFiles: cachedInputFiles, rtFilePath: cachedRTFilePath)

        // Match by fingerprint first, then fall back to activePackID
        let existingPack = vault.pack(forWorkflow: "3w", fingerprint: fingerprint)
            ?? activePackID.flatMap { vault.get(id: $0) }

        if let existing = existingPack {
            // Update existing pack (same source files)
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
            // New source files → create new pack
            let label = _autoPackLabel()
            do {
                let pack = try AnalysisPack(
                    label: label,
                    workflowID: "3w",
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

    /// Loads a pack from the vault into the workbench.
    /// `restoreSearchState` is a bridge closure from WorkbenchFeatureStore.
    func loadPack(id: AnalysisPack.ID, restoreSearchState: (([WorkflowMeasurementSearchHit], String) -> Void)) {
        // Cancel any in-flight analysis/scaling tasks to prevent stale overwrites
        analysisTask?.cancel()
        analysisTask = nil
        scalingTask?.cancel()
        scalingTask = nil

        guard let vault, let pack = vault.get(id: id) else {
            analysisMessage = "Pack not found."
            return
        }
        guard let config = try? pack.decodeConfig(ThreeOmegaPackConfig.self),
              let result = try? pack.decodeResult(ThreeOmegaPackResult.self) else {
            analysisMessage = "Failed to decode pack data."
            return
        }

        // Restore analysis params
        geometry = config.geometry
        fitRanges = config.fitRanges
        v3Method = ThreeOmegaV3Method(rawValue: config.v3Method) ?? .highField
        rahe1omegaMethod = ThreeOmegaV3Method(rawValue: config.rahe1Method) ?? .highField
        rahe3omegaMethod = ThreeOmegaV3Method(rawValue: config.rahe3Method) ?? .highField
        rtQuery = config.rtQuery
        selectedRTHit = config.selectedRTHit

        // Restore display settings
        if let tab = ThreeOmegaWorkbenchTab.allCases.first(where: { $0.stableKey == config.activeTab }) {
            activeTab = tab
        }
        titleTemplate = config.titleTemplate
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        showPlotGrid = config.showPlotGrid
        plotLegendAnchor = config.plotLegendAnchor
        plotTitleOverride = config.plotTitleOverride

        // Restore per-tab settings
        plotLegendPoints = [:]
        for (key, val) in config.plotLegendPoints {
            if let tab = ThreeOmegaWorkbenchTab.allCases.first(where: { $0.stableKey == key }) {
                plotLegendPoints[tab] = val.cgPoint
            }
        }
        plotSeriesLabelOverrides = [:]
        for (key, val) in config.plotSeriesLabelOverrides {
            if let tab = ThreeOmegaWorkbenchTab.allCases.first(where: { $0.stableKey == key }) {
                plotSeriesLabelOverrides[tab] = val
            }
        }
        plotXLabelOverrides = [:]
        for (key, val) in config.plotXLabelOverrides {
            if let tab = ThreeOmegaWorkbenchTab.allCases.first(where: { $0.stableKey == key }) {
                plotXLabelOverrides[tab] = val
            }
        }
        plotYLabelOverrides = [:]
        for (key, val) in config.plotYLabelOverrides {
            if let tab = ThreeOmegaWorkbenchTab.allCases.first(where: { $0.stableKey == key }) {
                plotYLabelOverrides[tab] = val
            }
        }

        // Restore search selection state
        cachedSearchResults = config.cachedSearchResults
        selectedSearchResultIDs = Set(config.selectedSearchResultIDs)

        // Restore results
        ingestionResult = result.ingestionResult
        scalingResult = result.scalingResult

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
        cachedRTFilePath = config.rtFilePath

        // Set active pack
        activePackID = id

        // Clear overlays
        overlayPackIDs = []
        overlaySnapshots = [:]

        // Bridge: restore search results into WorkbenchFeatureStore
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        // Re-render all tabs
        _rerenderAllTabs()
        _snapshotAndCacheManifestPayloads()

        analysisMessage = "Loaded: \(pack.label)"
    }

    /// Adds an overlay from a vault pack onto the current RAHE plots.
    func addOverlay(id: AnalysisPack.ID) {
        guard let vault, let pack = vault.get(id: id) else { return }
        guard let result = try? pack.decodeResult(ThreeOmegaPackResult.self) else { return }
        guard !overlayPackIDs.contains(id) else { return }

        overlaySnapshots[id] = OverlaySnapshot(
            label: pack.label,
            sweeps: result.ingestionResult.fieldSweeps,
            sourceFiles: pack.filePaths,
            sampleKeys: pack.sampleKeys
        )
        overlayPackIDs.append(id)
        _renderRAHEWithOverlays()
    }

    /// Removes an overlay.
    func removeOverlay(id: AnalysisPack.ID) {
        overlayPackIDs.removeAll { $0 == id }
        overlaySnapshots.removeValue(forKey: id)
        _renderRAHEWithOverlays()
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
        activePackID             = nil
        overlayPackIDs           = []
        overlaySnapshots         = [:]
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

        // For RAHE tabs with overlays, delegate to overlay renderer
        if !overlayPackIDs.isEmpty,
           (activeTab == .rahe1omegaVsT || activeTab == .rahe3omegaVsT) {
            _renderRAHEWithOverlays()
            return
        }

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

        _renderRevision &+= 1
        let revision = _renderRevision

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
                guard let self, self._renderRevision == revision else { return }
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

    private func _buildPackConfig() -> ThreeOmegaPackConfig {
        let legendPts: [String: CGPointCodable] = plotLegendPoints.reduce(into: [:]) { d, kv in
            d[kv.key.stableKey] = CGPointCodable(kv.value)
        }
        let seriesOverrides: [String: [Int: String]] = plotSeriesLabelOverrides.reduce(into: [:]) { d, kv in
            d[kv.key.stableKey] = kv.value
        }
        let xOverrides: [String: String] = plotXLabelOverrides.reduce(into: [:]) { d, kv in
            d[kv.key.stableKey] = kv.value
        }
        let yOverrides: [String: String] = plotYLabelOverrides.reduce(into: [:]) { d, kv in
            d[kv.key.stableKey] = kv.value
        }
        return ThreeOmegaPackConfig(
            device: ingestionResult?.device ?? "",
            geometry: geometry,
            fitRanges: fitRanges,
            v3Method: v3Method.rawValue,
            rahe1Method: rahe1omegaMethod.rawValue,
            rahe3Method: rahe3omegaMethod.rawValue,
            rtFilePath: cachedRTFilePath,
            sampleBatchAndSubstrate: cachedSearchResults.first?.sampleBatchAndSubstrate ?? "",
            activeTab: activeTab.stableKey,
            titleTemplate: titleTemplate,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: showPlotGrid,
            plotLegendAnchor: plotLegendAnchor,
            plotTitleOverride: plotTitleOverride,
            plotLegendPoints: legendPts,
            plotSeriesLabelOverrides: seriesOverrides,
            plotXLabelOverrides: xOverrides,
            plotYLabelOverrides: yOverrides,
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: Array(selectedSearchResultIDs),
            selectedRTHit: selectedRTHit,
            rtQuery: rtQuery,
            searchQueryText: ""   // filled by caller at WorkbenchFeatureStore level
        )
    }

    private func _buildPackResult() -> ThreeOmegaPackResult {
        ThreeOmegaPackResult(
            ingestionResult: ingestionResult!,
            scalingResult: scalingResult
        )
    }

    private func _autoPackLabel() -> String {
        let sample = cachedSearchResults.first?.sampleBatchAndSubstrate ?? "Unknown"
        let device = ingestionResult?.device ?? ""
        return device.isEmpty ? sample : "\(sample) \(device)"
    }

    /// Re-renders RAHE tabs with overlays merged, then updates manifest payloads.
    func _renderRAHEWithOverlays() {
        guard let ingestion = ingestionResult else { return }

        // Build groups: first = active analysis, rest = overlays
        var groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])] = []
        let activeLabel = _autoPackLabel()
        groups.append((label: activeLabel, sweeps: ingestion.fieldSweeps, sourceFiles: cachedInputFiles))
        for oid in overlayPackIDs {
            if let snap = overlaySnapshots[oid] {
                groups.append((label: snap.label, sweeps: snap.sweeps, sourceFiles: snap.sourceFiles))
            }
        }

        let capturedGrid = showPlotGrid
        let capturedAnchor = plotLegendAnchor
        let capturedLegend1 = plotLegendPoints[.rahe1omegaVsT]
        let capturedLegend3 = plotLegendPoints[.rahe3omegaVsT]
        let titleOverride = plotTitleOverride
        let capturedTemplate = titleTemplate
        let capturedTokens = _titleTokens
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod
        let capturedXLabel1 = plotXLabelOverrides[.rahe1omegaVsT] ?? ""
        let capturedYLabel1 = plotYLabelOverrides[.rahe1omegaVsT] ?? ""
        let capturedXLabel3 = plotXLabelOverrides[.rahe3omegaVsT] ?? ""
        let capturedYLabel3 = plotYLabelOverrides[.rahe3omegaVsT] ?? ""
        let capturedSeriesOverrides1 = plotSeriesLabelOverrides[.rahe1omegaVsT] ?? [:]
        let capturedSeriesOverrides3 = plotSeriesLabelOverrides[.rahe3omegaVsT] ?? [:]

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self, groups] in
            var r1 = ThreeOmegaPlotRenderer()
            r1.showGrid = capturedGrid
            r1.legendAnchor = capturedAnchor
            r1.legendPoint = capturedLegend1
            r1.titleOverride = titleOverride
            r1.xLabelOverride = capturedXLabel1
            r1.yLabelOverride = capturedYLabel1
            r1.seriesLabelOverrides = capturedSeriesOverrides1
            r1.titleTemplate = capturedTemplate
            r1.titleTokens = capturedTokens
            let rahe1 = r1.renderRAHE1omegaVsTMulti(groups: groups, method: capturedRAHE1Method)

            var r3 = ThreeOmegaPlotRenderer()
            r3.showGrid = capturedGrid
            r3.legendAnchor = capturedAnchor
            r3.legendPoint = capturedLegend3
            r3.titleOverride = titleOverride
            r3.xLabelOverride = capturedXLabel3
            r3.yLabelOverride = capturedYLabel3
            r3.seriesLabelOverrides = capturedSeriesOverrides3
            r3.titleTemplate = capturedTemplate
            r3.titleTokens = capturedTokens
            let rahe3 = r3.renderRAHE3omegaVsTMulti(groups: groups, method: capturedRAHE3Method)

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                self.plotRAHE1omegaVsT = rahe1.0
                self.plotRAHE3omegaVsT = rahe3.0
                if let l = rahe1.1 { self.plotLayouts[.rahe1omegaVsT] = l }
                if let l = rahe3.1 { self.plotLayouts[.rahe3omegaVsT] = l }

                // Rebuild manifest payloads with individual sourceRef per file (not ;-joined)
                self._rebuildOverlayManifestPayloads(groups: groups)
            }
        }
    }

    /// Rebuilds manifest payloads for RAHE overlay tabs with one sourceRef per file.
    private func _rebuildOverlayManifestPayloads(
        groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])]
    ) {
        // Collect all source files across all groups (individual entries, not ;-joined)
        let allFiles = groups.flatMap(\.sourceFiles)
        let device = ingestionResult?.device ?? ""

        for tab in [ThreeOmegaWorkbenchTab.rahe1omegaVsT, .rahe3omegaVsT] {
            let isR1 = tab == .rahe1omegaVsT
            let method = isR1 ? rahe1omegaMethod : rahe3omegaMethod
            let methodTag = method == .highField ? "HFE" : "WA"
            let hLabel = isR1 ? "1ω" : "3ω"

            let series = allFiles.map {
                WorkbenchPlotSeries(label: URL(fileURLWithPath: $0).lastPathComponent, x: [], y: [], sourceRef: $0)
            }
            let params: [String: String] = ["device": device, "tabKey": tab.stableKey, "v3method": methodTag]
            let title = WorkbenchTitleResolver.resolve(
                template: titleTemplate,
                tokens: _titleTokens.merging(["tab": "RAHE(\(hLabel))", "device": device]) { _, new in new }
            ) + " (\(methodTag))"

            cachedManifestPayloads[tab] = WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: title,
                axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(\(hLabel)) (Ω)"),
                series: series,
                semanticParams: params
            )
        }
    }

    /// Re-renders all tabs from cached ingestion/scaling results (used after pack load).
    private func _rerenderAllTabs() {
        guard let ingestion = ingestionResult else { return }

        let capturedGrid       = showPlotGrid
        let capturedAnchor     = plotLegendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod

        Task.detached(priority: .userInitiated) { [weak self, ingestion] in
            var renderer = ThreeOmegaPlotRenderer()
            renderer.showGrid              = capturedGrid
            renderer.legendAnchor          = capturedAnchor
            renderer.stackOffsetMultiplier = capturedMultiplier
            renderer.minGapFraction        = capturedMinGap
            renderer.titleTemplate         = capturedTemplate
            renderer.titleTokens           = capturedTokens
            let plots = renderer.renderAllTabs(result: ingestion, rahe1Method: capturedRAHE1Method, rahe3Method: capturedRAHE3Method)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self._applyPlots(plots)
            }
        }

        // Also re-run scaling if geometry is complete
        if scalingResult != nil, geometry.isComplete {
            runScaling()
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

    var activeChartSampleKeys: [String] {
        guard !overlayPackIDs.isEmpty,
              (activeTab == .rahe1omegaVsT || activeTab == .rahe3omegaVsT) else {
            return cachedSampleKeys
        }
        // Merge overlay sample keys (deduplicated, stable order)
        var seen = Set(cachedSampleKeys)
        var merged = cachedSampleKeys
        for oid in overlayPackIDs {
            if let snap = overlaySnapshots[oid] {
                for key in snap.sampleKeys where seen.insert(key).inserted {
                    merged.append(key)
                }
            }
        }
        return merged
    }

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

// MARK: - Overlay snapshot

/// Lightweight snapshot of overlay data — decoupled from vault so overlays survive deletion.
struct OverlaySnapshot: Sendable {
    let label: String
    let sweeps: [ThreeOmegaFieldSweepResult]
    let sourceFiles: [String]
    let sampleKeys: [String]
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
