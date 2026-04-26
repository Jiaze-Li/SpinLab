import Foundation
import XCTest
@testable import SpinLabApp

/// Regression for the 2x-PNG hit-test mapping: layout rects are in logical
/// renderer space (options.width × options.height), not the rendered image's
/// pixel space (logical × pixelScale). The on-screen mapping must divide by
/// the logical size, otherwise hit rects collapse to the upper-left quadrant.
final class V535HitRectScreenMappingTests: XCTestCase {

    func testCgToScreenUsesLogicalRendererSize() {
        let logical = CGSize(width: 800, height: 600)
        let fitted = CGRect(x: 0, y: 0, width: 800, height: 600)

        // Hit rect spanning the full plot width (in logical CG space).
        let cgRect = CGRect(x: 100, y: 540, width: 600, height: 30)

        let screen = WorkbenchPlotLayout.cgToScreen(
            cgRect,
            fittedIn: fitted,
            rendererWidth:  logical.width,
            rendererHeight: logical.height
        )

        XCTAssertEqual(screen.minX,  100, accuracy: 0.5)
        XCTAssertEqual(screen.width, 600, accuracy: 0.5)
        XCTAssertEqual(screen.height, 30, accuracy: 0.5)
    }

    func testCgToScreenWithImagePixelSizeWouldHalve() {
        // Demonstrates the broken mapping: passing pixel size (1600x1200)
        // for a layout authored in logical space (800x600) shrinks every rect
        // to half. This is exactly the regression we are guarding against.
        let pixelSize = CGSize(width: 1600, height: 1200)
        let fitted = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cgRect = CGRect(x: 100, y: 540, width: 600, height: 30)

        let broken = WorkbenchPlotLayout.cgToScreen(
            cgRect,
            fittedIn: fitted,
            rendererWidth:  pixelSize.width,
            rendererHeight: pixelSize.height
        )

        XCTAssertEqual(broken.width, 300, accuracy: 0.5)
        XCTAssertEqual(broken.height, 15, accuracy: 0.5)
    }

    func testLayoutTitleRectMapsToTopBand() {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "WF",
            title: "Title",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1])]
        )
        let layout = WorkbenchPlotLayout.compute(
            options: .init(),
            payload: payload,
            legendPoint: nil
        )

        XCTAssertEqual(layout.rendererSize.width,  800, accuracy: 0.001)
        XCTAssertEqual(layout.rendererSize.height, 600, accuracy: 0.001)

        let fitted = CGRect(x: 0, y: 0, width: 800, height: 600)
        let titleScreen = WorkbenchPlotLayout.cgToScreen(
            layout.titleHitRect,
            fittedIn: fitted,
            rendererWidth:  layout.rendererSize.width,
            rendererHeight: layout.rendererSize.height
        )

        XCTAssertLessThan(titleScreen.minY, 60)
        XCTAssertGreaterThan(titleScreen.width, 400)
    }
}
