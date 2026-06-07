import SwiftUI

struct WorkflowWorkspaceActionBar<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState

    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    var body: some View {
        let readiness = workbench.readinessProjection(for: workflowID, store: store)

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
            .disabled(!readiness.hasFoundData)

            Button("Analyze") {
                let selectedSnapshot = workbench.selectedHitsSnapshot(
                    for: workflowID,
                    selectedIDs: store.selectedSearchResultIDs,
                    legacyHits: store.cachedSearchResults
                )
                store.runAnalysis(selectedHitsSnapshot: selectedSnapshot)
            }
            .buttonStyle(.bordered)
            .disabled(!readiness.hasSelectedData || store.isAnalyzing)

            WorkflowWorkspaceLoadPackPlacement(workflowID: workflowID, store: store)

            if readiness.isRunning {
                ProgressView().controlSize(.small)
            }
        }
    }
}
