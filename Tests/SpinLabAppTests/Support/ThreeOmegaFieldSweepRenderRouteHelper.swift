import Foundation
@testable import SpinLabApp

/// Test-only mirror of the runtime field-sweep render route
/// (`ThreeOmegaWorkspaceStore+Rendering.swift`'s `.fieldSweep1omega`/`.fieldSweep3omega`
/// cases): `makeR1omegaDisplayPayload`/`makeR3omegaDisplayPayload` →
/// `TabRenderManager.buildPipelineInput` → `WorkbenchRenderPipeline.render`.
///
/// Exists so tests that need an actual rendered `Data`/`WorkbenchPlotLayout` can assert
/// on the same `(imageData, pdfData, layout, displayPayload, warnings)` shape the obsolete
/// `renderR1omega`/`renderR3omega` returned, without resurrecting those entry points.
///
/// `seriesOrder`/`hiddenSeriesKeys` are threaded through twice, exactly like the runtime
/// route: once into the payload accessor (drives actual stacking/visibility) and again
/// into the pipeline `Input` via `WorkbenchTabDisplayStateSnapshot` (drives the
/// "seriesOrder mismatch" pipeline-level check). Does not model other tab-persisted
/// display state (title/axis overrides, legend position, axis range, tick overrides).
/// `TabRenderManager` is @MainActor-isolated, so callers must run on the main actor too.

@MainActor
enum ThreeOmegaFieldSweepRenderRoute {
    static func renderR1omega(
        renderer: ThreeOmegaPlotRenderer,
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        render(
            displayResult: renderer.makeR1omegaDisplayPayload(
                sweeps: sweeps,
                device: device,
                seriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys
            ),
            sweepCount: sweeps.count,
            tab: .fieldSweep1omega,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        )
    }

    static func renderR3omega(
        renderer: ThreeOmegaPlotRenderer,
        sweeps: [ThreeOmegaFieldSweepResult],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        render(
            displayResult: renderer.makeR3omegaDisplayPayload(
                sweeps: sweeps,
                device: device,
                seriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys
            ),
            sweepCount: sweeps.count,
            tab: .fieldSweep3omega,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        )
    }

    private static func render(
        displayResult: (payload: WorkbenchPlotPayload, warnings: [String])?,
        sweepCount: Int,
        tab: ThreeOmegaWorkbenchTab,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String]
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let displayResult else {
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
            showPointTags: true
        )
        let input = manager.buildPipelineInput(
            payload: displayResult.payload,
            baseOptions: ThreeOmegaPlotRenderer.stackedOptions(sweepCount: sweepCount),
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
            // Matches ThreeOmegaWorkspaceStore+Rendering.swift's catch: on pipeline failure
            // the store reports only the failure warning, not the payload-construction ones.
            return (nil, nil, nil, nil, ["pipeline failure: \(error)"])
        }
    }
}
