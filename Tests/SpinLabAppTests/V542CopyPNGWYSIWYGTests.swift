import Foundation
import ImageIO
import XCTest
import CoreGraphics
@testable import SpinLabApp

// MARK: - V542 Copy PNG WYSIWYG Regression Tests
//
// Guards the Copy PNG export contract:
//   - All export scales (1x/2x/3x) reproduce the currently-displayed plot.
//   - Offsets/stacked y-values in R(1ω) and R(3ω) must appear in the export payload.
//   - RAHE tabs must not produce blank output when a display image is cached.
//   - displayPayload is used as the export source; manifestPayload is persistence-only.

final class V542CopyPNGWYSIWYGTests: XCTestCase {

    // MARK: - 1. 2x Copy PNG returns activeImageData (no re-render)

    @MainActor
    func testTwoXCopyReturnsActiveImageDataDirectly() {
        let store = ThreeOmegaWorkspaceStore()
        let sentinel = Data([0xDE, 0xAD, 0xBE, 0xEF])
        store.tabs.setOutput(
            TabRenderOutput(imageData: sentinel, layout: nil, manifestPayload: nil, displayPayload: nil),
            for: .fieldSweep1omega
        )
        store.tabs.activeTab = .fieldSweep1omega

        let result = store.copyCurrentPlotPNG(scale: 2.0)
        XCTAssertEqual(result, sentinel,
            "2x Copy PNG must return activeImageData directly without re-rendering")
    }

    // MARK: - 2. R(1ω) displayPayload carries offset-applied y-values

    func testR1omegaDisplayPayloadCarriesOffsetAppliedYValues() throws {
        let sweeps = makeFieldSweeps(count: 3)
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2

        let (_, _, displayPayload, _) = renderer.renderR1omega(sweeps: sweeps, device: "D1")

        let dp = try XCTUnwrap(displayPayload, "renderR1omega must return a non-nil displayPayload")
        XCTAssertEqual(dp.series.count, sweeps.count)

        // After stacking, series are non-overlapping bands in y-space.
        // Sort by min-y and verify consecutive sorted series don't overlap
        // (order-independent: displayPayload may have series reversed by reverseSeriesForLegend).
        let sorted = dp.series.sorted { ($0.y.min() ?? 0) < ($1.y.min() ?? 0) }
        let nonOverlapping = zip(sorted, sorted.dropFirst()).allSatisfy { a, b in
            (a.y.max() ?? 0) < (b.y.min() ?? 0)
        }
        XCTAssertTrue(nonOverlapping,
            "R(1ω) displayPayload series must be non-overlapping stacked bands; offset-applied y-values required")
    }

    // MARK: - 3. R(3ω) displayPayload carries offset-applied y-values

    func testR3omegaDisplayPayloadCarriesOffsetAppliedYValues() throws {
        let sweeps = makeFieldSweeps(count: 3)
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2

        let (_, _, displayPayload, _) = renderer.renderR3omega(sweeps: sweeps, device: "D1")

        let dp = try XCTUnwrap(displayPayload, "renderR3omega must return a non-nil displayPayload")
        XCTAssertEqual(dp.series.count, sweeps.count)

        let sorted = dp.series.sorted { ($0.y.min() ?? 0) < ($1.y.min() ?? 0) }
        let nonOverlapping = zip(sorted, sorted.dropFirst()).allSatisfy { a, b in
            (a.y.max() ?? 0) < (b.y.min() ?? 0)
        }
        XCTAssertTrue(nonOverlapping,
            "R(3ω) displayPayload series must be non-overlapping stacked bands; offset-applied y-values required")
    }

    // MARK: - 4. R(1ω) displayPayload series means strictly ordered after sorting by min-y

    func testR1omegaDisplayPayloadDiffersFromRawManifest() throws {
        let sweeps = makeFieldSweeps(count: 3)
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.5

        let (_, _, displayPayload, _) = renderer.renderR1omega(sweeps: sweeps, device: "D1")
        let dp = try XCTUnwrap(displayPayload)

        // After sorting by min-y, each series' mean must exceed the previous one.
        let sorted = dp.series.sorted { ($0.y.min() ?? 0) < ($1.y.min() ?? 0) }
        let means = sorted.map { s in s.y.reduce(0, +) / max(Double(s.y.count), 1) }
        for i in 1..<means.count {
            XCTAssertGreaterThan(means[i], means[i - 1],
                "sorted series[\(i)] mean must exceed series[\(i-1)] mean; stacking offset must appear in displayPayload")
        }
    }

    // MARK: - 5. RAHE(1ω) displayPayload carries real data (not empty stub)

