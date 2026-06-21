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
                    HStack(spacing: 8) {
                        Text("View")
                            .font(WorkbenchUIStyle.controlLabelFont)
                            .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
                        Picker("", selection: $bindableStore.activeView) {
                            ForEach(RSMView.allCases, id: \.self) { view in
                                Text(view.rawValue.uppercased()).tag(view)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 160)
                        .onChange(of: store.activeView) { _, _ in
                            store.rerenderForStyleChange()
                            appState.flushInteractionSnapshotNow()
                        }
                        if let dataset = store.parsedDataset, !dataset.isViewCompatible(store.activeView) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("This view is not valid for the loaded data. Recommended: \(dataset.recommendedView.rawValue.uppercased())")
                        }
                    }

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
