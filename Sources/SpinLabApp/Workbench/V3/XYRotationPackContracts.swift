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

    // --- Per-tab render states (keyed by tab.rawValue) ---
    var tabStates: [String: TabRenderState] = [:]

    // --- Search state ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var searchQueryText: String
}

// MARK: - XYRotationPackResult

/// The analysis output snapshot.
struct XYRotationPackResult: Codable, Hashable, Sendable {
    var ingestionResult: XYRotationIngestionResult
}

extension XYRotationPackConfig: SearchQueryTextInjectable {}
