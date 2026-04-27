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
            conditions: sidecar.effectiveConditions,
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
        switch tabs.activeTab {
        case .rahe1omegaVsT: return rahe1omegaMethod
        case .rahe3omegaVsT: return rahe3omegaMethod
        default: return nil
        }
    }

    /// Explicit RAHE method switch — re-renders active tab and refreshes manifests.
    func updateRAHEMethod(_ method: ThreeOmegaV3Method) {
        switch tabs.activeTab {
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
    var currentRunTrace: WorkbenchRunTraceProjection?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Warning log (persists across runs within the session)

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()

    // MARK: - Multi-tab render state (shell capability)

    var tabs = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: .fieldSweep1omega)

    // MARK: - Plot controls (workflow-specific)

    var titleTemplate: String = "#tab #method #device #sample #氧压 #能量"
    var stackOffsetMultiplier: Double = 1.2     // 0 = no stacking; >0 = curve spacing
    var minGapFraction: Double = 0.15            // minimum gap as fraction of max peak-to-peak

    /// Cached per-sample numericDisplay from library index, populated by WorkbenchFeatureStore after search.
    var cachedSampleNumericDisplay: [String: [String: String]] = [:]
    /// Title tokens resolved from selected hit (sample + numericDisplay). Tab/device added by renderer.
    private(set) var _titleTokens: [String: String] = [:]

    // MARK: - Persistence

    /// Set by WorkbenchFeatureStore during search; required for artifact I/O.
    var lastLibraryRootPath: String = ""
    private(set) var persistenceOutcome: PersistenceOutcome?

    // cachedManifestPayloads now managed by tabs (TabRenderManager)
    /// Sample keys snapshot from the analysis run that produced current plots.
    @ObservationIgnored private(set) var cachedSampleKeys: [String] = []
    /// Per-sample conditions snapshot from the analysis run.
    @ObservationIgnored private(set) var cachedConditionsBySampleKey: [String: [String: String]] = [:]
    /// Input file paths snapshot from the analysis run.
    @ObservationIgnored private(set) var cachedInputFiles: [String] = []
    /// RT file path snapshot from the analysis run.
    @ObservationIgnored private(set) var cachedRTFilePath: String? = nil

    // MARK: - Related charts (hover popover)

    /// Charts grouped by canonical inputFiles key, loaded from library indices.
    private(set) var relatedChartsGrouped: [String: [WorkbenchResultReference]] = [:]
    @ObservationIgnored private var relatedChartsTask: Task<Void, Never>?

    /// Refreshes the related charts cache from library indices.
    /// Cancels any in-flight load and guards against stale results.
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
        relatedChartsTask?.cancel()
        relatedChartsTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                LoadRelatedChartsUseCase().execute(sampleKeys: keys, libraryRootURL: rootURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.relatedChartsGrouped = result
        }
    }

    /// Returns related charts for a specific tab based on that tab's inputFiles.
    func relatedCharts(for tab: ThreeOmegaWorkbenchTab) -> [WorkbenchResultReference] {
        guard let payload = tabs.output(for: tab).manifestPayload else { return [] }
        let inputFiles = payload.series.compactMap(\.sourceRef)
        guard !inputFiles.isEmpty else { return [] }
        let key = InputFilesCanonicalKey.make(from: inputFiles)
        return relatedChartsGrouped[key] ?? []
    }

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
        relatedChartsTask?.cancel()
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

        let capturedGrid       = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor     = tabs.legendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedRAHE1MethodForPlots = rahe1omegaMethod
        let capturedRAHE3MethodForPlots = rahe3omegaMethod

        let capturedRTHit = selectedRTHit
        let capturedNumericDisplay: [String: [String: String]] = cachedSampleNumericDisplay
        let capturedOrder1 = tabs.state(for: .fieldSweep1omega).seriesOrder
        let capturedOrder3 = tabs.state(for: .fieldSweep3omega).seriesOrder

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let (result, plots, aligned1, aligned3) = await Task.detached(priority: .userInitiated) { [selectedHits] in
                let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                let result = ingestUseCase.execute(hits: selectedHits, rtHit: capturedRTHit, numericDisplayBySample: capturedNumericDisplay)
                let defaultIDs = result.fieldSweeps.compactMap(\.sampleID)
                let aligned1 = ThreeOmegaWorkspaceStore.alignSeriesOrder(old: capturedOrder1, defaultIDs: defaultIDs)
                let aligned3 = ThreeOmegaWorkspaceStore.alignSeriesOrder(old: capturedOrder3, defaultIDs: defaultIDs)
                var renderer = ThreeOmegaPlotRenderer()
                renderer.showGrid              = capturedGrid
                renderer.seriesRenderMode      = capturedRenderMode
                renderer.chartStyleOverrides   = capturedStyleOverrides
                renderer.legendAnchor          = capturedAnchor
                renderer.stackOffsetMultiplier = capturedMultiplier
                renderer.minGapFraction        = capturedMinGap
                renderer.titleTemplate          = capturedTemplate
                renderer.titleTokens            = capturedTokens
                let plots = renderer.renderAllTabs(result: result, seriesOrder1omega: aligned1, seriesOrder3omega: aligned3, rahe1Method: capturedRAHE1MethodForPlots, rahe3Method: capturedRAHE3MethodForPlots)
                return (result, plots, aligned1, aligned3)
            }.value

            guard !Task.isCancelled else { return }
            self.ingestionResult = result
            self._applyPlots(plots)
            self.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].seriesOrder = aligned1
            self.tabs.tabStates[.fieldSweep3omega, default: TabRenderState()].seriesOrder = aligned3

            // Pipeline warnings (legend resolver)
            for w in plots.pipelineWarnings {
                self.appendWarning(source: "Legend", message: w)
            }

            let sweepCount = result.fieldSweeps.count
            let rtNote     = result.rtResult != nil ? ", RT curve loaded" : ""
            self.analysisMessage = "Analyzed \(sweepCount) field-sweep file(s)\(rtNote)."

            for w in result.warnings {
                self.appendWarning(source: "Ingestion", message: w)
            }

            self._snapshotAndCacheManifestPayloads()
            self.commitRunTrace()
            self.isAnalyzing = false
            self.refreshRelatedCharts()
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
        let capturedGrid     = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor   = tabs.legendAnchor
        let capturedLegend   = tabs.state(for: .scaling).legendPoint?.cgPoint
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
                renderer.seriesRenderMode = capturedRenderMode
                renderer.chartStyleOverrides = capturedStyleOverrides
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
            self.tabs.setOutput(TabRenderOutput(imageData: scalingData, layout: scalingLayout, manifestPayload: nil), for: .scaling)
            // Refresh manifest payloads (v3Method may have changed) using frozen inputFiles
            self._refreshManifestPayloads()

            for w in scalingRes.warnings {
                self.appendWarning(source: "Scaling", message: w)
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
            return makePayload(title: resolveTitle("Hc"), xField: "T (K)", yField: "Hc (Oe)", files: inputFiles)
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

        for tab in ThreeOmegaWorkbenchTab.allCases {
            let payload = _buildManifestPayload(
                tab: tab,
                device: device,
                inputFiles: cachedInputFiles,
                rtFilePath: cachedRTFilePath,
                titleTemplate: titleTemplate,
                titleTokens: _titleTokens,
                v3Method: v3Method
            )
            var existing = tabs.tabOutputs[tab] ?? TabRenderOutput()
            existing.manifestPayload = payload
            tabs.tabOutputs[tab] = existing
        }
    }

    // MARK: - Stack offset

    /// Re-renders Tab 1 and Tab 2 after stack offset multiplier changes.
    func rerenderFieldSweepTabs() {
        guard let ingestion = ingestionResult else { return }
        let capturedGrid       = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor     = tabs.legendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedLegend1    = tabs.state(for: .fieldSweep1omega).legendPoint?.cgPoint
        let capturedLegend3    = tabs.state(for: .fieldSweep3omega).legendPoint?.cgPoint
        let capturedOrder1     = tabs.state(for: .fieldSweep1omega).seriesOrder
        let capturedOrder3     = tabs.state(for: .fieldSweep3omega).seriesOrder

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.seriesRenderMode      = capturedRenderMode
            r.chartStyleOverrides   = capturedStyleOverrides
            r.legendAnchor          = capturedAnchor
            r.stackOffsetMultiplier = capturedMultiplier
            r.minGapFraction        = capturedMinGap
            r.titleTemplate         = capturedTemplate
            r.titleTokens           = capturedTokens
            r.legendPoint           = capturedLegend1
            let r1 = r.renderR1omega(sweeps: ingestion.fieldSweeps, device: ingestion.device, seriesOrder: capturedOrder1)
            r.legendPoint           = capturedLegend3
            let r3 = r.renderR3omega(sweeps: ingestion.fieldSweeps, device: ingestion.device, seriesOrder: capturedOrder3)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let m1 = self.tabs.output(for: .fieldSweep1omega).manifestPayload
                self.tabs.setOutput(TabRenderOutput(imageData: r1.0, layout: r1.1, manifestPayload: m1), for: .fieldSweep1omega)
                let m3 = self.tabs.output(for: .fieldSweep3omega).manifestPayload
                self.tabs.setOutput(TabRenderOutput(imageData: r3.0, layout: r3.1, manifestPayload: m3), for: .fieldSweep3omega)
            }
        }
    }

    // MARK: - Interactive callbacks (delegated to TabRenderManager)

    /// Re-renders the active tab for style-only changes (grid, etc.)
    /// without mutating legend position or anchor state.
    func rerenderForStyleChange() {
        _rerenderActiveTab()
    }

    // MARK: - Analysis Pack (overlay support)

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

    func clearPlot() {
        analysisTask?.cancel()
        scalingTask?.cancel()
        ingestionResult          = nil
        scalingResult            = nil
        currentRunTrace          = nil
        isAnalyzing              = false
        analysisMessage          = nil
        _titleTokens             = [:]
        tabs.clearAll()
        warningLog.clear()
        activePackID             = nil
        overlayPackIDs           = []
        overlaySnapshots         = [:]
        relatedChartsTask?.cancel()
        relatedChartsTask        = nil
        relatedChartsGrouped     = [:]
        cachedSampleKeys         = []
        cachedConditionsBySampleKey = [:]
        cachedInputFiles         = []
        cachedRTFilePath         = nil
    }

    func clearResults() {
        selectedSearchResultIDs  = []
        cachedSearchResults      = []
        cachedSampleNumericDisplay = [:]
        rtQuery                  = ""
        rtSearchResults          = []
        rtSearchMessage          = nil
        isRTSearching            = false
        showRTPopover            = false
        selectedRTHit            = nil
    }

    // MARK: - Private helpers

    private func _applyPlots(_ plots: ThreeOmegaRenderedPlots) {
        tabs.setOutput(TabRenderOutput(imageData: plots.r1omega, layout: plots.layoutR1omega, manifestPayload: nil), for: .fieldSweep1omega)
        tabs.setOutput(TabRenderOutput(imageData: plots.r3omega, layout: plots.layoutR3omega, manifestPayload: nil), for: .fieldSweep3omega)
        tabs.setOutput(TabRenderOutput(imageData: plots.rahe1omegaVsT, layout: plots.layoutRAHE1omegaVsT, manifestPayload: nil), for: .rahe1omegaVsT)
        tabs.setOutput(TabRenderOutput(imageData: plots.rahe3omegaVsT, layout: plots.layoutRAHE3omegaVsT, manifestPayload: nil), for: .rahe3omegaVsT)
        tabs.setOutput(TabRenderOutput(imageData: plots.hcVsT, layout: plots.layoutHcVsT, manifestPayload: nil), for: .hcVsT)
        tabs.setOutput(TabRenderOutput(imageData: plots.rtCurve, layout: plots.layoutRTCurve, manifestPayload: nil), for: .rtCurve)
        if plots.scaling != nil {
            tabs.setOutput(TabRenderOutput(imageData: plots.scaling, layout: nil, manifestPayload: nil), for: .scaling)
        }
    }

    /// Re-renders only the active tab using cached ingestion/scaling result.
    private func _rerenderActiveTab() {
        guard let ingestion = ingestionResult else { return }

        // For RAHE tabs with overlays, delegate to overlay renderer
        let tab = tabs.activeTab
        if !overlayPackIDs.isEmpty,
           (tab == .rahe1omegaVsT || tab == .rahe3omegaVsT) {
            _renderRAHEWithOverlays()
            return
        }

        let tabState       = tabs.state(for: tab)
        let capturedGrid   = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor = tabs.legendAnchor
        let capturedLegend = tabState.legendPoint?.cgPoint
        let capturedHiddenLabels = tabs.hiddenPointLabelsBySampleID(for: tab)
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let titleOverride  = tabState.titleOverride
        let xLabelOverride = tabState.xLabelOverride
        let yLabelOverride = tabState.yLabelOverride
        let capturedLabelOverrides = tabState.seriesLabelOverrides
        let capturedSeriesOrder = tabState.seriesOrder
        let capturedFieldSweeps = ingestion.fieldSweeps
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
            let orderedSweeps = ThreeOmegaWorkspaceStore._applySeriesOrder(capturedSeriesOrder, to: capturedFieldSweeps)
            let fakeSeries = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(orderedSweeps)
            var r = ThreeOmegaPlotRenderer()
            r.showGrid              = capturedGrid
            r.seriesRenderMode      = capturedRenderMode
            r.chartStyleOverrides   = capturedStyleOverrides
            r.legendAnchor          = capturedAnchor
            r.legendPoint           = capturedLegend
            r.hiddenPointLabelsBySeries = toIndexedOverrides(capturedHiddenLabels, series: fakeSeries).mapValues { Set($0) }
            r.stackOffsetMultiplier = capturedMultiplier
            r.minGapFraction        = capturedMinGap
            r.titleOverride         = titleOverride
            r.xLabelOverride        = xLabelOverride
            r.yLabelOverride        = yLabelOverride
            r.seriesLabelOverrides  = toIndexedOverrides(capturedLabelOverrides, series: fakeSeries)
            r.titleTemplate         = capturedTemplate
            r.titleTokens           = capturedTokens

            let rendered: (Data?, WorkbenchPlotLayout?)
            switch tab {
            case .fieldSweep1omega:
                rendered = r.renderR1omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: capturedSeriesOrder)
            case .fieldSweep3omega:
                rendered = r.renderR3omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: capturedSeriesOrder)
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
                let existingManifest = self.tabs.output(for: tab).manifestPayload
                self.tabs.setOutput(TabRenderOutput(imageData: plotData, layout: plotLayout, manifestPayload: existingManifest), for: tab)
            }
        }
    }

    private func _buildPackConfig() -> ThreeOmegaPackConfig {
        return ThreeOmegaPackConfig(
            device: ingestionResult?.device ?? "",
            geometry: geometry,
            fitRanges: fitRanges,
            v3Method: v3Method.rawValue,
            rahe1Method: rahe1omegaMethod.rawValue,
            rahe3Method: rahe3omegaMethod.rawValue,
            rtFilePath: cachedRTFilePath,
            sampleBatchAndSubstrate: cachedSearchResults.first?.sampleBatchAndSubstrate ?? "",
            activeTab: tabs.activeTab.stableKey,
            titleTemplate: titleTemplate,
            stackOffsetMultiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction,
            showPlotGrid: tabs.showPlotGrid,
            plotLegendAnchor: tabs.legendAnchor,
            tabStates: tabs.snapshotStates(keyFor: { $0.stableKey }),
            chartStyleOverrides: tabs.chartStyleOverrides,
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

        let capturedGrid = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor = tabs.legendAnchor
        let state1 = tabs.state(for: .rahe1omegaVsT)
        let state3 = tabs.state(for: .rahe3omegaVsT)
        let capturedLegend1 = state1.legendPoint?.cgPoint
        let capturedLegend3 = state3.legendPoint?.cgPoint
        let titleOverride1 = state1.titleOverride
        let titleOverride3 = state3.titleOverride
        let capturedTemplate = titleTemplate
        let capturedTokens = _titleTokens
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod
        let capturedXLabel1 = state1.xLabelOverride
        let capturedYLabel1 = state1.yLabelOverride
        let capturedXLabel3 = state3.xLabelOverride
        let capturedYLabel3 = state3.yLabelOverride
        let capturedSeriesOverrides1 = state1.seriesLabelOverrides
        let capturedSeriesOverrides3 = state3.seriesLabelOverrides
        let capturedRAHEFieldSweeps = ingestion.fieldSweeps

        _renderRevision &+= 1
        let revision = _renderRevision

        Task.detached(priority: .userInitiated) { [weak self, groups] in
            let fakeSeries = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(capturedRAHEFieldSweeps)
            var r1 = ThreeOmegaPlotRenderer()
            r1.showGrid = capturedGrid
            r1.seriesRenderMode = capturedRenderMode
            r1.chartStyleOverrides = capturedStyleOverrides
            r1.legendAnchor = capturedAnchor
            r1.legendPoint = capturedLegend1
            r1.titleOverride = titleOverride1
            r1.xLabelOverride = capturedXLabel1
            r1.yLabelOverride = capturedYLabel1
            r1.seriesLabelOverrides = toIndexedOverrides(capturedSeriesOverrides1, series: fakeSeries)
            r1.titleTemplate = capturedTemplate
            r1.titleTokens = capturedTokens
            let rahe1 = r1.renderRAHE1omegaVsTMulti(groups: groups, method: capturedRAHE1Method)

            var r3 = ThreeOmegaPlotRenderer()
            r3.showGrid = capturedGrid
            r3.seriesRenderMode = capturedRenderMode
            r3.chartStyleOverrides = capturedStyleOverrides
            r3.legendAnchor = capturedAnchor
            r3.legendPoint = capturedLegend3
            r3.titleOverride = titleOverride3
            r3.xLabelOverride = capturedXLabel3
            r3.yLabelOverride = capturedYLabel3
            r3.seriesLabelOverrides = toIndexedOverrides(capturedSeriesOverrides3, series: fakeSeries)
            r3.titleTemplate = capturedTemplate
            r3.titleTokens = capturedTokens
            let rahe3 = r3.renderRAHE3omegaVsTMulti(groups: groups, method: capturedRAHE3Method)

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                let mR1 = self.tabs.output(for: .rahe1omegaVsT).manifestPayload
                self.tabs.setOutput(TabRenderOutput(imageData: rahe1.0, layout: rahe1.1, manifestPayload: mR1), for: .rahe1omegaVsT)
                let mR3 = self.tabs.output(for: .rahe3omegaVsT).manifestPayload
                self.tabs.setOutput(TabRenderOutput(imageData: rahe3.0, layout: rahe3.1, manifestPayload: mR3), for: .rahe3omegaVsT)

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

            var existing = tabs.tabOutputs[tab] ?? TabRenderOutput()
            existing.manifestPayload = WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: title,
                axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(\(hLabel)) (Ω)"),
                series: series,
                semanticParams: params
            )
            tabs.tabOutputs[tab] = existing
        }
    }

    /// Re-renders all tabs from cached ingestion/scaling results (used after pack load).
    private func _rerenderAllTabs() {
        guard let ingestion = ingestionResult else { return }

        let capturedGrid       = tabs.showPlotGrid
        let capturedRenderMode = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor     = tabs.legendAnchor
        let capturedMultiplier = stackOffsetMultiplier
        let capturedMinGap     = minGapFraction
        let capturedTemplate   = titleTemplate
        let capturedTokens     = _titleTokens
        let capturedRAHE1Method = rahe1omegaMethod
        let capturedRAHE3Method = rahe3omegaMethod
        Task.detached(priority: .userInitiated) { [weak self, ingestion] in
            var renderer = ThreeOmegaPlotRenderer()
            renderer.showGrid              = capturedGrid
            renderer.seriesRenderMode      = capturedRenderMode
            renderer.chartStyleOverrides   = capturedStyleOverrides
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
        tabs.clearOutputs()
        cachedSampleKeys = []
        cachedConditionsBySampleKey = [:]
        cachedInputFiles = []
        cachedRTFilePath = nil
    }

    // MARK: - Series order management

    func updateSeriesOrder(_ order: [String]) {
        tabs.updateSeriesOrder(order)
        _rerenderActiveTab()
    }

    func resetSeriesOrder() {
        tabs.resetSeriesOrder()
        _rerenderActiveTab()
    }

    /// Applies a bottom-to-top seriesOrder to fieldSweeps, producing the render order.
    nonisolated static func _applySeriesOrder(
        _ order: [String]?,
        to sweeps: [ThreeOmegaFieldSweepResult]
    ) -> [ThreeOmegaFieldSweepResult] {
        guard let order, !order.isEmpty else { return sweeps }
        let bySampleID = Dictionary(uniqueKeysWithValues: sweeps.compactMap { s in s.sampleID.map { ($0, s) } })
        var result: [ThreeOmegaFieldSweepResult] = []
        var consumed = Set<String>()
        for id in order {
            if let s = bySampleID[id] { result.append(s); consumed.insert(id) }
        }
        for s in sweeps where s.sampleID.map({ !consumed.contains($0) }) ?? true {
            result.append(s)
        }
        return result
    }

    /// Builds a minimal WorkbenchPlotSeries array from sweeps (for toIndexedOverrides translation).
    nonisolated static func _sweepsToFakeSeries(_ sweeps: [ThreeOmegaFieldSweepResult]) -> [WorkbenchPlotSeries] {
        sweeps.map { WorkbenchPlotSeries(label: $0.sampleID ?? "", x: [], y: [], sampleID: $0.sampleID) }
    }

    /// Aligns old seriesOrder against current sweep IDs.
    /// Returns nil when alignment matches the default order (no user customization needed).
    nonisolated static func alignSeriesOrder(old: [String]?, defaultIDs: [String]) -> [String]? {
        guard let old, !old.isEmpty else { return nil }
        let currentSet = Set(defaultIDs)
        var seen: Set<String> = []
        var kept: [String] = []
        for id in old where currentSet.contains(id) && seen.insert(id).inserted {
            kept.append(id)
        }
        let keptSet = Set(kept)
        var result = kept
        for id in defaultIDs where !keptSet.contains(id) {
            result.append(id)
        }
        return result == defaultIDs ? nil : result
    }
}

