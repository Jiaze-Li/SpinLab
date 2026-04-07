import SwiftUI

/// XY Rotation workflow workspace.
///
/// 列结构与 ThreeOmegaWorkspaceView / AHEWorkspaceView 对齐：
///   左列 → 搜索 + PlotControlsPanel + ResultsList
///   右列 → "Result" + WorkbenchStatusArea + WorkbenchPlotCanvas (交互) + TracePanel
struct XYRotationWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell {
            XYRotationLeftColumn()
                .environment(appState)
        } rightColumn: {
            XYRotationRightColumn()
                .environment(appState)
        }
    }
}

// MARK: - 左列

private struct XYRotationLeftColumn: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 固定控制区 ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .firstTextBaseline) {
                    Text("XY Rotation")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.top, 4)

                XYRotationSearchSection()
                    .environment(appState)

                XYRotationPlotControlsPanel()
                    .environment(appState)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // ── 可滚动结果列表 ──────────────────────────────────────
            XYRotationResultsList()
                .environment(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 搜索 + 操作按钮

private struct XYRotationSearchSection: View {
    @Environment(SpinLabAppState.self) private var appState
    private let wf: WorkbenchWorkflowID = .xyRotation

    var body: some View {
        @Bindable var workbench = appState.workbench
        let store = appState.workbench.xyRotationWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        let queryBinding = Binding<String>(
            get: { workbench.searchQueryText(for: wf) },
            set: { workbench.setSearchQueryText($0, for: wf) }
        )

        VStack(alignment: .leading, spacing: 8) {
            TextField("xy PN20, xy 80K …", text: queryBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    workbench.runWorkflowMeasurementSearch(workflowID: wf, libraryRootPath: libraryRoot)
                }

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
                    workbench.runWorkflowMeasurementSearch(workflowID: wf, libraryRootPath: libraryRoot)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workbench.isSearchRunning(for: wf) || libraryRoot == nil)

                Button("Select All") {
                    store.selectAll()
                }
                .buttonStyle(.bordered)
                .disabled(workbench.searchResultsList(for: wf).isEmpty)

                Button("Analyze") {
                    // TODO: 4.2.2 — wire to IngestXYRotationSelectionsUseCase
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedSearchResultIDs.isEmpty || store.isAnalyzing)

                Button("Clear") {
                    store.clearAll()
                    workbench.clearWorkflowMeasurementSearch(workflowID: wf)
                }
                .buttonStyle(.bordered)

                if workbench.isSearchRunning(for: wf) || store.isAnalyzing {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Plot Controls Panel

private struct XYRotationPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.xyRotationWorkspace

        WorkbenchPlotControlsPanel {
            HStack(spacing: 8) {
                Picker("Tab", selection: $store.activeTab) {
                    ForEach(XYRotationWorkbenchTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Toggle("Grid", isOn: $store.showPlotGrid)
                    .toggleStyle(.checkbox)
            }
        }
    }
}

// MARK: - Results list

private struct XYRotationResultsList: View {
    @Environment(SpinLabAppState.self) private var appState
    private let wf: WorkbenchWorkflowID = .xyRotation

    var body: some View {
        let workbench = appState.workbench
        let store = workbench.xyRotationWorkspace
        let results = workbench.searchResultsList(for: wf)
        let message = workbench.searchMessage(for: wf)

        if results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let msg = message, !msg.isEmpty {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Run a search to find XY Rotation measurements.")
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if let msg = message, !msg.isEmpty {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { hit in
                        let isSelected = store.selectedSearchResultIDs.contains(hit.id)
                        WorkflowHitRow(hit: hit, isSelected: isSelected) {
                            store.toggleSearchHitSelection(hit.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - 右列

private struct XYRotationRightColumn: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.xyRotationWorkspace

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Text("Result")
                        .font(.title2.bold())
                    Spacer()
                }

                WorkbenchStatusArea(
                    searchMessage: nil,
                    plotMessage: store.analysisMessage,
                    loadMessage: nil
                )

                // TODO: 4.2.3 — WorkbenchPlotCanvas here

                WorkbenchTracePanel(trace: store.currentRunTrace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }
}
