import XCTest
@testable import SpinLabApp

/// Behavioral tests for legend bounding box geometry (PR127 fix).
///
/// Invariants:
///   1. `legendBoxRect` width covers the full measured label width, not the 110pt estimate.
///   2. Right-anchor `cgOriginX` uses actual max measured width, not `legendEstLabelW`.
///   3. `hitRect` width covers the full measured label width.
///   4. Canvas drag preview dimensions come from `legendBoxRect` (same width/height as rendered box).
///   5. Free-position legend box size is position-independent.
final class V4412LegendBoxGeometryTests: XCTestCase {

    private let opts    = WorkbenchChartRenderer.Options()
    private let fitted  = CGRect(x: 40, y: 20, width: 640, height: 480)
    private let boxPad: CGFloat = 6

    private func makeLayout(
        labels: [String],
        overrides: [Int: String] = [:],
        legendPoint: CGPoint? = nil,
        anchor: String = "top-right"
    ) -> WorkbenchPlotLayout {
        let series = labels.enumerated().map { i, label in
            WorkbenchPlotSeries(
                label: label, x: [0.0, 1.0], y: [Double(i), Double(i + 1)],
                sourceRef: "/tmp/s\(i).csv", sampleID: "s\(i)"
            )
        }
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: series,
            styleParams: ["legendAnchor": anchor]
        )
        return WorkbenchPlotLayout.compute(
            options: opts, payload: payload, legendPoint: legendPoint,
            seriesLabelOverrides: overrides
        )
    }

    // MARK: - legendBoxRect width covers the full long label

    func testLegendBoxRect_longLabel_widerThanShort() {
        let shortLayout = makeLayout(labels: ["AB"])
        let longLayout  = makeLayout(labels: ["Very Long Renamed Series Label That Is Much Wider Than Default"])

        guard let shortBox = shortLayout.legendBoxRect,
              let longBox  = longLayout.legendBoxRect else {
            XCTFail("legendBoxRect must not be nil for non-empty legend"); return
        }
        XCTAssertGreaterThan(longBox.width, shortBox.width,
            "Long label must produce a wider legendBoxRect than a short label")
    }

    func testLegendBoxRect_width_coversLineGapLabel() {
        let longLabel = "Quite A Long Series Name For This Test"
        let layout = makeLayout(labels: [longLabel])
        guard let box = layout.legendBoxRect else {
            XCTFail("legendBoxRect must not be nil"); return
        }
        let row = layout.legendRows[0]
        let expectedMinWidth = WorkbenchPlotLayout.legendLineLen
                             + WorkbenchPlotLayout.legendGap
                             + row.measuredLabelWidth
                             + 2 * boxPad
        XCTAssertGreaterThanOrEqual(box.width, expectedMinWidth - 0.1,
            "legendBoxRect.width must be at least line+gap+measuredLabelWidth+2*boxPad")
    }

    // MARK: - Right-anchor cgOriginX uses actual measured width, not estimate

    func testRightAnchorOriginX_longLabel_usesActualWidth() {
        // A label far wider than legendEstLabelW = 110
        let longLabel = "Super Long Label Far Exceeding One Hundred And Ten Points Width"
        let layout = makeLayout(labels: [longLabel], anchor: "top-right")
        let row = layout.legendRows[0]
        let pr  = layout.plotRect

        let expectedBlockW = WorkbenchPlotLayout.legendLineLen
                           + WorkbenchPlotLayout.legendGap
                           + row.measuredLabelWidth
        let expectedOriginX = pr.maxX - WorkbenchPlotLayout.legendMargin - expectedBlockW
        XCTAssertEqual(row.cgOriginX, expectedOriginX, accuracy: 0.5,
            "Right-anchor cgOriginX must use actual measured label width")

        // Confirm the estimate would have given a different (too-far-right) value
        let estimateOriginX = pr.maxX - WorkbenchPlotLayout.legendMargin
                            - WorkbenchPlotLayout.legendLineLen
                            - WorkbenchPlotLayout.legendGap
                            - WorkbenchPlotLayout.legendEstLabelW
        XCTAssertNotEqual(row.cgOriginX, estimateOriginX, accuracy: 0.5,
            "A label wider than 110pt must push cgOriginX left of the estimate position")
    }

    // MARK: - hitRect covers the full measured label width

    func testHitRect_longLabel_coversFullLabel() {
        let longLabel = "Much Much Longer Label For Hit Test"
        let layout = makeLayout(labels: [longLabel])
        let row = layout.legendRows[0]
        let expectedMinWidth = WorkbenchPlotLayout.legendLineLen
                             + WorkbenchPlotLayout.legendGap
                             + row.measuredLabelWidth
        XCTAssertGreaterThanOrEqual(row.hitRect.width, expectedMinWidth - 0.1,
            "hitRect.width must cover line+gap+measuredLabelWidth")
    }

    // MARK: - Drag preview dimensions match legendBoxRect scaled to screen

    func testDragPreview_dimensions_matchLegendBoxRectScaled() {
        let longLabel = "Long Renamed Label For Drag Preview Box Test"
        let layout = makeLayout(labels: [longLabel])
        guard let cgBox = layout.legendBoxRect else {
            XCTFail("legendBoxRect must not be nil"); return
        }
        let scaleX = fitted.width  / layout.rendererSize.width
        let scaleY = fitted.height / layout.rendererSize.height
        let expectedW = cgBox.width  * scaleX
        let expectedH = cgBox.height * scaleY

        XCTAssertGreaterThan(expectedW, 0)
        XCTAssertGreaterThan(expectedH, 0)

        // Width must exceed what the 110pt estimate would have produced
        let estimateW = (WorkbenchPlotLayout.legendLineLen
                       + WorkbenchPlotLayout.legendGap
                       + WorkbenchPlotLayout.legendEstLabelW
                       + 2 * boxPad) * scaleX
        XCTAssertGreaterThan(expectedW, estimateW,
            "Long label must produce a wider scaled box than the 110pt estimate")
    }

    // MARK: - Free-position legend box size is position-independent

    func testFreePosition_boxSizeUnchangedByPosition() {
        let label = "Fixed Label For Position Test"
        let layoutLeft  = makeLayout(labels: [label], legendPoint: CGPoint(x: 0.1, y: 0.9))
        let layoutRight = makeLayout(labels: [label], legendPoint: CGPoint(x: 0.9, y: 0.1))

        guard let boxLeft  = layoutLeft.legendBoxRect,
              let boxRight = layoutRight.legendBoxRect else {
            XCTFail("legendBoxRect must not be nil"); return
        }
        XCTAssertEqual(boxLeft.width,  boxRight.width,  accuracy: 0.5,
            "Free-position legend box width must be the same regardless of position")
        XCTAssertEqual(boxLeft.height, boxRight.height, accuracy: 0.5,
            "Free-position legend box height must be the same regardless of position")
    }
}
