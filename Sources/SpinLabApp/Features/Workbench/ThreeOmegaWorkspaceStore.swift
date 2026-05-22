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

    @ObservationIgnored let env: WorkbenchEnvironment

    // MARK: - Search / Selection

    var selectedSearchResultIDs: Set<String> = []
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []

    var isAllSelected: Bool {
        !cachedSearchResults.isEmpty && selectedSearchResultIDs.count == cachedSearchResults.count
    }

    // MARK: - RT file search (independent of main 3w search)

    static let rtQueryDefaultsKey = "workbench.searchQuery.3w.rt"

    var rtQuery: String = ""
    var rtSearchResults: [WorkflowMeasurementSearchHit] = []
    var rtSearchMessage: String?
    var isRTSearching: Bool = false
    var showRTPopover: Bool = false
    var selectedRTHit: WorkflowMeasurementSearchHit?

    /// Set during restore; consumed on first 3w search to rebuild selectedRTHit.
    var pendingRTSidecarPath: String?

    init(env: WorkbenchEnvironment = .live) {
        self.env = env
        self.rtQuery = UserDefaults.standard.string(forKey: Self.rtQueryDefaultsKey) ?? ""
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

    // MARK: - Fit ranges (session-only, not persisted)

    var fitRanges: [ThreeOmegaFitRange] = [ThreeOmegaFitRange()]

    // MARK: - Analysis output

    var ingestionResult: ThreeOmegaIngestionResult?
    var scalingResult: ThreeOmegaScalingResult?
    var currentRunTrace: WorkbenchRunTraceProjection?
    var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Warning log (persists across runs within the session)

    var warningLog: WorkbenchWarningLog = WorkbenchWarningLog()

    // MARK: - Multi-tab render state (shell capability)

    var tabs = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: .fieldSweep1omega)

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
    var persistenceOutcome: PersistenceOutcome?

    var activeChartPNG: Data? { tabs.activeImageData }

    var activeChartManifestPayload: WorkbenchPlotPayload? { tabs.activeManifestPayload }

    var activeChartSampleKeys: [String] {
        let tab = tabs.activeTab
        guard !overlayPackIDs.isEmpty,
              (tab == .rahe1omegaVsT || tab == .rahe3omegaVsT) else {
            return cachedSampleKeys
        }
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

    /// IDs of packs currently overlaid on RAHE tabs.
    var overlayPackIDs: [AnalysisPack.ID] = []

    /// Decoupled snapshots of overlay data — survive vault deletion.
    @ObservationIgnored var overlaySnapshots: [AnalysisPack.ID: OverlaySnapshot] = [:]

    var packWorkflowID: String { "3w" }
    var packInputFiles: [String] { cachedInputFiles }
    var packSampleKeys: [String] { cachedSampleKeys }
    var packRTFilePath: String? { cachedRTFilePath }
    var hasAnalysisResult: Bool { ingestionResult != nil }

    // MARK: - Workbench workspace projection

    var activeImageData: Data? { tabs.activeImageData }
    var activeLayout: WorkbenchPlotLayout? { tabs.activeLayout }
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
