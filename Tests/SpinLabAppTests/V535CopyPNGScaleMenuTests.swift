import Foundation
import XCTest
import CoreGraphics
@testable import SpinLabApp

final class V535CopyPNGScaleMenuTests: XCTestCase {

    // MARK: - Structural alignment

    func testCopyPNGScalesCount() {
        XCTAssertEqual(WorkbenchPlotCanvas.copyPNGScales.count, 3)
    }

    func testCopyPNGScalesValues() {
        XCTAssertEqual(WorkbenchPlotCanvas.copyPNGScales, [1, 2, 3])
    }

    // MARK: - pixelScaleOverride field defaults

    func testPixelScaleOverrideDefaultNil() {
        let payload = makePayload()
        let input = WorkbenchRenderPipeline.Input(payload: payload)
        XCTAssertNil(input.pixelScaleOverride)
    }

    // MARK: - Output pixel dimensions = baseWidth × scale

    func testOutputWidthScalesWithOverride() throws {
        let payload = makePayload()
        let base = WorkbenchChartRenderer.Options() // width=800, height=600

        func renderWidth(_ scale: CGFloat) throws -> Int {
            var input = WorkbenchRenderPipeline.Input(payload: payload)
            input.baseOptions = base
            input.pixelScaleOverride = scale
            let output = try WorkbenchRenderPipeline.render(input)
            return pngPixelWidth(output.imageData)
        }

        let w1 = try renderWidth(1)
        let w2 = try renderWidth(2)
        let w3 = try renderWidth(3)
        XCTAssertEqual(w1, base.width * 1)
        XCTAssertEqual(w2, base.width * 2)
        XCTAssertEqual(w3, base.width * 3)
    }

    // MARK: - 2x fast path: same bytes as cached

    func testTwoXFastPathMatchesCachedData() throws {
        let payload = makePayload()
        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.pixelScaleOverride = 2
        let cached = try WorkbenchRenderPipeline.render(input).imageData

        // Simulate fast path: same pipeline at 2x should produce identical bytes.
        let again = try WorkbenchRenderPipeline.render(input).imageData
        XCTAssertEqual(cached, again,
            "2x renders with identical input must produce deterministic bytes for fast-path caching.")
    }

    // MARK: - 1x and 3x produce different dims than 2x

    func testOneXAndThreeXDifferFromTwoX() throws {
        let payload = makePayload()

        func renderWidth(_ scale: CGFloat) throws -> Int {
            var input = WorkbenchRenderPipeline.Input(payload: payload)
            input.pixelScaleOverride = scale
            return pngPixelWidth(try WorkbenchRenderPipeline.render(input).imageData)
        }

        let w1 = try renderWidth(1)
        let w2 = try renderWidth(2)
        let w3 = try renderWidth(3)
        XCTAssertNotEqual(w1, w2)
        XCTAssertNotEqual(w3, w2)
    }

    // MARK: - Helpers

    private func makePayload() -> WorkbenchPlotPayload {
        let series = WorkbenchPlotSeries(
            label: "A", x: [0, 1, 2], y: [1, 2, 3],
            pointLabels: ["p0", "p1", "p2"]
        )
        return WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Scale Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [series]
        )
    }

    private func pngPixelWidth(_ data: Data) -> Int {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int else { return 0 }
        return w
    }
}
