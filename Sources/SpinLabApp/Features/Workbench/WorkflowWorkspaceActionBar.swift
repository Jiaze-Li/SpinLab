import SwiftUI

struct WorkflowWorkspaceActionBar<Store: WorkbenchWorkspaceProviding, ActionBarTrailing: View>: View {
    @Environment(SpinLabAppState.self) private var appState

    let workflowID: String
    let store: Store
    let workbench: WorkbenchFeatureStore
    let actionBarTrailing: ActionBarTrailing

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

            Button("Clear Selected") {
                workbench.deselectAll(for: workflowID)
            }
            .buttonStyle(.bordered)
            .disabled(workbench.selectedCount(for: workflowID) == 0)

            Button(workbench.isAllSelected(for: workflowID) ? "Deselect All" : "Select All") {
                if workbench.isAllSelected(for: workflowID) {
                    workbench.deselectCurrentResults(for: workflowID)
                } else {
                    workbench.selectAll(for: workflowID)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!readiness.hasFoundData)

            Button("Analyze") {
                store.runAnalysis(selectedHitsSnapshot: workbench.selectedHitsSnapshot(for: workflowID))
            }
            .buttonStyle(.bordered)
            .disabled(!readiness.hasSelectedData || store.isAnalyzing)

            WorkflowWorkspaceLoadPackPlacement(workflowID: workflowID, store: store)

            actionBarTrailing

            if readiness.isRunning {
                ProgressView().controlSize(.small)
            }
        }
    }
}

extension WorkflowWorkspaceActionBar where ActionBarTrailing == EmptyView {
    init(workflowID: String, store: Store, workbench: WorkbenchFeatureStore) {
        self.workflowID = workflowID
        self.store = store
        self.workbench = workbench
        self.actionBarTrailing = EmptyView()
    }
}
