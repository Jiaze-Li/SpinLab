import SwiftUI
import AppKit

/// AHE workflow workspace — left column (search/action bar/plot controls/results).
struct AHEWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let ahe = appState.workbench.aheWorkspace

        WorkflowWorkspaceLeftColumn(
            workflowID: ahe.workflowID,
            store: ahe,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                AHEPlotControlsPanel()
                    .environment(appState)
            },
            leftExtra: { EmptyView() }
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

        WorkbenchStandardPlotControls(
            store: ahe,
            tabLabel: { _ in "AHE" },
            globalPlotDefaults: $workbench.globalPlotDefaults,
            // AHE's `WorkbenchWorkspaceProviding` conformance relies on the protocol's
            // default canReorderSeries/activeSeriesOrder (false/nil) — its real reordering
            // state lives only in tabs.activeState.seriesOrder, and it's always reorderable.
            // See `WorkbenchStandardPlotWorkspaceStore`.
            canReorderSeries: true,
            currentSeriesOrder: ahe.tabs.activeState.seriesOrder,
            onSeriesOrderCommit: { order in
                // Series order lives only in per-tab render state (TabRenderManager),
                // which is not part of SpinLabInteractionSnapshot — no flush here.
                ahe.updateSeriesOrder(order)
            },
            onChange: {
                ahe.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "aheStyleChange")
            },
            onTransientChange: {
                // Series order/rename/visibility and title/axis label overrides are
                // per-tab render state, not a snapshot field — rerender only, no flush.
                ahe.rerenderForStyleChange()
            },
            onTitleOverride: { ahe.updatePlotTitle($0) },
            onXLabelOverride: { ahe.updateXAxisLabel($0) },
            onYLabelOverride: { ahe.updateYAxisLabel($0) },
            onRenameSeriesLabel: { key, label in
                ahe.updateSeriesLabel(identityKey: key, newLabel: label)
            },
            onVisibilityChange: { key, isVisible in
                // Series visibility is per-tab render state, not a snapshot field — no flush.
                ahe.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
            },
            onAxisBoundUpdate: { bound, value in
                // Axis-bound overrides are per-tab render state, not a snapshot field — no flush.
                ahe.updateAxisBound(bound, value: value)
            },
            onResetRanges: {
                // Resets only the transient per-tab axis override above — no snapshot field, no flush.
                ahe.resetAxisRanges()
            },
            onTickCountUpdate: { axis, count in
                // Tick-count overrides are per-tab render state, not a snapshot field — no flush.
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
