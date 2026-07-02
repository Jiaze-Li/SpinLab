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
    ) -> (Data?, DualAxisPlotLayout?, DualAxisPlotPayload?, [String]) {
        guard let payload = makeTemperatureDependencePayload(result: result) else {
            return (nil, nil, nil, [])
        }

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
            return (output.imageData, output.layout, displayPayload, warnings)
        } catch {
            let reason = "dual-axis pipeline failure: \(error)"
            fputs("[SpinLab] ThreeOmegaPlotRenderer: \(reason)\n", stderr)
            return (nil, nil, nil, [reason])
        }
    }
}
