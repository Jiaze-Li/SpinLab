import SwiftUI

/// 3ω workflow workspace — shell-based layout.
struct ThreeOmegaWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.threeOmegaWorkspace
        @Bindable var bindableStore = appState.workbench.threeOmegaWorkspace

        WorkflowWorkspaceShell(
            workflowID: .threeOmega,
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
                if store.tabs.activeTab == .scaling {
                    ThreeOmegaGeometryPanel()
                        .environment(appState)
                }
            },
            rightExtra: {
                if store.tabs.activeTab == .scaling, let sr = store.scalingResult {
                    ThreeOmegaScalingResultPanel(result: sr)
                }
            }
        )
    }
}

// MARK: - Plot Controls Panel (3ω-specific: RAHE method + overlays)

private struct ThreeOmegaPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace
        @Bindable var workbench = appState.workbench

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
            onRenameSeriesLabel: { key, label in store.updateSeriesLabel(sampleID: key, newLabel: label) }
        ) {
            // Row 3: RAHE method picker + Add Analysis (visible on RAHE tabs only)
            if store.tabs.activeTab == .rahe1omegaVsT || store.tabs.activeTab == .rahe3omegaVsT {
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

                // Active overlays (capsule chips) — read from common overlay runtime.
                let overlayRuntime = appState.workbench.overlayRuntime
                if !overlayRuntime.overlayIDs.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(overlayRuntime.overlayIDs, id: \.self) { oid in
                            if let label = overlayRuntime.displayLabels[oid] {
                                HStack(spacing: 6) {
                                    Text(label)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Button {
                                        store.removeOverlay(id: oid)
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove overlay")
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

// MARK: - Geometry Panel (Scaling tab only)

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
                    .accessibilityLabel("Add fit range")
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
                        .accessibilityLabel("Remove fit range")
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

// MARK: - Add overlay button (RAHE tabs)

private struct ThreeOmegaAddOverlayButton: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var showPopover = false

    var body: some View {
        let vault = appState.workbench.analysisVault
        let store = appState.workbench.threeOmegaWorkspace
        let available = store.availableOverlayPacks(in: vault)

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
