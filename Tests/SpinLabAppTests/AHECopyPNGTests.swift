import Foundation
import ImageIO
import XCTest
import CoreGraphics
@testable import SpinLabApp

// MARK: - AHE Copy PNG contract tests
//
// Guards the AHE Copy PNG export contract now that AHE uses WorkbenchPlotExportService:
//   - 1x / 2x / 3x produce real PNG exports (not the same cached imageData).
//   - 2x pixel width = 1x × 2, 3x pixel width = 1x × 3.
//   - activeImageData is fallback only when displayPayload is nil.

final class AHECopyPNGTests: XCTestCase {

    // MARK: - 1. All scales render real PNGs when displayPayload is stored

    @MainActor
    func testAllScalesRenderFromDisplayPayload() throws {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let payload = makePayload()
        let layout = makeLayout(for: payload)
        let sentinel = Data([0xAE, 0xAE, 0xAE, 0xAE])

        store.tabs.setOutput(
            TabRenderOutput(
                imageData: sentinel,
                layout: layout,
                manifestPayload: payload,
                displayPayload: payload
            ),
            for: .ahe
        )
        store.tabs.activeTab = .ahe

        let png1x = try XCTUnwrap(store.renderPNGAtScale(1.0))
        let png2x = try XCTUnwrap(store.renderPNGAtScale(2.0))
        let png3x = try XCTUnwrap(store.renderPNGAtScale(3.0))

        XCTAssertNotEqual(png1x, sentinel, "1x must render from displayPayload, not sentinel imageData")
        XCTAssertNotEqual(png2x, sentinel, "2x must render from displayPayload, not sentinel imageData")
        XCTAssertNotEqual(png3x, sentinel, "3x must render from displayPayload, not sentinel imageData")
    }

    // MARK: - 2. 2x pixel width = 1x × 2, 3x pixel width = 1x × 3

    @MainActor
    func testPixelDimensionsScaleCorrectly() throws {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let payload = makePayload()
        let layout = makeLayout(for: payload)

        store.tabs.setOutput(
            TabRenderOutput(imageData: nil, layout: layout, manifestPayload: payload, displayPayload: payload),
            for: .ahe
        )
        store.tabs.activeTab = .ahe

        let png1x = try XCTUnwrap(store.renderPNGAtScale(1.0))
        let png2x = try XCTUnwrap(store.renderPNGAtScale(2.0))
        let png3x = try XCTUnwrap(store.renderPNGAtScale(3.0))

        let w1 = pngPixelWidth(png1x)
        XCTAssertGreaterThan(w1, 0, "1x export must be non-empty")
        XCTAssertEqual(pngPixelWidth(png2x), w1 * 2, "2x width must be 2× that of 1x")
        XCTAssertEqual(pngPixelWidth(png3x), w1 * 3, "3x width must be 3× that of 1x")
    }

    // MARK: - 3. activeImageData is fallback when displayPayload is nil

    @MainActor
    func testFallsBackToImageDataWhenDisplayPayloadIsNil() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let sentinel = Data([0xFA, 0x11, 0xBA, 0xCF])

        store.tabs.setOutput(
            TabRenderOutput(imageData: sentinel, layout: nil, manifestPayload: nil, displayPayload: nil),
            for: .ahe
        )
        store.tabs.activeTab = .ahe

        XCTAssertEqual(store.renderPNGAtScale(1.0), sentinel, "1x must fall back to activeImageData when displayPayload is nil")
        XCTAssertEqual(store.renderPNGAtScale(2.0), sentinel, "2x must fall back to activeImageData when displayPayload is nil")
        XCTAssertEqual(store.renderPNGAtScale(3.0), sentinel, "3x must fall back to activeImageData when displayPayload is nil")
    }

    // MARK: - 4. exportSnapshot helper assembles the correct fields

    @MainActor
    func testExportSnapshotReflectsTabState() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let payload = makePayload()
        let layout = makeLayout(for: payload)
        let sentinel = Data([0x01, 0x02])

        store.tabs.setOutput(
            TabRenderOutput(imageData: sentinel, layout: layout, manifestPayload: payload, displayPayload: payload),
            for: .ahe
        )
        store.tabs.updateTitleOverride("My Title")
        store.tabs.activeTab = .ahe

        let snapshot = store.tabs.exportSnapshot(for: .ahe, globalPlotDefaults: [:])
        XCTAssertEqual(snapshot.imageData, sentinel)
        XCTAssertNotNil(snapshot.displayPayload)
        XCTAssertNotNil(snapshot.layout)
        XCTAssertEqual(snapshot.tabState.titleOverride, "My Title")
    }

    // MARK: - Helpers

    private func makePayload() -> WorkbenchPlotPayload {
        let series = WorkbenchPlotSeries(label: "Sample A", x: [-1.0, 0.0, 1.0], y: [0.5, 0.0, -0.5])
        return WorkbenchPlotPayload(
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            title: "AHE Test",
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R_AHE (Ω)"),
            series: [series]
        )
    }

    private func makeLayout(for payload: WorkbenchPlotPayload) -> WorkbenchPlotLayout {
        WorkbenchPlotLayout.compute(
            options: .init(), payload: payload, legendPoint: nil,
            style: .from(styleParams: [:]), seriesLabelOverrides: [:]
        )
    }

    private func pngPixelWidth(_ data: Data) -> Int {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int else { return 0 }
        return w
    }
}
