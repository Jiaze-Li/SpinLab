import CryptoKit
import Foundation
import Observation

enum ThreeOmegaTransportRequirement: String, CaseIterable, Hashable, Sendable {
    case rt = "RT"
    case lxx = "Lxx"
    case lxy = "Lxy"
    case d = "d"
}

enum ThreeOmegaTransportDerivedStatus: Hashable, Sendable {
    case idle
    case refreshing
    case missing([ThreeOmegaTransportRequirement])
    case ready
    case unavailable(String)
}

/// Isolated state and actions for the 3ω AHE workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
/// Geometry parameters are session-only (not persisted).
@MainActor
@Observable
final class ThreeOmegaWorkspaceStore {

    let workflowID: String
    let relatedRTWorkflowID: String?
    @ObservationIgnored let env: WorkbenchEnvironment

    // MARK: - Search / Selection bridge

    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []
    /// Injected by WorkbenchFeatureStore; typed protocol reference to WorkbenchSelectionRuntime.
    @ObservationIgnored weak var selectionReading: (any SelectionReading)?

    // MARK: - RT file search (independent of main 3w search)

    static let rtQueryDefaultsKey = "workbench.searchQuery.3w.rt"

    /// Injected by WorkbenchFeatureStore. When set, the five RT session properties
    /// below forward reads/writes through it. When nil (standalone/test construction),
    /// they fall back to the backing _rt* vars so existing behaviour is unchanged.
    @ObservationIgnored weak var secondaryInputRuntime: WorkbenchSecondaryInputSearchRuntime?

    // Standalone/unwired fallback only. Wired app path reads from the secondary runtime via the
    // property below. Only used when secondaryInputRuntime is nil (e.g. direct ThreeOmegaWorkspaceStore
    // construction in tests that do not go through WorkbenchFeatureStore).
    @ObservationIgnored private var _rtQuery: String = ""
    var rtQuery: String {
        get { secondaryInputRuntime?.query(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) ?? _rtQuery }
        set {
            if let rt = secondaryInputRuntime { rt.setQuery(newValue, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) }
            else { _rtQuery = newValue }
        }
    }

    @ObservationIgnored private var _rtSearchResults: [WorkflowMeasurementSearchHit] = []
    var rtSearchResults: [WorkflowMeasurementSearchHit] {
        get { secondaryInputRuntime?.results(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) ?? _rtSearchResults }
        set {
            if let rt = secondaryInputRuntime { rt.setResults(newValue, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) }
            else { _rtSearchResults = newValue }
        }
    }

    @ObservationIgnored private var _rtSearchMessage: String? = nil
    var rtSearchMessage: String? {
        get { secondaryInputRuntime?.message(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) ?? _rtSearchMessage }
        set {
            if let rt = secondaryInputRuntime { rt.setMessage(newValue, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) }
            else { _rtSearchMessage = newValue }
        }
    }

    @ObservationIgnored private var _isRTSearching: Bool = false
    var isRTSearching: Bool {
        get { secondaryInputRuntime?.isSearching(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) ?? _isRTSearching }
        set {
            if let rt = secondaryInputRuntime { rt.setIsSearching(newValue, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) }
            else { _isRTSearching = newValue }
        }
    }

    @ObservationIgnored private var _showRTPopover: Bool = false
    var showRTPopover: Bool {
        get { secondaryInputRuntime?.isPopoverVisible(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) ?? _showRTPopover }
        set {
            if let rt = secondaryInputRuntime { rt.setPopoverVisible(newValue, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) }
            else { _showRTPopover = newValue }
        }
    }

    @ObservationIgnored private var _selectedRTHit: WorkflowMeasurementSearchHit? = nil
    var selectedRTHit: WorkflowMeasurementSearchHit? {
        get { secondaryInputRuntime?.selectedHit(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) ?? _selectedRTHit }
        set {
            if let rt = secondaryInputRuntime { rt.setSelectedHit(newValue, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) }
            else { _selectedRTHit = newValue }
        }
    }

    /// Set during restore; consumed on first 3w search to rebuild selectedRTHit.
    var pendingRTSidecarPath: String?

    // MARK: - RT analysis state (set by selectRTHit, cleared by clearRTSelection)

    var cachedRTResult: RTAnalysisResult?
    var isAnalyzingRT: Bool = false
    var rtAnalysisMessage: String?

    init(workflowID: String, relatedRTWorkflowID: String? = nil, env: WorkbenchEnvironment = .live) {
        self.workflowID = workflowID
        self.relatedRTWorkflowID = relatedRTWorkflowID
        self.env = env
        self._rtQuery = UserDefaults.standard.string(forKey: Self.rtQueryDefaultsKey) ?? ""
    }

    // MARK: - Geometry (session-only, not persisted)

    var geometry = ThreeOmegaGeometry()
    var v3Method: ThreeOmegaV3Method = .highField

