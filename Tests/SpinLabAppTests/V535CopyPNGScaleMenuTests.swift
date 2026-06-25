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

    // MARK: - Deterministic render output

    func testRenderPipelineIsDeterministicForIdenticalInput() throws {
        let payload = makePayload()
        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.pixelScaleOverride = 2
        let first = try WorkbenchRenderPipeline.render(input).imageData

        // Identical render input should produce identical PNG bytes.
        let second = try WorkbenchRenderPipeline.render(input).imageData
        XCTAssertEqual(first, second,
            "Renders with identical input must produce deterministic PNG bytes.")
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

    // MARK: - 3ω scaling: renderScaling stores displayPayload

    func testRenderScalingReturnsDisplayPayload() {
        var renderer = ThreeOmegaPlotRenderer()
        let (_, _, displayPayload, _) = renderer.renderScaling(result: makeScalingResult(), device: "Device", method: "(HFE)")
        XCTAssertNotNil(displayPayload, "renderScaling must return a non-nil displayPayload when points are non-empty")
        XCTAssertFalse(displayPayload?.series.isEmpty ?? true, "scaling displayPayload must contain series data")
    }

    // MARK: - 3ω scaling: copyCurrentPlotPNG uses WorkbenchPlotExportService path

    @MainActor
    func testScalingCopyPNGUsesStoredDisplayPayload() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .scaling

        var renderer = ThreeOmegaPlotRenderer()
        let (_, layout, displayPayload, _) = renderer.renderScaling(result: makeScalingResult(), device: "Device", method: "(HFE)")
        XCTAssertNotNil(layout)
        XCTAssertNotNil(displayPayload)

        let sentinel = Data([0xDE, 0xAD, 0xBE, 0xEF])
        store.tabs.setOutput(
            TabRenderOutput(imageData: sentinel, layout: layout, manifestPayload: nil, displayPayload: displayPayload),
            for: .scaling
        )

        for scale in [1.0, 2.0, 3.0] as [CGFloat] {
            let data = try XCTUnwrap(store.copyCurrentPlotPNG(scale: scale))
            XCTAssertNotEqual(data, sentinel, "\(scale)x must render from displayPayload, not sentinel imageData")
            XCTAssertFalse(data.isEmpty)
        }
    }

    // MARK: - 3ω scaling: 1x / 2x / 3x have correct pixel-size ratios

    @MainActor
    func testScalingCopyPNGPixelRatios() throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .scaling

        var renderer = ThreeOmegaPlotRenderer()
        let (imageData, layout, displayPayload, _) = renderer.renderScaling(result: makeScalingResult(), device: "Device", method: "(HFE)")
        store.tabs.setOutput(
            TabRenderOutput(imageData: imageData, layout: layout, manifestPayload: nil, displayPayload: displayPayload),
            for: .scaling
        )

        let png1x = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 1.0))
        let png2x = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 2.0))
        let png3x = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 3.0))

        let w1 = pngPixelWidth(png1x)
        XCTAssertGreaterThan(w1, 0)
        XCTAssertEqual(pngPixelWidth(png2x), w1 * 2, "2x scaling export width must be 2× that of 1x")
        XCTAssertEqual(pngPixelWidth(png3x), w1 * 3, "3x scaling export width must be 3× that of 1x")
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
