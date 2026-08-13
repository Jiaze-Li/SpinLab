import SwiftUI

/// IV workflow workspace — left column (search/action bar/plot controls/results).
struct IVWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        WorkflowWorkspaceLeftColumn(
            workflowID: appState.workbench.ivWorkspace.workflowID,
            store: appState.workbench.ivWorkspace,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                IVPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() },
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
                // Active tab is per-session render state, not a snapshot field — no flush.
                store.rerenderForStyleChange()
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
                appState.scheduleInteractionSnapshotFlush(source: "ivStyleChange")
            },
            sliderWidth: 110
        )
    }
}

// MARK: - Plot Controls Panel

private struct IVPlotControlsPanel: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.ivWorkspace
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
                appState.scheduleInteractionSnapshotFlush(source: "ivStyleChange")
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
                IVSpacingInlineControls()
                    .environment(appState)
            }
        ) {
            IVSpecificPlotControls()
                .environment(appState)
        }
    }
}
