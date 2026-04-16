import SwiftUI

extension LibraryView {
    var searchWorkspaceSection: some View {
        SearchWorkspaceSectionView(
            isExpanded: $isSearchWorkspaceExpanded,
            batchIdText: $searchBatchIdText,
            substrateText: $searchSubstrateText,
            keywordText: $searchKeywordText,
            thicknessText: $searchThicknessText,
            oxygenText: $searchOxygenText,
            temperatureText: $searchTemperatureText,
            energyText: $searchEnergyText,
            thicknessToleranceText: $searchThicknessToleranceText,
            oxygenToleranceText: $searchOxygenToleranceText,
            temperatureToleranceText: $searchTemperatureToleranceText,
            energyToleranceText: $searchEnergyToleranceText,
            level2HeaderFont: level2HeaderFont,
            level3HeaderFont: level3HeaderFont,
            searchHasExecuted: searchHasExecuted,
            searchMatchedResults: searchMatchedResults,
            onSearch: {
                executeSearch()
            },
            onClear: {
                clearSearchFilters()
            },
            onSelectResult: { result in
                selectSearchResultSample(result)
            },
            isSelectedResult: { result in
                isSelectedSearchResult(result)
            }
        )
    }

    var existingDrawerSampleSection: some View {
        LibraryExistingDrawerSampleSectionView(
            level2HeaderFont: level2HeaderFont,
            level3HeaderFont: level3HeaderFont,
            selectedPrefix: lib.librarySelectedPrefix,
            selectedBatchId: lib.librarySelectedBatchId,
            selectedSampleId: lib.librarySelectedSampleId,
            selectedExistingBatchSamples: selectedExistingBatchSamples
        ) { sample in
            guard let prefix = lib.librarySelectedPrefix,
                  let batchId = lib.librarySelectedBatchId else {
                return
            }
            viewModel.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sample.id)
        }
    }
    var allExistingDrawerSamples: [SearchResultItem] {
        let groups = lib.libraryExistingGroups
        return groups
            .flatMap { prefix, batchGroups in
                batchGroups.flatMap { group in
                    group.samples.map { sample in
                        SearchResultItem(prefix: prefix, sample: sample)
                    }
                }
            }
            .sorted {
                if $0.prefix != $1.prefix {
                    return $0.prefix < $1.prefix
                }
                if LibrarySort.compareBatch($0.sample.batchId, $1.sample.batchId) {
                    return true
                }
                if LibrarySort.compareBatch($1.sample.batchId, $0.sample.batchId) {
                    return false
                }
                return $0.sample.substrateDisplay < $1.sample.substrateDisplay
            }
    }

    var searchThicknessValue: Double? {
        Double(searchThicknessText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchOxygenValue: Double? {
        Double(searchOxygenText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchTemperatureValue: Double? {
        Double(searchTemperatureText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchEnergyValue: Double? {
        Double(searchEnergyText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchThicknessToleranceValue: Double? {
        Double(searchThicknessToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchOxygenToleranceValue: Double? {
        Double(searchOxygenToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchTemperatureToleranceValue: Double? {
        Double(searchTemperatureToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchEnergyToleranceValue: Double? {
        Double(searchEnergyToleranceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func clearSearchFilters() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
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
    }

    func executeSearch() {
        searchMatchedResults = allExistingDrawerSamples.filter { result in
            computationService.matchesSearch(sample: result.sample, filters: searchFilters)
        }
        searchHasExecuted = true
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

    func scheduleDebouncedSearchIfNeeded() {
        guard searchHasExecuted else {
            return
        }

        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else {
                return
            }
            executeSearch()
        }
    }
    var searchFilters: LibrarySearchFilters {
        LibrarySearchFilters(
            batchText: searchBatchIdText,
            substrateText: searchSubstrateText,
            keywordText: searchKeywordText,
            thickness: searchThicknessValue,
            oxygen: searchOxygenValue,
            temperature: searchTemperatureValue,
            energy: searchEnergyValue,
            thicknessTolerance: searchThicknessToleranceValue,
            oxygenTolerance: searchOxygenToleranceValue,
            temperatureTolerance: searchTemperatureToleranceValue,
            energyTolerance: searchEnergyToleranceValue
        )
    }

    func selectSearchResultSample(_ result: SearchResultItem) {
        viewModel.selectExistingDrawer(prefix: result.prefix, batchId: result.sample.batchId, sampleId: result.sample.id)
    }

    func isSelectedSearchResult(_ result: SearchResultItem) -> Bool {
        lib.libraryActiveSelectionSource == .drawer
            && lib.librarySelectedPrefix == result.prefix
            && lib.librarySelectedBatchId == result.sample.batchId
            && lib.librarySelectedSampleId == result.sample.id
    }
}
