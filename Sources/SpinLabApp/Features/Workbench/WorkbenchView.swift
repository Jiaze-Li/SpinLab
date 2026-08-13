import SwiftUI

/// Workbench Primary pane content: measurements dashboard, or the active
/// workflow's left column (search/action bar/plot controls/results).
/// Workbench no longer owns an independent split layout — see
/// `AppWorkspaceShell`. Workflow dispatch happens *inside* this switch, not
/// around a per-workflow shell, so identity in the app-wide Primary pane
/// survives workflow switches.
struct WorkbenchPrimaryView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        switch appState.workbench.currentRoute {
        case .measurements:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Workbench")
                        .font(AppFontScale.sectionTitle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 72)
                .padding(.bottom, 10)

                Divider()

                ScrollView {
                    WorkbenchMeasurementsPanel(runtime: appState.workbench.sampleWorkTracker)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .workflow(let id):
            WorkflowWorkspaceRegistry.leftContent(for: id, featureStore: appState.workbenchFeatureStore)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Workbench Detail pane content: empty for the measurements dashboard
/// (which has no right-hand content), or the active workflow's right column
/// (results/status).
struct WorkbenchDetailView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        switch appState.workbench.currentRoute {
        case .measurements:
            EmptyView()

        case .workflow(let id):
            WorkflowWorkspaceRegistry.rightContent(for: id, featureStore: appState.workbenchFeatureStore)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
