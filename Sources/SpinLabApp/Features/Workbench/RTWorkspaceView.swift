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
            currentSeriesOrder: store.activeSeriesOrder,
            canReorderSeries: store.canReorderSeries,
            onSeriesOrderCommit: { order in
                store.updateSeriesOrder(order)
                appState.flushInteractionSnapshotNow()
            },
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
            onRenameSeriesLabel: { key, label in
                store.updateSeriesLabel(identityKey: key, newLabel: label)
                appState.flushInteractionSnapshotNow()
            },
            activeLayout: store.tabs.activeLayout,
            axisRangeOverride: store.tabs.activeState.axisRangeOverride,
            onAxisBoundUpdate: { bound, value in
                store.tabs.updateAxisBound(bound, value: value)
                store.rerenderForStyleChange()
                appState.flushInteractionSnapshotNow()
            }
        )
    }
}
