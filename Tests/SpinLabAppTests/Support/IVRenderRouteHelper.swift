import Foundation
@testable import SpinLabApp

/// Test-only mirror of the runtime IV render route
/// (`IVWorkspaceStore._rerenderActiveTab`):
/// `makeFirstHarmonicPayloads`/`makeSecondHarmonicPayloads` →
/// `TabRenderManager.buildPipelineInput` → `WorkbenchRenderPipeline.render`.
///
/// Exists so tests that need an actual rendered `Data`/`WorkbenchPlotLayout` can assert
/// on the same `(Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String])` shape the
/// obsolete `renderFirstHarmonicVsCurrent`/`renderSecondHarmonicVsCurrent` returned,
/// without resurrecting those entry points.
///
/// `seriesOrder` comes from the renderer's own `seriesOrder` property (set by callers the
/// same way `IVWorkspaceStore._snapshotRenderer` does), threaded into the pipeline
/// `Input` via `WorkbenchTabDisplayStateSnapshot` — this drives the "seriesOrder
/// mismatch" pipeline-level check exactly like the runtime route. Does not model other
/// tab-persisted display state (title/axis overrides, legend position, axis range, tick
/// overrides). `TabRenderManager` is @MainActor-isolated, so callers must run on the main
/// actor too.

@MainActor
enum IVRenderRoute {
    static func renderFirstHarmonicVsCurrent(
        renderer: IVPlotRenderer,
        sweeps: [IVSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        var renderer = renderer
        return render(
            payloads: renderer.makeFirstHarmonicPayloads(
                sweeps: sweeps,
                device: device,
                hiddenSeriesKeys: hiddenSeriesKeys
            ),
            tab: .voltage,
            seriesOrder: renderer.seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        )
    }

    static func renderSecondHarmonicVsCurrent(
        renderer: IVPlotRenderer,
        sweeps: [IVSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        var renderer = renderer
        return render(
            payloads: renderer.makeSecondHarmonicPayloads(
                sweeps: sweeps,
                device: device,
                hiddenSeriesKeys: hiddenSeriesKeys
            ),
            tab: .resistance,
            seriesOrder: renderer.seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        )
    }

    private static func render(
        payloads: IVPlotRenderer.StackedIVPayloads?,
        tab: IVWorkbenchTab,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String]
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payloads else {
            return (nil, nil, nil, [])
        }
        let manager = TabRenderManager<IVWorkbenchTab>(defaultTab: tab)
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
            payload: payloads.displayPayload,
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
                output.layout,
                payloads.displayPayload,
                output.warnings + payloads.warnings
            )
        } catch {
            // Matches IVPlotRenderer's catch: on pipeline failure the store reports
            // only the failure warning, not the payload-construction ones.
            return (nil, nil, nil, ["pipeline failure: \(error)"])
        }
    }
}
