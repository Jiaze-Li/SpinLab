import SwiftUI

struct WorkbenchView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var workbench = appState.workbench

        switch workbench.currentRoute {

        case .registry:
            // Registry 保留 header + picker
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Workbench")
                            .font(AppFontScale.sectionTitle)
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 72)
                .padding(.bottom, 10)

                Divider()

                switch workbench.selectedSection {
                case .workflows:
                    ScrollView {
                        WorkflowRegistryView().padding(16)
                    }
                case .measurements:
                    ScrollView {
                        GroupBox("Measurements") {
                            ContentUnavailableView(
                                "Planned for V3.4",
                                systemImage: "chart.xyaxis.line",
                                description: Text("Measurement history will be available in V3.4 Library Writeback.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .workflow(let id):
            // standardDetailTopInset 已改为 20，与 Library 一致，直接用同样的 padding。
            WorkflowWorkspaceRegistry.workspace(for: id)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
