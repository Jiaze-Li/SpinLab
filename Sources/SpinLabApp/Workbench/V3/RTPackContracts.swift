import Foundation

// MARK: - RTPackConfig

/// Everything needed to restore an RT workbench session.
struct RTPackConfig: Codable, Hashable, Sendable {

    // --- Display settings ---
    var titleTemplate: String
    var showPlotGrid: Bool
    var stackOffsetMultiplier: Double
    var minGapFraction: Double
    /// true = `minGapFraction` is the single Gap input (net gap = max peak-to-peak × Gap) and
    /// `stackOffsetMultiplier` is unused; absent in packs saved before it existed = legacy Stack × Gap.
    var uniformGapSpacing: Bool
    var legendAnchor: String
    var seriesRenderMode: SeriesRenderMode

    // --- Shared chart style overrides ---
    var chartStyleOverrides: [String: String]

    // --- Per-tab display states (keyed by RTWorkbenchTab.stableKey) ---
    var tabStates: [String: TabRenderState]

    // --- Search state ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var searchQueryText: String

    init(
        titleTemplate: String = "#tab #device #sample",
        showPlotGrid: Bool = true,
        stackOffsetMultiplier: Double = 0.0,
        minGapFraction: Double = 0.15,
        uniformGapSpacing: Bool = false,
        legendAnchor: String = "",
        seriesRenderMode: SeriesRenderMode = .line,
        chartStyleOverrides: [String: String] = [:],
        tabStates: [String: TabRenderState] = [:],
        cachedSearchResults: [WorkflowMeasurementSearchHit] = [],
        selectedSearchResultIDs: [String] = [],
        searchQueryText: String = ""
    ) {
        self.titleTemplate = titleTemplate
        self.showPlotGrid = showPlotGrid
        self.stackOffsetMultiplier = stackOffsetMultiplier
        self.minGapFraction = minGapFraction
        self.uniformGapSpacing = uniformGapSpacing
        self.legendAnchor = legendAnchor
        self.seriesRenderMode = seriesRenderMode
        self.chartStyleOverrides = chartStyleOverrides
        self.tabStates = tabStates
        self.cachedSearchResults = cachedSearchResults
        self.selectedSearchResultIDs = selectedSearchResultIDs
        self.searchQueryText = searchQueryText
    }

    // Backward-compatible decode: fields added after initial release default safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titleTemplate           = try c.decodeIfPresent(String.self, forKey: .titleTemplate) ?? "#tab #device #sample"
        showPlotGrid            = try c.decodeIfPresent(Bool.self, forKey: .showPlotGrid) ?? true
        stackOffsetMultiplier   = try c.decodeIfPresent(Double.self, forKey: .stackOffsetMultiplier) ?? 0.0
        minGapFraction          = try c.decodeIfPresent(Double.self, forKey: .minGapFraction) ?? 0.15
        uniformGapSpacing       = try c.decodeIfPresent(Bool.self, forKey: .uniformGapSpacing) ?? false
        legendAnchor            = try c.decodeIfPresent(String.self, forKey: .legendAnchor) ?? ""
        seriesRenderMode        = try c.decodeIfPresent(SeriesRenderMode.self, forKey: .seriesRenderMode) ?? .line
        chartStyleOverrides     = try c.decodeIfPresent([String: String].self, forKey: .chartStyleOverrides) ?? [:]
        tabStates               = try c.decodeIfPresent([String: TabRenderState].self, forKey: .tabStates) ?? [:]
        cachedSearchResults     = try c.decodeIfPresent([WorkflowMeasurementSearchHit].self, forKey: .cachedSearchResults) ?? []
        selectedSearchResultIDs = try c.decodeIfPresent([String].self, forKey: .selectedSearchResultIDs) ?? []
        searchQueryText         = try c.decodeIfPresent(String.self, forKey: .searchQueryText) ?? ""
    }
}

extension RTPackConfig: SearchQueryTextInjectable {}

// MARK: - RTPackResult

/// The analysis output snapshot.
struct RTPackResult: Codable, Hashable, Sendable {
    var rtResults: [RTAnalysisResult]

    init(rtResults: [RTAnalysisResult] = []) {
        self.rtResults = rtResults
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rtResults = try c.decodeIfPresent([RTAnalysisResult].self, forKey: .rtResults) ?? []
    }
}
