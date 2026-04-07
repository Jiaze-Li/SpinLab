import Foundation
import Observation

/// Isolated state and actions for the XY Rotation workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
@MainActor
@Observable
final class XYRotationWorkspaceStore {

    // MARK: - Search / Selection

    var selectedSearchResultIDs: Set<String> = []
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []

    // MARK: - Analysis output

    private(set) var currentRunTrace: WorkbenchRunTraceProjection?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Tab selection

    var activeTab: XYRotationWorkbenchTab = .rVsPhi

    // MARK: - Plot controls

    var showPlotGrid: Bool = true

    // MARK: - Context from WorkbenchFeatureStore

    var lastLibraryRootPath: String?

    // MARK: - Selection helpers

    func toggleSearchHitSelection(_ hitID: String) {
        if selectedSearchResultIDs.contains(hitID) {
            selectedSearchResultIDs.remove(hitID)
        } else {
            selectedSearchResultIDs.insert(hitID)
        }
    }

    func selectAll() {
        selectedSearchResultIDs = Set(cachedSearchResults.map(\.id))
    }

    func clearAll() {
        selectedSearchResultIDs = []
        currentRunTrace = nil
        isAnalyzing = false
        analysisMessage = nil
    }
}

// MARK: - WorkbenchPlottingStore

extension XYRotationWorkspaceStore: WorkbenchPlottingStore {
    func updateLegendPoint(_ point: CGPoint) {}
    func updatePlotTitle(_ title: String) {}
    func updateXAxisLabel(_ label: String) {}
    func updateYAxisLabel(_ label: String) {}
    func updateSeriesLabel(index: Int, newLabel: String) {}
}
