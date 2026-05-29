import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Selection

    func toggleSearchHitSelection(_ id: String) {
        if selectedSearchResultIDs.contains(id) {
            selectedSearchResultIDs.remove(id)
        } else {
            selectedSearchResultIDs.insert(id)
        }
    }


    func selectAll() {
        selectedSearchResultIDs = Set(cachedSearchResults.map { $0.id })
    }


    func deselectAll() {
        selectedSearchResultIDs = []
    }


    // MARK: - Clear

    func clearPlot() {
        analysisTask?.cancel()
        scalingTask?.cancel()
        ingestionResult          = nil
        scalingResult            = nil
        currentRunTrace          = nil
        isAnalyzing              = false
        analysisMessage          = nil
        saveMessage              = nil
        _titleTokens             = [:]
        tabs.clearAll()
        warningLog.clear()
        activePackID             = nil
        overlayPackIDs           = []
        overlaySnapshots         = [:]
        relatedChartsTask?.cancel()
        relatedChartsTask        = nil
        relatedChartsGrouped     = [:]
        cachedSampleKeys         = []
        cachedConditionsBySampleKey = [:]
        cachedInputFiles         = []
        cachedRTFilePath         = nil
    }


    func clearResults() {
        selectedSearchResultIDs  = []
        cachedSearchResults      = []
        cachedSampleNumericDisplay = [:]
        rtQuery                  = ""
        persistRTQuery()
        rtSearchResults          = []
        rtSearchMessage          = nil
        isRTSearching            = false
        showRTPopover            = false
        selectedRTHit            = nil
    }
}
