import CoreGraphics
import Foundation
import XCTest
@testable import SpinLabApp

private func v400PlotRendererRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SpinLabAppTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

final class V400WorkbenchPlotRendererTests: XCTestCase {

    private final class RecordingLatexAxisLabelRenderer: LatexAxisLabelRendering {
        struct Call {
            let latex: String
            let orientation: LatexAxisLabelRenderer.Orientation
        }

        var calls: [Call] = []
        var shouldSucceed = true

        func draw(
            ctx: CGContext,
            latex: String,
            fontSize: CGFloat,
            color: CGColor,
            at center: CGPoint,
            orientation: LatexAxisLabelRenderer.Orientation
        ) -> Bool {
            calls.append(Call(latex: latex, orientation: orientation))
            return shouldSucceed
        }
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

        // Scientific-notation Y values produce wide tick labels — the old renderer-side
        // padding formula would inflate paddingLeft here. Verify it no longer does.
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

        // Axis spacing is owned exclusively by PlotAxisLayoutPlan; resolvedOptions must be a pass-through.
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

    func testMathAxisLabelsBypassLatexRenderer() throws {
        let spy = RecordingLatexAxisLabelRenderer()
        let renderer = WorkbenchChartRenderer(latexAxisLabelRenderer: spy)
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

        _ = try renderer.renderPNG(payload: payload)

        XCTAssertTrue(spy.calls.isEmpty)
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

    func testWorkbenchChartRendererLatexBranchDoesNotFallbackToRawSource() throws {
        let src = try String(
            contentsOf: v400PlotRendererRepoRoot()
                .appendingPathComponent("Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(src.contains("latexAxisLabelRenderer.draw("))
        XCTAssertTrue(src.contains("raw LaTeX suppressed"))
        XCTAssertFalse(src.contains("let fallback = latex"))
        XCTAssertFalse(src.contains("LatexAxisLabelRenderer.shared.draw("))
    }
}
