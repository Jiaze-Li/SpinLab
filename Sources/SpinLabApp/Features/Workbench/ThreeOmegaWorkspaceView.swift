import SwiftUI

/// 3ω workflow workspace — shell-based layout.
struct ThreeOmegaWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

        WorkflowWorkspaceShell(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            searchExtra: {
                ThreeOmegaRTSearchField()
                    .environment(appState)
            },
            plotControls: {
                ThreeOmegaPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: {
                if store.tabs.activeTab == .scaling || store.tabs.activeTab == .temperatureDependence {
                    ThreeOmegaGeometryPanel()
                        .environment(appState)
                }
            },
            rightExtra: {
                if store.tabs.activeTab == .scaling {
                    VStack(alignment: .leading, spacing: 12) {
                        ThreeOmegaTransportStatusPanel()
                            .environment(appState)
                        if let sr = store.scalingResult {
                            ThreeOmegaScalingResultPanel(result: sr)
                        }
                    }
                }
            }
        )
    }
}

// MARK: - Workspace-level tab / navigation strip (all 3ω tabs)

/// Tab picker + stack offset + gap — workspace-level controls shared by all 3ω plot modes.
/// Rendered above the plot-type-specific controls regardless of which tab is active.
private struct ThreeOmegaWorkspaceTabStrip: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        HStack(spacing: 8) {
            Picker("Tab", selection: $store.tabs.activeTab) {
                ForEach(ThreeOmegaWorkbenchTab.visibleTabs) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
            .onChange(of: store.tabs.activeTab) { _, _ in
                store.rerenderForStyleChange()
                appState.flushInteractionSnapshotNow()
            }

            Slider(value: $store.stackOffsetMultiplier, in: 0...1.6, step: 0.1)
                .onChange(of: store.stackOffsetMultiplier) { _, _ in
                    store.rerenderForStyleChange()
                    appState.flushInteractionSnapshotNow()
                }
            Text(String(format: "%.1f×", store.stackOffsetMultiplier))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Text("Gap")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            TextField("0.15", value: $store.minGapFraction, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .font(.system(size: 12))
                .onSubmit {
                    store.rerenderForStyleChange()
                    appState.flushInteractionSnapshotNow()
                }
        }
    }
}

// MARK: - Plot Controls Panel (3ω-specific: RAHE method + overlays)

