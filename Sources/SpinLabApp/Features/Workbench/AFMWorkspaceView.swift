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
            legacyPlotControls: {
                HeatmapPlotControlsPanel(
                    globalPlotDefaults: $bindableWorkbench.globalPlotDefaults,
                    colorScaleMode: bindableStore.heatmapDisplayState.colorScaleMode,
                    interpolationMode: bindableStore.heatmapDisplayState.interpolationMode,
                    zDomainState: bindableStore.heatmapDisplayState.zDomainState,
                    showColorbar: bindableStore.heatmapDisplayState.showColorbar,
                    showTitle: bindableStore.heatmapDisplayState.showTitle,
                    titleOverride: bindableStore.heatmapDisplayState.titleOverride,
                    renderedTitle: bindableStore.parsedDataset?.title ?? "",
                    sourceResetToken: "\(bindableStore.cachedInputFiles.first ?? "")|\(bindableStore.processingConfiguration.activeChannelID)",
                    onColorScaleModeChange: { store.updateHeatmapColorScaleMode($0) },
                    onInterpolationModeChange: { store.updateHeatmapInterpolationMode($0) },
                    onZDomainStateChange: { store.updateHeatmapZDomainState($0) },
                    onShowColorbarChange: { store.updateHeatmapShowColorbar($0) },
                    onShowTitleChange: { store.updateHeatmapShowTitle($0) },
                    onTitleOverride: { store.updateHeatmapTitle($0) },
                    onStyleChange: {
                        store.rerenderForStyleChange()
                        appState.scheduleInteractionSnapshotFlush(source: "afmStyleChange")
                    },
                    pluginControls: {
                        AFMPlotControls(
                            channels: bindableStore.parsedDataset?.channels ?? [],
                            activeChannelID: bindableStore.processingConfiguration.activeChannelID,
                            surfaceLevel: bindableStore.processingConfiguration.surfaceLevel,
                            lineFlattenOrder: bindableStore.processingConfiguration.lineFlattenOrder,
                            zeroReference: bindableStore.processingConfiguration.zeroReference,
                            scaleBar: bindableStore.scaleBar,
                            onChannelChange: { store.updateActiveChannel($0) },
                            onSurfaceLevelChange: { store.updateSurfaceLevel($0) },
                            onLineFlattenChange: { store.updateLineFlattenOrder($0) },
                            onZeroReferenceChange: { store.updateZeroReference($0) },
                            onScaleBarChange: { store.updateScaleBar($0) }
                        )
                    }
                )
            },
            leftExtra: { EmptyView() }
        )
    }
}
