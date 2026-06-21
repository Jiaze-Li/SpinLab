import SwiftUI

/// RSM workflow workspace — shell-based layout.
struct RSMWorkspaceView: View, WorkflowWorkspaceProvider {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        let store = appState.workbench.rsmWorkspace
        @Bindable var bindableStore = appState.workbench.rsmWorkspace
        @Bindable var bindableWorkbench = appState.workbench

        WorkflowWorkspaceShell(
            workflowID: .rsm,
            store: store,
            workbench: appState.workbench,
            searchExtra: { EmptyView() },
            plotControls: {
                VStack(alignment: .leading, spacing: 8) {
                    RSMViewSelector(
                        activeView: $bindableStore.activeView,
                        parsedDataset: bindableStore.parsedDataset,
                        onChange: {
                            store.rerenderForStyleChange()
                            appState.flushInteractionSnapshotNow()
                        }
                    )

                    HeatmapPlotControlsPanel(
                        globalPlotDefaults: $bindableWorkbench.globalPlotDefaults,
                        colorScaleMode: bindableStore.heatmapDisplayState.colorScaleMode,
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
                        onColorScaleModeChange: { store.updateHeatmapColorScaleMode($0) },
                        onTitleOverride: { store.updateHeatmapTitle($0) },
                        onXLabelOverride: { store.updateHeatmapXAxisLabel($0) },
                        onYLabelOverride: { store.updateHeatmapYAxisLabel($0) },
                        onZLabelOverride: { store.updateHeatmapZLabel($0) },
                        onStyleChange: {
                            store.rerenderForStyleChange()
                            appState.flushInteractionSnapshotNow()
                        }
                    )
                }
            },
            leftExtra: { EmptyView() },
            rightExtra: { EmptyView() }
        )
    }
}
