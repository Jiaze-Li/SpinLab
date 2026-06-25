import SwiftUI

struct WorkbenchView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var workbench = appState.workbench

        switch workbench.currentRoute {

        case .registry:
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
            // standardDetailTopInset 已改为 20，与 Library 一致，直接用同样的 padding。
            WorkflowWorkspaceRegistry.workspace(for: id, featureStore: appState.workbenchFeatureStore)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
