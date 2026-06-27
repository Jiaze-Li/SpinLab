import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Clear

    func clearPlot() {
        analysisTask?.cancel()
        scalingTask?.cancel()
        scalingTask = nil
        ingestionResult          = nil
        scalingResult            = nil
        transportDerivedStatus    = .idle
        isRefreshingTransportDerivedPlots = false
        currentRunTrace          = nil
        isAnalyzing              = false
        analysisMessage          = nil
        saveMessage              = nil
        _titleTokens             = [:]
        tabs.clearAll()
        warningLog.clear()
        activePackID             = nil
        overlayRuntime?.clear()
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
        cachedSearchResults        = []
        cachedSampleNumericDisplay = [:]
        rtQuery                    = ""
        persistRTQuery()
        rtSearchResults            = []
        rtSearchMessage            = nil
        isRTSearching              = false
        showRTPopover              = false
        selectedRTHit              = nil
    }
}
