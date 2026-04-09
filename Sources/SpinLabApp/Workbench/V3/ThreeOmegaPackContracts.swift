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
    var plotTitleOverride: String

    // --- Per-tab settings (keyed by stableKey for Codable) ---
    var plotLegendPoints: [String: CGPointCodable]
    var plotSeriesLabelOverrides: [String: [Int: String]]
    var plotXLabelOverrides: [String: String]
    var plotYLabelOverrides: [String: String]

    // --- Search state ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var selectedRTHit: WorkflowMeasurementSearchHit?
    var rtQuery: String
    var searchQueryText: String
}

/// CGPoint wrapper for Codable.
struct CGPointCodable: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - ThreeOmegaPackResult

/// The analysis output snapshot.
struct ThreeOmegaPackResult: Codable, Hashable, Sendable {
    var ingestionResult: ThreeOmegaIngestionResult
    var scalingResult: ThreeOmegaScalingResult?
}
