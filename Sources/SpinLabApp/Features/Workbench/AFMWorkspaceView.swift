import SwiftUI

/// AFM workflow workspace — left column (search/action bar/plot controls/results).
struct AFMWorkspaceView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.afmWorkspace
        @Bindable var bindableStore = appState.workbench.afmWorkspace
        @Bindable var bindableWorkbench = appState.workbench

        WorkflowWorkspaceLeftColumn(
            workflowID: store.workflowID,
            store: store,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                HeatmapPlotControlsPanel(
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
                    renderedXLabel: "X (\(CanonicalAFMDataset.xUnit))",
                    renderedYLabel: "Y (\(CanonicalAFMDataset.yUnit))",
                    renderedZLabel: bindableStore.activeChannel.map { "\($0.displayLabel) (\($0.canonicalUnit))" } ?? "",
                    sourceResetToken: "\(bindableStore.cachedInputFiles.first ?? "")|\(bindableStore.processingConfiguration.activeChannelID)",
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
                        appState.scheduleInteractionSnapshotFlush(source: "afmStyleChange")
                    },
                    onTickCountRenderChange: {
                        store.rerenderForStyleChange()
                    },
                    pluginControls: {
                        AFMPlotControls(
                            channels: bindableStore.parsedDataset?.channels ?? [],
                            activeChannelID: bindableStore.processingConfiguration.activeChannelID,
                            planeLevelEnabled: bindableStore.processingConfiguration.planeLevelEnabled,
                            lineFlattenOrder: bindableStore.processingConfiguration.lineFlattenOrder,
                            zeroReference: bindableStore.processingConfiguration.zeroReference,
                            onChannelChange: { store.updateActiveChannel($0) },
                            onPlaneLevelChange: { store.updatePlaneLevelEnabled($0) },
                            onLineFlattenChange: { store.updateLineFlattenOrder($0) },
                            onZeroReferenceChange: { store.updateZeroReference($0) }
                        )
                    }
                )
            },
            leftExtra: { EmptyView() }
        )
    }
}