// MARK: - WorkbenchPlottingStore conformance

extension ThreeOmegaWorkspaceStore: WorkbenchPlottingStore {
    var showPlotGrid: Bool {
        get { tabs.showPlotGrid }
        set { tabs.showPlotGrid = newValue }
    }
    var seriesRenderMode: SeriesRenderMode {
        get { tabs.seriesRenderMode }
        set { tabs.seriesRenderMode = newValue }
    }
    var chartStyleOverrides: [String: String] {
        get { tabs.chartStyleOverrides }
        set { tabs.chartStyleOverrides = newValue }
    }

    func updateLegendPoint(_ point: CGPoint) {
        tabs.updateLegendPoint(point)
        tabs.legendAnchor = ""
        _rerenderActiveTab()
    }

    func updatePlotTitle(_ title: String) {
        tabs.updateTitleOverride(title)
        _rerenderActiveTab()
    }

    func updateXAxisLabel(_ label: String) {
        tabs.updateXLabelOverride(label)
        _rerenderActiveTab()
    }

    func updateYAxisLabel(_ label: String) {
        tabs.updateYLabelOverride(label)
        _rerenderActiveTab()
    }

    func updateSeriesLabel(sampleID: String, newLabel: String) {
        tabs.updateSeriesLabel(sampleID: sampleID, newLabel: newLabel)
        _rerenderActiveTab()
    }

    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {
        tabs.togglePointLabelVisibility(sampleID: sampleID, pointIndex: pointIndex)
        rerenderForStyleChange()
    }

