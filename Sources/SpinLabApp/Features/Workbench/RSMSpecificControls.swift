import SwiftUI

// MARK: - RSM-specific controls
//
// Specific content for the shared Controls Surface (spec 06 §4.1, §5): View Selection and the
// Z (colorbar) label. RSM's X/Y labels, X/Y tick counts and Axis/Ticks fonts are Shared Axes and
// Shared Typography in the Plot region (CS-38, CS-38a); RSM supplies only state and callbacks.

extension RSMViewSelector: WorkbenchLeafInput {}

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
        // Tick counts and labels live only in RSM's display state (not a snapshot field): re-render only.
        let tickChange: () -> Void = { self.rerenderForStyleChange() }
        let axes = PlotAxesModel(
            sourceResetToken: sourceToken,
            labels: [
                PlotAxisLabelModel(role: .x, rendered: activeView.xLabel, override: state.xLabelOverride,
                                   onCommit: { self.updateHeatmapXAxisLabel($0) }),
                PlotAxisLabelModel(role: .y, rendered: activeView.yLabel, override: state.yLabelOverride,
                                   onCommit: { self.updateHeatmapYAxisLabel($0) }),
            ],
            ticks: [
                PlotAxisTickModel(role: .x, count: state.xTickCount) { self.updateHeatmapXTickCount($0); tickChange() },
                PlotAxisTickModel(role: .y, count: state.yTickCount) { self.updateHeatmapYTickCount($0); tickChange() },
            ])

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
            WorkbenchSpecificGroup("zLabel", title: "Z Label") {
                WorkbenchSpecificRow("zLabel", label: "Z label") {
                    WorkbenchSpecificInput.control("field", fills: true, RSMLabelInput(
                        renderedDefault: zLabel, currentValue: state.zLabelOverride,
                        sourceResetToken: sourceToken, onCommit: { self.updateHeatmapZLabel($0) }))
                }
            }
        }
        return heatmapControlsDescriptor(
            appState: appState, globalPlotDefaults: globalPlotDefaults, flushSource: "rsmStyleChange",
            defaultTitle: parsedDataset?.title ?? "", sourceResetToken: sourceToken,
            axes: axes, fontRoles: [.title, .axis, .ticks], specific: specific)
    }
}
