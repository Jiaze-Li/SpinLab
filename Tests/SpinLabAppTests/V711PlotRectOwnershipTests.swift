import Foundation
import XCTest
@testable import SpinLabApp

/// Gate 7.11E — WorkbenchPlotLayout is the single owner of plotRect geometry.
/// WorkbenchChartRenderer.drawCanvas no longer recomputes plotRect locally;
/// it consumes layout.plotRect exclusively.
final class V711PlotRectOwnershipTests: XCTestCase {

    /// layout.plotRect must match the padding-derived formula the renderer previously duplicated.
    func testLayoutPlotRectMatchesPaddingMath() {
        var opts = WorkbenchChartRenderer.Options()
        opts.paddingLeft   = 120
        opts.paddingRight  = 40
        opts.paddingTop    = 80
        opts.paddingBottom = 100

        let layout = WorkbenchPlotLayout.compute(
            options: opts,
            payload: minimalPayload(),
            legendPoint: nil
        )

        let expected = CGRect(
            x: 120, y: 100,
            width:  CGFloat(opts.width)  - 120 - 40,
            height: CGFloat(opts.height) - 80  - 100
        )
        XCTAssertEqual(layout.plotRect, expected)
    }

    /// Pipeline path: renderPNG with an explicit externalLayout must not crash,
    /// and the layout's plotRect must honour the custom padding options.
    func testExternalLayoutPlotRectHonoursCustomPadding() throws {
        var opts = WorkbenchChartRenderer.Options()
        opts.paddingLeft   = 120
        opts.paddingRight  = 40
        opts.paddingTop    = 80
        opts.paddingBottom = 100

        let payload = minimalPayload()
        let externalLayout = WorkbenchPlotLayout.compute(
            options: opts, payload: payload, legendPoint: nil
        )

        XCTAssertEqual(externalLayout.plotRect.origin.x, 120, accuracy: 0.001)
        XCTAssertEqual(externalLayout.plotRect.origin.y, 100, accuracy: 0.001)
        XCTAssertEqual(externalLayout.plotRect.width,
                       CGFloat(opts.width) - 120 - 40, accuracy: 0.001)
        XCTAssertEqual(externalLayout.plotRect.height,
                       CGFloat(opts.height) - 80 - 100, accuracy: 0.001)

        let renderer = WorkbenchChartRenderer()
        _ = try renderer.renderPNG(payload: payload, options: opts, layout: externalLayout)
    }

    private func minimalPayload() -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [WorkbenchPlotSeries(label: "S", x: [1.0, 2.0], y: [3.0, 4.0])]
        )
    }
}