    // MARK: - Per-tab RAHE method (independent of v3Method used by Scaling Law)

    var rahe1omegaMethod: ThreeOmegaV3Method = .highField
    var rahe3omegaMethod: ThreeOmegaV3Method = .highField
    var rahe1omegaVsDeviceMethod: ThreeOmegaV3Method = .highField
    var rahe3omegaVsDeviceMethod: ThreeOmegaV3Method = .highField

    /// The RAHE method for the currently active device-angle tab (nil otherwise).
    var activeRAHEMethod: ThreeOmegaV3Method? {
        switch tabs.activeTab {
        case .rahe1omegaVsDevice: return rahe1omegaVsDeviceMethod
        case .rahe3omegaVsDevice: return rahe3omegaVsDeviceMethod
        default: return nil
        }
    }

    // MARK: - Fit ranges (session-only, not persisted)

    var fitRanges: [ThreeOmegaFitRange] = [ThreeOmegaFitRange()]

    // MARK: - Analysis output

    var ingestionResult: ThreeOmegaIngestionResult?
    var scalingResult: ThreeOmegaScalingResult?
    var scalingAngleCoefficient: ThreeOmegaScalingCoefficientKind = .beta
    var scalingAngleMethod: String? = nil
    var scalingAngleFitRange: String? = nil
    /// Legacy single global candidate (packs saved before the per-angle model).
    /// Retained for backward-compatible pack decode / best-effort migration only.
    var scalingAngleCandidate: String? = nil
    /// angleKey -> chosen candidate ID. The per-angle candidate selection model:
    /// resolving one ambiguous angle never filters out the others.
    var scalingAngleCandidateSelections: [String: String] = [:]
    var scalingVsAngleResult: ThreeOmegaScalingVsAngleResult? = nil
    var transportDerivedStatus: ThreeOmegaTransportDerivedStatus = .idle
    var isRefreshingTransportDerivedPlots: Bool = false
    var currentRunTrace: WorkbenchRunTraceProjection?
    var isAnalyzing: Bool = false
    var analysisMessage: String?
    @ObservationIgnored var packRestoreErrorMessage: String? = nil

    var missingTransportRequirements: [ThreeOmegaTransportRequirement] {
        if case let .missing(requirements) = transportDerivedStatus {
            return requirements
        }
        return []
    }

    var transportDerivedStatusMessage: String? {
        switch transportDerivedStatus {
        case .idle:
            return nil
        case .refreshing:
            return "Updating Scaling Law…"
        case .missing(let requirements):
            return "Scaling Law unavailable: missing \(requirements.map(\.rawValue).joined(separator: ", "))."
        case .ready:
            return nil
        case .unavailable(let message):
            return message
        }
    }

    /// Save-to-library status message. Written only by `persistToLibrary()`.
    /// Cleared on `clearPlot()` and at analysis start.
    /// Preferred over `analysisMessage` (analysis status) for save status display.
    var saveMessage: String?

    // MARK: - Warning log (persists across runs within the session)

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()

    // MARK: - Multi-tab render state (shell capability)

