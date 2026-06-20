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
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        renderedZLabel: bindableStore.parsedDataset?.detectorColumnName ?? "",
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
                labelOverridesRow
                fontSizeRow
            }
            .padding(.vertical, 4)
        }
    }

    private var colorScaleRow: some View {
        HStack(spacing: 8) {
            Text("Color Scale")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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

    private var labelOverridesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                LabelOverrideField(
                    label: "Title",
                    renderedDefault: renderedTitle,
                    currentValue: titleOverride,
                    sourceResetToken: sourceResetToken,
                    onCommit: { onTitleOverride($0) },
                    fieldMaxWidth: 220
                )
                LabelOverrideField(
                    label: "X",
                    renderedDefault: renderedXLabel,
                    currentValue: xLabelOverride,
                    sourceResetToken: sourceResetToken,
                    onCommit: { onXLabelOverride($0) },
                    fieldMaxWidth: 90
                )
                LabelOverrideField(
                    label: "Y",
                    renderedDefault: renderedYLabel,
                    currentValue: yLabelOverride,
                    sourceResetToken: sourceResetToken,
                    onCommit: { onYLabelOverride($0) },
                    fieldMaxWidth: 90
                )
            }
            HStack(spacing: 12) {
                LabelOverrideField(
                    label: "Z",
                    renderedDefault: renderedZLabel,
                    currentValue: zLabelOverride,
                    sourceResetToken: sourceResetToken,
                    onCommit: { onZLabelOverride($0) },
                    fieldMaxWidth: 220
                )
            }
        }
    }

    private var fontSizeRow: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        return HStack(spacing: 10) {
            Text("Size")
                .font(.system(size: 12))
                .fixedSize()
            heatmapFontSizePicker(label: "Title", key: "titleFontSize", current: style.titleFontSize)
            heatmapFontSizePicker(label: "Axis", key: "axisTitleFontSize", current: style.axisTitleFontSize)
            heatmapFontSizePicker(label: "Ticks", key: "tickLabelFontSize", current: style.tickLabelFontSize)
        }
    }

    @ViewBuilder
    private func heatmapFontSizePicker(label: String, key: String, current: CGFloat) -> some View {
        let options: [CGFloat] = [12, 14, 16, 18, 19, 20, 22, 24, 25, 28, 32]
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .fixedSize()
            Picker("", selection: Binding<CGFloat>(
                get: { globalPlotDefaults[key].flatMap { Double($0).map { CGFloat($0) } } ?? current },
                set: { newValue in
                    globalPlotDefaults[key] = "\(Int(newValue))"
                    onStyleChange()
                }
            )) {
                ForEach(options, id: \.self) { value in
                    Text("\(Int(value))").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 58)
        }
    }
}
