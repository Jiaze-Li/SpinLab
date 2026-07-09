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
/// Does not model tab-persisted display state (series order overrides, hidden series
/// persistence, legend position) — pass `seriesOrder`/`hiddenSeriesKeys` explicitly per call.
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
            tab: .fieldSweep1omega
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
            tab: .fieldSweep3omega
        )
    }

    private static func render(
        displayResult: (payload: WorkbenchPlotPayload, warnings: [String])?,
        sweepCount: Int,
        tab: ThreeOmegaWorkbenchTab
    ) -> (Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let displayResult else {
            return (nil, nil, nil, nil, [])
        }
        let manager = TabRenderManager<ThreeOmegaWorkbenchTab>(defaultTab: tab)
        let input = manager.buildPipelineInput(
            payload: displayResult.payload,
            baseOptions: ThreeOmegaPlotRenderer.stackedOptions(sweepCount: sweepCount),
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
