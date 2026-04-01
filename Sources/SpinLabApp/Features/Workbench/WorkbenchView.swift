import SwiftUI

struct WorkbenchView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var workbench = appState.workbench

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Workbench")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button("Rules Handbook") {
                        openWindow(id: "rules-handbook")
                    }
                        .buttonStyle(.borderedProminent)
                }

                Picker("Section", selection: $workbench.selectedSection) {
                    ForEach(WorkbenchSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)

                switch workbench.selectedSection {
                case .workflows:
                    switch workbench.currentRoute {
                    case .registry(_):
                        WorkflowRegistryView()
                    case .workflow:
                        workflowWorkspacePlaceholder
                    }
                case .measurements:
                    GroupBox("Measurements") {
                        ContentUnavailableView(
                            "Coming in V2.6",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Measurement history will be displayed once sidecar reading is added.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var workflowWorkspacePlaceholder: some View {
        let selected = appState.workbench.selectedWorkflowDefinition
        GroupBox(selected?.displayName ?? selected?.id ?? "Workflow") {
            ContentUnavailableView(
                "Workflow Workspace",
                systemImage: "hammer",
                description: Text("Workflow operation workspace is reserved for upcoming features.")
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }
}
