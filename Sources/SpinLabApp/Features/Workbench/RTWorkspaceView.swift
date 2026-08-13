import SwiftUI

/// RT workflow workspace — left column (search/action bar/plot controls/results).
struct RTWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceLeftColumn(
            workflowID: appState.workbench.rtWorkspace.workflowID,
            store: appState.workbench.rtWorkspace,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                RTPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() }
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
        let store = appState.workbench.rtWorkspace
        @Bindable var workbench = appState.workbench

        WorkbenchStandardPlotControls(
            store: store,
            tabLabel: { $0.displayName },
            globalPlotDefaults: $workbench.globalPlotDefaults,
            canReorderSeries: store.canReorderSeries,
            currentSeriesOrder: store.activeSeriesOrder,
            onSeriesOrderCommit: { order in
                store.updateSeriesOrder(order)
                appState.scheduleInteractionSnapshotFlush(source: "rtSeriesOrderCommit")
            },
            onChange: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "rtStyleChange")
            },
            onTitleOverride: { store.updatePlotTitle($0) },
            onXLabelOverride: { store.updateXAxisLabel($0) },
            onYLabelOverride: { store.updateYAxisLabel($0) },
            onRenameSeriesLabel: { key, label in
                store.updateSeriesLabel(identityKey: key, newLabel: label)
                appState.scheduleInteractionSnapshotFlush(source: "rtSeriesRename")
            },
            onVisibilityChange: { key, isVisible in
                store.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                appState.scheduleInteractionSnapshotFlush(source: "rtSeriesVisibility")
            },
            onAxisBoundUpdate: { bound, value in
                store.updateAxisBound(bound, value: value)
                appState.scheduleInteractionSnapshotFlush(source: "rtAxisBound")
            },
            onResetRanges: {
                store.resetAxisRanges()
                appState.scheduleInteractionSnapshotFlush(source: "rtAxisRangesReset")
            },
            onTickCountUpdate: { axis, count in
                store.updateTickCount(axis: axis, count: count)
                appState.scheduleInteractionSnapshotFlush(source: "rtTickCount")
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
