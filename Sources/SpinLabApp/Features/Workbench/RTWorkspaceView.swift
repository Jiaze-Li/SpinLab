import SwiftUI

/// RT workflow workspace — shell-based layout.
struct RTWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceShell(
            workflowID: appState.workbench.rtWorkspace.workflowID,
            store: appState.workbench.rtWorkspace,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                RTPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() },
            rightExtra: { EmptyView() }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=RT")
        }
    }
}

// MARK: - Title-row spacing controls

/// Stack offset slider + gap field only — rendered next to the title template row.
/// RT has exactly one tab (`RTWorkbenchTab.rtCurve`), so the tab picker is hidden via
/// `hideTabRow: true` below rather than shown for a single, non-switchable tab.
private struct RTSpacingInlineControls: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.rtWorkspace

        WorkbenchPlotSpacingInlineControls(
            stackOffset: $store.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $store.minGapFraction,
            onStackChange: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "rtStyleChange")
            },
            sliderWidth: 110
        )
    }
}

// MARK: - Plot Controls Panel

private struct RTPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        @Bindable var store = appState.workbench.rtWorkspace
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
                appState.scheduleInteractionSnapshotFlush(source: "rtSeriesOrderCommit")
            },
            onChange: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "rtStyleChange")
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
                appState.scheduleInteractionSnapshotFlush(source: "rtSeriesRename")
            },
            onVisibilityChange: { key, isVisible in
                store.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                appState.scheduleInteractionSnapshotFlush(source: "rtSeriesVisibility")
            },
            activeLayout: store.tabs.activeLayout,
            axisRangeOverride: store.tabs.activeState.axisRangeOverride,
            onAxisBoundUpdate: { bound, value in
                store.updateAxisBound(bound, value: value)
                appState.scheduleInteractionSnapshotFlush(source: "rtAxisBound")
            },
            hideTabRow: true,
            titleRowTrailingContent: {
                RTSpacingInlineControls()
                    .environment(appState)
            }
        ) {
            EmptyView()
        }
        .onChange(of: store.tabs.activeTab) { _, _ in
            store.rerenderForStyleChange()
            appState.scheduleInteractionSnapshotFlush(source: "rtTabSwitch")
        }
    }
}
