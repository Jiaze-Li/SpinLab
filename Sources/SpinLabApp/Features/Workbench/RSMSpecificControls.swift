import SwiftUI

// MARK: - RSM-specific controls
//
// Specific content for the shared Controls Surface (spec 06 §4.1, §5): View Selection and the
// RSM Axis Controls (X/Y/Z labels, X/Y tick counts, axis/tick font sizes). The axis controls
// are built from the Plot System's shared field primitives; RSM supplies only state and
// callbacks. AFM draws no axes and receives none of these (CS-16).

extension RSMViewSelector: WorkbenchLeafInput {}

struct RSMTickCountsInput: WorkbenchLeafInput {
    let xTickCount: Int
    let yTickCount: Int
    let onXChange: (Int) -> Void
    let onYChange: (Int) -> Void

    var body: some View {
        SharedPlotTickCountControls(
            xTickCount: xTickCount, yTickCount: yTickCount,
            onXTickCountChange: onXChange, onYTickCountChange: onYChange)
    }
}

struct RSMAxisFontSizesInput: WorkbenchLeafInput {
    @Binding var globalPlotDefaults: [String: String]
    let onStyleChange: () -> Void

    var body: some View {
        let style = WorkbenchChartStyle.from(styleParams: globalPlotDefaults)
        HStack(spacing: AppSpacing.sm) {
            SharedPlotFontSizePicker(
                label: "Axis", current: style.axisTitleFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "axisTitleFontSize"),
                onStyleChange: onStyleChange, pickerWidth: 50)
            SharedPlotFontSizePicker(
                label: "Ticks", current: style.tickLabelFontSize,
                rawValue: $globalPlotDefaults.valueBinding(forKey: "tickLabelFontSize"),
                onStyleChange: onStyleChange, pickerWidth: 50)
        }
    }
}

struct RSMLabelInput: WorkbenchLeafInput {
    let renderedDefault: String
    let currentValue: String
    let sourceResetToken: String
    let onCommit: (String) -> Void

    var body: some View {
        LabelOverrideField(
            label: "", renderedDefault: renderedDefault, currentValue: currentValue,
            sourceResetToken: sourceResetToken, onCommit: onCommit, fieldMaxWidth: .infinity)
    }
}

extension RSMWorkspaceStore {
    @MainActor
    func controlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>
    ) -> WorkbenchControlsDescriptor {
        let state = heatmapDisplayState
        let sourceToken = "\(cachedInputFiles.first ?? "")|\(activeView.rawValue)"
        let zLabel = parsedDataset.map { RSMWorkspaceStore.publicationZLabel(for: $0.detectorColumnName) } ?? ""
        let styleChange: () -> Void = {
            self.rerenderForStyleChange()
            appState.scheduleInteractionSnapshotFlush(source: "rsmStyleChange")
        }
        // Tick counts live only in RSM's display state (not a snapshot field): re-render only.
        let tickChange: () -> Void = { self.rerenderForStyleChange() }
        let defaults = globalPlotDefaults

        let specific = WorkbenchSpecificContent {
            WorkbenchSpecificGroup("viewSelection", title: "View Selection") {
                WorkbenchSpecificRow("view") {
                    WorkbenchSpecificInput.control("selector", RSMViewSelector(
                        activeView: Binding(get: { self.activeView }, set: { self.activeView = $0 }),
                        parsedDataset: parsedDataset,
                        // activeView is per-session render state — no flush.
                        onChange: { self.rerenderForStyleChange() }))
                }
            }
            WorkbenchSpecificGroup("axisControls", title: "Axis Controls") {
                WorkbenchSpecificRow("xLabel", label: "X label") {
                    WorkbenchSpecificInput.control("field", fills: true, RSMLabelInput(
                        renderedDefault: activeView.xLabel, currentValue: state.xLabelOverride,
                        sourceResetToken: sourceToken, onCommit: { self.updateHeatmapXAxisLabel($0) }))
                }
                WorkbenchSpecificRow("yLabel", label: "Y label") {
                    WorkbenchSpecificInput.control("field", fills: true, RSMLabelInput(
                        renderedDefault: activeView.yLabel, currentValue: state.yLabelOverride,
                        sourceResetToken: sourceToken, onCommit: { self.updateHeatmapYAxisLabel($0) }))
                }
                WorkbenchSpecificRow("zLabel", label: "Z label") {
                    WorkbenchSpecificInput.control("field", fills: true, RSMLabelInput(
                        renderedDefault: zLabel, currentValue: state.zLabelOverride,
                        sourceResetToken: sourceToken, onCommit: { self.updateHeatmapZLabel($0) }))
                }
                WorkbenchSpecificRow("ticks") {
                    WorkbenchSpecificInput.control("counts", RSMTickCountsInput(
                        xTickCount: state.xTickCount, yTickCount: state.yTickCount,
                        onXChange: { self.updateHeatmapXTickCount($0); tickChange() },
                        onYChange: { self.updateHeatmapYTickCount($0); tickChange() }))
                }
                WorkbenchSpecificRow("fontSizes", label: "Font") {
                    WorkbenchSpecificInput.control("sizes", RSMAxisFontSizesInput(
                        globalPlotDefaults: defaults, onStyleChange: styleChange))
                }
            }
        }
        return heatmapControlsDescriptor(
            appState: appState, globalPlotDefaults: globalPlotDefaults, flushSource: "rsmStyleChange",
            renderedTitle: parsedDataset?.title ?? "", sourceResetToken: sourceToken, specific: specific)
    }
}
