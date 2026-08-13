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
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "ivTabSwitch")
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
                store.updateSeriesOrder(order)
                appState.scheduleInteractionSnapshotFlush(source: "ivSeriesOrderCommit")
            },
            onChange: {
                store.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: "ivStyleChange")
            },
            onTitleOverride: { store.updatePlotTitle($0) },
            onXLabelOverride: { store.updateXAxisLabel($0) },
            onYLabelOverride: { store.updateYAxisLabel($0) },
            onRenameSeriesLabel: { key, label in
                store.updateSeriesLabel(identityKey: key, newLabel: label)
                appState.scheduleInteractionSnapshotFlush(source: "ivSeriesRename")
            },
            onVisibilityChange: { key, isVisible in
                store.updateSeriesVisibility(identityKey: key, isVisible: isVisible)
                appState.scheduleInteractionSnapshotFlush(source: "ivSeriesVisibility")
            },
            onAxisBoundUpdate: { bound, value in
                store.updateAxisBound(bound, value: value)
                appState.scheduleInteractionSnapshotFlush(source: "ivAxisBound")
            },
            onResetRanges: {
                store.resetAxisRanges()
                appState.scheduleInteractionSnapshotFlush(source: "ivAxisRangesReset")
            },
            onTickCountUpdate: { axis, count in
                store.updateTickCount(axis: axis, count: count)
                appState.scheduleInteractionSnapshotFlush(source: "ivTickCount")
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
