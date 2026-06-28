import Foundation

// MARK: - XYRotationPackConfig

/// Everything needed to restore an XY Rotation workbench session.
struct XYRotationPackConfig: Codable, Hashable, Sendable {

    // --- Analysis params ---
    var phiOffsetOverrides: [String: Double]
    var centerBaseline: Bool
    var linearDetrend: Bool = false

    // --- Display settings ---
    var activeTab: String                          // XYRotationWorkbenchTab.rawValue
    var titleTemplate: String
    var stackOffsetMultiplier: Double
    var minGapFraction: Double
    var showPlotGrid: Bool
    var showAuxiliaryLine180: Bool
    // --- PlotControl display status (v8.5A+) ---
    var legendAnchor: String
    var seriesRenderMode: SeriesRenderMode
    var chartStyleOverrides: [String: String]

    // --- Per-tab render states (v5.3.3+, keyed by tab.rawValue) ---
    var tabStates: [String: TabRenderState] = [:]

    // --- Search state (v5.3.4+) ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var searchQueryText: String

    init(phiOffsetOverrides: [String: Double], centerBaseline: Bool, linearDetrend: Bool = false,
         activeTab: String, titleTemplate: String, stackOffsetMultiplier: Double, minGapFraction: Double,
         showPlotGrid: Bool, showAuxiliaryLine180: Bool = false,
         legendAnchor: String = "", seriesRenderMode: SeriesRenderMode = .line,
         chartStyleOverrides: [String: String] = [:],
         tabStates: [String: TabRenderState] = [:],
         cachedSearchResults: [WorkflowMeasurementSearchHit] = [], selectedSearchResultIDs: [String] = [],
         searchQueryText: String = "") {
        self.phiOffsetOverrides = phiOffsetOverrides; self.centerBaseline = centerBaseline
        self.linearDetrend = linearDetrend; self.activeTab = activeTab
        self.titleTemplate = titleTemplate; self.stackOffsetMultiplier = stackOffsetMultiplier
        self.minGapFraction = minGapFraction; self.showPlotGrid = showPlotGrid
        self.showAuxiliaryLine180 = showAuxiliaryLine180
        self.legendAnchor = legendAnchor; self.seriesRenderMode = seriesRenderMode
        self.chartStyleOverrides = chartStyleOverrides
        self.tabStates = tabStates; self.cachedSearchResults = cachedSearchResults
        self.selectedSearchResultIDs = selectedSearchResultIDs; self.searchQueryText = searchQueryText
    }

    // Backward-compatible decode: fields added after initial release default safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phiOffsetOverrides      = try c.decode([String: Double].self, forKey: .phiOffsetOverrides)
        centerBaseline          = try c.decode(Bool.self, forKey: .centerBaseline)
        linearDetrend           = try c.decodeIfPresent(Bool.self, forKey: .linearDetrend) ?? false
        activeTab               = try c.decode(String.self, forKey: .activeTab)
        titleTemplate           = try c.decodeIfPresent(String.self, forKey: .titleTemplate) ?? ""
        stackOffsetMultiplier   = try c.decodeIfPresent(Double.self, forKey: .stackOffsetMultiplier) ?? 0.0
        minGapFraction          = try c.decodeIfPresent(Double.self, forKey: .minGapFraction) ?? 0.15
        showPlotGrid            = try c.decodeIfPresent(Bool.self, forKey: .showPlotGrid) ?? true
        showAuxiliaryLine180    = try c.decodeIfPresent(Bool.self, forKey: .showAuxiliaryLine180) ?? false
        legendAnchor            = try c.decodeIfPresent(String.self, forKey: .legendAnchor) ?? ""
        seriesRenderMode        = try c.decodeIfPresent(SeriesRenderMode.self, forKey: .seriesRenderMode) ?? .line
        chartStyleOverrides     = try c.decodeIfPresent([String: String].self, forKey: .chartStyleOverrides) ?? [:]
        tabStates               = try c.decodeIfPresent([String: TabRenderState].self, forKey: .tabStates) ?? [:]
        cachedSearchResults     = try c.decodeIfPresent([WorkflowMeasurementSearchHit].self, forKey: .cachedSearchResults) ?? []
        selectedSearchResultIDs = try c.decodeIfPresent([String].self, forKey: .selectedSearchResultIDs) ?? []
        searchQueryText         = try c.decodeIfPresent(String.self, forKey: .searchQueryText) ?? ""
    }
}

// MARK: - XYRotationPackResult

/// The analysis output snapshot.
struct XYRotationPackResult: Codable, Hashable, Sendable {
    var ingestionResult: XYRotationIngestionResult
}

extension XYRotationPackConfig: SearchQueryTextInjectable {}
