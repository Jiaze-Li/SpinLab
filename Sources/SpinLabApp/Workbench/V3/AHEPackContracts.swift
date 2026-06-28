import Foundation

// MARK: - AHEPackConfig

/// Everything needed to restore an AHE workbench session.
struct AHEPackConfig: Codable, Hashable, Sendable {

    // --- Display settings ---
    var titleTemplate: String
    var showPlotGrid: Bool
    // --- PlotControl display status (v8.5A+) ---
    var legendAnchor: String
    var seriesRenderMode: SeriesRenderMode
    var chartStyleOverrides: [String: String]

    // --- Per-tab display states (v5.3.3+) ---
    var tabStates: [String: TabRenderState]

    // --- Search state (v5.3.4+) ---
    var cachedSearchResults: [WorkflowMeasurementSearchHit]
    var selectedSearchResultIDs: [String]
    var searchQueryText: String

    init(titleTemplate: String, showPlotGrid: Bool,
         legendAnchor: String = "", seriesRenderMode: SeriesRenderMode = .line,
         chartStyleOverrides: [String: String] = [:],
         tabStates: [String: TabRenderState] = [:],
         cachedSearchResults: [WorkflowMeasurementSearchHit] = [],
         selectedSearchResultIDs: [String] = [], searchQueryText: String = "") {
        self.titleTemplate = titleTemplate; self.showPlotGrid = showPlotGrid
        self.legendAnchor = legendAnchor; self.seriesRenderMode = seriesRenderMode
        self.chartStyleOverrides = chartStyleOverrides
        self.tabStates = tabStates; self.cachedSearchResults = cachedSearchResults
        self.selectedSearchResultIDs = selectedSearchResultIDs; self.searchQueryText = searchQueryText
    }

    private enum DeprecatedCodingKeys: String, CodingKey {
        case plotAxisXOverride
        case plotAxisYOverride
    }

    // Decode deliberately rejects packs from the retired AHE axis override module.
    init(from decoder: Decoder) throws {
        let deprecated = try decoder.container(keyedBy: DeprecatedCodingKeys.self)
        if deprecated.contains(.plotAxisXOverride) || deprecated.contains(.plotAxisYOverride) {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "This AHE pack uses deprecated AHE axis overrides. Re-run the AHE analysis with fixed semantic axes H (T) vs R_H (\u{03A9}) and save a new pack."
                )
            )
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titleTemplate          = try c.decodeIfPresent(String.self, forKey: .titleTemplate) ?? ""
        showPlotGrid           = try c.decodeIfPresent(Bool.self, forKey: .showPlotGrid) ?? true
        legendAnchor           = try c.decodeIfPresent(String.self, forKey: .legendAnchor) ?? ""
        seriesRenderMode       = try c.decodeIfPresent(SeriesRenderMode.self, forKey: .seriesRenderMode) ?? .line
        chartStyleOverrides    = try c.decodeIfPresent([String: String].self, forKey: .chartStyleOverrides) ?? [:]
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
