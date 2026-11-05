import Foundation

// MARK: - Global Search (filters persisted by the stable owner; results and
// the preview target are page-local and rebuilt from current Library data)

extension LibraryWorkspaceState {

    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchFilters: LibrarySearchFilters {
        LibrarySearchFilters(
            batchText: searchBatchIdText,
            substrateText: searchSubstrateText,
            keywordText: searchKeywordText,
            thickness: Self.number(searchThicknessText),
            oxygen: Self.number(searchOxygenText),
            temperature: Self.number(searchTemperatureText),
            energy: Self.number(searchEnergyText),
            thicknessTolerance: Self.number(searchThicknessToleranceText),
            oxygenTolerance: Self.number(searchOxygenToleranceText),
            temperatureTolerance: Self.number(searchTemperatureToleranceText),
            energyTolerance: Self.number(searchEnergyToleranceText)
        )
    }

    var searchFingerprint: String {
        [
            searchBatchIdText,
            searchSubstrateText,
            searchKeywordText,
            searchThicknessText,
            searchOxygenText,
            searchTemperatureText,
            searchEnergyText,
            searchThicknessToleranceText,
            searchOxygenToleranceText,
            searchTemperatureToleranceText,
            searchEnergyToleranceText
        ].joined(separator: "|")
    }

    /// Every existing-drawer sample in the legacy sort order.
    func allExistingDrawerSamples(_ appState: SpinLabAppState) -> [SearchResultItem] {
        let flat = appState.library.libraryExistingGroups.flatMap { prefix, batchGroups in
            batchGroups.flatMap { group in
                group.samples.map { SearchResultItem(prefix: prefix, sample: $0) }
            }
        }
        return LibrarySort.sortedExistingDrawerSamples(flat, prefix: \.prefix, batchId: \.sample.batchId, substrate: \.sample.substrateDisplay)
    }

    func executeSearch(appState: SpinLabAppState) {
        let service = LibraryViewComputationService()
        let filters = searchFilters
        searchMatchedResults = allExistingDrawerSamples(appState).filter {
            service.matchesSearch(sample: $0.sample, filters: filters)
        }
        searchHasExecuted = true
        reconcileSearchPreview(appState: appState)
    }

    func clearSearchFilters() {
        searchBatchIdText = ""
        searchSubstrateText = ""
        searchKeywordText = ""
        searchThicknessText = ""
        searchOxygenText = ""
        searchTemperatureText = ""
        searchEnergyText = ""
        searchThicknessToleranceText = ""
        searchOxygenToleranceText = ""
        searchTemperatureToleranceText = ""
        searchEnergyToleranceText = ""
        searchMatchedResults = []
        searchHasExecuted = false
        searchPreviewTarget = nil
    }

    // MARK: Preview target (search-local; never touches Drawer/Browser selection)

    func selectSearchPreview(_ result: SearchResultItem) {
        searchPreviewTarget = SearchPreviewTarget(
            prefix: result.prefix,
            batchId: result.sample.batchId,
            sampleId: result.sample.id
        )
    }

    func isSearchPreviewTarget(_ result: SearchResultItem) -> Bool {
        searchPreviewTarget == SearchPreviewTarget(
            prefix: result.prefix,
            batchId: result.sample.batchId,
            sampleId: result.sample.id
        )
    }

    /// Current sample for the preview target, resolved from live Library data
    /// and required to still be a match. Nil when anything no longer lines up.
    func resolvedSearchPreviewSample(_ appState: SpinLabAppState) -> LibrarySample? {
        guard let target = searchPreviewTarget, searchHasExecuted else {
            return nil
        }
        guard searchMatchedResults.contains(where: {
            $0.prefix == target.prefix && $0.sample.batchId == target.batchId && $0.sample.id == target.sampleId
        }) else {
            return nil
        }
        return appState.library.libraryExistingGroups[target.prefix]?
            .first(where: { $0.batchId == target.batchId })?
            .samples.first(where: { $0.id == target.sampleId })
    }

    /// Drops a preview whose result vanished (filters changed / data refreshed).
    func reconcileSearchPreview(appState: SpinLabAppState) {
        if searchPreviewTarget != nil, resolvedSearchPreviewSample(appState) == nil {
            searchPreviewTarget = nil
        }
    }
}
