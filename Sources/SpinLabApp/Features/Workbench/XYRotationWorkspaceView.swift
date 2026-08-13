import SwiftUI

/// XY Rotation workflow workspace — left column (search/action bar/plot controls/results).
struct XYRotationWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.xyRotationWorkspace
        @Bindable var bindableStore = appState.workbench.xyRotationWorkspace
        @Bindable var bindableWorkbench = appState.workbench

        WorkflowWorkspaceLeftColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                WorkbenchStandardPlotControls(
                    store: store,
                    tabLabel: { $0.displayName },
                    globalPlotDefaults: $bindableWorkbench.globalPlotDefaults,
                    canReorderSeries: store.canReorderSeries,
                    currentSeriesOrder: store.activeSeriesOrder,
                    onSeriesOrderCommit: { order in
                        // Series order lives only in per-tab render state — not a snapshot field, no flush.
                        store.updateSeriesOrder(order)
                    },
                    onChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "xyRotationStyleChange")
                    },
                    onTransientChange: {
                        // Series order/rename/visibility and title/axis label overrides are
                        // per-tab render state, not a snapshot field — rerender only, no flush.
                        store.rerenderForStyleChange()
                    },
                    onTitleOverride: { store.updatePlotTitle($0) },
                    onXLabelOverride: { store.updateXAxisLabel($0) },
                    onYLabelOverride: { store.updateYAxisLabel($0) },
                    onRenameSeriesLabel: { key, label in
                        // Series label overrides are per-tab render state — not a snapshot field, no flush.
                        store.updateSeriesLabel(identityKey: key, newLabel: label)
                    },
                    onVisibilityChange: { key, isVisible in
                        // Series visibility is per-tab render state — not a snapshot field, no flush.
                        store.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                    },
                    onAxisBoundUpdate: { bound, value in
                        // Axis-bound overrides are per-tab render state — not a snapshot field, no flush.
                        store.updateAxisBound(bound, value: value)
                    },
                    onResetRanges: {
                        // Resets only the transient per-tab axis override above — no snapshot field, no flush.
                        store.resetAxisRanges()
                    },
                    onTickCountUpdate: { axis, count in
                        // Tick-count overrides are per-tab render state — not a snapshot field, no flush.
                        store.updateTickCount(axis: axis, count: count)
                    },
                    hideTabRow: true,
                    titleRowTrailingContent: {
                        XYRotationSpacingInlineControls()
                            .environment(appState)
                    }
                ) {
                    WorkbenchPlotControlsPluginSection {
                        HStack(spacing: 12) {
                            Toggle("Center", isOn: $bindableStore.centerBaseline)
                                .toggleStyle(.checkbox)
                                .onChange(of: store.centerBaseline) { _, _ in
                                    store.rerenderForStyleChange()
                                    appState.scheduleInteractionSnapshotFlush(source: "xyRotationCenterBaselineChange")
                                }
                            Toggle("Detrend", isOn: $bindableStore.linearDetrend)
                                .toggleStyle(.checkbox)
                                .onChange(of: store.linearDetrend) { _, _ in
                                    store.rerenderForStyleChange()
                                    appState.scheduleInteractionSnapshotFlush(source: "xyRotationLinearDetrendChange")
                                }
                            Toggle("x=180", isOn: $bindableStore.showAuxiliaryLine180)
                                .toggleStyle(.checkbox)
                                .onChange(of: store.showAuxiliaryLine180) { _, _ in
                                    store.rerenderForStyleChange()
                                }
                        }
                    }
                }
            },
            leftExtra: {
                XYRotationPhiOffsetPanel()
                    .environment(appState)
            },
            actionBarTrailing: {
                XYRotationActionBarTabPicker()
                    .environment(appState)
            }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=XYRotation")
        }
    }
}

// MARK: - Action-bar tab picker

/// Tab picker only — rendered in the workflow action bar's trailing slot, after Load.
/// Stack offset / gap live inline next to the title template field instead (see
/// `XYRotationSpacingInlineControls` below), matching the 3ω layout split.
private struct XYRotationActionBarTabPicker: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.xyRotationWorkspace

        WorkbenchPlotTabPicker(
            activeTab: $store.tabs.activeTab,
            tabs: XYRotationWorkbenchTab.allCases,
            tabLabel: { $0.displayName },
            onChange: { _, _ in
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "xyRotationTabSwitch")
            }
        )
    }
}

/// Stack offset slider + gap field only — rendered next to the title template row.
private struct XYRotationSpacingInlineControls: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.xyRotationWorkspace

        WorkbenchPlotSpacingInlineControls(
            stackOffset: $store.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $store.minGapFraction,
            onStackChange: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "xyRotationStyleChange")
            },
            sliderWidth: 110
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
                                    set: {
                                        store.updatePhiOffset(sweepID: sweep.id, offset: $0)
                                        appState.scheduleInteractionSnapshotFlush(source: "xyRotationPhiOffsetChange")
                                    }
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
