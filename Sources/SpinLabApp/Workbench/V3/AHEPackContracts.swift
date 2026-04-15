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

    // --- Per-tab display states (v5.3.3+) ---
    var tabStates: [String: TabRenderState]

    // --- Search state (v5.3.4+) ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var searchQueryText: String

    init(plotAxisXOverride: String, plotAxisYOverride: String, titleTemplate: String, showPlotGrid: Bool,
         tabStates: [String: TabRenderState] = [:], cachedSearchResults: [WorkflowMeasurementSearchHit] = [],
         selectedSearchResultIDs: [String] = [], searchQueryText: String = "") {
        self.plotAxisXOverride = plotAxisXOverride; self.plotAxisYOverride = plotAxisYOverride
        self.titleTemplate = titleTemplate; self.showPlotGrid = showPlotGrid
        self.tabStates = tabStates; self.cachedSearchResults = cachedSearchResults
        self.selectedSearchResultIDs = selectedSearchResultIDs; self.searchQueryText = searchQueryText
    }

    // Backward-compatible decode: fields added after initial release default safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plotAxisXOverride      = try c.decodeIfPresent(String.self, forKey: .plotAxisXOverride) ?? ""
        plotAxisYOverride      = try c.decodeIfPresent(String.self, forKey: .plotAxisYOverride) ?? ""
        titleTemplate          = try c.decodeIfPresent(String.self, forKey: .titleTemplate) ?? ""
        showPlotGrid           = try c.decodeIfPresent(Bool.self, forKey: .showPlotGrid) ?? true
        tabStates              = try c.decodeIfPresent([String: TabRenderState].self, forKey: .tabStates) ?? [:]
        cachedSearchResults    = try c.decodeIfPresent([WorkflowMeasurementSearchHit].self, forKey: .cachedSearchResults) ?? []
        selectedSearchResultIDs = try c.decodeIfPresent([String].self, forKey: .selectedSearchResultIDs) ?? []
        searchQueryText        = try c.decodeIfPresent(String.self, forKey: .searchQueryText) ?? ""
    }
}

extension AHEPackConfig: SearchQueryTextInjectable {}

// MARK: - AHEPackResult

/// The analysis output snapshot.
struct AHEPackResult: Codable, Hashable, Sendable {
    var ingestionResult: AHEIngestionResult?

    // Backward-compatible decode: legacy packs had only `placeholder: Bool`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ingestionResult = try c.decodeIfPresent(AHEIngestionResult.self, forKey: .ingestionResult)
    }

    init(ingestionResult: AHEIngestionResult?) {
        self.ingestionResult = ingestionResult
    }
}
