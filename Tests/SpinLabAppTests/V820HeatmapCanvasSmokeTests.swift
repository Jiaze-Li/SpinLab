import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Demo payload

private func makeDemoPayload() -> HeatmapPlotPayload {
    let grid = HeatmapGrid(
        xValues: [0.0, 1.0, 2.0],
        yValues: [0.0, 1.0, 2.0],
        zMatrix: [
            [0.10, 0.40, 0.70],
            [0.20, 0.50, 0.80],
            [0.30, 0.60, 0.90],
        ]
    )
    return HeatmapPlotPayload(
        workflowID: "demo",
        title: "Smoke Heatmap",
        xLabel: "X",
        yLabel: "Y",
        zLabel: "Z",
        grid: grid,
        colormapKey: nil,
        zRangeClamp: nil
    )
}

private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

// MARK: - Gate E: Canvas smoke integration

@Suite("Heatmap Canvas Smoke Integration")
struct V820HeatmapCanvasSmokeTests {

    // HeatmapRenderPipeline produces non-empty, valid PNG bytes from a fake payload.
    @Test func heatmapPipelineProducesValidPNG() throws {
        let output = try HeatmapRenderPipeline.render(.init(payload: makeDemoPayload()))
        #expect(output.imageData.count > 1000)
        #expect(output.imageData.prefix(8) == pngSignature)
    }

    // WorkbenchPlotCanvas accepts heatmap imageData with nil layout (V1 contract).
    @Test func canvasInstantiatesWithHeatmapDataAndNilLayout() throws {
        let output = try HeatmapRenderPipeline.render(.init(payload: makeDemoPayload()))
        let canvas = WorkbenchPlotCanvas(imageData: output.imageData, layout: nil)
        #expect(canvas.layout == nil)
        #expect(canvas.imageData == output.imageData)
    }

    // XY-specific interaction callbacks are absent on the heatmap canvas path.
    @Test func xyInteractionsAreInactiveForHeatmap() throws {
        let output = try HeatmapRenderPipeline.render(.init(payload: makeDemoPayload()))
        let canvas = WorkbenchPlotCanvas(imageData: output.imageData, layout: nil)
        #expect(canvas.onLegendDrag == nil)
        #expect(canvas.onTogglePointLabelVisibility == nil)
        #expect(canvas.seriesPayload == nil)
    }

    // Pipeline output contains a HeatmapPlotLayout, but V1 passes nil to the canvas.
    @Test func v1PassesNilLayoutToCanvas() throws {
        let output = try HeatmapRenderPipeline.render(.init(payload: makeDemoPayload()))
        // Pipeline produces a layout (used internally); canvas receives nil per V1 contract.
        #expect(output.imageData.count > 0)
        let canvas = WorkbenchPlotCanvas(imageData: output.imageData, layout: nil)
        #expect(canvas.layout == nil)
    }
}
