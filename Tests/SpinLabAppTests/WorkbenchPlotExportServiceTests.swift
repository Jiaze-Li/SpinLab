import Foundation
import ImageIO
import XCTest
import CoreGraphics
@testable import SpinLabApp

// MARK: - WorkbenchPlotExportService contract tests
//
// Guards the cross-workflow export service contract:
//   - displayPayload present → re-render at requested scale (not sentinel imageData).
//   - displayPayload nil → return sentinel imageData.
//   - Empty render result → fall back to sentinel imageData.
//   - 1x / 2x / 3x differ only by pixel dimensions.

final class WorkbenchPlotExportServiceTests: XCTestCase {

    // MARK: - 1. displayPayload present → does not return sentinel

    func testDisplayPayloadPresentRendersRealPNG() throws {
        let sentinel = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: sentinel,
            displayPayload: makePayload(),
            layout: nil,
            tabState: TabRenderState(),
            showGrid: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )
        let result = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))
        XCTAssertNotEqual(result, sentinel, "Service must render from displayPayload, not return sentinel imageData")
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - 2. displayPayload nil → returns sentinel imageData

    func testNilDisplayPayloadReturnsSentinel() {
        let sentinel = Data([0xFA, 0x11, 0xBA, 0xCF])
        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: sentinel,
            displayPayload: nil,
            layout: nil,
            tabState: TabRenderState(),
            showGrid: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )
        XCTAssertEqual(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0), sentinel)
        XCTAssertEqual(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 2.0), sentinel)
        XCTAssertEqual(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 3.0), sentinel)
    }

    // MARK: - 3. 1x / 2x / 3x differ only in pixel dimensions

    func testScalesDifferOnlyInPixelDimensions() throws {
        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: nil,
            displayPayload: makePayload(),
            layout: nil,
            tabState: TabRenderState(),
            showGrid: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )
        let png1 = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))
        let png2 = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 2.0))
        let png3 = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 3.0))

        let w1 = pngPixelWidth(png1)
        XCTAssertGreaterThan(w1, 0)
        XCTAssertEqual(pngPixelWidth(png2), w1 * 2, "2x must be 2× the pixel width of 1x")
        XCTAssertEqual(pngPixelWidth(png3), w1 * 3, "3x must be 3× the pixel width of 1x")
    }

    // MARK: - 4. Layout size is respected

    func testLayoutSizeMatchesRenderedDimensions() throws {
        let payload = makePayload()
        let layout = WorkbenchPlotLayout.compute(
            options: .init(), payload: payload, legendPoint: nil,
            style: .from(styleParams: [:]), seriesLabelOverrides: [:]
        )
        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: nil,
            displayPayload: payload,
            layout: layout,
            tabState: TabRenderState(),
            showGrid: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )
        let png1x = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))
        let expectedWidth = Int(layout.rendererSize.width.rounded())
        XCTAssertEqual(pngPixelWidth(png1x), expectedWidth, "1x export width must match layout rendererSize")
    }

    // MARK: - 5. 3ω stacked Copy PNG matches visible render

    func testStackedThreeOmegaCopyPNGMatchesVisibleRender() throws {
        let renderer = ThreeOmegaPlotRenderer()
        let sweeps = makeStackedThreeOmegaSweeps()
        let payload = try XCTUnwrap(renderer.makeR1omegaPayload(sweeps: sweeps, device: "0deg"))
        var visibleInput = WorkbenchRenderPipeline.Input(payload: payload)
        visibleInput.pixelScaleOverride = 1.0
        let visibleOutput = try WorkbenchRenderPipeline.render(visibleInput)

        let snapshot = WorkbenchPlotExportSnapshot(
            imageData: visibleOutput.imageData,
            displayPayload: payload,
            layout: visibleOutput.layout,
            tabState: TabRenderState(),
            showGrid: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            globalPlotDefaults: [:]
        )

        let exported = try XCTUnwrap(WorkbenchPlotExportService.exportPNG(snapshot: snapshot, scale: 1.0))
        let visiblePixels = try XCTUnwrap(pngPixels(visibleOutput.imageData))
        let exportedPixels = try XCTUnwrap(pngPixels(exported))
        XCTAssertEqual(exportedPixels.width, visiblePixels.width)
        XCTAssertEqual(exportedPixels.height, visiblePixels.height)
        XCTAssertEqual(exportedPixels.pixels, visiblePixels.pixels, "Copy PNG must match the visible 3ω render when given the workflow payload")
    }

    // MARK: - Helpers

    private func makePayload() -> WorkbenchPlotPayload {
        let series = WorkbenchPlotSeries(label: "S", x: [0, 1, 2], y: [1.0, 2.0, 1.5])
        return WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Export Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [series]
        )
    }

    private func makeStackedThreeOmegaSweeps() -> [ThreeOmegaFieldSweepResult] {
        [10, 30, 50, 70, 90, 110].map(makeStackedThreeOmegaSweep)
    }

    private func makeStackedThreeOmegaSweep(_ temperatureK: Int) -> ThreeOmegaFieldSweepResult {
        let temperature = Double(temperatureK)
        let sourceFilePath = "/tmp/\(temperatureK).csv"
        return ThreeOmegaFieldSweepResult(
            temperatureK: temperature,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-\(temperatureK)",
            sourceFilePath: sourceFilePath,
            hField: [-1000, 0, 1000],
            r1omega: [temperature, temperature + 1, temperature + 2],
            r3omega: [temperature / 10.0, temperature / 10.0 + 1, temperature / 10.0 + 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
    }

    private func pngPixelWidth(_ data: Data) -> Int {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int else { return 0 }
        return w
    }

    private func pngPixels(_ data: Data) -> (width: Int, height: Int, pixels: [UInt8])? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let result = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard result else { return nil }
        return (width: width, height: height, pixels: pixels)
    }
}
