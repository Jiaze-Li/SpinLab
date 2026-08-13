import SwiftUI

/// RSM workflow workspace — left column (search/action bar/plot controls/results).
struct RSMWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.rsmWorkspace
        @Bindable var bindableStore = appState.workbench.rsmWorkspace
        @Bindable var bindableWorkbench = appState.workbench

        WorkflowWorkspaceLeftColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                HeatmapPlotControlsPanel(
                    hostControls: RSMViewSelector(
                        activeView: $bindableStore.activeView,
                        parsedDataset: bindableStore.parsedDataset,
                        onChange: {
                            store.rerenderForStyleChange()
                            appState.scheduleInteractionSnapshotFlush(source: "rsmViewChange")
                        }
                    ),
                    globalPlotDefaults: $bindableWorkbench.globalPlotDefaults,
                    colorScaleMode: bindableStore.heatmapDisplayState.colorScaleMode,
                    interpolationMode: bindableStore.heatmapDisplayState.interpolationMode,
                    zDomainState: bindableStore.heatmapDisplayState.zDomainState,
                    showColorbar: bindableStore.heatmapDisplayState.showColorbar,
                    showTitle: bindableStore.heatmapDisplayState.showTitle,
                    xTickCount: bindableStore.heatmapDisplayState.xTickCount,
                    yTickCount: bindableStore.heatmapDisplayState.yTickCount,
                    titleOverride: bindableStore.heatmapDisplayState.titleOverride,
                    xLabelOverride: bindableStore.heatmapDisplayState.xLabelOverride,
                    yLabelOverride: bindableStore.heatmapDisplayState.yLabelOverride,
                    zLabelOverride: bindableStore.heatmapDisplayState.zLabelOverride,
                    renderedTitle: bindableStore.parsedDataset?.title ?? "",
                    renderedXLabel: bindableStore.activeView.xLabel,
                    renderedYLabel: bindableStore.activeView.yLabel,
                    renderedZLabel: bindableStore.parsedDataset
                        .map { RSMWorkspaceStore.publicationZLabel(for: $0.detectorColumnName) }
                        ?? "",
                    sourceResetToken: "\(bindableStore.cachedInputFiles.first ?? "")|\(bindableStore.activeView.rawValue)",
                    showsZRangeControl: true,
                    onColorScaleModeChange: { store.updateHeatmapColorScaleMode($0) },
                    onInterpolationModeChange: { store.updateHeatmapInterpolationMode($0) },
                    onZDomainStateChange: { store.updateHeatmapZDomainState($0) },
                    onShowColorbarChange: { store.updateHeatmapShowColorbar($0) },
                    onShowTitleChange: { store.updateHeatmapShowTitle($0) },
                    onXTickCountChange: { store.updateHeatmapXTickCount($0) },
                    onYTickCountChange: { store.updateHeatmapYTickCount($0) },
                    onTitleOverride: { store.updateHeatmapTitle($0) },
                    onXLabelOverride: { store.updateHeatmapXAxisLabel($0) },
                    onYLabelOverride: { store.updateHeatmapYAxisLabel($0) },
                    onZLabelOverride: { store.updateHeatmapZLabel($0) },
                    onStyleChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "rsmStyleChange")
                    }
                )
            },
            leftExtra: { EmptyView() }
        )
    }
}

