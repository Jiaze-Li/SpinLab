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

    // --- Per-tab display states (keyed by stableKey for Codable) ---
    var tabStates: [String: TabRenderState] = [:]

    // --- Search state ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var selectedRTHit: WorkflowMeasurementSearchHit?
    var rtQuery: String
    var searchQueryText: String
}

// MARK: - ThreeOmegaPackResult

/// The analysis output snapshot.
struct ThreeOmegaPackResult: Codable, Hashable, Sendable {
    var ingestionResult: ThreeOmegaIngestionResult
    var scalingResult: ThreeOmegaScalingResult?
}

extension ThreeOmegaPackConfig: SearchQueryTextInjectable {}
