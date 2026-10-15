import SwiftUI

/// Heatmap workflows (AFM, RSM) share one state shape for the controls Surface: the Common
/// title controls and the `heatmap` Plot section read the same display state and call the same
/// update methods. The workflow supplies only its rendered title, source-reset token and
/// Specific content (CS-15, CS-28).
@MainActor
protocol WorkbenchHeatmapControlsStore: WorkbenchWorkspaceProviding {
    var heatmapDisplayState: HeatmapTabRenderState { get }
    func updateHeatmapColorScaleMode(_ mode: HeatmapColorScaleMode)
    func updateHeatmapInterpolationMode(_ mode: HeatmapInterpolationMode)
    func updateHeatmapTitle(_ title: String)
    func updateHeatmapShowColorbar(_ isShown: Bool)
    func updateHeatmapShowTitle(_ isShown: Bool)
    func updateHeatmapZDomainState(_ state: HeatmapZDomainState)
}

extension RSMWorkspaceStore: WorkbenchHeatmapControlsStore {}
extension AFMWorkspaceStore: WorkbenchHeatmapControlsStore {}

extension WorkbenchHeatmapControlsStore {
    func heatmapControlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>,
        flushSource: String,
        renderedTitle: String,
        sourceResetToken: String,
        specific: WorkbenchSpecificContent
    ) -> WorkbenchControlsDescriptor {
        let state = heatmapDisplayState
        let common = WorkbenchCommonControlsModel(
            showTitle: state.showTitle,
            titleOverride: state.titleOverride,
            renderedTitle: renderedTitle,
            sourceResetToken: sourceResetToken,
            globalPlotDefaults: globalPlotDefaults,
            onShowTitleChange: { self.updateHeatmapShowTitle($0) },
            onTitleOverride: { self.updateHeatmapTitle($0) },
            onStyleChange: {
                // Title size / transparent background write into the shared plot defaults,
                // a snapshot field — legitimately flushed.
                self.rerenderForStyleChange()
                appState.scheduleInteractionSnapshotFlush(source: flushSource)
            }
        )
        let plot = HeatmapControlsModel(
            colorScaleMode: state.colorScaleMode,
            interpolationMode: state.interpolationMode,
            zDomainState: state.zDomainState,
            showColorbar: state.showColorbar,
            onColorScaleModeChange: { self.updateHeatmapColorScaleMode($0) },
            onInterpolationModeChange: { self.updateHeatmapInterpolationMode($0) },
            onZDomainStateChange: { self.updateHeatmapZDomainState($0) },
            onShowColorbarChange: { self.updateHeatmapShowColorbar($0) }
        )
        return WorkbenchControlsDescriptor(common: common, plot: .heatmap(plot), specific: specific)
    }
}
