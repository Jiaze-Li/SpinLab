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

// MARK: - Plot Controls Panel (3ω-specific: RAHE method + overlays)

private struct ThreeOmegaPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.threeOmegaWorkspace
        @Bindable var workbench = appState.workbench

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
                onRenameSeriesLabel: { key, label in store.updateSeriesLabel(identityKey: key, newLabel: label) },
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
                } : nil
            ) {
                // Row 3: RAHE method picker + Add Analysis (visible on RAHE tabs only)
                if store.tabs.activeTab == .rahe1omegaVsT || store.tabs.activeTab == .rahe3omegaVsT
                    || store.tabs.activeTab == .rahe1omegaVsDevice || store.tabs.activeTab == .rahe3omegaVsDevice {
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

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Fit Ranges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            ForEach($store.fitRanges) { $range in
                                HStack(spacing: 4) {
                                    FitRangeBoundField(placeholder: "T_lo (K)", value: $range.tLo)
                                    Text("–")
                                    FitRangeBoundField(placeholder: "T_hi (K)", value: $range.tHi)
                                    if store.fitRanges.count > 1 {
                                        Button {
                                            store.fitRanges.removeAll { $0.id == range.id }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            Button {
                                store.fitRanges.append(ThreeOmegaFitRange())
                            } label: {
                                Label("Add", systemImage: "plus.circle")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .onChange(of: store.geometry) { _, _ in
                store.refreshTransportDerivedPlots(reason: "geometry changed")
            }
            .onChange(of: store.v3Method) { _, _ in
                store.refreshTransportDerivedPlots(reason: "V3 method changed")
            }
            .onChange(of: store.fitRanges) { _, _ in
                store.refreshTransportDerivedPlots(reason: "fit ranges changed")
            }
        }
    }
}
