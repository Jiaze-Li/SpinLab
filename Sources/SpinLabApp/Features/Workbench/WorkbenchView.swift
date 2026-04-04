import SwiftUI

struct WorkbenchView: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var workflowSearchRootPathOverride: String = ""

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
        @Bindable var workbench = appState.workbench

        GroupBox(selected?.displayName ?? selected?.id ?? "Workflow Search") {
            VStack(alignment: .leading, spacing: 12) {
                Text("V3.2.0 Workflow Search")
                    .font(.headline)

                TextField("Query (examples: AHE, AHE PN31, AHE 80K, AHE PN31 80K)", text: $workbench.workflowSearchQueryText)
                    .textFieldStyle(.roundedBorder)

                TextField("Library Root Path", text: $workflowSearchRootPathOverride)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        if workflowSearchRootPathOverride.isEmpty {
                            workflowSearchRootPathOverride = appState.library.librarySettings.rootPath ?? ""
                        }
                    }

                HStack(spacing: 10) {
                    Button("Search") {
                        workbench.runWorkflowMeasurementSearch(libraryRootPath: resolvedSearchRootPath)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workbench.isWorkflowSearchRunning)

                    Button("Clear") {
                        workbench.clearWorkflowMeasurementSearch()
                    }
                    .buttonStyle(.bordered)

                    if workbench.isWorkflowSearchRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let message = workbench.workflowSearchMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if workbench.workflowSearchResults.isEmpty {
                    ContentUnavailableView(
                        "No Search Results",
                        systemImage: "magnifyingglass",
                        description: Text("Run a workflow query to inspect files across drawers.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(workbench.workflowSearchResults) { hit in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("Workflow")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(hit.workflowDisplayName)
                                            .font(.body.weight(.semibold))
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("Sample")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(hit.sampleBatchAndSubstrate)
                                        Text("[\(hit.sampleKey)]")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("Condition")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(hit.conditionSummary)
                                            .font(.caption)
                                    }
                                    Text(hit.measurementFilePath)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .frame(minHeight: 240)
                }
            }
        }
    }

    private var resolvedSearchRootPath: String {
        let override = workflowSearchRootPathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            return override
        }
        return appState.library.librarySettings.rootPath ?? ""
    }
}
