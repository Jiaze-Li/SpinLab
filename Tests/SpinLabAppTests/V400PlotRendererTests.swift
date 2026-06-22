import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SpinLabApp

final class V400WorkbenchPlotRendererTests: XCTestCase {

    private func v400PlotRendererRepoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testFormatTick_compactScientificCases() {
        let renderer = WorkbenchChartRenderer()

        XCTAssertEqual(renderer.formatTick(2.0e-4, step: 1.0e-4), "2e-4")
        XCTAssertEqual(renderer.formatTick(2.5e-4, step: 1.0e-4), "2.5e-4")
        XCTAssertEqual(renderer.formatTick(2.25e-4, step: 1.0e-4), "2.25e-4")
        XCTAssertEqual(renderer.formatTick(-1.0e-5, step: 1.0e-6), "-1e-5")
    }

    func testDenseSmallRangeXAxisReducesTickCount() {
        let renderer = WorkbenchChartRenderer()
        var style = WorkbenchChartStyle()
        style.tickTargetX = 6
        style.tickLabelFontSize = 19

        let result = renderer.resolvedXTicks(
            min: 2.0e-4,
            max: 2.6e-4,
            plotRect: CGRect(x: 0, y: 0, width: 40, height: 100),
            style: style
        )

        XCTAssertEqual(result.targetCount, 3)
        XCTAssertLessThan(result.targetCount, style.tickTargetX)
        XCTAssertGreaterThanOrEqual(result.ticks.count, 3)
    }

    func testResolvedOptionsDoesNotMutatePaddingLeftForAxisSpacing() {
        let renderer = WorkbenchChartRenderer()
        var style = WorkbenchChartStyle()
        style.tickLabelFontSize = 19

        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Tiny Y Values",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(
                    label: "series",
                    x: [0.0, 1.0],
                    y: [2.0e-4, 2.5e-4]
                )
            ]
        )
        let base = WorkbenchChartRenderer.Options()
        let resolved = renderer.resolvedOptions(payload: payload, base: base, style: style)

        XCTAssertEqual(resolved.paddingLeft, base.paddingLeft, accuracy: 0.001)
    }

    func testPlotFontOverridesFlowThroughStyleAndLegendLayout() {
        let style = WorkbenchChartStyle.from(styleParams: [
            "plotFontName": "AvenirNext-Regular",
            "plotBoldFontName": "AvenirNext-Bold",
        ])

        XCTAssertEqual(style.fontName, "AvenirNext-Regular")
        XCTAssertEqual(style.boldFontName, "AvenirNext-Bold")

        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Font Check",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(
                    label: "series",
                    x: [0.0, 1.0],
                    y: [0.0, 1.0]
                )
            ]
        )
        let layout = WorkbenchPlotLayout.compute(
            options: .init(),
            payload: payload,
            legendPoint: nil,
            style: style
        )

        XCTAssertEqual(layout.legendStyle.fontName, style.fontName)
    }

    func testMathAxisLabelsRenderThroughMathMarkup() throws {
        let renderer = WorkbenchChartRenderer()
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Math Labels",
            axisMapping: WorkbenchAxisMapping(
                xField: ThreeOmegaPlotRenderer.scalingXAxisLabel,
                yField: ThreeOmegaPlotRenderer.scalingYAxisLabel
            ),
            series: [
                WorkbenchPlotSeries(label: "series", x: [0.0, 1.0], y: [1.0, 2.0])
            ]
        )

        let data = try renderer.renderPNG(payload: payload)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(
            PlotTextMeasurer.measuredWidth(
                ThreeOmegaPlotRenderer.scalingXAxisLabel,
                fontSize: WorkbenchChartStyle().axisTitleFontSize,
                fontName: WorkbenchChartStyle().fontName
            ),
            PlotTextMeasurer.measuredWidth(
                MathMarkupRenderer.extractMathMarkup(ThreeOmegaPlotRenderer.scalingXAxisLabel),
                fontSize: WorkbenchChartStyle().axisTitleFontSize,
                fontName: WorkbenchChartStyle().fontName
            )
        )
        XCTAssertEqual(
            PlotTextMeasurer.measuredWidth(
                ThreeOmegaPlotRenderer.scalingYAxisLabel,
                fontSize: WorkbenchChartStyle().axisTitleFontSize,
                fontName: WorkbenchChartStyle().fontName
            ),
            PlotTextMeasurer.measuredWidth(
                MathMarkupRenderer.extractMathMarkup(ThreeOmegaPlotRenderer.scalingYAxisLabel),
                fontSize: WorkbenchChartStyle().axisTitleFontSize,
                fontName: WorkbenchChartStyle().fontName
            )
        )
    }

    func testRenderPNGUsesRequestedPixelScaleForScalingPayload() throws {
        let renderer = WorkbenchChartRenderer()
        let scalingRenderer = ThreeOmegaPlotRenderer()
        let result = ThreeOmegaScalingResult(
            points: [
                ThreeOmegaScalingPoint(temperatureK: 300, sigma2xx: 1.25e12, scalingY: 3.5e-4)
            ],
            segments: []
        )
        let payload = try XCTUnwrap(
            scalingRenderer.makeScalingPayload(result: result, device: "Device", method: "(HFE)")
        )

        XCTAssertFalse(payload.series.isEmpty)
        XCTAssertGreaterThan(payload.series[0].x.count, 0)

        let logicalSize = CGSize(width: WorkbenchChartRenderer.Options().width,
                                 height: WorkbenchChartRenderer.Options().height)

        for scale in [1.0, 2.0, 3.0] as [CGFloat] {
            var opts = WorkbenchChartRenderer.Options()
            opts.pixelScale = scale
            let data = try renderer.renderPNG(payload: payload, options: opts)
            XCTAssertFalse(data.isEmpty)
            let pixelSize = pngPixelSize(data)
            XCTAssertEqual(pixelSize.width, Int((logicalSize.width * scale).rounded()))
            XCTAssertEqual(pixelSize.height, Int((logicalSize.height * scale).rounded()))
        }
    }

    func testWorkbenchChartRendererLatexBranchDoesNotFallbackToRawSource() throws {
        let src = try String(
            contentsOf: v400PlotRendererRepoRoot()
                .appendingPathComponent("Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(src.contains("LatexAxisLabelRenderer"))
        XCTAssertFalse(src.contains("LatexAxisLabelRendering"))
        XCTAssertFalse(src.contains("raw LaTeX suppressed"))
        XCTAssertFalse(src.contains("[LatexAxisLabel]"))
        XCTAssertFalse(src.contains("latexAxisLabelRenderer"))
    }

    private func pngPixelSize(_ data: Data) -> (width: Int, height: Int) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            return (0, 0)
        }
        return (w, h)
    }
}
