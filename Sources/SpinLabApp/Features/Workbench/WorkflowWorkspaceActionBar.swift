import SwiftUI

struct WorkflowWorkspaceActionBar<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState

    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Button("Search") {
                workbench.runWorkflowMeasurementSearch(
                    workflowID: workflowID,
                    libraryRootPath: appState.library.librarySettings.rootPath,
                    librarySettings: appState.library.librarySettings
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(workbench.isSearchRunning(for: workflowID) || appState.library.librarySettings.rootPath == nil)

            Button(store.isAllSelected ? "Deselect All" : "Select All") {
                if store.isAllSelected {
                    store.deselectAll()
                } else {
                    store.selectAll()
                }
            }
            .buttonStyle(.bordered)
            .disabled(workbench.searchResultsList(for: workflowID).isEmpty)

            Button("Analyze") {
                let selectedSnapshot = workbench.selectedHitsSnapshot(
                    for: workflowID,
                    selectedIDs: store.selectedSearchResultIDs,
                    legacyHits: store.cachedSearchResults
                )
                store.runAnalysis(selectedHitsSnapshot: selectedSnapshot)
            }
            .buttonStyle(.bordered)
            .disabled(store.selectedSearchResultIDs.isEmpty || store.isAnalyzing)

            WorkbenchLoadPackPopover(workflowID: workflowID.rawValue, store: store)

            if workbench.isSearchRunning(for: workflowID) || store.isAnalyzing {
                ProgressView().controlSize(.small)
            }
        }
    }
}