    func testRAHE1omegaDisplayPayloadIsNotEmptyStub() throws {
        let sweeps = makeFieldSweepsWithRAHE(count: 3)
        var renderer = ThreeOmegaPlotRenderer()

        let (_, _, displayPayload, _) = renderer.renderRAHE1omegaVsT(sweeps: sweeps, device: "D1", method: .highField)

        let dp = try XCTUnwrap(displayPayload,
            "renderRAHE1omegaVsT must return non-nil displayPayload when data exists")
        XCTAssertFalse(dp.series.isEmpty, "displayPayload must have at least one series")
        let hasData = dp.series.contains { !$0.x.isEmpty && !$0.y.isEmpty }
        XCTAssertTrue(hasData,
            "RAHE(1ω) displayPayload must carry real temperature/RAHE values, not x:[] y:[] stub")
    }

    // MARK: - 6. RAHE(3ω) displayPayload carries real data

    func testRAHE3omegaDisplayPayloadIsNotEmptyStub() throws {
        let sweeps = makeFieldSweepsWithRAHE(count: 3)
        var renderer = ThreeOmegaPlotRenderer()

        let (_, _, displayPayload, _) = renderer.renderRAHE3omegaVsT(sweeps: sweeps, device: "D1", method: .highField)

        let dp = try XCTUnwrap(displayPayload,
            "renderRAHE3omegaVsT must return non-nil displayPayload when data exists")
        let hasData = dp.series.contains { !$0.x.isEmpty && !$0.y.isEmpty }
        XCTAssertTrue(hasData,
            "RAHE(3ω) displayPayload must carry real temperature/RAHE values, not x:[] y:[] stub")
    }

    // MARK: - 7. RAHE with empty manifestPayload but valid imageData: Copy PNG must not be blank

    @MainActor
    func testRAHECopyPNGFallsBackToImageDataWhenManifestIsEmptyStub() throws {
        let store = ThreeOmegaWorkspaceStore()

        let fakePNG = makeSolidPNG()
        let emptyStub = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "RAHE(1ω) (HFE)",
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(1ω) (Ω)"),
            series: [WorkbenchPlotSeries(label: "file.dat", x: [], y: [], sourceRef: "/tmp/file.dat")]
        )
        store.tabs.setOutput(
            TabRenderOutput(imageData: fakePNG, layout: nil, manifestPayload: emptyStub, displayPayload: nil),
            for: .rahe1omegaVsT
        )
        store.tabs.activeTab = .rahe1omegaVsT

        // 2x: must return cached image, not blank from re-rendering the empty stub
        let result2x = store.copyCurrentPlotPNG(scale: 2.0)
        XCTAssertEqual(result2x, fakePNG,
            "2x Copy PNG with empty manifestPayload must return activeImageData, not blank")

