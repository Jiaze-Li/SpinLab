import SwiftUI

/// 3w workflow workspace.
///
/// 列结构与 AHEWorkspaceView 对齐：
///   左列 → 搜索 + PlotControlsPanel + GeometryPanel (Fig 5b) + ResultsList
///   右列 → "Result" + WorkbenchStatusArea + WorkbenchPlotCanvas (交互) + ScalingResultPanel
struct ThreeOmegaWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell {
            ThreeOmegaLeftColumn()
                .environment(appState)
        } rightColumn: {
            ThreeOmegaRightColumn()
                .environment(appState)
        }
    }
}

// MARK: - 左列

private struct ThreeOmegaLeftColumn: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 固定控制区 ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .firstTextBaseline) {
                    Text("3w")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.top, 4)

                ThreeOmegaSearchSection()
                    .environment(appState)

                ThreeOmegaPlotControlsPanel()
                    .environment(appState)

                // Geometry panel 只在 Fig 5b tab 时显示
                if appState.workbench.threeOmegaWorkspace.activeTab == .scaling {
                    ThreeOmegaGeometryPanel()
                        .environment(appState)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // ── 可滚动结果列表 ──────────────────────────────────────
            ThreeOmegaResultsList()
                .environment(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 搜索 + 操作按钮

private struct ThreeOmegaSearchSection: View {
    @Environment(SpinLabAppState.self) private var appState
    private let wf: WorkbenchWorkflowID = .threeOmega

    var body: some View {
        @Bindable var workbench = appState.workbench
        let store = appState.workbench.threeOmegaWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        let queryBinding = Binding<String>(
            get: { workbench.searchQueryText(for: wf) },
            set: { workbench.setSearchQueryText($0, for: wf) }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("3w PN69, 3w 5K …", text: queryBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        workbench.runWorkflowMeasurementSearch(workflowID: wf, libraryRootPath: libraryRoot)
                    }

                ThreeOmegaRTSearchField()
                    .environment(appState)
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

                Button(store.isAllSelected ? "Deselect All" : "Select All") {
                    if store.isAllSelected {
                        store.deselectAll()
                    } else {
                        store.selectAll()
                    }
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

                if workbench.isSearchRunning(for: wf) || store.isAnalyzing {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Plot Controls Panel

private struct ThreeOmegaPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        WorkbenchPlotControlsPanel {
            // Tab 选择 + Grid
            HStack(spacing: 8) {
                Picker("Tab", selection: $store.activeTab) {
                    ForEach(ThreeOmegaWorkbenchTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Toggle("Grid", isOn: $store.showPlotGrid)
                    .toggleStyle(.checkbox)
                    .onChange(of: store.showPlotGrid) { _, _ in
                        store.rerenderForStyleChange()
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Stack Offset").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Slider(value: $store.stackOffsetMultiplier, in: 0...1.6, step: 0.1)
                        .onChange(of: store.stackOffsetMultiplier) { _, _ in
                            store.rerenderFieldSweepTabs()
                        }
                    Text(String(format: "%.1f×", store.stackOffsetMultiplier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Geometry Panel (Fig 5b only)

private struct ThreeOmegaGeometryPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        GroupBox("Geometry (for Scaling Law)") {
            VStack(alignment: .leading, spacing: 8) {

                // ── Geometry dimensions (single row) ─────────────────
                HStack(spacing: 8) {
                    (Text("L").font(.body)
                     + Text("xx").font(.system(size: 9)).baselineOffset(-3)
                     + Text(" (μm)").font(.body))
                    TextField("26", value: $store.geometry.lxx, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                    (Text("L").font(.body)
                     + Text("xy").font(.system(size: 9)).baselineOffset(-3)
                     + Text(" (μm)").font(.body))
                    TextField("21", value: $store.geometry.lxy, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                    Text("d (nm)").font(.body)
                    TextField("30", value: $store.geometry.dNm, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                }

                // ── V(3ω) method + Run Scaling (same row) ───────────
                HStack {
                    Picker("V(3ω)", selection: $store.v3Method) {
                        ForEach(ThreeOmegaV3Method.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    Spacer()
                    Button("Run Scaling") {
                        store.runScaling()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.geometry.isComplete || store.ingestionResult == nil)
                }

                Divider()

                // ── Fit Ranges ────────────────────────────────────────
                HStack {
                    Text("Fit Ranges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.addFitRange()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                ForEach($store.fitRanges) { $range in
                    HStack(spacing: 4) {
                        FitRangeBoundField(placeholder: "T_lo (K)", value: $range.tLo)
                        Text("–")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FitRangeBoundField(placeholder: "T_hi (K)", value: $range.tHi)
                        Button {
                            store.removeFitRange(id: range.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.fitRanges.count <= 1)
                    }
                }
            }
            .padding(.vertical, 4)
            .onChange(of: store.geometry) { _, _ in
                appState.flushInteractionSnapshotNow()
            }
        }
    }
}

/// Text field for an optional Double temperature bound.
/// Empty field = nil (use data boundary). Accepts integer or decimal input.
private struct FitRangeBoundField: View {
    let placeholder: String
    @Binding var value: Double?

    @State private var text: String = ""
    @State private var didAppear = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 68)
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                text = value.map { String(Int($0.rounded())) } ?? ""
            }
            .onChange(of: text) { _, newVal in
                let trimmed = newVal.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    value = nil
                } else if let d = Double(trimmed) {
                    value = d
                }
            }
    }
}

// MARK: - Results list

private struct ThreeOmegaResultsList: View {
    @Environment(SpinLabAppState.self) private var appState
    private let wf: WorkbenchWorkflowID = .threeOmega

    var body: some View {
        let workbench = appState.workbench
        let store = workbench.threeOmegaWorkspace
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
                    description: Text("Run a search to find 3w measurements.")
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

private struct ThreeOmegaRightColumn: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

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

                if let warnings = store.ingestionResult?.warnings, !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(warnings, id: \.self) { w in
                            Text("⚠ \(w)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .textSelection(.enabled)
                }

                WorkbenchPlotCanvas(
                    imageData: _activeImageData(store),
                    layout: store.plotLayouts[store.activeTab],
                    seriesLabelOverrides: store.plotSeriesLabelOverrides[store.activeTab] ?? [:],
                    onLegendDrag: { pt in store.updateLegendPoint(pt) },
                    onEditTitle:  { title in store.updatePlotTitle(title) },
                    onEditXLabel: { label in store.updateXAxisLabel(label) },
                    onEditYLabel: { label in store.updateYAxisLabel(label) },
                    onEditLegendLabel: { idx, label in
                        store.updateSeriesLabel(index: idx, newLabel: label)
                    }
                )

                // Scaling Law fit results (only on scaling tab)
                if store.activeTab == .scaling, let sr = store.scalingResult {
                    ThreeOmegaScalingResultPanel(result: sr)
                }

                WorkbenchTracePanel(trace: store.currentRunTrace)

                ThreeOmegaWarningLogPanel(entries: store.warningLog)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    private func _activeImageData(_ store: ThreeOmegaWorkspaceStore) -> Data? {
        switch store.activeTab {
        case .fieldSweep1omega: return store.plotR1omega
        case .fieldSweep3omega: return store.plotR3omega
        case .raheVsT:          return store.plotRAHEvsT
        case .hcVsT:            return store.plotHcvsT
        case .rtCurve:          return store.plotRT
        case .scaling:          return store.plotScaling
        }
    }
}

// MARK: - Warning log panel

private struct ThreeOmegaWarningLogPanel: View {
    let entries: [ThreeOmegaWarningEntry]

    @State private var isExpanded = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        if !entries.isEmpty {
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

// MARK: - Scaling result panel

private struct ThreeOmegaScalingResultPanel: View {
    let result: ThreeOmegaScalingResult

    var body: some View {
        GroupBox("Scaling Law Fit Results") {
            VStack(alignment: .leading, spacing: 6) {
                if result.isSingleFullRange(), let seg = result.segments.first {
                    // Compact format when one segment covers all points (legacy behaviour)
                    Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "R² = %.4f", seg.rSquared))
                        .font(.system(.body, design: .monospaced))
                    Text("\(result.points.count) data point(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Multi-segment format: one block per segment, ascending temperature order
                    ForEach(Array(result.segments.enumerated()), id: \.element.id) { idx, seg in
                        if idx > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(seg.tLo.rounded())) K – \(Int(seg.tHi.rounded())) K  (n=\(seg.pointCount))")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                                .font(.system(.caption, design: .monospaced))
                            Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                                .font(.system(.caption, design: .monospaced))
                            Text(String(format: "R² = %.4f", seg.rSquared))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                ForEach(result.warnings, id: \.self) { w in
                    Text("⚠ \(w)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - RT search field with popover

private struct ThreeOmegaRTSearchField: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        HStack(spacing: 4) {
            TextField("RT file…", text: $store.rtQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .onChange(of: store.rtQuery) { _, newValue in
                    // Clear RT selection only if the user edits the text manually
                    // (not when selectRTHit programmatically sets rtQuery).
                    if let hit = store.selectedRTHit {
                        let hitName = hit.measurementFilePath.components(separatedBy: "/").last ?? hit.id
                        if newValue == hitName { return }
                    }
                    store.clearRTSelection()
                }
                .onSubmit {
                    appState.workbench.runThreeOmegaRTSearch(libraryRootPath: libraryRoot)
                }
                .popover(isPresented: $store.showRTPopover, arrowEdge: .bottom) {
                    ThreeOmegaRTPopover()
                        .environment(appState)
                }

            Button {
                appState.workbench.runThreeOmegaRTSearch(libraryRootPath: libraryRoot)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.rtQuery.trimmingCharacters(in: .whitespaces).isEmpty || store.isRTSearching || libraryRoot == nil)
        }
    }
}

private struct ThreeOmegaRTPopover: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

        VStack(alignment: .leading, spacing: 6) {
            if store.isRTSearching {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Searching…").font(.caption)
                }
            } else if store.rtSearchResults.isEmpty {
                Text(store.rtSearchMessage ?? "No results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(store.rtSearchMessage ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.rtSearchResults) { hit in
                            Button {
                                store.selectRTHit(hit)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.measurementFilePath.components(separatedBy: "/").last ?? hit.id)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(hit.conditionSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
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
                .frame(minHeight: 120, maxHeight: 360)
            }
        }
        .padding(8)
        .frame(width: 320)
    }
}
