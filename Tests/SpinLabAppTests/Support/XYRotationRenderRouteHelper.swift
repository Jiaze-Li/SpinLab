import Foundation
@testable import SpinLabApp

/// Test-only mirror of the runtime XY Rotation render route
/// (`XYRotationWorkspaceStore._buildTabRenderPlan`/`_rerenderActiveTab`):
/// `makeRxxVsPhiDisplayPayload`/`makeRxyVsPhiDisplayPayload` →
/// `TabRenderManager.buildPipelineInput` → `WorkbenchRenderPipeline.render`.
///
/// Exists so tests that need an actual rendered `Data`/`WorkbenchPlotLayout` can assert
/// on the same `(imageData, pdfData, layout, displayPayload, warnings)` shape the obsolete
/// `renderRxxVsPhi`/`renderRxyVsPhi` returned, without resurrecting those entry points.
///
/// `seriesOrder`/`hiddenSeriesKeys` are threaded through twice, exactly like the runtime
/// route: once into the payload accessor (drives actual stacking/visibility) and again
/// into the pipeline `Input` via `WorkbenchTabDisplayStateSnapshot` (drives the
/// "seriesOrder mismatch" pipeline-level check). Does not model other tab-persisted
/// display state (title/axis overrides, legend position, axis range, tick overrides).
/// `TabRenderManager` is @MainActor-isolated, so callers must run on the main actor too.

@MainActor
enum XYRotationRenderRoute {
    static func renderRxxVsPhi(
        renderer: XYRotationPlotRenderer,
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        render(
            displayResult: renderer.makeRxxVsPhiDisplayPayload(
                sweeps: sweeps,
                device: device,
                seriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys
            ),
            sweepCount: sweeps.count,
            tab: .rxxVsPhi,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        )
    }

    static func renderRxyVsPhi(
        renderer: XYRotationPlotRenderer,
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        let rxySweeps = sweeps.filter { $0.resistanceXY != nil }
        return render(
            displayResult: renderer.makeRxyVsPhiDisplayPayload(
                sweeps: rxySweeps,
                device: device,
                seriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys
            ),
            sweepCount: rxySweeps.count,
            tab: .rxyVsPhi,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        )
    }

    private static func render(
        displayResult: (payload: WorkbenchPlotPayload, warnings: [String])?,
        sweepCount: Int,
        tab: XYRotationWorkbenchTab,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String]
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let displayResult else {
            return (nil, nil, nil, nil, [])
        }
        let manager = TabRenderManager<XYRotationWorkbenchTab>(defaultTab: tab)
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
            showPointTags: true
        )
        let input = manager.buildPipelineInput(
            payload: displayResult.payload,
            baseOptions: XYRotationPlotRenderer.stackedOptions(sweepCount: sweepCount),
            tabState: tabState,
            showPlotGrid: manager.showPlotGrid,
            seriesRenderMode: manager.seriesRenderMode,
            chartStyleOverrides: manager.chartStyleOverrides,
            legendAnchor: manager.legendAnchor,
            for: tab
        )
        do {
            let output = try WorkbenchRenderPipeline.render(input)
            return (
                output.imageData,
                output.pdfData,
                output.layout,
                displayResult.payload,
                output.warnings + displayResult.warnings
            )
        } catch {
            // Matches XYRotationPlotRenderer's catch: on pipeline failure the store
            // reports only the failure warning, not the payload-construction ones.
            return (nil, nil, nil, nil, ["pipeline failure: \(error)"])
        }
    }
}
