import Foundation
import XCTest
@testable import SpinLabApp

final class WorkbenchPlotSeriesOverlayTests: XCTestCase {

    private func makeBasePayload(
        series: [WorkbenchPlotSeries],
        overlays: [WorkbenchPlotSeriesOverlay] = []
    ) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Overlay Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: series,
            seriesOverlays: overlays
        )
    }

    func testOverlayCodableRoundTripsParentIdentity() throws {
        let overlay = WorkbenchPlotSeriesOverlay(
            overlayIdentityKey: "overlay-1",
            parentSeriesIdentityKey: "parent-1",
            series: WorkbenchPlotSeries(label: "fit", x: [0, 1], y: [1, 2])
        )
        var displayOverlay = overlay
        displayOverlay.displaySeries = WorkbenchPlotSeries(label: "fit", x: [0, 1], y: [5, 6])

        let decoded = try JSONDecoder().decode(WorkbenchPlotSeriesOverlay.self, from: JSONEncoder().encode(displayOverlay))

        XCTAssertEqual(decoded.overlayIdentityKey, overlay.overlayIdentityKey)
        XCTAssertEqual(decoded.parentSeriesIdentityKey, overlay.parentSeriesIdentityKey)
        XCTAssertEqual(decoded.series.label, overlay.series.label)
        XCTAssertNil(decoded.displaySeries)
    }

    func testOverlayResolverAppliesParentOffsetAndHidesHiddenParent() {
        let base = WorkbenchPlotSeries(label: "base", x: [0, 1], y: [10, 20])
            .withSeriesIdentityKey("series-a")
        let overlay = WorkbenchPlotSeriesOverlay(
            overlayIdentityKey: "overlay-a",
            parentSeriesIdentityKey: "series-a",
            series: WorkbenchPlotSeries(label: "fit", x: [0, 1], y: [1, 2])
        )

        let resolved = WorkbenchPlotSeriesOverlayResolver.resolve(
            overlays: [overlay],
            baseSeries: [base],
            displayOffsetsByIdentityKey: ["series-a": 4.5]
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.displaySeries?.y, [5.5, 6.5])

        let hidden = WorkbenchPlotSeriesOverlayResolver.resolve(
            overlays: [overlay],
            baseSeries: [base],
            displayOffsetsByIdentityKey: ["series-a": 4.5],
            hiddenSeriesKeys: ["series-a"]
        )

        XCTAssertTrue(hidden.isEmpty)
    }

    func testOverlayPipelinePreservesManifestAndRendersDisplayPayload() throws {
        let base = WorkbenchPlotSeries(label: "base", x: [0, 1, 2], y: [10, 20, 30])
            .withSeriesIdentityKey("series-a")
        var overlay = WorkbenchPlotSeriesOverlay(
            overlayIdentityKey: "overlay-a",
            parentSeriesIdentityKey: "series-a",
            series: WorkbenchPlotSeries(label: "fit", x: [0, 1, 2], y: [1, 2, 3], renderMode: .line, renderModeLocked: true)
        )
        overlay.displaySeries = WorkbenchPlotSeries(
            label: "fit",
            x: [0, 1, 2],
            y: [14.5, 24.5, 34.5],
            renderMode: .line,
            renderModeLocked: true
        )

        let payload = makeBasePayload(series: [base], overlays: [overlay])
        let output = try WorkbenchRenderPipeline.render(.init(payload: payload))

        XCTAssertEqual(output.manifestPayload.seriesOverlays.count, 1)
        XCTAssertEqual(output.displayPayload.seriesOverlays.count, 1)
        XCTAssertEqual(output.displayPayload.seriesOverlays.first?.displaySeries?.y, [14.5, 24.5, 34.5])
        XCTAssertEqual(output.layout.legendRows.count, 1, "Overlay must stay out of legend inference")
        XCTAssertFalse(output.imageData.isEmpty)
        XCTAssertFalse(output.pdfData.isEmpty)
        XCTAssertTrue(output.pdfData.starts(with: Array("%PDF-".utf8)))
    }
}