private struct ThreeOmegaPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace
        @Bindable var workbench = appState.workbench

        VStack(alignment: .leading, spacing: 0) {
            // Workspace-level strip: always visible regardless of active plot mode
            ThreeOmegaWorkspaceTabStrip()
                .environment(appState)

            if store.tabs.activeTab == .temperatureDependence {
                DualAxisPlotControlsPanel(
                    displayState: $store.temperatureDependenceDisplayState,
                    activeLayout: store.tabs.output(for: .temperatureDependence).dualAxisLayout,
                    sourceResetToken: store.tabs.activeSourceIdentityKey,
                    onDisplayStateChange: {
                        store.rerenderTemperatureDependenceForDualAxisControlChange()
                        appState.flushInteractionSnapshotNow()
                    }
                )
            } else {
                WorkbenchStandardPlotControls(
                    activeTab: $store.tabs.activeTab,
                    tabLabel: { $0.rawValue },
                    stackOffset: $store.stackOffsetMultiplier,
                    stackRange: 0...1.6,
                    minGapFraction: $store.minGapFraction,
                    showGrid: $store.tabs.showPlotGrid,
                    titleTemplate: $store.titleTemplate,
                    numericDisplayCache: store.cachedSampleNumericDisplay,
                    seriesRenderMode: $store.tabs.seriesRenderMode,
                    globalPlotDefaults: $workbench.globalPlotDefaults,
                    chartStyleOverrides: $store.tabs.chartStyleOverrides,
                    seriesOrderPayload: store.activeChartManifestPayload,
                    seriesControlModel: store.tabs.activeOutput.seriesControlModel,
                    currentSeriesOrder: store.activeSeriesOrder,
                    canReorderSeries: store.canReorderSeries,
                    onSeriesOrderCommit: { order in store.updateSeriesOrder(order) },
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.flushInteractionSnapshotNow()
                    },
                    activeTitleOverride: store.tabs.activeState.titleOverride,
                    activeXLabelOverride: store.tabs.activeState.xLabelOverride,
                    activeYLabelOverride: store.tabs.activeState.yLabelOverride,
                    renderedTitle: store.tabs.activeLayout?.chartTitle ?? "",
                    renderedXLabel: store.tabs.activeLayout?.xAxisLabel ?? "",
                    renderedYLabel: store.tabs.activeLayout?.yAxisLabel ?? "",
                    sourceResetToken: store.tabs.activeSourceIdentityKey,
                    onTitleOverride: { store.updatePlotTitle($0) },
                    onXLabelOverride: { store.updateXAxisLabel($0) },
                    onYLabelOverride: { store.updateYAxisLabel($0) },
                    activeSeriesLabelOverrides: store.seriesLabelOverrides,
                    activeSeriesHiddenKeys: store.tabs.activeState.hiddenSeriesKeys,
                    onRenameSeriesLabel: { key, label in store.updateSeriesLabel(identityKey: key, newLabel: label) },
                    onVisibilityChange: { key, isVisible in store.updateSeriesVisibility(identityKey: key, isVisible: isVisible) },
                    activeLayout: store.tabs.activeLayout,
                    axisRangeOverride: store.tabs.activeState.axisRangeOverride,
                    onAxisBoundUpdate: { bound, value in
                        AxisRangeDebug.log("ThreeOmegaWorkspaceView onAxisBoundUpdate BEFORE updateAxisBound bound=\(bound) value=\(value.map { String(format: "%g", $0) } ?? "nil") | axisRangeOverride=\(String(describing: store.tabs.activeState.axisRangeOverride))")
                        store.tabs.updateAxisBound(bound, value: value)
                        AxisRangeDebug.log("ThreeOmegaWorkspaceView onAxisBoundUpdate AFTER updateAxisBound | axisRangeOverride=\(String(describing: store.tabs.activeState.axisRangeOverride))")
                        AxisRangeDebug.log("ThreeOmegaWorkspaceView onAxisBoundUpdate BEFORE rerenderForStyleChange")
                        store.rerenderForStyleChange()
                        AxisRangeDebug.log("ThreeOmegaWorkspaceView onAxisBoundUpdate AFTER rerenderForStyleChange")
                        appState.flushInteractionSnapshotNow()
                    },
                    showPointTagsForActiveTab: store.tabs.activeState.showPointTags,
                    onPointTagsToggle: (store.tabs.activeTab == .rahe1omegaVsDevice || store.tabs.activeTab == .rahe3omegaVsDevice) ? { show in
                        store.tabs.setShowPointTags(show)
                        store.rerenderForStyleChange()
                        appState.flushInteractionSnapshotNow()
                    } : nil,
                    hideTabRow: true
                ) {
                    // Extra: RAHE method picker for the device-angle tabs.
                    if store.tabs.activeTab == .rahe1omegaVsDevice || store.tabs.activeTab == .rahe3omegaVsDevice {
                        HStack {
                            Picker("RAHE Method", selection: Binding<ThreeOmegaV3Method>(
                                get: { store.activeRAHEMethod ?? .highField },
                                set: { store.updateRAHEMethod($0) }
                            )) {
                                ForEach(ThreeOmegaV3Method.allCases) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 220)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Geometry Panel (Scaling tab only)

private struct ThreeOmegaGeometryPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace

        let geometryFieldsRow = HStack(spacing: 16) {
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

        let v3MethodRow = Picker("V(3ω)", selection: $store.v3Method) {
            ForEach(ThreeOmegaV3Method.allCases) { method in
                Text(method.geometryDisplayLabel).tag(method)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150, alignment: .leading)
        .help(store.v3Method.rawValue)
        .accessibilityLabel("V(3ω) method \(store.v3Method.rawValue)")

        let geometryRow = HStack(alignment: .firstTextBaseline, spacing: 14) {
            geometryFieldsRow
            v3MethodRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        GroupBox("Transport Geometry") {
            VStack(alignment: .leading, spacing: 8) {
                geometryRow

                Divider()

                HStack(alignment: .center, spacing: 10) {
                    Text("Fit Ranges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
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
                                    .accessibilityLabel("Remove fit range")
                                    .disabled(store.fitRanges.count <= 1)
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        store.addFitRange()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add fit range")
                }
            }
            .padding(.vertical, 4)
            .onChange(of: store.geometry) { _, _ in
                store.refreshTransportDerivedPlots(reason: "geometry changed")
                appState.flushInteractionSnapshotNow()
            }
            .onChange(of: store.v3Method) { _, _ in
                store.refreshTransportDerivedPlots(reason: "v3Method changed")
                appState.flushInteractionSnapshotNow()
            }
            .onChange(of: store.fitRanges) { _, _ in
                store.refreshTransportDerivedPlots(reason: "fit ranges changed")
                appState.flushInteractionSnapshotNow()
            }
        }
    }
}

private extension ThreeOmegaV3Method {
    var geometryDisplayLabel: String {
        switch self {
        case .highField:
            return "HFE"
        case .window:
            return "WA"
        }
    }
}

private struct ThreeOmegaTransportStatusPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace

        GroupBox("Scaling Status") {
            VStack(alignment: .leading, spacing: 6) {
                switch store.transportDerivedStatus {
                case .idle:
                    Text("Scaling Law waits for Analyze.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .refreshing:
                    Text("Updating Scaling Law…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .missing(let requirements):
                    Text("Scaling Law unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Missing: \(requirements.map(\.rawValue).joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.orange)
                case .ready:
                    Text("Scaling Law is up to date.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .unavailable(let message):
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

/// Text field for an optional Double temperature bound.
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

// MARK: - Scaling result panel

private struct ThreeOmegaScalingResultPanel: View {
    let result: ThreeOmegaScalingResult

    var body: some View {
        GroupBox("Scaling Law Fit Results") {
            VStack(alignment: .leading, spacing: 6) {
                if result.isSingleFullRange(), let seg = result.segments.first {
                    Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "R² = %.4f", seg.rSquared))
                        .font(.system(.body, design: .monospaced))
                    Text("\(result.points.count) data point(s)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(result.segments.enumerated()), id: \.element.id) { idx, seg in
                        if idx > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(seg.tLo.rounded())) K – \(Int(seg.tHi.rounded())) K  (n=\(seg.pointCount))")
                                .font(.callout.bold())
                                .foregroundStyle(.secondary)
                            Text(String(format: "β (Q_xxz) = %.4e Ω·μm³·V⁻²", seg.beta * 1e20))
                                .font(.system(.callout, design: .monospaced))
                            Text(String(format: "α (skew) = %.4e Ω·μm³·cm²·V⁻²·S⁻²", seg.alpha * 1e31))
                                .font(.system(.callout, design: .monospaced))
                            Text(String(format: "R² = %.4f", seg.rSquared))
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                ForEach(result.warnings, id: \.self) { w in
                    Text("⚠ \(w)")
                        .font(.callout)
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
                TextField("RT file…", text: Binding(
                    get: { store.rtQuery },
                    set: { store.updateRTQuery($0) }
                ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit {
                        store.clearRTSelection()
                        appState.workbench.runThreeOmegaRTSearch(
                            libraryRootPath: libraryRoot,
                            librarySettings: appState.library.librarySettings
                        )
                    }
                    .popover(isPresented: $store.showRTPopover, arrowEdge: .bottom) {
                        ThreeOmegaRTPopover()
                            .environment(appState)
                    }

                Button {
                    store.clearRTSelection()
                    appState.workbench.runThreeOmegaRTSearch(
                        libraryRootPath: libraryRoot,
                        librarySettings: appState.library.librarySettings
                    )
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Search RT files")
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
