import SwiftUI

/// 3ω AHE workflow workspace.
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
                    Text("3ω AHE")
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

    var body: some View {
        @Bindable var workbench = appState.workbench
        let store = appState.workbench.threeOmegaWorkspace
        let libraryRoot = appState.library.librarySettings.rootPath

        VStack(alignment: .leading, spacing: 8) {
            TextField("3ω, PN69, 5K …", text: $workbench.workflowSearchQueryText)
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

                Button("Select All") {
                    store.selectAll()
                }
                .buttonStyle(.bordered)
                .disabled(workbench.workflowSearchResults.isEmpty)

                Button("Analyze") {
                    store.runAnalysis()
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedSearchResultIDs.isEmpty || store.isAnalyzing)

                Button("Clear") {
                    store.clearAll()
                    workbench.clearWorkflowMeasurementSearch()
                }
                .buttonStyle(.bordered)

                if workbench.isWorkflowSearchRunning || store.isAnalyzing {
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
                        store.updateLegendPoint(store.plotLegendPoints[store.activeTab] ?? .zero)
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

                // ── Geometry dimensions ───────────────────────────────
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        (Text("L").font(.body)
                         + Text("xx").font(.system(size: 9)).baselineOffset(-3)
                         + Text(" (μm)").font(.body))
                        .gridColumnAlignment(.trailing)
                        TextField("e.g. 26", value: $store.geometry.lxx, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        (Text("L").font(.body)
                         + Text("xy").font(.system(size: 9)).baselineOffset(-3)
                         + Text(" (μm)").font(.body))
                        .gridColumnAlignment(.trailing)
                        TextField("e.g. 21", value: $store.geometry.lxy, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                    }
                    GridRow {
                        Text("d (nm)").font(.body)
                            .gridColumnAlignment(.trailing)
                        TextField("e.g. 30", value: $store.geometry.dNm, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                        Button("Run Scaling") {
                            store.runScaling()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.geometry.isComplete || store.ingestionResult == nil)
                        .gridCellColumns(2)
                        .gridCellAnchor(.trailing)
                    }
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

    var body: some View {
        let workbench = appState.workbench
        let store = workbench.threeOmegaWorkspace

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
                    description: Text("Run a search to find 3ω AHE measurements.")
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
