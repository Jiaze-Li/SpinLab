import Foundation
@testable import SpinLabApp

/// Test-only mirror of the runtime shared XY render route used by the ThreeOmega tabs
/// that thread hidden-series/order state generically through `tabState` rather than
/// baking it into the payload accessor itself (unlike the field-sweep tabs, see
/// `ThreeOmegaFieldSweepRenderRoute`): RAHE, RAHE-vs-Device (1ω/3ω), Hc-vs-T, RT, Scaling.
/// Mirrors `ThreeOmegaWorkspaceStore+Rendering.swift`'s `.rahe`/`.rahe1omegaVsDevice`/
/// `.rahe3omegaVsDevice`/`.hcVsT`/`.rtCurve`/`.scaling` cases: payload accessor →
/// `TabRenderManager.buildPipelineInput` → `WorkbenchRenderPipeline.render`. Exists so
/// tests that need an actual rendered `Data`/`WorkbenchPlotLayout`, or hidden-series
/// filtering as production performs it (generically, inside the pipeline via
/// `tabState.hiddenSeriesKeys`), can assert on the same shape the obsolete
/// `renderRAHE`/`renderRAHE1omegaVsDevice`/`renderRAHE3omegaVsDevice`/`renderHcVsT`/
/// `renderRT`/`renderScaling` returned, without resurrecting those entry points.
///
/// `TabRenderManager` is @MainActor-isolated, so callers must run on the main actor too.
@MainActor
enum ThreeOmegaSharedRenderRoute {
    static func render(
        payload: WorkbenchPlotPayload?,
        tab: ThreeOmegaWorkbenchTab,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = [],
        showPointTags: Bool = true
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payload else {
            return (nil, nil, nil, nil, [])
        }
        let manager = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: tab)
        let tabState = WorkbenchTabDisplayStateSnapshot(
            titleOverride: "",
            xLabelOverride: "",
            yLabelOverride: "",
            seriesLabelOverrides: [:],
            legendPoint: nil,
            hiddenSeriesKeys: hiddenSeriesKeys,
            hiddenPointLabelsBySeries: [:],
            seriesOrder: seriesOrder,
            axisRangeOverride: nil,
            showPointTags: showPointTags
        )
        let input = manager.buildPipelineInput(
            payload: payload,
            baseOptions: WorkbenchChartRenderer.Options(),
            tabState: tabState,
            showPlotGrid: manager.showPlotGrid,
            seriesRenderMode: manager.seriesRenderMode,
            chartStyleOverrides: manager.chartStyleOverrides,
            legendAnchor: manager.legendAnchor,
            for: tab
        )
        do {
            let output = try WorkbenchRenderPipeline.render(input)
            return (output.imageData, output.pdfData, output.layout, payload, output.warnings)
        } catch {
            // Matches ThreeOmegaWorkspaceStore+Rendering.swift's catch: on pipeline failure
            // the store reports only the failure warning.
            return (nil, nil, nil, nil, ["pipeline failure: \(error)"])
        }
    }
}