    var tabs = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: .fieldSweep1omega)
    var globalPlotDefaults: [String: String] = [:]

    // MARK: - DualAxis display state

    /// Display-only state for the Temperature Dependence dual-axis tab.
    /// This is intentionally separate from Cartesian XY `TabRenderState`.
    var temperatureDependenceDisplayState = DualAxisDisplayState()

    // MARK: - Plot controls (workflow-specific)

    var titleTemplate: String = "#tab #method #device #sample #氧压 #能量"
    var stackOffsetMultiplier: Double = 1.2     // 0 = no stacking; >0 = curve spacing
    var minGapFraction: Double = 0.15            // minimum gap as fraction of max peak-to-peak

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

    /// Cached per-sample numericDisplay from library index, populated by WorkbenchFeatureStore after search.
    var cachedSampleNumericDisplay: [String: [String: String]] = [:]
    /// Title tokens resolved from selected hit (sample + numericDisplay). Tab/device added by renderer.
    var _titleTokens: [String: String] = [:]

    // MARK: - Persistence

    /// Set by WorkbenchFeatureStore during search; required for artifact I/O.
    var lastLibraryRootPath: String = ""
    private(set) var persistenceOutcome: PersistenceOutcome?

    func applyPersistenceOutcome(_ outcome: PersistenceOutcome) {
        persistenceOutcome = outcome
    }

    var activeChartPNG: Data? { tabs.activeImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { tabs.activeManifestPayload }

    var activeChartSampleKeys: [String] {
        cachedSampleKeys
    }

    // cachedManifestPayloads now managed by tabs (TabRenderManager)
    /// Sample keys snapshot from the analysis run that produced current plots.
    @ObservationIgnored var cachedSampleKeys: [String] = []
    /// Per-sample conditions snapshot from the analysis run.
    @ObservationIgnored var cachedConditionsBySampleKey: [String: [String: String]] = [:]
    /// Input file paths snapshot from the analysis run.
    @ObservationIgnored var cachedInputFiles: [String] = []
    /// RT file path snapshot from the analysis run.
    @ObservationIgnored var cachedRTFilePath: String? = nil

    // MARK: - Related charts (hover popover)

    /// Charts grouped by canonical inputFiles key, loaded from library indices.
    var relatedChartsGrouped: [String: [WorkbenchResultReference]] = [:]
    @ObservationIgnored var relatedChartsTask: Task<Void, Never>?

    var relatedCharts: [WorkbenchResultReference]? {
        let charts = self.relatedCharts(for: tabs.activeTab)
        return charts.isEmpty ? nil : charts
    }

    var libraryRootURL: URL? {
        lastLibraryRootPath.isEmpty ? nil : URL(fileURLWithPath: lastLibraryRootPath)
    }

    // MARK: - Analysis Pack (vault integration)

    /// Vault reference, set by WorkbenchFeatureStore after init.
    @ObservationIgnored var vault: AnalysisVault?

    /// ID of the pack that was last saved or loaded. nil = fresh (unsaved) analysis.
    var activePackID: AnalysisPack.ID?

    /// Injected by WorkbenchFeatureStore. When set, overlayPackIDs forwards reads through it
    /// and all overlay mutations go through WorkbenchAnalysisOverlayRuntime.
    /// When nil, overlay state is unavailable and overlayPackIDs returns [].
    @ObservationIgnored weak var overlayRuntime: WorkbenchAnalysisOverlayRuntime?

    /// Ordered overlay IDs — forwarded from overlayRuntime when wired; empty when not wired.
    var overlayPackIDs: [AnalysisPack.ID] {
        overlayRuntime?.overlayIDs ?? []
    }

    /// Decoupled snapshots of overlay data — survive vault deletion.
    /// Workflow-specific content (sweeps, sampleKeys, sourceFiles) stays here,
    /// never in WorkbenchAnalysisOverlayRuntime.
    @ObservationIgnored var overlaySnapshots: [AnalysisPack.ID: OverlaySnapshot] = [:]

    var packWorkflowID: String { workflowID }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var packRTFilePath: String? { cachedRTFilePath }
    var hasAnalysisResult: Bool { ingestionResult != nil }

    // MARK: - Workbench workspace projection

    var activeImageData: Data? { tabs.activeImageData }
    var activePdfData: Data? { tabs.activePdfData }
    var activeLayout: WorkbenchPlotLayout? { tabs.activeLayout }
    var activeLegendDragGeometry: PlotLegendDragGeometry? {
        switch tabs.activeTab {
        case .temperatureDependence:
            return tabs.output(for: .temperatureDependence).dualAxisLayout?.legendDragGeometry
        default:
            return tabs.activeLayout?.legendDragGeometry
        }
    }
    var seriesLabelOverrides: [String: String] { tabs.activeSeriesLabelOverrides }
    var activeSeriesOrder: [String]? {
        switch tabs.activeTab {
        case .fieldSweep1omega, .fieldSweep3omega:
            return fieldSweepSeriesOrder
        default:
            return tabs.activeState.seriesOrder
        }
    }
    var canReorderSeries: Bool { tabs.activeOutput.manifestPayload?.seriesReorderable ?? false }

    // MARK: - Task lifetimes

    @ObservationIgnored var analysisTask: Task<Void, Never>?
    @ObservationIgnored var _renderRevision: UInt64 = 0
    @ObservationIgnored var _temperatureDependenceRevision: UInt64 = 0
    /// Incremented each time _runAnalysis starts. Captured by the analysis Task and
    /// checked before every tabs.setOutput inside renderThreeOmegaTab so that a
    /// cancelled/superseded analysis cannot write output after a newer one begins.
    @ObservationIgnored var _analysisRevision: UInt64 = 0
    @ObservationIgnored var scalingTask: Task<Void, Never>?

    deinit {
        analysisTask?.cancel()
        scalingTask?.cancel()
        relatedChartsTask?.cancel()
    }

    // MARK: - Field-sweep series order

    /// Canonical shared order for the AHE 1ω/3ω field-sweep tabs.
    /// 1ω takes precedence when both tabs still carry divergent legacy state.
    var fieldSweepSeriesOrder: [String]? {
        tabs.state(for: .fieldSweep1omega).seriesOrder ?? tabs.state(for: .fieldSweep3omega).seriesOrder
    }

    func setFieldSweepSeriesOrder(_ order: [String]?) {
        tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].seriesOrder = order
        tabs.tabStates[.fieldSweep3omega, default: TabRenderState()].seriesOrder = order
    }
}
