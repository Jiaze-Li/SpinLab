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
                appState.scheduleInteractionSnapshotFlush(source: "rtStackOffsetChange")
            },
            onGapSubmit: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "rtGapSubmit")
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
                // Series order lives only in per-tab render state — not a snapshot field, no flush.
                store.updateSeriesOrder(order)
            },
            onChange: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "rtStyleChange")
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
                RTSpacingInlineControls()
                    .environment(appState)
            }
        ) {
            EmptyView()
        }
        .onChange(of: store.tabs.activeTab) { _, _ in
            // Active tab is per-session render state, not a snapshot field — no flush.
            store.rerenderForStyleChange()
        }
    }
}
