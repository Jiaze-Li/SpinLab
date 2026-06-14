import SwiftUI

/// XY Rotation workflow workspace — shell-based layout.
struct XYRotationWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.xyRotationWorkspace
        @Bindable var bindableStore = appState.workbench.xyRotationWorkspace

        WorkflowWorkspaceShell(
            workflowID: .xyRotation,
            store: store,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                WorkbenchStandardPlotControls(
                    activeTab: $bindableStore.tabs.activeTab,
                    tabLabel: { $0.displayName },
                    stackOffset: $bindableStore.stackOffsetMultiplier,
                    stackRange: 0...1.6,
                    minGapFraction: $bindableStore.minGapFraction,
                    showGrid: $bindableStore.tabs.showPlotGrid,
                    titleTemplate: $bindableStore.titleTemplate,
                    numericDisplayCache: store.cachedSampleNumericDisplay,
                    seriesRenderMode: $bindableStore.tabs.seriesRenderMode,
                    chartStyleOverrides: $bindableStore.tabs.chartStyleOverrides,
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
                    HStack(spacing: 12) {
                        Toggle("Center", isOn: $bindableStore.centerBaseline)
                            .toggleStyle(.checkbox)
                            .onChange(of: store.centerBaseline) { _, _ in
                                store.rerenderForStyleChange()
                            }
                        Toggle("Detrend", isOn: $bindableStore.linearDetrend)
                            .toggleStyle(.checkbox)
                            .onChange(of: store.linearDetrend) { _, _ in
                                store.rerenderForStyleChange()
                            }
                        Toggle("x=180", isOn: $bindableStore.showAuxiliaryLine180)
                            .toggleStyle(.checkbox)
                            .onChange(of: store.showAuxiliaryLine180) { _, _ in
                                store.rerenderForStyleChange()
                            }
                    }
                }
            },
            leftExtra: {
                XYRotationPhiOffsetPanel()
                    .environment(appState)
            },
            rightExtra: { EmptyView() }
        )
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
