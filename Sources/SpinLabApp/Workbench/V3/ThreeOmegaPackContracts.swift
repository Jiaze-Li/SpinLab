import Foundation

// MARK: - ThreeOmegaPackConfig

/// Everything needed to restore a 3ω workbench session.
struct ThreeOmegaPackConfig: Codable, Hashable, Sendable {

    // --- Analysis params ---
    var device: String
    var geometry: ThreeOmegaGeometry
    var fitRanges: [ThreeOmegaFitRange]
    var v3Method: String                    // ThreeOmegaV3Method.rawValue
    var rahe1Method: String                 // ThreeOmegaV3Method.rawValue
    var rahe3Method: String                 // ThreeOmegaV3Method.rawValue
    var rtFilePath: String?
    var sampleBatchAndSubstrate: String

    // --- Display settings ---
    var activeTab: String                   // ThreeOmegaWorkbenchTab.stableKey
    var titleTemplate: String
    var stackOffsetMultiplier: Double
    var minGapFraction: Double
    var showPlotGrid: Bool
    var plotLegendAnchor: String
    var seriesRenderMode: SeriesRenderMode

    // --- Per-tab display states (v5.3.3+, keyed by stableKey for Codable) ---
    var tabStates: [String: TabRenderState] = [:]
    // --- Shared chart style overrides (v5.3.5+, e.g. font sizes) ---
    var chartStyleOverrides: [String: String] = [:]

    // --- Search state (v5.3.4+) ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var selectedRTHit: WorkflowMeasurementSearchHit?
    var rtQuery: String
    var searchQueryText: String

    init(device: String, geometry: ThreeOmegaGeometry, fitRanges: [ThreeOmegaFitRange],
         v3Method: String, rahe1Method: String, rahe3Method: String, rtFilePath: String?,
         sampleBatchAndSubstrate: String, activeTab: String, titleTemplate: String,
         stackOffsetMultiplier: Double, minGapFraction: Double, showPlotGrid: Bool,
         plotLegendAnchor: String, seriesRenderMode: SeriesRenderMode = .line,
         tabStates: [String: TabRenderState] = [:],
         chartStyleOverrides: [String: String] = [:],
         cachedSearchResults: [WorkflowMeasurementSearchHit] = [], selectedSearchResultIDs: [String] = [],
         selectedRTHit: WorkflowMeasurementSearchHit? = nil, rtQuery: String = "", searchQueryText: String = "") {
        self.device = device; self.geometry = geometry; self.fitRanges = fitRanges
        self.v3Method = v3Method; self.rahe1Method = rahe1Method; self.rahe3Method = rahe3Method
        self.rtFilePath = rtFilePath; self.sampleBatchAndSubstrate = sampleBatchAndSubstrate
        self.activeTab = activeTab; self.titleTemplate = titleTemplate
        self.stackOffsetMultiplier = stackOffsetMultiplier; self.minGapFraction = minGapFraction
        self.showPlotGrid = showPlotGrid; self.plotLegendAnchor = plotLegendAnchor
        self.seriesRenderMode = seriesRenderMode
        self.tabStates = tabStates; self.chartStyleOverrides = chartStyleOverrides
        self.cachedSearchResults = cachedSearchResults
        self.selectedSearchResultIDs = selectedSearchResultIDs; self.selectedRTHit = selectedRTHit
        self.rtQuery = rtQuery; self.searchQueryText = searchQueryText
    }

    // Backward-compatible decode: fields added after initial release default safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device                  = try c.decode(String.self, forKey: .device)
        geometry                = try c.decode(ThreeOmegaGeometry.self, forKey: .geometry)
        fitRanges               = try c.decode([ThreeOmegaFitRange].self, forKey: .fitRanges)
        v3Method                = try c.decode(String.self, forKey: .v3Method)
        rahe1Method             = try c.decodeIfPresent(String.self, forKey: .rahe1Method) ?? v3Method
        rahe3Method             = try c.decodeIfPresent(String.self, forKey: .rahe3Method) ?? v3Method
        rtFilePath              = try c.decodeIfPresent(String.self, forKey: .rtFilePath)
        sampleBatchAndSubstrate = try c.decode(String.self, forKey: .sampleBatchAndSubstrate)
        activeTab               = try c.decode(String.self, forKey: .activeTab)
        titleTemplate           = try c.decodeIfPresent(String.self, forKey: .titleTemplate) ?? ""
        stackOffsetMultiplier   = try c.decode(Double.self, forKey: .stackOffsetMultiplier)
        minGapFraction          = try c.decodeIfPresent(Double.self, forKey: .minGapFraction) ?? 0.15
        showPlotGrid            = try c.decode(Bool.self, forKey: .showPlotGrid)
        plotLegendAnchor        = try c.decodeIfPresent(String.self, forKey: .plotLegendAnchor) ?? ""
        seriesRenderMode        = try c.decodeIfPresent(SeriesRenderMode.self, forKey: .seriesRenderMode) ?? .line
        tabStates               = try c.decodeIfPresent([String: TabRenderState].self, forKey: .tabStates) ?? [:]
        chartStyleOverrides     = try c.decodeIfPresent([String: String].self, forKey: .chartStyleOverrides) ?? [:]
        cachedSearchResults     = try c.decodeIfPresent([WorkflowMeasurementSearchHit].self, forKey: .cachedSearchResults) ?? []
        selectedSearchResultIDs = try c.decodeIfPresent([String].self, forKey: .selectedSearchResultIDs) ?? []
        selectedRTHit           = try c.decodeIfPresent(WorkflowMeasurementSearchHit.self, forKey: .selectedRTHit)
        rtQuery                 = try c.decodeIfPresent(String.self, forKey: .rtQuery) ?? ""
        searchQueryText         = try c.decodeIfPresent(String.self, forKey: .searchQueryText) ?? ""
    }
}

// MARK: - ThreeOmegaPackResult

/// The analysis output snapshot.
struct ThreeOmegaPackResult: Codable, Hashable, Sendable {
    var ingestionResult: ThreeOmegaIngestionResult
    var scalingResult: ThreeOmegaScalingResult?
}

extension ThreeOmegaPackConfig: SearchQueryTextInjectable {}
