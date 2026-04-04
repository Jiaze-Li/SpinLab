import SwiftUI
import AppKit

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
        @Bindable var workbench = appState.workbench

        GroupBox(selected?.displayName ?? selected?.id ?? "Workflow Search") {
            VStack(alignment: .leading, spacing: 12) {
                Text("V3.2.0 Workflow Search")
                    .font(.headline)

                TextField("Query (examples: AHE, AHE PN31, AHE 80K, AHE PN31 80K)", text: $workbench.workflowSearchQueryText)
                    .textFieldStyle(.roundedBorder)

                let libraryRoot = appState.library.librarySettings.rootPath
                HStack(spacing: 4) {
                    Text("Library Root:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(libraryRoot ?? "Not configured — set in Library settings")
                        .font(.caption)
                        .foregroundStyle(libraryRoot == nil ? .red : .secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button("Search") {
                        workbench.runWorkflowMeasurementSearch(libraryRootPath: libraryRoot)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workbench.isWorkflowSearchRunning || libraryRoot == nil)

                    Button("Clear") {
                        workbench.clearWorkflowMeasurementSearch()
                    }
                    .buttonStyle(.bordered)

                    Button("Plot") {
                        workbench.renderAHEPlot()
                    }
                    .buttonStyle(.bordered)
                    .disabled(workbench.selectedSearchResultIDs.isEmpty || workbench.isPlotRendering)

                    Button("Clear Plot") {
                        workbench.clearPlot()
                    }
                    .buttonStyle(.bordered)
                    .disabled(workbench.currentPlotImageData == nil && !workbench.isPlotRendering)

                    if let firstHit = workbench.workflowSearchResults.first {
                        Button("Load Saved") {
                            workbench.loadPersistedArtifact(sampleKey: firstHit.sampleKey)
                        }
                        .buttonStyle(.bordered)
                        .disabled(workbench.isLoadingArtifact)
                    }

                    if workbench.isWorkflowSearchRunning || workbench.isPlotRendering || workbench.isLoadingArtifact {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let message = workbench.workflowSearchMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Plot status + preview — shown immediately below buttons
                if let plotMsg = workbench.plotMessage, !plotMsg.isEmpty {
                    Text(plotMsg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let loadMsg = workbench.artifactLoadMessage, !loadMsg.isEmpty {
                    Text(loadMsg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let imageData = workbench.currentPlotImageData,
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 360)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let trace = workbench.currentRunTrace {
                    runTraceSection(trace)
                }

                if !workbench.workflowSearchResults.isEmpty {
                    plotControlsSection
                }

                if workbench.workflowSearchResults.isEmpty {
                    ContentUnavailableView(
                        "No Search Results",
                        systemImage: "magnifyingglass",
                        description: Text("Run a workflow query to inspect files across drawers.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    // No inner ScrollView — outer ScrollView handles all scrolling
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(workbench.workflowSearchResults) { hit in
                            let isSelected = workbench.selectedSearchResultIDs.contains(hit.id)
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .font(.body)
                                    .padding(.top, 2)
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
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                                    : AnyShapeStyle(.regularMaterial),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                            .onTapGesture {
                                workbench.toggleSearchHitSelection(hit.id)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var plotControlsSection: some View {
        @Bindable var workbench = appState.workbench
        let candidates = workbench.currentCandidateAxisFields.isEmpty
            ? ["Magnetic Field (Oe)", "Temperature (K)", "Bridge 1 Resistance (Ohms)", "Bridge 2 Resistance (Ohms)", "Bridge 3 Resistance (Ohms)"]
            : workbench.currentCandidateAxisFields

        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("X Axis").font(.caption).foregroundStyle(.secondary)
                        Picker("X Axis", selection: $workbench.plotAxisXOverride) {
                            Text("Default").tag("")
                            ForEach(candidates, id: \.self) { field in
                                Text(field).tag(field)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 200)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Y Axis").font(.caption).foregroundStyle(.secondary)
                        Picker("Y Axis", selection: $workbench.plotAxisYOverride) {
                            Text("Default").tag("")
                            ForEach(candidates, id: \.self) { field in
                                Text(field).tag(field)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 200)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Title Override").font(.caption).foregroundStyle(.secondary)
                        TextField("AHE Plot", text: $workbench.plotTitleOverride)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 140)
                    }
                    Toggle("Grid", isOn: $workbench.showPlotGrid)
                        .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Legend").font(.caption).foregroundStyle(.secondary)
                        Picker("Legend", selection: $workbench.plotLegendAnchor) {
                            Text("Top Right").tag("")
                            Text("Top Left").tag("top-left")
                            Text("Bottom Right").tag("bottom-right")
                            Text("Bottom Left").tag("bottom-left")
                        }
                        .labelsHidden()
                        .frame(minWidth: 110)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func runTraceSection(_ trace: WorkbenchRunTraceProjection) -> some View {
        GroupBox("Last Run Trace") {
            VStack(alignment: .leading, spacing: 6) {
                traceRow(label: "Run ID", value: trace.runID)
                traceRow(label: "Workflow", value: trace.workflowID)
                traceRow(label: "X Axis", value: trace.axisMapping.xField)
                traceRow(label: "Y Axis", value: trace.axisMapping.yField)
                traceRow(label: "Inputs", value: trace.inputFiles.joined(separator: "\n"))
                traceRow(label: "Output", value: trace.outputImagePath)
                traceRow(label: "Identity", value: trace.chartIdentityKey)
                traceRow(label: "Generated", value: trace.generatedAt.formatted(.dateTime))
                traceRow(label: "Version", value: trace.appVersion)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func traceRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
