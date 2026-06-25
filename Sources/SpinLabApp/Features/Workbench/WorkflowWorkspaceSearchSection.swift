import SwiftUI

struct WorkflowWorkspaceSearchSection<Store: WorkbenchWorkspaceProviding, SearchExtra: View>: View {
    @Environment(SpinLabAppState.self) private var appState

    let workflowID: String
    let store: Store
    let workbench: WorkbenchFeatureStore

    let searchExtra: SearchExtra

    var body: some View {
        let libraryRoot = appState.library.librarySettings.rootPath
        let queryBinding = Binding<String>(
            get: { workbench.searchQueryText(for: workflowID) },
            set: { workbench.setSearchQueryText($0, for: workflowID) }
        )

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                TextField(
                    "e.g. PN20, 80K …",
                    text: queryBinding
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    workbench.runWorkflowMeasurementSearch(
                        workflowID: workflowID,
                        libraryRootPath: libraryRoot,
                        librarySettings: appState.library.librarySettings
                    )
                }

                Button("Clear") {
                    store.clearResults()
                    workbench.clearWorkflowMeasurementSearch(workflowID: workflowID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                searchExtra
            }
            .padding(.leading, AppSpacing.xs)

            HStack(spacing: AppSpacing.xs) {
                Text("Library Root:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(libraryRoot ?? "Not configured — set in Library settings")
                    .font(.caption)
                    .foregroundStyle(libraryRoot == nil ? .red : .secondary)
                    .textSelection(.enabled)
            }

            WorkflowWorkspaceActionBar(
                workflowID: workflowID,
                store: store,
                workbench: workbench
            )
        }
    }
}