    func renderPNGAtScale(_ scale: CGFloat) -> Data? {
        if scale == 2.0, let cached = activeImageData { return cached }
        guard let payload = activeChartManifestPayload else { return nil }
        let tab = tabs.activeTab
        let tabState = tabs.state(for: tab)
        var patch: [String: String] = [:]
        if tabs.showPlotGrid { patch["showGrid"] = "true" }
        if !tabs.legendAnchor.isEmpty { patch["legendAnchor"] = tabs.legendAnchor }
        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.pixelScaleOverride = scale
        input.legendPoint = tabState.legendPoint?.cgPoint
        input.seriesRenderMode = tabs.seriesRenderMode
        input.chartStyleOverrides = tabs.chartStyleOverrides
        input.seriesLabelOverrides = toIndexedOverrides(tabState.seriesLabelOverrides, series: payload.series)
        input.titleOverride = tabState.titleOverride
        input.xLabelOverride = tabState.xLabelOverride
        input.yLabelOverride = tabState.yLabelOverride
        input.hiddenPointLabelsBySeries = toIndexedOverrides(tabs.hiddenPointLabelsBySampleID(for: tab), series: payload.series).mapValues { Set($0) }
        input.styleParamsPatch = patch
        return try? WorkbenchRenderPipeline.render(input).imageData
    }
}

