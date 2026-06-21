import Foundation
import ImageIO
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

    @MainActor
    func testCopyCurrentPlotPNGUsesScalingPayloadForAllScales() throws {
        let store = ThreeOmegaWorkspaceStore()
        store.tabs.activeTab = .scaling
        store.v3Method = .highField
        store.ingestionResult = ThreeOmegaIngestionResult(device: "Device")
        store.scalingResult = makeScalingResult()

        var renderer = ThreeOmegaPlotRenderer()
        let (_, layout, _) = renderer.renderScaling(result: makeScalingResult(), device: "Device", method: "(HFE)")
        XCTAssertNotNil(layout)

        store.tabs.setOutput(
            TabRenderOutput(
                imageData: Data(),
                layout: layout,
                manifestPayload: makeEmptyScalingManifestPayload()
            ),
            for: .scaling
        )

        let logicalSize = layout?.rendererSize ?? CGSize(width: 800, height: 600)
        for scale in [1.0, 2.0, 3.0] as [CGFloat] {
            let data = try XCTUnwrap(store.copyCurrentPlotPNG(scale: scale))
            XCTAssertFalse(data.isEmpty)
            XCTAssertEqual(pngPixelSize(data).width, Int((logicalSize.width * scale).rounded()))
            XCTAssertEqual(pngPixelSize(data).height, Int((logicalSize.height * scale).rounded()))
        }
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

    private func makeScalingResult() -> ThreeOmegaScalingResult {
        let point = ThreeOmegaScalingPoint(temperatureK: 300, sigma2xx: 1.25e12, scalingY: 3.5e-4)
        let segment = ThreeOmegaScalingSegment(
            id: UUID(),
            tLo: 200,
            tHi: 400,
            alpha: 0.0,
            beta: 3.5e-24,
            rSquared: 1.0,
            pointCount: 1,
            participatingXValues: [1.25e12]
        )
        return ThreeOmegaScalingResult(points: [point], segments: [segment])
    }

    private func makeEmptyScalingManifestPayload() -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "Scaling Law",
            axisMapping: WorkbenchAxisMapping(
                xField: ThreeOmegaPlotRenderer.scalingXAxisLabel,
                yField: ThreeOmegaPlotRenderer.scalingYAxisLabel
            ),
            series: []
        )
    }

    private func pngPixelSize(_ data: Data) -> (width: Int, height: Int) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return (0, 0) }
        return (w, h)
    }

    private func pngPixelWidth(_ data: Data) -> Int {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int else { return 0 }
        return w
    }
}
