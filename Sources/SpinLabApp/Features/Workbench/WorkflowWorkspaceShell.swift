import SwiftUI

/// 通用两列工作区容器。
///
/// 配合 app 侧边栏共同构成整体三列布局：侧边栏 | 左列 | 右列。
/// Shell 负责所有三个 workflow 共享的 UI 区块（操作栏、结果头、状态、图表、trace、warning）。
/// Workflow 专属内容通过 ViewBuilder slot 注入。
///
/// 泛型参数说明：
/// - `Store`: conform `WorkbenchWorkspaceProviding` 的 workflow store
/// - `SearchExtra`: 搜索区扩展（例如 3ω 的 RT 搜索框）
/// - `PlotControls`: Plot 控件区（每个 workflow 自行构建，因 Tab 泛型不同）
/// - `LeftExtra`: 左栏底部扩展（例如 Geometry 面板、Override 面板）
/// - `RightExtra`: 右栏扩展（例如 Scaling 面板）
struct WorkflowWorkspaceShell<
    Store: WorkbenchWorkspaceProviding,
    SearchExtra: View,
    PlotControls: View,
    LeftExtra: View,
    RightExtra: View
>: View {

    @Environment(SpinLabAppState.self) private var appState

    let workflowID: WorkbenchWorkflowID
    let store: Store
    let workbench: WorkbenchFeatureStore

    @ViewBuilder let searchExtra: SearchExtra
    @ViewBuilder let plotControls: PlotControls
    @ViewBuilder let leftExtra: LeftExtra
    @ViewBuilder let rightExtra: RightExtra

    var body: some View {
        AppColumnShell(columnKey: "workbench", defaults: .workbench, left: {
            leftColumn
        }, right: {
            rightColumn
        })
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 固定控制区 ──
            VStack(alignment: .leading, spacing: 10) {
                titleBar
                searchSection
                plotControls
                leftExtra
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // ── 可滚动结果列表 ──
            resultsList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(appState.workbench.selectedWorkflowDefinition?.displayName ?? "Workflow")
                .font(AppFontScale.sectionTitle)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Search section

    private var searchSection: some View {
        let libraryRoot = appState.library.librarySettings.rootPath
        let queryBinding = Binding<String>(
            get: { workbench.searchQueryText(for: workflowID) },
            set: { workbench.setSearchQueryText($0, for: workflowID) }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField(workflowID.searchPrefix + "PN20, \(workflowID.searchPrefix)80K …",
                          text: queryBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        workbench.runWorkflowMeasurementSearch(workflowID: workflowID, libraryRootPath: libraryRoot)
                    }

                Button("Clear") {
                    store.clearResults()
                    workbench.clearWorkflowMeasurementSearch(workflowID: workflowID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                searchExtra
            }
            .padding(.leading, 4)

            HStack(spacing: 4) {
                Text("Library Root:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(libraryRoot ?? "Not configured — set in Library settings")
                    .font(.caption)
                    .foregroundStyle(libraryRoot == nil ? .red : .secondary)
                    .textSelection(.enabled)
            }

            actionBar(libraryRoot: libraryRoot)
        }
    }

    // MARK: - Action bar

    private func actionBar(libraryRoot: String?) -> some View {
        HStack(spacing: 8) {
            Button("Search") {
                workbench.runWorkflowMeasurementSearch(workflowID: workflowID, libraryRootPath: libraryRoot)
            }
            .buttonStyle(.borderedProminent)
            .disabled(workbench.isSearchRunning(for: workflowID) || libraryRoot == nil)

            Button(store.isAllSelected ? "Deselect All" : "Select All") {
                if store.isAllSelected {
                    store.deselectAll()
                } else {
                    store.selectAll()
                }
            }
            .buttonStyle(.bordered)
            .disabled(workbench.searchResultsList(for: workflowID).isEmpty)

            Button("Analyze") {
                store.runAnalysis()
            }
            .buttonStyle(.bordered)
            .disabled(store.selectedSearchResultIDs.isEmpty || store.isAnalyzing)

            WorkbenchLoadPackPopover(workflowID: workflowID.rawValue, store: store)

            if workbench.isSearchRunning(for: workflowID) || store.isAnalyzing {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Search results list

    private var resultsList: some View {
        let results = workbench.searchResultsList(for: workflowID)
        let message = workbench.searchMessage(for: workflowID)

        return Group {
            if results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if let msg = message, !msg.isEmpty {
                        Text("\(msg)  Numeric tolerance: ±\(Int(NumericUnitMap.relativeTolerance * 100))%")
                            .font(.callout)
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
                        if let msg = message, !msg.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(msg)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("Numeric tolerance: ±\(Int(NumericUnitMap.relativeTolerance * 100))% (min ±\(NumericUnitMap.absoluteToleranceFloor, specifier: "%.0f"))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        ForEach(results) { hit in
                            let isSelected = store.selectedSearchResultIDs.contains(hit.id)
                            WorkflowHitRow(
                                hit: hit,
                                isSelected: isSelected,
                                numericDisplay: store.cachedSampleNumericDisplay[hit.sampleKey] ?? [:]
                            ) {
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

    // MARK: - Right column

    private var rightColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                resultHeader
                statusArea
                plotCanvas
                rightExtra
                WorkbenchTracePanel(trace: store.currentRunTrace)
                WorkbenchWarningPanel(entries: store.warningLog)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    // MARK: - Result header (Save/Update + Save to Library)

    private var resultHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Result")
                    .font(AppFontScale.sectionTitle)
                Spacer()

                Button("Clear Plot") {
                    store.clearPlot()
                }
                .buttonStyle(.bordered)
                .disabled(store.activeImageData == nil && !store.isAnalyzing)

                if store.matchingVaultPack != nil {
                    Button("Update Analysis") {
                        let queryText = workbench.searchQueryText(for: workflowID)
                        store.saveAnalysis(searchQueryText: queryText)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.hasAnalysisResult)
                } else {
                    Button("Save Analysis") {
                        let queryText = workbench.searchQueryText(for: workflowID)
                        store.saveAnalysis(searchQueryText: queryText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.hasAnalysisResult)
                }

                Button("Save to Library") {
                    store.persistToLibrary {
                        appState.library.loadWorkbenchResultsForCurrentSelection()
                        appState.library.loadMeasurementDataForCurrentSelection()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!store.hasAnalysisResult)
            }

            if let pack = store.matchingVaultPack {
                Text("→ \(pack.label)")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - Status area

    @ViewBuilder
    private var statusArea: some View {
        let warningCount = store.warningLog.count
        if let msg = store.analysisMessage {
            if warningCount > 0 {
                (Text(msg).foregroundStyle(.secondary)
                 + Text(" (\(warningCount) warning(s))").foregroundStyle(.orange))
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Plot canvas

    private var plotCanvas: some View {
        WorkbenchPlotCanvas(
            imageData: store.activeImageData,
            layout: store.activeLayout,
            seriesLabelOverrides: store.seriesLabelOverrides,
            onLegendDrag: { pt in
                store.updateLegendPoint(pt)
                appState.flushInteractionSnapshotNow()
            },
            onEditTitle: { title in store.updatePlotTitle(title) },
            onEditXLabel: { label in store.updateXAxisLabel(label) },
            onEditYLabel: { label in store.updateYAxisLabel(label) },
            onEditLegendLabel: { idx, label in
                store.updateSeriesLabel(index: idx, newLabel: label)
            },
            onFontSizeChange: { key, size in
                store.chartStyleOverrides[key] = "\(Int(size))"
                store.rerenderForStyleChange()
            },
            onStyleOverrideChange: { key, value in
                store.chartStyleOverrides[key] = value
                store.rerenderForStyleChange()
            },
            chartStyleOverrides: store.chartStyleOverrides,
            relatedCharts: store.relatedCharts,
            libraryRootURL: store.libraryRootURL
        )
    }
}

// MARK: - Vault row (shared by Load popover)

private struct WorkbenchVaultRow<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState
    let pack: AnalysisPack
    @Binding var editingPackID: UUID?
    let workflowID: String
    let store: Store
    var onLoad: ((AnalysisPack.ID) -> Void)? = nil

    @State private var editingLabel = ""
    private var isEditing: Bool { editingPackID == pack.id }

    var body: some View {
        let vault = appState.workbench.analysisVault
        let isActive = store.activePackID == pack.id

        HStack(spacing: 6) {
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.body)
            }

            if isEditing {
                TextField("Label", text: $editingLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit { _commitRename(vault: vault) }
            } else {
                Text(pack.label)
                    .font(.body)
                    .lineLimit(1)
            }

            Spacer()

            if !isEditing {
                Button { editingLabel = pack.label; editingPackID = pack.id } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .accessibilityLabel("Rename pack")

                Button {
                    vault.remove(id: pack.id)
                    if store.activePackID == pack.id {
                        store.activePackID = nil
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityLabel("Delete pack")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isActive ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing else { return }
            onLoad?(pack.id)
        }
    }

    private func _commitRename(vault: AnalysisVault) {
        let trimmed = editingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, var updated = vault.get(id: pack.id) {
            updated.label = trimmed
            vault.update(updated)
        }
        editingPackID = nil
    }
}

// MARK: - Unified Load Pack popover

private struct WorkbenchLoadPackPopover<Store: WorkbenchWorkspaceProviding>: View {
    @Environment(SpinLabAppState.self) private var appState
    let workflowID: String
    let store: Store
    @State private var showPopover = false
    @State private var showUnsavedAlert = false
    @State private var pendingLoadID: UUID?
    @State private var editingPackID: UUID?
    @State private var filterText = ""

    var body: some View {
        let vault = appState.workbench.analysisVault
        let allPacks = vault.packs(forWorkflow: workflowID)
        let packs = filterText.isEmpty ? allPacks : allPacks.filter {
            $0.label.localizedCaseInsensitiveContains(filterText)
        }

        Button("Load") {
            showPopover.toggle()
        }
        .buttonStyle(.bordered)
        .disabled(allPacks.isEmpty)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Analyses")
                    .font(.body.bold())
                    .foregroundStyle(.secondary)

                if allPacks.count > 3 {
                    TextField("Filter…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                }

                if packs.isEmpty {
                    Text(filterText.isEmpty ? "No saved analyses." : "No match.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(packs) { pack in
                                WorkbenchVaultRow(
                                    pack: pack,
                                    editingPackID: $editingPackID,
                                    workflowID: workflowID,
                                    store: store,
                                    onLoad: { id in
                                        if store.hasUnsavedAnalysis {
                                            pendingLoadID = id
                                            showPopover = false
                                            showUnsavedAlert = true
                                        } else {
                                            _load(id)
                                            showPopover = false
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
            .padding(12)
            .frame(width: 300)
            .onTapGesture { editingPackID = nil }
        }
        .alert("Unsaved Analysis", isPresented: $showUnsavedAlert) {
            Button("Discard & Load", role: .destructive) {
                if let id = pendingLoadID {
                    _load(id)
                }
                pendingLoadID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLoadID = nil
            }
        } message: {
            Text("Current analysis has unsaved changes. Loading will replace it.")
        }
        .onChange(of: showPopover) { _, isOpen in
            if !isOpen { editingPackID = nil; filterText = "" }
        }
    }

    private func _load(_ id: AnalysisPack.ID) {
        let wfID: WorkbenchWorkflowID? = WorkbenchWorkflowID(rawValue: workflowID)
        store.loadPack(id: id) { results, queryText in
            guard let wfID else { return }
            appState.workbench.restoreSearchState(results: results, queryText: queryText, for: wfID)
        }
    }
}

// MARK: - Warning panel

struct WorkbenchWarningPanel: View {
    let entries: [WorkbenchWarningEntry]

    @State private var isExpanded = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        if entries.isEmpty {
            GroupBox {
                Text("No warnings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } label: {
                Label("Warnings (0)", systemImage: "checkmark.circle")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.timeFormatter.string(from: entry.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            Text("[\(entry.source)]")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                            Text(entry.message)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Label("Warnings (\(entries.count))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            .groupBoxStyle(.automatic)
            .padding(.vertical, 4)
        }
    }
}
