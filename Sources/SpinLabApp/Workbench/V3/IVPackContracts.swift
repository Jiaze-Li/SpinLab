import Foundation

// MARK: - IVPackConfig

/// Everything needed to restore an IV workbench session.
struct IVPackConfig: Codable, Hashable, Sendable {

    // --- Active tab ---
    var activeTab: String
    // --- Display settings ---
    var titleTemplate: String
    var stackOffsetMultiplier: Double
    var minGapFraction: Double
    var showPlotGrid: Bool
    var legendAnchor: String
    var seriesRenderMode: SeriesRenderMode
    var chartStyleOverrides: [String: String]

    // --- Channel component overrides ---
    var ch1Component: String
    var ch2Component: String
    var xCurrentBasis: IVCurrentBasis

    // --- Power-law fit module state (IV-owned; see IVPowerLawFitAdapter) ---
    var fitMode: PowerLawFitMode
    var zeroAtCurrentOrigin: Bool

    // --- Angle-dependence module state (IV-owned; see IVAngleDependence) ---
    var angularPlotEnabled: Bool

    // --- Angular harmonic fit overlay state (IV-owned; see IVAngularFitAdapter) ---
    var angularFitMode: AngularFitMode
    var angularFitFold: Int

    // --- Per-tab render states (keyed by IVWorkbenchTab.rawValue) ---
    var tabStates: [String: TabRenderState] = [:]

    // --- Search state ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var searchQueryText: String

    init(titleTemplate: String,
         activeTab: String = IVWorkbenchTab.voltage.rawValue,
         stackOffsetMultiplier: Double = 0.0,
         minGapFraction: Double = 0.15,
         showPlotGrid: Bool,
         legendAnchor: String = "",
         seriesRenderMode: SeriesRenderMode = .line,
         chartStyleOverrides: [String: String] = [:],
         ch1Component: String = IVSignalComponent.x.rawValue,
         ch2Component: String = IVSignalComponent.x.rawValue,
         xCurrentBasis: IVCurrentBasis = .peak,
         fitMode: PowerLawFitMode = .none,
         zeroAtCurrentOrigin: Bool = false,
         angularPlotEnabled: Bool = false,
         angularFitMode: AngularFitMode = .none,
         angularFitFold: Int = 1,
         tabStates: [String: TabRenderState] = [:],
         cachedSearchResults: [WorkflowMeasurementSearchHit] = [],
         selectedSearchResultIDs: [String] = [],
         searchQueryText: String = "") {
        self.activeTab = activeTab
        self.titleTemplate = titleTemplate
        self.stackOffsetMultiplier = stackOffsetMultiplier
        self.minGapFraction = minGapFraction
        self.showPlotGrid = showPlotGrid
        self.legendAnchor = legendAnchor
        self.seriesRenderMode = seriesRenderMode
        self.chartStyleOverrides = chartStyleOverrides
        self.ch1Component = ch1Component
        self.ch2Component = ch2Component
        self.xCurrentBasis = xCurrentBasis
        self.fitMode = fitMode
        self.zeroAtCurrentOrigin = zeroAtCurrentOrigin
        self.angularPlotEnabled = angularPlotEnabled
        self.angularFitMode = angularFitMode
        self.angularFitFold = angularFitFold
        self.tabStates = tabStates
        self.cachedSearchResults = cachedSearchResults
        self.selectedSearchResultIDs = selectedSearchResultIDs
        self.searchQueryText = searchQueryText
    }

    // Backward-compatible decode: fields added after initial release default safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeTab               = try c.decodeIfPresent(String.self, forKey: .activeTab) ?? IVWorkbenchTab.voltage.rawValue
        titleTemplate           = try c.decodeIfPresent(String.self, forKey: .titleTemplate) ?? ""
        stackOffsetMultiplier   = try c.decodeIfPresent(Double.self, forKey: .stackOffsetMultiplier) ?? 0.0
        minGapFraction          = try c.decodeIfPresent(Double.self, forKey: .minGapFraction) ?? 0.15
        showPlotGrid            = try c.decodeIfPresent(Bool.self, forKey: .showPlotGrid) ?? true
        legendAnchor            = try c.decodeIfPresent(String.self, forKey: .legendAnchor) ?? ""
        seriesRenderMode        = try c.decodeIfPresent(SeriesRenderMode.self, forKey: .seriesRenderMode) ?? .line
        chartStyleOverrides     = try c.decodeIfPresent([String: String].self, forKey: .chartStyleOverrides) ?? [:]
        ch1Component            = try c.decodeIfPresent(String.self, forKey: .ch1Component) ?? IVSignalComponent.x.rawValue
        ch2Component            = try c.decodeIfPresent(String.self, forKey: .ch2Component) ?? IVSignalComponent.x.rawValue
        xCurrentBasis           = try c.decodeIfPresent(IVCurrentBasis.self, forKey: .xCurrentBasis) ?? .peak
        fitMode                 = try c.decodeIfPresent(PowerLawFitMode.self, forKey: .fitMode) ?? .none
        zeroAtCurrentOrigin     = try c.decodeIfPresent(Bool.self, forKey: .zeroAtCurrentOrigin) ?? false
        angularPlotEnabled      = try c.decodeIfPresent(Bool.self, forKey: .angularPlotEnabled) ?? false
        angularFitMode          = try c.decodeIfPresent(AngularFitMode.self, forKey: .angularFitMode) ?? .none
        angularFitFold          = try c.decodeIfPresent(Int.self, forKey: .angularFitFold) ?? 1
        tabStates               = try c.decodeIfPresent([String: TabRenderState].self, forKey: .tabStates) ?? [:]
        cachedSearchResults     = try c.decodeIfPresent([WorkflowMeasurementSearchHit].self, forKey: .cachedSearchResults) ?? []
        selectedSearchResultIDs = try c.decodeIfPresent([String].self, forKey: .selectedSearchResultIDs) ?? []
        searchQueryText         = try c.decodeIfPresent(String.self, forKey: .searchQueryText) ?? ""
    }
}

// MARK: - IVPackResult

/// The analysis output snapshot.
struct IVPackResult: Codable, Hashable, Sendable {
    var ingestionResult: IVIngestionResult
}

extension IVPackConfig: SearchQueryTextInjectable {}
