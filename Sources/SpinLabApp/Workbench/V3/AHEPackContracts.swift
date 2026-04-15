import Foundation

// MARK: - AHEPackConfig

/// Everything needed to restore an AHE workbench session.
struct AHEPackConfig: Codable, Hashable, Sendable {

    // --- Plot axis overrides ---
    var plotAxisXOverride: String
    var plotAxisYOverride: String

    // --- Display settings ---
    var titleTemplate: String
    var showPlotGrid: Bool

    // --- Per-tab display states ---
    var tabStates: [String: TabRenderState]

    // --- Search state ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var searchQueryText: String
}

extension AHEPackConfig: SearchQueryTextInjectable {}

// MARK: - AHEPackResult

/// The analysis output snapshot.
struct AHEPackResult: Codable, Hashable, Sendable {
    var ingestionResult: AHEIngestionResult
}