// MARK: - ActiveChartProviding conformance

extension ThreeOmegaWorkspaceStore: ActiveChartProviding {

    var activeChartPNG: Data? { tabs.activeImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { tabs.activeManifestPayload }

    var activeChartSampleKeys: [String] {
        let tab = tabs.activeTab
        guard !overlayPackIDs.isEmpty,
              (tab == .rahe1omegaVsT || tab == .rahe3omegaVsT) else {
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
        guard tabs.activeTab == .scaling,
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

// MARK: - AnalysisPackProviding conformance

extension ThreeOmegaWorkspaceStore: AnalysisPackProviding {
    typealias PackConfig = ThreeOmegaPackConfig
    typealias PackResult = ThreeOmegaPackResult

    var packWorkflowID: String { "3w" }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var packRTFilePath: String? { cachedRTFilePath }
    var hasAnalysisResult: Bool { ingestionResult != nil }

    func buildPackConfig() -> ThreeOmegaPackConfig { _buildPackConfig() }
    func buildPackResult() -> ThreeOmegaPackResult { _buildPackResult() }
    func autoPackLabel() -> String { _autoPackLabel() }

    func cancelInflightWork() {
        analysisTask?.cancel(); analysisTask = nil
        scalingTask?.cancel(); scalingTask = nil
        isAnalyzing = false
    }

    func restoreFromPack(config: ThreeOmegaPackConfig, result: ThreeOmegaPackResult,
                         pack: AnalysisPack,
                         restoreSearchState: @escaping ([WorkflowMeasurementSearchHit], String) -> Void) {
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
            tabs.activeTab = tab
        }
        titleTemplate = config.titleTemplate
        stackOffsetMultiplier = config.stackOffsetMultiplier
        minGapFraction = config.minGapFraction
        tabs.showPlotGrid = config.showPlotGrid
        tabs.legendAnchor = config.plotLegendAnchor

        // Restore per-tab states
        tabs.restoreStates(config.tabStates) { key in
            ThreeOmegaWorkbenchTab.allCases.first { $0.stableKey == key }
        }
        tabs.chartStyleOverrides = config.chartStyleOverrides

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

        // Restore library root from vault so persistToLibrary works without a prior search
        if lastLibraryRootPath.isEmpty, let root = vault?.libraryRootPath {
            lastLibraryRootPath = root
        }

        // Clear overlays
        overlayPackIDs = []
        overlaySnapshots = [:]

        // Bridge: restore search results into WorkbenchFeatureStore
        restoreSearchState(config.cachedSearchResults, config.searchQueryText)

        // Migrate any Int-string-keyed overrides (packs saved before 5.3.6) to sampleID keys.
        for tab in ThreeOmegaWorkbenchTab.allCases {
            if var state = tabs.tabStates[tab] {
                let seriesForTab = tabs.output(for: tab).manifestPayload?.series ?? []
                migrateStateIfNeeded(&state, series: seriesForTab)
                tabs.tabStates[tab] = state
            }
        }

        // Re-render all tabs respecting restored per-tab state and refreshing library tokens.
        // _rerenderAllTabs() does not apply per-tab overrides (titleOverride, legendPoint, etc.),
        // so we use _rerenderAllTabsFromRestoredState() in the Pack load path instead.
        _rerenderAllTabsFromRestoredState()
        _snapshotAndCacheManifestPayloads()
        refreshRelatedCharts()
    }

    /// Re-renders all tabs using the current per-tab TabRenderState overrides.
    /// Also refreshes numeric display tokens from the library index so that
    /// title tokens like #氧压 / #能量 resolve correctly after Pack load.
    /// Used exclusively in the Pack restore path.
    private func _rerenderAllTabsFromRestoredState() {
        guard let ingestion = ingestionResult else { return }

        _renderRevision &+= 1
        let revision = _renderRevision

        let capturedGrid          = tabs.showPlotGrid
        let capturedRenderMode    = tabs.seriesRenderMode
        let capturedStyleOverrides = tabs.chartStyleOverrides
        let capturedAnchor        = tabs.legendAnchor
        let capturedMultiplier    = stackOffsetMultiplier
        let capturedMinGap        = minGapFraction
        let capturedTemplate      = titleTemplate
        let capturedRAHE1Method   = rahe1omegaMethod
        let capturedRAHE3Method   = rahe3omegaMethod
        let capturedScaling       = scalingResult
        let capturedGeometry      = geometry
        let capturedV3Method      = v3Method
        let capturedDevice        = ingestion.device

        struct PerTabSnap: Sendable {
            let titleOverride: String
            let xLabelOverride: String
            let yLabelOverride: String
            let seriesLabelOverrides: [String: String]
            let legendPoint: CGPoint?
            let hiddenPointLabelsBySeries: [String: [Int]]
            let seriesOrder: [String]?
        }
        let tabSnaps: [ThreeOmegaWorkbenchTab: PerTabSnap] = Dictionary(
            uniqueKeysWithValues: ThreeOmegaWorkbenchTab.allCases.map { tab in
                let s = tabs.state(for: tab)
                return (tab, PerTabSnap(
                    titleOverride: s.titleOverride,
                    xLabelOverride: s.xLabelOverride,
                    yLabelOverride: s.yLabelOverride,
                    seriesLabelOverrides: s.seriesLabelOverrides,
                    legendPoint: s.legendPoint?.cgPoint,
                    hiddenPointLabelsBySeries: tabs.hiddenPointLabelsBySampleID(for: tab),
                    seriesOrder: s.seriesOrder
                ))
            }
        )
        let capturedRestoredFieldSweeps = ingestion.fieldSweeps

        let lookupHit         = cachedSearchResults.first
        let lookupLibraryRoot = lastLibraryRootPath
        let fallbackTokens    = _titleTokens

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Refresh numeric display tokens from library index.
            // cachedSampleNumericDisplay may be empty after Pack load (no search was run),
            // so we reload directly from disk here.
            var tokens = fallbackTokens
            if let hit = lookupHit, !lookupLibraryRoot.isEmpty {
                let rootURL = URL(fileURLWithPath: lookupLibraryRoot, isDirectory: true)
                if let nd = LibraryStore().loadIndex(from: rootURL)?
                    .sample(matchingDiskKey: hit.sampleKey)?.numericDisplay,
                   !nd.isEmpty {
                    tokens = ["sample": hit.sampleBatchAndSubstrate]
                    for (k, v) in nd { tokens[k] = v }
                }
            }

            func makeRenderer(for tab: ThreeOmegaWorkbenchTab) -> ThreeOmegaPlotRenderer {
                let s = tabSnaps[tab]!
                let orderedSweeps = ThreeOmegaWorkspaceStore._applySeriesOrder(s.seriesOrder, to: capturedRestoredFieldSweeps)
                let fakeSeries = ThreeOmegaWorkspaceStore._sweepsToFakeSeries(orderedSweeps)
                var r = ThreeOmegaPlotRenderer()
                r.showGrid                   = capturedGrid
                r.seriesRenderMode           = capturedRenderMode
                r.chartStyleOverrides        = capturedStyleOverrides
                r.legendAnchor               = capturedAnchor
                r.legendPoint                = s.legendPoint
                r.hiddenPointLabelsBySeries  = toIndexedOverrides(s.hiddenPointLabelsBySeries, series: fakeSeries).mapValues { Set($0) }
                r.stackOffsetMultiplier      = capturedMultiplier
                r.minGapFraction             = capturedMinGap
                r.titleTemplate              = capturedTemplate
                r.titleTokens               = tokens
                r.titleOverride              = s.titleOverride
                r.xLabelOverride             = s.xLabelOverride
                r.yLabelOverride             = s.yLabelOverride
                r.seriesLabelOverrides       = toIndexedOverrides(s.seriesLabelOverrides, series: fakeSeries)
                return r
            }

            var plots = ThreeOmegaRenderedPlots()
            var r1 = makeRenderer(for: .fieldSweep1omega)
            (plots.r1omega, plots.layoutR1omega) = r1.renderR1omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: tabSnaps[.fieldSweep1omega]?.seriesOrder)
            var r3 = makeRenderer(for: .fieldSweep3omega)
            (plots.r3omega, plots.layoutR3omega) = r3.renderR3omega(sweeps: ingestion.fieldSweeps, device: capturedDevice, seriesOrder: tabSnaps[.fieldSweep3omega]?.seriesOrder)
            var rahe1 = makeRenderer(for: .rahe1omegaVsT)
            (plots.rahe1omegaVsT, plots.layoutRAHE1omegaVsT) = rahe1.renderRAHE1omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE1Method)
            var rahe3 = makeRenderer(for: .rahe3omegaVsT)
            (plots.rahe3omegaVsT, plots.layoutRAHE3omegaVsT) = rahe3.renderRAHE3omegaVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice, method: capturedRAHE3Method)
            var hc = makeRenderer(for: .hcVsT)
            (plots.hcVsT, plots.layoutHcVsT) = hc.renderHcVsT(sweeps: ingestion.fieldSweeps, device: capturedDevice)
            if let rt = ingestion.rtResult {
                var rtR = makeRenderer(for: .rtCurve)
                (plots.rtCurve, plots.layoutRTCurve) = rtR.renderRT(rt: rt)
            }
            if let sr = capturedScaling, capturedGeometry.isComplete {
                let method = capturedV3Method == .highField ? "(HFE)" : "(WA)"
                var scR = makeRenderer(for: .scaling)
                (plots.scaling, _) = scR.renderScaling(result: sr, device: capturedDevice, method: method)
            }

            await MainActor.run { [weak self] in
                guard let self, self._renderRevision == revision else { return }
                self._titleTokens = tokens
                self._applyPlots(plots)
            }
        }
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
    var pipelineWarnings:      [String] = []
}

// MARK: - WorkbenchWorkspaceProviding conformance

extension ThreeOmegaWorkspaceStore: WorkbenchWorkspaceProviding {

    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard let result = ingestionResult else { return nil }
        let sweepCount = result.fieldSweeps.count
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: "3w",
            inputFiles: cachedInputFiles,
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
    }

    var activeImageData: Data? { tabs.activeImageData }
    var activeLayout: WorkbenchPlotLayout? { tabs.activeLayout }
    var seriesLabelOverrides: [String: String] { tabs.activeSeriesLabelOverrides }
    var activeSeriesOrder: [String]? { tabs.activeState.seriesOrder }
    var canReorderSeries: Bool { tabs.activeOutput.manifestPayload?.seriesReorderable ?? false }

    var relatedCharts: [WorkbenchResultReference]? {
        let charts = relatedCharts(for: tabs.activeTab)
        return charts.isEmpty ? nil : charts
    }

    var libraryRootURL: URL? {
        lastLibraryRootPath.isEmpty ? nil : URL(fileURLWithPath: lastLibraryRootPath)
    }
}
