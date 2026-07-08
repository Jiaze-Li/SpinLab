import CoreGraphics
import Foundation

extension ThreeOmegaPlotRenderer {
    /// Temperature Dependence render path that consumes the Plot System-owned
    /// DualAxis display-state snapshot. This keeps 3ω physics payload construction
    /// separate from generic DualAxis display controls.
    mutating func renderTemperatureDependence(
        result: ThreeOmegaScalingResult,
        displayState: DualAxisDisplayStateSnapshot,
        legendPoint: CGPoint? = nil
    ) -> (Data?, Data?, DualAxisPlotLayout?, DualAxisPlotPayload?, [String]) {
        guard var payload = makeTemperatureDependencePayload(result: result) else {
            return (nil, nil, nil, nil, [])
        }

        var tokens = titleTokens
        tokens["tab"] = "Temperature Dependence"
        let resolvedTitle = WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
        // An empty/invalid template must not blank the chart title — DualAxisChartRenderer
        // skips drawing entirely when payload.title is empty (unlike WorkbenchPlotLayout,
        // which falls back to workflowDisplayName at layout-compute time).
        payload.title = resolvedTitle.isEmpty ? "Temperature Dependence" : resolvedTitle

        var warnings: [String] = []
        let style = WorkbenchChartStyle.from(
            styleParams: globalPlotDefaults.merging(chartStyleOverrides) { _, new in new }
        )
        let input = DualAxisRenderPipeline.Input(
            payload: payload,
            style: style,
            legendPoint: legendPoint,
            displayState: displayState
        )

        do {
            let output = try DualAxisRenderPipeline.render(input)
            warnings.append(contentsOf: output.warnings)
            let displayPayload = displayState.applying(to: payload)
            return (output.imageData, output.pdfData, output.layout, displayPayload, warnings)
        } catch {
            let reason = "dual-axis pipeline failure: \(error)"
            fputs("[SpinLab] ThreeOmegaPlotRenderer: \(reason)\n", stderr)
            return (nil, nil, nil, nil, [reason])
        }
    }
}
