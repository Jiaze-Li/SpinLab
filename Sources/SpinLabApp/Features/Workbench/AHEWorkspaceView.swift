import SwiftUI
import AppKit

/// AHE 工作流 workspace view。
/// 列结构直接照抄 LibraryView 的两列框架：
///   左列 → librarySettingsColumn 骨架
///   右列 → libraryDetailColumn 骨架
struct AHEWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell {
            aheLeftColumn
        } rightColumn: {
            aheRightColumn
        }
    }

    // MARK: - 左列

    private var aheLeftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 固定控制区（始终可见）────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .firstTextBaseline) {
                    Text(appState.workbench.selectedWorkflowDefinition?.displayName ?? "Workflow")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.top, 4)

                AHESearchSection()
                    .environment(appState)

                AHEPlotControlsPanel()
                    .environment(appState)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // ── 可滚动结果列表 ──────────────────────────────────────
            AHEResultsList()
                .environment(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 右列（镜像 libraryDetailColumn）

    private var aheRightColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {

                // 列标题（镜像 sampleDetailHeader）
                HStack {
                    Text("Result")
                        .font(.title2.bold())
                    Spacer()
                }

                // 内容区
                WorkbenchStatusArea(
                    searchMessage: nil,
                    plotMessage: appState.workbench.aheWorkspace.plotMessage,
                    loadMessage: nil
                )

                WorkbenchPlotCanvas(
                    imageData: appState.workbench.aheWorkspace.currentPlotImageData,
                    layout: appState.workbench.aheWorkspace.currentPlotLayout,
                    seriesLabelOverrides: appState.workbench.aheWorkspace.plotSeriesLabelOverrides,
                    onLegendDrag: { pt in appState.workbench.aheWorkspace.updateLegendPoint(pt) },
                    onEditTitle: { title in appState.workbench.aheWorkspace.updatePlotTitle(title) },
                    onEditXLabel: { label in appState.workbench.aheWorkspace.updateXAxisLabel(label) },
                    onEditYLabel: { label in appState.workbench.aheWorkspace.updateYAxisLabel(label) },
                    onEditLegendLabel: { orig, label in
                        appState.workbench.aheWorkspace.updateSeriesLabel(originalLabel: orig, newLabel: label)
                    }
                )

                WorkbenchTracePanel(trace: appState.workbench.aheWorkspace.currentRunTrace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }
}

// MARK: - 左列：搜索 + 操作区

private struct AHESearchSection: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var workbench = appState.workbench
        let ahe = appState.workbench.aheWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        VStack(alignment: .leading, spacing: 8) {
            TextField("AHE, AHE PN31, AHE 80K …", text: $workbench.workflowSearchQueryText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 4) {
                Text("Library Root:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(libraryRoot ?? "Not configured — set in Library settings")
                    .font(.caption)
                    .foregroundStyle(libraryRoot == nil ? .red : .secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
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
                    ahe.renderAHEPlot()
                }
                .buttonStyle(.bordered)
                .disabled(ahe.selectedSearchResultIDs.isEmpty || ahe.isPlotRendering)

                Button("Clear Plot") {
                    ahe.clearPlot()
                }
                .buttonStyle(.bordered)
                .disabled(ahe.currentPlotImageData == nil && !ahe.isPlotRendering)

                if workbench.isWorkflowSearchRunning || ahe.isPlotRendering {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}

// MARK: - 左列：可滚动结果列表

private struct AHEResultsList: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let workbench = appState.workbench
        let ahe = appState.workbench.aheWorkspace

        if workbench.workflowSearchResults.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let msg = workbench.workflowSearchMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Run a search to find measurements.")
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if let msg = workbench.workflowSearchMessage, !msg.isEmpty {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workbench.workflowSearchResults) { hit in
                        let isSelected = ahe.selectedSearchResultIDs.contains(hit.id)
                        AHEHitRow(hit: hit, isSelected: isSelected) {
                            ahe.toggleSearchHitSelection(hit.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - 图表参数面板

private struct AHEPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var ahe = appState.workbench.aheWorkspace
        let candidates = ahe.currentCandidateAxisFields.isEmpty
            ? ["Magnetic Field (Oe)", "Magnetic Field (T)", "Temperature (K)",
               "R_H (\u{03A9})", "Bridge 1 Resistance (Ohms)", "Bridge 2 Resistance (Ohms)", "Bridge 3 Resistance (Ohms)"]
            : ahe.currentCandidateAxisFields

        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("X Axis").font(.caption).foregroundStyle(.secondary)
                    Picker("X Axis", selection: $ahe.plotAxisXOverride) {
                        Text("Default").tag("")
                        ForEach(candidates, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Y Axis").font(.caption).foregroundStyle(.secondary)
                    Picker("Y Axis", selection: $ahe.plotAxisYOverride) {
                        Text("Default").tag("")
                        ForEach(candidates, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Title").font(.caption).foregroundStyle(.secondary)
                    TextField("AHE", text: $ahe.plotTitleOverride)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 16) {
                    Toggle("Grid", isOn: $ahe.showPlotGrid)
                        .toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Legend").font(.caption).foregroundStyle(.secondary)
                        Picker("Legend", selection: $ahe.plotLegendAnchor) {
                            Text("Top Right").tag("")
                            Text("Top Left").tag("top-left")
                            Text("Bottom Right").tag("bottom-right")
                            Text("Bottom Left").tag("bottom-left")
                        }
                        .labelsHidden()
                        .onChange(of: ahe.plotLegendAnchor) { _, _ in
                            ahe.plotLegendPoint = nil
                            ahe.renderAHEPlot(persistArtifact: false)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 搜索结果行

private struct AHEHitRow: View {
    let hit: WorkflowMeasurementSearchHit
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Workflow").font(.caption).foregroundStyle(.secondary)
                    Text(hit.workflowDisplayName).font(.body.weight(.semibold))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Sample").font(.caption).foregroundStyle(.secondary)
                    Text(hit.sampleBatchAndSubstrate)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Condition").font(.caption).foregroundStyle(.secondary)
                    Text(hit.conditionSummary).font(.callout)
                }
                if !hit.channels.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Channels").font(.caption).foregroundStyle(.secondary)
                        Text(hit.channels.joined(separator: ", ")).font(.callout)
                    }
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
        .onTapGesture(perform: onTap)
    }
}