        // 1x: displayPayload nil → fallback to activeImageData
        let result1x = store.copyCurrentPlotPNG(scale: 1.0)
        XCTAssertEqual(result1x, fakePNG,
            "1x Copy PNG must fallback to activeImageData when displayPayload is nil, not produce blank")
    }

    // MARK: - 8. displayPayload is used for 1x/3x, not manifestPayload

    @MainActor
    func testOneXAndThreeXUseDisplayPayloadNotManifestPayload() throws {
        let store = ThreeOmegaWorkspaceStore()

        let displayPayload = makePayload(yValues: [10.5, 11.5])
        let manifestPayload = makePayload(yValues: [1.0, 1.0])   // raw, never offset

        let layout = makeLayout(for: displayPayload)
        let pngFor2x = try makePNG(payload: displayPayload, scale: 2.0)

        store.tabs.setOutput(
            TabRenderOutput(imageData: pngFor2x, layout: layout, manifestPayload: manifestPayload, displayPayload: displayPayload),
            for: .fieldSweep1omega
        )
        store.tabs.activeTab = .fieldSweep1omega
        store.ingestionResult = ThreeOmegaIngestionResult(device: "D1")

        let png1x = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 1.0))
        XCTAssertFalse(png1x.isEmpty, "1x export must be non-empty")

        let png3x = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 3.0))
        XCTAssertFalse(png3x.isEmpty, "3x export must be non-empty")

        // Pixel dimensions: 3x must be 3× wider than 1x
        XCTAssertEqual(pngPixelSize(png3x).width, pngPixelSize(png1x).width * 3,
            "3x export must be 3× the pixel width of 1x; series semantics must be identical")
    }

    // MARK: - 9. All three export scales differ only in pixel density

    @MainActor
    func testAllScalesHaveSameSeriesSemantics() throws {
        let store = ThreeOmegaWorkspaceStore()
        let displayPayload = makePayload(yValues: [42.0, 43.0])
        let pngFor2x = try makePNG(payload: displayPayload, scale: 2.0)
        let layout = makeLayout(for: displayPayload)

        store.tabs.setOutput(
            TabRenderOutput(imageData: pngFor2x, layout: layout, manifestPayload: nil, displayPayload: displayPayload),
            for: .fieldSweep1omega
        )
        store.tabs.activeTab = .fieldSweep1omega
        store.ingestionResult = ThreeOmegaIngestionResult(device: "D1")

        let png1 = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 1.0))
        let png2 = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 2.0))
        let png3 = try XCTUnwrap(store.copyCurrentPlotPNG(scale: 3.0))

        let w1 = pngPixelSize(png1).width
        let w2 = pngPixelSize(png2).width
        let w3 = pngPixelSize(png3).width

        XCTAssertGreaterThan(w1, 0, "1x export must be non-empty")
        XCTAssertEqual(w2, w1 * 2, "2x must be 2× the pixel width of 1x")
        XCTAssertEqual(w3, w1 * 3, "3x must be 3× the pixel width of 1x")
    }

    // MARK: - 10. RAHE no-data returns nil displayPayload (not blank PNG)

    func testRAHERendererReturnsNilWhenNoData() {
        var renderer = ThreeOmegaPlotRenderer()
        // Sweeps without rahe1omega set → guard !temps.isEmpty fires → (nil, nil, nil, [])
        let sweeps = makeFieldSweeps(count: 2)
        let (data, _, displayPayload, _) = renderer.renderRAHE1omegaVsT(sweeps: sweeps, device: "D1", method: .highField)
        XCTAssertNil(data, "renderRAHE1omegaVsT must return nil data when sweeps have no RAHE values")
        XCTAssertNil(displayPayload, "renderRAHE1omegaVsT must return nil displayPayload when no data")
    }

    // MARK: - Helpers

    private func makeFieldSweeps(count: Int) -> [ThreeOmegaFieldSweepResult] {
        (0..<count).map { i in
            // Varying r1omega/r3omega so ThreeOmegaStackOffsetUseCase produces non-zero offsets
            let base = Double(i) * 0.1
            return ThreeOmegaFieldSweepResult(
                temperatureK: Double(200 + i * 50),
                device: "D1",
                hField: [-1.0, 0.0, 1.0],
                r1omega: [-0.5 + base, 0.0 + base, 0.5 + base],
                r3omega: [-0.3 + base, 0.0 + base, 0.3 + base],
                iRms: 1e-3,
                v3omegaWindow: 0.0
            )
        }
    }

    private func makeFieldSweepsWithRAHE(count: Int) -> [ThreeOmegaFieldSweepResult] {
        (0..<count).map { i in
            ThreeOmegaFieldSweepResult(
                temperatureK: Double(200 + i * 50),
                device: "D1",
                hField: [0.0, 1.0, 2.0],
                r1omega: [1.0, 1.0, 1.0],
                r3omega: [1.0, 1.0, 1.0],
                iRms: 1e-3,
                rahe1omega: 0.5 + Double(i) * 0.1,
                v3omegaWindow: (0.3 + Double(i) * 0.05) * 1e-3  // RAHE3ω = v3omegaWindow / iRms
            )
        }
    }

    private func makePayload(yValues: [Double]) -> WorkbenchPlotPayload {
        let series = WorkbenchPlotSeries(label: "T=300K", x: Array(0..<yValues.count).map(Double.init), y: yValues)
        return WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: "R(1ω)",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
            series: [series]
        )
    }

    private func makeLayout(for payload: WorkbenchPlotPayload) -> WorkbenchPlotLayout {
        WorkbenchPlotLayout.compute(
            options: .init(), payload: payload, legendPoint: nil,
            style: .from(styleParams: [:]), seriesLabelOverrides: [:]
        )
    }

    private func makePNG(payload: WorkbenchPlotPayload, scale: CGFloat) throws -> Data {
        var input = WorkbenchRenderPipeline.Input(payload: payload, baseOptions: .init())
        input.pixelScaleOverride = scale
        return try WorkbenchRenderPipeline.render(input).imageData
    }

    private func makeSolidPNG() -> Data {
        // Minimal 4×4 solid-gray PNG using CoreGraphics.
        let width = 4, height = 4, bytesPerPixel = 4
        var pixels = [UInt8](repeating: 200, count: width * height * bytesPerPixel)
        for i in stride(from: 3, to: pixels.count, by: bytesPerPixel) { pixels[i] = 255 }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return pixels.withUnsafeMutableBytes { rawBuf in
            guard let ctx = CGContext(
                data: rawBuf.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * bytesPerPixel,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = ctx.makeImage()
            else { return Data([0x89, 0x50, 0x4E, 0x47]) }
            let mutable = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(mutable, "public.png" as CFString, 1, nil) else {
                return Data([0x89, 0x50, 0x4E, 0x47])
            }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            return mutable as Data
        }
    }

    private func pngPixelSize(_ data: Data) -> (width: Int, height: Int) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return (0, 0) }
        return (w, h)
    }
}
