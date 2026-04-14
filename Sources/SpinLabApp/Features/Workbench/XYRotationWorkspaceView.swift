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
                    XYRotationVaultButton()
                        .environment(appState)
                    Spacer()
                }
                .padding(.top, 4)

                XYRotationSearchSection()
                    .environment(appState)

                XYRotationPlotControlsPanel()
                    .environment(appState)

                XYRotationPhiOffsetPanel()
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
                    store.runAnalysis()
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedSearchResultIDs.isEmpty || store.isAnalyzing)

                Button("Clear") {
                    store.clearAll()
                    workbench.clearWorkflowMeasurementSearch(workflowID: wf)
                }
                .buttonStyle(.bordered)

                XYRotationLoadPackButton()
                    .environment(appState)

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

        WorkbenchStandardPlotControls(
            activeTab: $store.tabs.activeTab,
            tabLabel: { $0.displayName },
            stackOffset: $store.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $store.minGapFraction,
            showGrid: $store.tabs.showPlotGrid,
            titleTemplate: $store.titleTemplate,
            numericDisplayCache: store.cachedSampleNumericDisplay,
            seriesRenderMode: $store.tabs.seriesRenderMode,
            chartStyleOverrides: $store.tabs.chartStyleOverrides,
            onChange: { store.rerenderForStyleChange() }
        ) {
            HStack(spacing: 12) {
                Toggle("Center", isOn: $store.centerBaseline)
                    .toggleStyle(.checkbox)
                    .onChange(of: store.centerBaseline) { _, _ in
                        store.rerenderForStyleChange()
                    }
                Toggle("Detrend", isOn: $store.linearDetrend)
                    .toggleStyle(.checkbox)
                    .onChange(of: store.linearDetrend) { _, _ in
                        store.rerenderForStyleChange()
                    }
                Toggle("x=180", isOn: $store.showAuxiliaryLine180)
                    .toggleStyle(.checkbox)
                    .onChange(of: store.showAuxiliaryLine180) { _, _ in
                        store.rerenderForStyleChange()
                    }
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
                    Text("\(msg)  Numeric tolerance: ±\(Int(NumericUnitMap.relativeTolerance * 100))%")
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Numeric tolerance: ±\(Int(NumericUnitMap.relativeTolerance * 100))% (min ±\(NumericUnitMap.absoluteToleranceFloor, specifier: "%.0f"))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(results) { hit in
                        let isSelected = store.selectedSearchResultIDs.contains(hit.id)
                        WorkflowHitRow(hit: hit, isSelected: isSelected, numericDisplay: store.cachedSampleNumericDisplay[hit.sampleKey] ?? [:]) {
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
                    VStack(alignment: .trailing, spacing: 2) {
                        if store.matchingVaultPack != nil {
                            Button("Update Analysis") {
                                let queryText = appState.workbench.searchQueryText(for: .xyRotation)
                                store.saveAnalysis(searchQueryText: queryText)
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.ingestionResult == nil)
                        } else {
                            Button("Save Analysis") {
                                let queryText = appState.workbench.searchQueryText(for: .xyRotation)
                                store.saveAnalysis(searchQueryText: queryText)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.ingestionResult == nil)
                        }

                        Text(store.matchingVaultPack.map { "→ \($0.label)" } ?? " ")
                            .font(.caption)
                            .foregroundColor(store.matchingVaultPack != nil ? .accentColor : .clear)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Button("Save to Library") {
                            store.persistToLibrary {
                                appState.library.loadWorkbenchResultsForCurrentSelection()
                                appState.library.loadMeasurementDataForCurrentSelection()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.ingestionResult == nil)

                        Text(" ")
                            .font(.caption)
                            .foregroundColor(.clear)
                    }
                }

                WorkbenchStatusArea(
                    searchMessage: nil,
                    plotMessage: store.analysisMessage,
                    loadMessage: nil
                )

                WorkbenchPlotCanvas(
                    imageData: store.tabs.activeImageData,
                    layout: store.tabs.activeLayout,
                    seriesLabelOverrides: store.tabs.activeSeriesLabelOverrides,
                    onLegendDrag: { pt in store.updateLegendPoint(pt) },
                    onEditTitle: { title in store.updatePlotTitle(title) },
                    onEditXLabel: { label in store.updateXAxisLabel(label) },
                    onEditYLabel: { label in store.updateYAxisLabel(label) },
                    onEditLegendLabel: { idx, label in store.updateSeriesLabel(index: idx, newLabel: label) },
                    onFontSizeChange: { key, size in
                        store.tabs.chartStyleOverrides[key] = "\(Int(size))"
                        store.rerenderForStyleChange()
                    },
                    onStyleOverrideChange: { key, value in
                        store.tabs.chartStyleOverrides[key] = value
                        store.rerenderForStyleChange()
                    },
                    chartStyleOverrides: store.tabs.chartStyleOverrides,
                    relatedCharts: store.relatedCharts(for: store.tabs.activeTab),
                    libraryRootURL: store.lastLibraryRootPath.isEmpty
                        ? nil
                        : URL(fileURLWithPath: store.lastLibraryRootPath)
                )

                WorkbenchTracePanel(trace: store.currentRunTrace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }
}

// MARK: - φ Offset Panel

private struct XYRotationPhiOffsetPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.xyRotationWorkspace

        GroupBox("φ Offset (deg)") {
            if let result = store.ingestionResult, !result.sweeps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.sweeps) { sweep in
                        HStack(spacing: 6) {
                            Text(sweep.stem)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            let currentValue = store.phiOffsetOverrides[sweep.id]
                                ?? sweep.defaultPhiOffset

                            TextField(
                                "0",
                                value: Binding(
                                    get: { currentValue },
                                    set: { store.updatePhiOffset(sweepID: sweep.id, offset: $0) }
                                ),
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .monospacedDigit()
                        }
                    }
                }
            } else {
                Text("Run analysis to see per-file offsets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Vault management button (title bar)

private struct XYRotationVaultButton: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var showPopover = false
    @State private var editingPackID: UUID?
    @State private var filterText = ""

    var body: some View {
        let vault = appState.workbench.analysisVault
        let allPacks = vault.packs(forWorkflow: "xy")
        let packs = filterText.isEmpty ? allPacks : allPacks.filter {
            $0.label.localizedCaseInsensitiveContains(filterText)
        }

        Button("Analyses") {
            showPopover.toggle()
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Analyses")
                    .font(.body.bold())
                    .foregroundStyle(.secondary)
                    .onTapGesture { editingPackID = nil }

                if allPacks.count > 3 {
                    TextField("Filter…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }

                if packs.isEmpty {
                    Text(filterText.isEmpty ? "No saved analyses yet." : "No match.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(packs) { pack in
                                XYRotationVaultRow(pack: pack, editingPackID: $editingPackID)
                                    .environment(appState)
                            }
                        }
                    }
                    .frame(minHeight: 60, maxHeight: 300)
                }
            }
            .padding(8)
            .frame(width: 280)
            .contentShape(Rectangle())
            .onTapGesture { editingPackID = nil }
            .onChange(of: showPopover) { _, isOpen in
                if !isOpen { editingPackID = nil; filterText = "" }
            }
        }
    }
}

private struct XYRotationVaultRow: View {
    @Environment(SpinLabAppState.self) private var appState
    let pack: AnalysisPack
    @Binding var editingPackID: UUID?
    @State private var editingLabel: String = ""

    private var isEditing: Bool { editingPackID == pack.id }

    var body: some View {
        let vault = appState.workbench.analysisVault
        let store = appState.workbench.xyRotationWorkspace
        let isActive = store.activePackID == pack.id

        HStack(spacing: 6) {
            if isEditing {
                TextField("Label", text: $editingLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit { _commitRename(vault: vault) }
                    .onExitCommand { _commitRename(vault: vault) }
            } else {
                Text(pack.label)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }

            Spacer()

            Image(systemName: "pencil")
                .font(.body)
                .foregroundStyle(.secondary)
                .onTapGesture {
                    editingLabel = pack.label
                    editingPackID = pack.id
                }

            Image(systemName: "trash")
                .font(.body)
                .foregroundStyle(.red.opacity(0.7))
                .onTapGesture {
                    vault.remove(id: pack.id)
                    if store.activePackID == pack.id {
                        store.activePackID = nil
                    }
                }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        )
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

// MARK: - Load pack button (search section)

private struct XYRotationLoadPackButton: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var showPopover = false
    @State private var showUnsavedAlert = false
    @State private var pendingLoadID: UUID?
    @State private var filterText = ""

    var body: some View {
        let vault = appState.workbench.analysisVault
        let store = appState.workbench.xyRotationWorkspace
        let allPacks = vault.packs(forWorkflow: "xy")
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
                Text("Load Analysis")
                    .font(.body.bold())
                    .foregroundStyle(.secondary)

                if allPacks.count > 3 {
                    TextField("Filter…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }

                if packs.isEmpty {
                    Text(filterText.isEmpty ? "No saved analyses." : "No match.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(packs) { pack in
                            Button {
                                if store.hasUnsavedAnalysis {
                                    pendingLoadID = pack.id
                                    showPopover = false
                                    showUnsavedAlert = true
                                } else {
                                    _load(pack.id)
                                    showPopover = false
                                }
                            } label: {
                                HStack {
                                    Text(pack.label)
                                        .font(.body)
                                        .lineLimit(1)
                                    Spacer()
                                    if store.activePackID == pack.id {
                                        Image(systemName: "checkmark")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: 300)
                }
            }
            .padding(8)
            .frame(width: 280)
            .onChange(of: showPopover) { _, isOpen in
                if !isOpen { filterText = "" }
            }
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
    }

    private func _load(_ id: UUID) {
        let store = appState.workbench.xyRotationWorkspace
        let workbench = appState.workbench
        store.loadPack(id: id) { results, queryText in
            workbench.restoreXYRotationSearchState(results: results, queryText: queryText)
        }
    }
}
