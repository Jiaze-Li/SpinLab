import XCTest
@testable import SpinLabApp

/// Tests for the final-box-clamp applied in WorkbenchPlotLayout.computeLegendRows().
///
/// Invariants:
///   1. legendBoxRect is fully inside plotRect regardless of where legendPoint is stored.
///   2. A zero-drag canvas previewRect equals the screen projection of legendBoxRect.
///   3. After saving a legendPoint near an edge, the canvas preview still matches the rendered legend.
final class V7110LegendFinalBoxClampTests: XCTestCase {

    private let opts   = WorkbenchChartRenderer.Options()
    private let fitted = CGRect(x: 40, y: 20, width: 640, height: 480)

    private func makeLayout(labels: [String], legendPoint: CGPoint? = nil) -> WorkbenchPlotLayout {
        let series = labels.enumerated().map { i, label in
            WorkbenchPlotSeries(label: label, x: [0.0, 1.0], y: [Double(i), Double(i + 1)],
                                sourceRef: "/tmp/s\(i).csv", sampleID: "s\(i)")
        }
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: series
        )
        return WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: legendPoint)
    }

    // MARK: - 1. legendPoint (1,1) → legendBoxRect fully inside plotRect

    func testFreePosition_topRightCorner_legendBoxFullyInsidePlotRect() {
        let layout = makeLayout(labels: ["Series A", "Series B"], legendPoint: CGPoint(x: 1, y: 1))
        let pr = layout.plotRect
        guard let box = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }

        XCTAssertGreaterThanOrEqual(box.minX, pr.minX - 0.5,
            "legendBoxRect.minX must be within plotRect when legendPoint.x = 1")
        XCTAssertLessThanOrEqual(box.maxX, pr.maxX + 0.5,
            "legendBoxRect.maxX must be within plotRect when legendPoint.x = 1")
        XCTAssertGreaterThanOrEqual(box.minY, pr.minY - 0.5,
            "legendBoxRect.minY must be within plotRect when legendPoint.y = 1")
        XCTAssertLessThanOrEqual(box.maxY, pr.maxY + 0.5,
            "legendBoxRect.maxY must be within plotRect when legendPoint.y = 1")
    }

    // MARK: - 2. legendPoint (0,0) → legendBoxRect fully inside plotRect

    func testFreePosition_bottomLeftCorner_legendBoxFullyInsidePlotRect() {
        let layout = makeLayout(labels: ["Series A", "Series B"], legendPoint: CGPoint(x: 0, y: 0))
        let pr = layout.plotRect
        guard let box = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }

        XCTAssertGreaterThanOrEqual(box.minX, pr.minX - 0.5,
            "legendBoxRect.minX must be within plotRect when legendPoint.x = 0")
        XCTAssertLessThanOrEqual(box.maxX, pr.maxX + 0.5,
            "legendBoxRect.maxX must be within plotRect when legendPoint.x = 0")
        XCTAssertGreaterThanOrEqual(box.minY, pr.minY - 0.5,
            "legendBoxRect.minY must be within plotRect when legendPoint.y = 0")
        XCTAssertLessThanOrEqual(box.maxY, pr.maxY + 0.5,
            "legendBoxRect.maxY must be within plotRect when legendPoint.y = 0")
    }

    // MARK: - 3. Zero-drag previewRect equals legendBoxRect screen projection near top-right

    func testZeroDragPreview_equalsLegendBoxScreenRect_nearTopRight() {
        let layout = makeLayout(labels: ["Series A"], legendPoint: CGPoint(x: 0.95, y: 0.95))
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .empty, layout: layout)
        guard let cgBox = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }

        let originCG = canvas.currentLegendOriginCG()
        let rSz = layout.rendererSize
        let pngY = rSz.height - originCG.y
        let originScreen = CGPoint(
            x: fitted.minX + originCG.x / rSz.width  * fitted.width,
            y: fitted.minY + pngY        / rSz.height * fitted.height
        )

        guard let step = canvas.legendDragStep(
            start: originScreen, current: originScreen,
            fittedRect: fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else { XCTFail("legendDragStep returned nil"); return }

        let expected = WorkbenchPlotLayout.cgToScreen(
            cgBox, fittedIn: fitted,
            rendererWidth: rSz.width, rendererHeight: rSz.height
        )

        XCTAssertEqual(step.previewRect.minX, expected.minX, accuracy: 1.0,
            "Zero-drag preview.minX must equal legendBoxRect screen projection")
        XCTAssertEqual(step.previewRect.minY, expected.minY, accuracy: 1.0,
            "Zero-drag preview.minY must equal legendBoxRect screen projection")
        XCTAssertEqual(step.previewRect.maxX, expected.maxX, accuracy: 1.0,
            "Zero-drag preview.maxX must equal legendBoxRect screen projection")
        XCTAssertEqual(step.previewRect.maxY, expected.maxY, accuracy: 1.0,
            "Zero-drag preview.maxY must equal legendBoxRect screen projection")
    }

    // MARK: - 4. After saving legendPoint near edge, canvas preview matches rendered legend

    func testSavedNearEdge_canvasPreviewMatchesRenderedLegend() {
        // legendPoint (0.98, 0.98) is near top-right; the raw box would exceed plotRect.
        // After the fix, layout clamps the box. Canvas legendDragStep must agree.
        let savedNorm = CGPoint(x: 0.98, y: 0.98)
        let layout = makeLayout(labels: ["Alpha", "Beta", "Gamma"], legendPoint: savedNorm)
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .empty, layout: layout)
        guard let cgBox = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }
        let pr = layout.plotRect

        // legendBoxRect must be inside plotRect after the fix.
        XCTAssertLessThanOrEqual(cgBox.maxX, pr.maxX + 0.5,
            "Saved near-edge legendPoint: rendered box right edge must be inside plotRect")
        XCTAssertLessThanOrEqual(cgBox.maxY, pr.maxY + 0.5,
            "Saved near-edge legendPoint: rendered box top edge must be inside plotRect")

        // Zero-drag preview must match the rendered box exactly.
        let originCG = canvas.currentLegendOriginCG()
        let rSz = layout.rendererSize
        let pngY = rSz.height - originCG.y
        let originScreen = CGPoint(
            x: fitted.minX + originCG.x / rSz.width  * fitted.width,
            y: fitted.minY + pngY        / rSz.height * fitted.height
        )

        guard let step = canvas.legendDragStep(
            start: originScreen, current: originScreen,
            fittedRect: fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else { XCTFail("legendDragStep returned nil"); return }

        let expected = WorkbenchPlotLayout.cgToScreen(
            cgBox, fittedIn: fitted,
            rendererWidth: rSz.width, rendererHeight: rSz.height
        )

        XCTAssertEqual(step.previewRect.minX, expected.minX, accuracy: 1.0,
            "Canvas preview must match rendered legend box for saved near-edge point")
        XCTAssertEqual(step.previewRect.minY, expected.minY, accuracy: 1.0,
            "Canvas preview must match rendered legend box for saved near-edge point")
        XCTAssertEqual(step.previewRect.maxX, expected.maxX, accuracy: 1.0,
            "Canvas preview must match rendered legend box for saved near-edge point")
        XCTAssertEqual(step.previewRect.maxY, expected.maxY, accuracy: 1.0,
            "Canvas preview must match rendered legend box for saved near-edge point")
    }
}
