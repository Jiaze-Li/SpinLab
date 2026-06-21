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

                    RSMHeatmapPlotControlsPanel(
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

// MARK: - Heatmap Plot Controls Panel

private struct RSMHeatmapPlotControlsPanel: View {
    @Binding var globalPlotDefaults: [String: String]
    let colorScaleMode: HeatmapColorScaleMode
    let titleOverride: String
    let xLabelOverride: String
    let yLabelOverride: String
    let zLabelOverride: String
    let renderedTitle: String
    let renderedXLabel: String
    let renderedYLabel: String
    let renderedZLabel: String
    let sourceResetToken: String
    let onColorScaleModeChange: (HeatmapColorScaleMode) -> Void
    let onTitleOverride: (String) -> Void
    let onXLabelOverride: (String) -> Void
    let onYLabelOverride: (String) -> Void
    let onZLabelOverride: (String) -> Void
    let onStyleChange: () -> Void

    var body: some View {
        GroupBox("Plot Controls") {
            VStack(alignment: .leading, spacing: 8) {
                colorScaleRow
                SharedPlotTextControls(
                    titleOverride: titleOverride,
                    xLabelOverride: xLabelOverride,
                    yLabelOverride: yLabelOverride,
                    renderedTitle: renderedTitle,
                    renderedXLabel: renderedXLabel,
                    renderedYLabel: renderedYLabel,
                    sourceResetToken: sourceResetToken,
                    onTitleOverride: onTitleOverride,
                    onXLabelOverride: onXLabelOverride,
                    onYLabelOverride: onYLabelOverride
                )
                OptionalPlotZLabelControl(
                    renderedDefault: renderedZLabel,
                    currentValue: zLabelOverride,
                    sourceResetToken: sourceResetToken,
                    onCommit: onZLabelOverride
                )
                SharedPlotFontSizeControls(
                    globalPlotDefaults: $globalPlotDefaults,
                    onStyleChange: onStyleChange
                )
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var colorScaleRow: some View {
        HStack(spacing: 8) {
            Text("Color Scale")
                .font(WorkbenchUIStyle.controlLabelFont)
                .foregroundStyle(WorkbenchUIStyle.primaryTextColor)
            Picker("", selection: Binding<HeatmapColorScaleMode>(
                get: { colorScaleMode },
                set: { onColorScaleModeChange($0) }
            )) {
                Text("Linear").tag(HeatmapColorScaleMode.linear)
                Text("Log").tag(HeatmapColorScaleMode.log10)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
        }
    }
}
