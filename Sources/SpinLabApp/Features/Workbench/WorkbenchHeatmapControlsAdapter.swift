import SwiftUI

/// Heatmap workflows (AFM, RSM) share one state shape for the controls Surface: the Common
/// title controls and the `heatmap` Plot section read the same display state and call the same
/// update methods. The workflow supplies only its rendered title, source-reset token and
/// Specific content (CS-15, CS-28).
@MainActor
protocol WorkbenchHeatmapControlsStore: WorkbenchWorkspaceProviding {
    var heatmapDisplayState: HeatmapTabRenderState { get }
    /// The hit that was actually analyzed; title tokens bind to it (never to the search list).
    var analyzedHit: WorkflowMeasurementSearchHit? { get }
    var cachedSampleNumericDisplay: [String: [String: String]] { get }
    /// Numeric title values frozen when the hit was analyzed; nil only for legacy restored packs.
    var analyzedNumericDisplay: [String: String]? { get }
    /// Value of the `#tab` template token ("AFM" / "RSM").
    var heatmapTitleTabToken: String { get }
    func updateHeatmapColorScaleMode(_ mode: HeatmapColorScaleMode)
    func updateHeatmapInterpolationMode(_ mode: HeatmapInterpolationMode)
    func updateHeatmapTitle(_ title: String)
    func updateHeatmapTitleTemplate(_ template: String)
    func updateHeatmapShowColorbar(_ isShown: Bool)
    func updateHeatmapShowTitle(_ isShown: Bool)
    func updateHeatmapZDomainState(_ state: HeatmapZDomainState)
}

extension RSMWorkspaceStore: WorkbenchHeatmapControlsStore {
    var heatmapTitleTabToken: String { "RSM" }
}
extension AFMWorkspaceStore: WorkbenchHeatmapControlsStore {
    var heatmapTitleTabToken: String { "AFM" }
}

extension WorkbenchHeatmapControlsStore {
    func heatmapControlsDescriptor(
        appState: SpinLabAppState,
        globalPlotDefaults: Binding<[String: String]>,
        flushSource: String,
        defaultTitle: String,
        sourceResetToken: String,
        axes: PlotAxesModel,
        fontRoles: [PlotFontRole],
        specific: WorkbenchSpecificContent
    ) -> WorkbenchControlsDescriptor {
        let state = heatmapDisplayState
        let hit = analyzedHit
        let tokens = HeatmapTitleResolution.tokens(
            tab: heatmapTitleTabToken, hit: hit, numeric: titleNumericDisplay)
        // The Plot title placeholder shows what renders when no manual title is set.
        let templateTitle = HeatmapTitleResolution.templateTitle(state.titleTemplate, tokens: tokens)
        let styleChange: () -> Void = {
            // Title size / transparent background write into the shared plot defaults,
            // a snapshot field — legitimately flushed.
            self.rerenderForStyleChange()
            appState.scheduleInteractionSnapshotFlush(source: flushSource)
        }
        let common = WorkbenchCommonControlsModel(
            showTitle: state.showTitle,
            titleOverride: state.titleOverride,
            renderedTitle: templateTitle.isEmpty ? defaultTitle : templateTitle,
            sourceResetToken: sourceResetToken,
            globalPlotDefaults: globalPlotDefaults,
            titleTemplate: Binding(
                get: { self.heatmapDisplayState.titleTemplate },
                set: { self.updateHeatmapTitleTemplate($0) }),
            availableTokens: HeatmapTitleResolution.availableTokens(from: tokens),
            onShowTitleChange: { self.updateHeatmapShowTitle($0) },
            onTitleOverride: { self.updateHeatmapTitle($0) },
            // The setter above already re-renders; the template is part of the pack's display state.
            onTitleTemplateChange: {},
            onStyleChange: styleChange
        )
        let plot = HeatmapControlsModel(
            colorScaleMode: state.colorScaleMode,
            interpolationMode: state.interpolationMode,
            zDomainState: state.zDomainState,
            showColorbar: state.showColorbar,
            globalPlotDefaults: globalPlotDefaults,
            fontRoles: fontRoles,
            axes: axes,
            onStyleChange: styleChange,
            onColorScaleModeChange: { self.updateHeatmapColorScaleMode($0) },
            onInterpolationModeChange: { self.updateHeatmapInterpolationMode($0) },
            onZDomainStateChange: { self.updateHeatmapZDomainState($0) },
            onShowColorbarChange: { self.updateHeatmapShowColorbar($0) }
        )
        return WorkbenchControlsDescriptor(common: common, plot: .heatmap(plot), specific: specific)
    }
}
