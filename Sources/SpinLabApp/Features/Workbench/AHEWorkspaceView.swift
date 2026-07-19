import SwiftUI
import AppKit

/// AHE workflow workspace — shell-based layout.
struct AHEWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace

        WorkflowWorkspaceShell(
            workflowID: ahe.workflowID,
            store: ahe,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                AHEPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() },
            rightExtra: { EmptyView() }
        )
        .onAppear {
            print("[PERF][workbench] workspaceAppear name=AHE")
        }
    }
}

// MARK: - AHE Plot Controls Panel

/// Stack offset slider + gap field only — rendered next to the title template row.
/// AHE has a single tab (`AHEWorkbenchTab.ahe`), so the tab picker itself is suppressed
/// via `hideTabRow`; this mirrors `IVSpacingInlineControls`.
private struct AHESpacingInlineControls: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace
        @Bindable var bindableAhe = appState.workbench.aheWorkspace

        WorkbenchPlotSpacingInlineControls(
            stackOffset: $bindableAhe.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $bindableAhe.minGapFraction,
            onStackChange: {
                ahe.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "aheStackOffsetChange")
            },
            onGapSubmit: {
                ahe.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "aheGapSubmit")
            },
            sliderWidth: 110
        )
    }
}

private struct AHEPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace
        @Bindable var workbench = appState.workbench
        @Bindable var bindableAhe = appState.workbench.aheWorkspace

        WorkbenchStandardPlotControls(
            activeTab: $bindableAhe.tabs.activeTab,
            tabLabel: { _ in "AHE" },
            stackOffset: $bindableAhe.stackOffsetMultiplier,
            stackRange: 0...1.6,
            minGapFraction: $bindableAhe.minGapFraction,
            showGrid: $bindableAhe.showPlotGrid,
            showTitle: Binding(
                get: { ahe.tabs.activeState.showTitle },
                set: { ahe.tabs.updateShowTitle($0) }
            ),
            titleTemplate: $bindableAhe.titleTemplate,
            numericDisplayCache: ahe.cachedSampleNumericDisplay,
            seriesRenderMode: $bindableAhe.seriesRenderMode,
            globalPlotDefaults: $workbench.globalPlotDefaults,
            chartStyleOverrides: $bindableAhe.chartStyleOverrides,
            seriesOrderPayload: ahe.activeChartManifestPayload,
            seriesControlModel: ahe.tabs.activeOutput.seriesControlModel,
            currentSeriesOrder: ahe.tabs.activeState.seriesOrder,
            canReorderSeries: true,
            onSeriesOrderCommit: { order in
                ahe.updateSeriesOrder(order)
                appState.scheduleInteractionSnapshotFlush(source: "aheSeriesOrderCommit")
            },
            onChange: {
                ahe.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "aheStyleChange")
            },
            activeTitleOverride: ahe.tabs.activeState.titleOverride,
            activeXLabelOverride: ahe.tabs.activeState.xLabelOverride,
            activeYLabelOverride: ahe.tabs.activeState.yLabelOverride,
            renderedTitle: ahe.tabs.activeLayout?.chartTitle ?? "",
            renderedXLabel: ahe.tabs.activeLayout?.xAxisLabel ?? "",
            renderedYLabel: ahe.tabs.activeLayout?.yAxisLabel ?? "",
            sourceResetToken: ahe.tabs.activeSourceIdentityKey,
            onTitleOverride: { ahe.updatePlotTitle($0) },
            onXLabelOverride: { ahe.updateXAxisLabel($0) },
            onYLabelOverride: { ahe.updateYAxisLabel($0) },
            activeSeriesLabelOverrides: ahe.tabs.activeSeriesLabelOverrides,
            activeSeriesHiddenKeys: ahe.tabs.activeState.hiddenSeriesKeys,
            onRenameSeriesLabel: { key, label in
                ahe.updateSeriesLabel(identityKey: key, newLabel: label)
            },
            onVisibilityChange: { key, isVisible in
                ahe.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                appState.scheduleInteractionSnapshotFlush(source: "aheSeriesVisibility")
            },
            activeLayout: ahe.tabs.activeLayout,
            axisRangeOverride: ahe.tabs.activeState.axisRangeOverride,
            onAxisBoundUpdate: { bound, value in
                ahe.updateAxisBound(bound, value: value)
                appState.scheduleInteractionSnapshotFlush(source: "aheAxisBound")
            },
            tickOverride: ahe.tabs.activeState.tickOverride,
            onTickCountUpdate: { axis, count in
                ahe.updateTickCount(axis: axis, count: count)
            },
            hideTabRow: true,
            titleRowTrailingContent: {
                AHESpacingInlineControls()
                    .environment(appState)
            }
        ) {
            WorkbenchPlotControlsPluginSection {
                AHEOverridesControls()
            }
        }
    }
}
