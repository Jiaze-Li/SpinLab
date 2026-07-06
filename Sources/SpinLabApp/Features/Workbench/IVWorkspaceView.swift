import SwiftUI

/// IV workflow workspace — shell-based layout.
struct IVWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell(
            workflowID: appState.workbench.ivWorkspace.workflowID,
            store: appState.workbench.ivWorkspace,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                IVPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() },
            rightExtra: { EmptyView() },
            actionBarTrailing: {
                IVActionBarTabPicker()
                    .environment(appState)
            }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=IV")
        }
    }
}

// MARK: - Action-bar tab picker

/// Tab picker only — rendered in the workflow action bar's trailing slot, after Load.
/// Stack offset / gap live inline next to the title template field instead (see
/// `IVSpacingInlineControls` below), matching the 3ω layout split.
private struct IVActionBarTabPicker: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.ivWorkspace

        WorkbenchPlotTabPicker(
            activeTab: $store.tabs.activeTab,
            tabs: IVWorkbenchTab.allCases,
            tabLabel: { $0.displayName },
            onChange: { _, _ in
                store.rerenderForStyleChange()
                appState.flushInteractionSnapshotNow(source: "ivTabSwitch")
            }
        )
    }
}

/// Stack offset slider + gap field only — rendered next to the title template row.
private struct IVSpacingInlineControls: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.ivWorkspace

        WorkbenchPlotSpacingInlineControls(
            stackOffset: $store.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $store.minGapFraction,
            onStackChange: {
                store.rerenderForStyleChange()
                appState.flushInteractionSnapshotNow(source: "ivStyleChange")
            },
            sliderWidth: 110
        )
    }
}

// MARK: - Plot Controls Panel

private struct IVPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.ivWorkspace
        @Bindable var workbench = appState.workbench

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
                globalPlotDefaults: $workbench.globalPlotDefaults,
                chartStyleOverrides: $store.tabs.chartStyleOverrides,
                seriesOrderPayload: store.activeChartManifestPayload,
                seriesControlModel: store.tabs.activeOutput.seriesControlModel,
                currentSeriesOrder: store.activeSeriesOrder,
                canReorderSeries: store.canReorderSeries,
                onSeriesOrderCommit: { order in
                    store.updateSeriesOrder(order)
                    appState.flushInteractionSnapshotNow(source: "ivSeriesOrderCommit")
                },
                onChange: {
                    store.rerenderForStyleChange()
                    appState.flushInteractionSnapshotNow(source: "ivStyleChange")
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
                onRenameSeriesLabel: { key, label in
                    store.updateSeriesLabel(identityKey: key, newLabel: label)
                    appState.flushInteractionSnapshotNow(source: "ivSeriesRename")
                },
                onVisibilityChange: { key, isVisible in
                    store.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                    appState.flushInteractionSnapshotNow(source: "ivSeriesVisibility")
                },
                activeLayout: store.tabs.activeLayout,
                axisRangeOverride: store.tabs.activeState.axisRangeOverride,
                onAxisBoundUpdate: { bound, value in
                    AxisRangeDebug.log("IVWorkspaceView onAxisBoundUpdate BEFORE updateAxisBound bound=\(bound) value=\(value.map { String(format: "%g", $0) } ?? "nil") | axisRangeOverride=\(String(describing: store.tabs.activeState.axisRangeOverride))")
                    store.tabs.updateAxisBound(bound, value: value)
                    AxisRangeDebug.log("IVWorkspaceView onAxisBoundUpdate AFTER updateAxisBound | axisRangeOverride=\(String(describing: store.tabs.activeState.axisRangeOverride))")
                    AxisRangeDebug.log("IVWorkspaceView onAxisBoundUpdate BEFORE rerenderForStyleChange")
                    store.rerenderForStyleChange()
                    AxisRangeDebug.log("IVWorkspaceView onAxisBoundUpdate AFTER rerenderForStyleChange")
                    appState.flushInteractionSnapshotNow(source: "ivAxisBound")
                },
                hideTabRow: true,
                titleRowTrailingContent: {
                    IVSpacingInlineControls()
                        .environment(appState)
                }
            ) {
                IVSpecificPlotControls()
                    .environment(appState)
            }
    }
}
