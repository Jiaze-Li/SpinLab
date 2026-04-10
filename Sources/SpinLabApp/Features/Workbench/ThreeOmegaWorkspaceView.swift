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
                    ThreeOmegaVaultButton()
                        .environment(appState)
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
            HStack(alignment: .top, spacing: 12) {
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

                ThreeOmegaLoadPackButton()
                    .environment(appState)

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

        WorkbenchStandardPlotControls(
            activeTab: $store.activeTab,
            tabLabel: { $0.rawValue },
            stackOffset: $store.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $store.minGapFraction,
            showGrid: $store.showPlotGrid,
            titleTemplate: $store.titleTemplate,
            numericDisplayCache: store.cachedSampleNumericDisplay,
            onChange: {
                store.rerenderForStyleChange()
                appState.flushInteractionSnapshotNow()
            }
        ) {
            // Row 3: RAHE method picker + Add Analysis (visible on RAHE tabs only)
            if store.activeTab == .rahe1omegaVsT || store.activeTab == .rahe3omegaVsT {
                HStack {
                    Picker("AHE Method", selection: Binding<ThreeOmegaV3Method>(
                        get: { store.activeRAHEMethod ?? .highField },
                        set: { store.updateRAHEMethod($0) }
                    )) {
                        ForEach(ThreeOmegaV3Method.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    Spacer()

                    ThreeOmegaAddOverlayButton()
                        .environment(appState)
                }

                // Active overlays (capsule chips)
                if !store.overlayPackIDs.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(store.overlayPackIDs, id: \.self) { oid in
                            if let snap = store.overlaySnapshots[oid] {
                                HStack(spacing: 6) {
                                    Text(snap.label)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Button {
                                        store.removeOverlay(id: oid)
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                    }
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
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        (Text("L").font(.body)
                         + Text("xx").font(.system(size: 9)).baselineOffset(-3)
                         + Text(" (μm)").font(.body))
                        TextField("26", value: $store.geometry.lxx, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                    }
                    HStack(spacing: 4) {
                        (Text("L").font(.body)
                         + Text("xy").font(.system(size: 9)).baselineOffset(-3)
                         + Text(" (μm)").font(.body))
                        TextField("21", value: $store.geometry.lxy, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                    }
                    HStack(spacing: 4) {
                        Text("d (nm)").font(.body)
                        TextField("30", value: $store.geometry.dNm, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                    }
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
            .onChange(of: store.v3Method) { _, _ in
                appState.flushInteractionSnapshotNow()
            }
            .onChange(of: store.fitRanges) { _, _ in
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
                    VStack(alignment: .trailing, spacing: 2) {
                        if store.matchingVaultPack != nil {
                            Button("Update Analysis") {
                                let queryText = appState.workbench.searchQueryText(for: .threeOmega)
                                store.saveAnalysis(searchQueryText: queryText)
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.ingestionResult == nil)
                        } else {
                            Button("Save Analysis") {
                                let queryText = appState.workbench.searchQueryText(for: .threeOmega)
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

                if let msg = store.analysisMessage, !msg.isEmpty {
                    let warnCount = store.ingestionResult?.warnings.count ?? 0
                    if warnCount > 0 {
                        (Text(msg).foregroundStyle(.secondary)
                         + Text(" (\(warnCount) warning(s))").foregroundStyle(.orange))
                            .font(.footnote)
                    } else {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }


                WorkbenchPlotCanvas(
                    imageData: _activeImageData(store),
                    layout: store.plotLayouts[store.activeTab],
                    seriesLabelOverrides: store.plotSeriesLabelOverrides[store.activeTab] ?? [:],
                    onLegendDrag: { pt in
                        store.updateLegendPoint(pt)
                        appState.flushInteractionSnapshotNow()
                    },
                    onEditTitle:  { title in store.updatePlotTitle(title) },
                    onEditXLabel: { label in store.updateXAxisLabel(label) },
                    onEditYLabel: { label in store.updateYAxisLabel(label) },
                    onEditLegendLabel: { idx, label in
                        store.updateSeriesLabel(index: idx, newLabel: label)
                    },
                    relatedCharts: store.relatedCharts(for: store.activeTab),
                    libraryRootURL: store.lastLibraryRootPath.isEmpty
                        ? nil
                        : URL(fileURLWithPath: store.lastLibraryRootPath)
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
        case .rahe1omegaVsT:    return store.plotRAHE1omegaVsT
        case .rahe3omegaVsT:    return store.plotRAHE3omegaVsT
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

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("RT file…", text: $store.rtQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit {
                        store.clearRTSelection()
                        appState.workbench.runThreeOmegaRTSearch(libraryRootPath: libraryRoot)
                    }
                    .popover(isPresented: $store.showRTPopover, arrowEdge: .bottom) {
                        ThreeOmegaRTPopover()
                            .environment(appState)
                    }

                Button {
                    store.clearRTSelection()
                    appState.workbench.runThreeOmegaRTSearch(libraryRootPath: libraryRoot)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.rtQuery.trimmingCharacters(in: .whitespaces).isEmpty || store.isRTSearching || libraryRoot == nil)
            }

            if let hit = store.selectedRTHit {
                let fullName = hit.measurementFilePath.components(separatedBy: "/").last ?? hit.id
                Text("✓ \(fullName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fullName)
            }
        }
        .frame(width: 170, alignment: .leading)
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
                                appState.flushInteractionSnapshotNow()
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

// MARK: - Vault management button (title bar)

private struct ThreeOmegaVaultButton: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var showPopover = false
    @State private var editingPackID: UUID?
    @State private var filterText = ""

    var body: some View {
        let vault = appState.workbench.analysisVault
        let allPacks = vault.packs(forWorkflow: "3w")
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
                                ThreeOmegaVaultRow(pack: pack, editingPackID: $editingPackID)
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

private struct ThreeOmegaVaultRow: View {
    @Environment(SpinLabAppState.self) private var appState
    let pack: AnalysisPack
    @Binding var editingPackID: UUID?
    @State private var editingLabel: String = ""

    private var isEditing: Bool { editingPackID == pack.id }

    var body: some View {
        let vault = appState.workbench.analysisVault
        let store = appState.workbench.threeOmegaWorkspace
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

private struct ThreeOmegaLoadPackButton: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var showPopover = false
    @State private var showUnsavedAlert = false
    @State private var pendingLoadID: UUID?
    @State private var filterText = ""

    var body: some View {
        let vault = appState.workbench.analysisVault
        let store = appState.workbench.threeOmegaWorkspace
        let allPacks = vault.packs(forWorkflow: "3w")
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
        let store = appState.workbench.threeOmegaWorkspace
        let workbench = appState.workbench
        store.loadPack(id: id) { results, queryText in
            workbench.restoreThreeOmegaSearchState(results: results, queryText: queryText)
        }
    }
}

// MARK: - Add overlay button (RAHE tabs)

private struct ThreeOmegaAddOverlayButton: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var showPopover = false

    var body: some View {
        let vault = appState.workbench.analysisVault
        let store = appState.workbench.threeOmegaWorkspace
        let excludeIDs: Set<UUID> = Set(store.overlayPackIDs).union(store.activePackID.map { [$0] } ?? [])
        let available = vault.packs(forWorkflow: "3w").filter { !excludeIDs.contains($0.id) }

        Button("Add Analysis") {
            showPopover.toggle()
        }
        .buttonStyle(.bordered)
        .disabled(available.isEmpty)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Overlay Analysis")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(available) { pack in
                            Button {
                                store.addOverlay(id: pack.id)
                                showPopover = false
                            } label: {
                                Text(pack.label)
                                    .font(.caption)
                                    .lineLimit(1)
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
                .frame(minHeight: 40, maxHeight: 200)
            }
            .padding(8)
            .frame(width: 240)
        }
    }
}
