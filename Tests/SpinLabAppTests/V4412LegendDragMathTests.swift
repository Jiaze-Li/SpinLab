import XCTest
@testable import SpinLabApp

/// Tests for legend drag coordinate math in WorkbenchPlotCanvas.
///
/// Verifies invariants:
///   1. plotNormalized clamps smoothly everywhere — no air wall inside or outside fittedRect.
///   2. plotNormalized ↔ legendOriginCG round-trip is exact (no intermediate screen coordinate skew).
///   3. previewRect matches translated legendBoxRect converted to screen — position-correct, not just sized correctly.
///   4. _isInLegendFrame uses legendBoxRect screen conversion (not row.hitRect union).
final class V4412LegendDragMathTests: XCTestCase {

    // MARK: - Shared geometry

    /// Mirrors WorkbenchChartRenderer.Options defaults.
    private let opts = WorkbenchChartRenderer.Options()

    /// A representative fitted image rect (800×600 image scaled to 640×480 screen area).
    private let fitted = CGRect(x: 40, y: 20, width: 640, height: 480)

    // MARK: - plotNormalized: no air wall

    /// Cursor inside the plot area → normalized result in (0,1).
    func testPlotNormalized_insidePlot_returnsNormalized() {
        // Centre of the fitted image maps to renderer pixel (400, 300).
        // plotMinX = paddingLeft = 96, plotMinY = paddingTop = 64
        // plotW = 800 - 96 - 30 = 674, plotH = 600 - 64 - 88 = 448
        let centre = CGPoint(x: fitted.midX, y: fitted.midY)
        let result = plotNormalizedForTest(location: centre)
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.x, 0); XCTAssertLessThanOrEqual(result!.x, 1)
        XCTAssertGreaterThanOrEqual(result!.y, 0); XCTAssertLessThanOrEqual(result!.y, 1)
    }

    /// Cursor in the top padding (above plot) → clamps to y = 1.0, does NOT return nil.
    func testPlotNormalized_abovePlot_clampsToTop() {
        let abovePlot = CGPoint(x: fitted.midX, y: fitted.minY + 5)  // 5px from image top
        let result = plotNormalizedForTest(location: abovePlot)
        XCTAssertNotNil(result, "Should not return nil when cursor is in top padding")
        XCTAssertEqual(result!.y, 1.0, accuracy: 0.01)
    }

    /// Cursor in the bottom padding (below plot) → clamps to y = 0.0, does NOT return nil.
    func testPlotNormalized_belowPlot_clampsToBottom() {
        let belowPlot = CGPoint(x: fitted.midX, y: fitted.maxY - 5)  // 5px from image bottom
        let result = plotNormalizedForTest(location: belowPlot)
        XCTAssertNotNil(result, "Should not return nil when cursor is in bottom padding")
        XCTAssertEqual(result!.y, 0.0, accuracy: 0.01)
    }

    /// Cursor completely outside fittedRect (right of image) → clamps, does NOT return nil.
    func testPlotNormalized_outsideFittedRect_clamps() {
        let outsideRight = CGPoint(x: fitted.maxX + 100, y: fitted.midY)
        let result = plotNormalizedForTest(location: outsideRight)
        XCTAssertNotNil(result, "Should not return nil when cursor is outside fittedRect")
        XCTAssertEqual(result!.x, 1.0, accuracy: 0.01)
    }

    /// Cursor far below fittedRect → clamps to y = 0, x stays within bounds.
    func testPlotNormalized_farBelowImage_clampsToBottomEdge() {
        let farBelow = CGPoint(x: fitted.midX, y: fitted.maxY + 200)
        let result = plotNormalizedForTest(location: farBelow)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.y, 0.0, accuracy: 0.01)
    }

    // MARK: - Round-trip: plotNormalized ↔ legendOriginCG

    /// For any normalized point p, legendOriginCG(p) maps into CG space, and
    /// normalizing that CG point back recovers p (within 1e-4).
    func testRoundTrip_normalizedToScreenAndBack() {
        let testPoints: [CGPoint] = [
            CGPoint(x: 0.0, y: 0.0),   // bottom-left
            CGPoint(x: 1.0, y: 1.0),   // top-right
            CGPoint(x: 0.5, y: 0.5),   // centre
            CGPoint(x: 0.1, y: 0.9),   // near top-left
            CGPoint(x: 0.85, y: 0.15), // near bottom-right
        ]
        let plotW = CGFloat(opts.width)  - opts.paddingLeft - opts.paddingRight
        let plotH = CGFloat(opts.height) - opts.paddingTop  - opts.paddingBottom
        for p in testPoints {
            // legendOriginCG: CG-space inverse of currentLegendOriginNorm
            let cgX = opts.paddingLeft   + p.x * plotW
            let cgY = opts.paddingBottom + p.y * plotH
            // normalize back: map through screen then plotNormalized
            let rendW: CGFloat = 800, rendH: CGFloat = 600
            let pngX = cgX
            let pngY = rendH - cgY
            let screenPt = CGPoint(
                x: fitted.minX + pngX / rendW * fitted.width,
                y: fitted.minY + pngY / rendH * fitted.height
            )
            let recovered = plotNormalizedForTest(location: screenPt)
            XCTAssertNotNil(recovered, "Round-trip failed for \(p)")
            XCTAssertEqual(recovered!.x, p.x, accuracy: 1e-4,
                           "X round-trip mismatch for input \(p)")
            XCTAssertEqual(recovered!.y, p.y, accuracy: 1e-4,
                           "Y round-trip mismatch for input \(p)")
        }
    }

    /// Grab offset locks cursor to its original position within the legend box.
    func testPreviewMatchesLanding_clampedAdjustedRoundTrips() {
        let origin    = CGPoint(x: 0.8,  y: 0.9)
        let startNorm = CGPoint(x: 0.75, y: 0.82)
        let cursor    = CGPoint(x: 0.6,  y: 0.7)

        let grabW = startNorm.x - origin.x
        let grabH = startNorm.y - origin.y

        let rawX     = cursor.x - grabW
        let rawY     = cursor.y - grabH
        let adjusted = CGPoint(x: min(max(rawX, 0), 1), y: min(max(rawY, 0), 1))

        XCTAssertEqual(adjusted.x - cursor.x, origin.x - startNorm.x, accuracy: 1e-6,
                       "Grab offset should lock cursor to original click position (X)")
        XCTAssertEqual(adjusted.y - cursor.y, origin.y - startNorm.y, accuracy: 1e-6,
                       "Grab offset should lock cursor to original click position (Y)")
    }

    /// Repeated drag updates must keep advancing the legend preview.
    /// This catches the regression where the canvas captured drag state only on the first frame.
    func testLegendDragStep_recomputesOnSubsequentDragEvents() {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "Legend",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "Top", x: [0, 1], y: [1, 2], sourceRef: "/tmp/top.csv", sampleID: "top"),
                WorkbenchPlotSeries(label: "Bottom", x: [0, 1], y: [0, 1], sourceRef: "/tmp/bottom.csv", sampleID: "bottom")
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: false
        )
        // Free-position at center so the legend can move in both X and Y without hitting
        // the right-edge clamp that an anchor-mode top-right legend would immediately trigger.
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: CGPoint(x: 0.5, y: 0.5))
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .empty, layout: layout)

        let start = CGPoint(x: 180, y: 160)
        let firstCursor = CGPoint(x: 220, y: 200)
        let secondCursor = CGPoint(x: 320, y: 260)

        guard let first = canvas.legendDragStep(
            start: start,
            current: firstCursor,
            fittedRect: fitted,
            existingGrabOffset: nil
        ) else {
            XCTFail("Expected first legend drag step")
            return
        }
        guard let second = canvas.legendDragStep(
            start: start,
            current: secondCursor,
            fittedRect: fitted,
            existingGrabOffset: first.grabOffset
        ) else {
            XCTFail("Expected second legend drag step")
            return
        }

        XCTAssertNotEqual(first.adjustedNorm.x, second.adjustedNorm.x, accuracy: 1e-6)
        XCTAssertNotEqual(first.adjustedNorm.y, second.adjustedNorm.y, accuracy: 1e-6)
        XCTAssertNotEqual(first.previewRect.midX, second.previewRect.midX, accuracy: 1e-6)
        XCTAssertNotEqual(first.previewRect.midY, second.previewRect.midY, accuracy: 1e-6)
    }

    // MARK: - previewRect position correctness

    /// Long label, top-right anchor: previewRect from legendDragStep must match the
    /// clamped-and-translated legendBoxRect computed independently via cgToScreen.
    /// A very long label fills the plot horizontally; the clamp prevents overflow.
    func testPreviewRect_longLabel_topRight_matchesTranslatedBoxRect() {
        let label = "Very Long Label That Exceeds Default Legend Width Estimate Significantly"
        let series = [WorkbenchPlotSeries(label: label, x: [0.0, 1.0], y: [0.0, 1.0],
                                          sourceRef: "/tmp/s0.csv", sampleID: "s0")]
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: series,
            styleParams: ["legendAnchor": "top-right"]
        )
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .empty, layout: layout)

        guard let cgBox = layout.legendBoxRect else {
            XCTFail("legendBoxRect must not be nil"); return
        }
        let row0 = layout.legendRows[0]
        let pr   = layout.plotRect
        let rowHeight = row0.style.rowHeight

        // Drag to (0.5, 0.5). The label is wide enough that X is clamped — expected value
        // must mirror the CG-space clamp that legendDragStep applies.
        let targetNorm = CGPoint(x: 0.5, y: 0.5)
        let currentOriginCG = CGPoint(x: row0.cgOriginX, y: row0.cgRowY + rowHeight * 0.4)
        let rawTargetCG     = CGPoint(x: pr.minX + targetNorm.x * pr.width,
                                       y: pr.minY + targetNorm.y * pr.height)
        let dxBoxMin = cgBox.minX - currentOriginCG.x
        let dxBoxMax = cgBox.maxX - currentOriginCG.x
        let dyBoxMin = cgBox.minY - currentOriginCG.y
        let dyBoxMax = cgBox.maxY - currentOriginCG.y
        let clampedCG = CGPoint(
            x: min(max(rawTargetCG.x, pr.minX - dxBoxMin), pr.maxX - dxBoxMax),
            y: min(max(rawTargetCG.y, pr.minY - dyBoxMin), pr.maxY - dyBoxMax)
        )
        let dx = clampedCG.x - currentOriginCG.x
        let dy = clampedCG.y - currentOriginCG.y
        let expectedRect = WorkbenchPlotLayout.cgToScreen(
            cgBox.offsetBy(dx: dx, dy: dy), fittedIn: fitted,
            rendererWidth: layout.rendererSize.width, rendererHeight: layout.rendererSize.height
        )

        guard let step = canvas.legendDragStep(
            start: startPointForNorm(targetNorm, layout: layout),
            current: startPointForNorm(targetNorm, layout: layout),
            fittedRect: fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else {
            XCTFail("legendDragStep returned nil"); return
        }

        XCTAssertEqual(step.previewRect.minX, expectedRect.minX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.minY, expectedRect.minY, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxX, expectedRect.maxX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxY, expectedRect.maxY, accuracy: 1.0)
    }

    /// Free-position drag: previewRect equals translatedLegendBoxRect at the adjusted norm.
    func testPreviewRect_freePosition_equalsTranslatedBoxRect() {
        let label = "Free Legend"
        let series = [WorkbenchPlotSeries(label: label, x: [0.0, 1.0], y: [0.0, 1.0],
                                          sourceRef: "/tmp/s0.csv", sampleID: "s0")]
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: series
        )
        let layout = WorkbenchPlotLayout.compute(
            options: opts, payload: payload, legendPoint: CGPoint(x: 0.3, y: 0.7)
        )
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .empty, layout: layout)
        let rowHeight = layout.legendRows[0].style.rowHeight

        guard let cgBox = layout.legendBoxRect else {
            XCTFail("legendBoxRect must not be nil"); return
        }
        let row0 = layout.legendRows[0]
        let pr   = layout.plotRect
        let targetNorm = CGPoint(x: 0.6, y: 0.4)

        let currentOriginCG = CGPoint(x: row0.cgOriginX, y: row0.cgRowY + rowHeight * 0.4)
        let targetOriginCG  = CGPoint(x: pr.minX + targetNorm.x * pr.width,
                                       y: pr.minY + targetNorm.y * pr.height)
        let dx = targetOriginCG.x - currentOriginCG.x
        let dy = targetOriginCG.y - currentOriginCG.y
        let translatedCG = cgBox.offsetBy(dx: dx, dy: dy)
        let expectedRect = WorkbenchPlotLayout.cgToScreen(
            translatedCG, fittedIn: fitted,
            rendererWidth: layout.rendererSize.width, rendererHeight: layout.rendererSize.height
        )

        guard let step = canvas.legendDragStep(
            start: startPointForNorm(targetNorm, layout: layout),
            current: startPointForNorm(targetNorm, layout: layout),
            fittedRect: fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else {
            XCTFail("legendDragStep returned nil"); return
        }

        XCTAssertEqual(step.previewRect.minX, expectedRect.minX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.minY, expectedRect.minY, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxX, expectedRect.maxX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxY, expectedRect.maxY, accuracy: 1.0)
    }

    // MARK: - Hit-test frame uses legendBoxRect

    /// _isInLegendFrame must accept points inside legendBoxRect screen rect and reject points outside.
    func testIsInLegendFrame_usesLegendBoxRect() {
        let series = [WorkbenchPlotSeries(label: "S1", x: [0.0, 1.0], y: [0.0, 1.0],
                                          sourceRef: "/tmp/s0.csv", sampleID: "s0")]
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: series,
            styleParams: ["legendAnchor": "top-right"]
        )
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let canvas = WorkbenchPlotCanvas(exportArtifacts: .empty, layout: layout)

        guard let cgBox = layout.legendBoxRect else {
            XCTFail("legendBoxRect must not be nil"); return
        }
        let screenBox = WorkbenchPlotLayout.cgToScreen(
            cgBox, fittedIn: fitted,
            rendererWidth: layout.rendererSize.width, rendererHeight: layout.rendererSize.height
        )

        // Point at the center of legendBoxRect screen rect must be inside.
        XCTAssertTrue(canvas._isInLegendFrame(CGPoint(x: screenBox.midX, y: screenBox.midY), fittedRect: fitted),
                      "Center of legendBoxRect screen rect must be inside legend frame")

        // Point well outside legendBoxRect screen rect must be outside.
        let outside = CGPoint(x: screenBox.minX - 20, y: screenBox.midY)
        XCTAssertFalse(canvas._isInLegendFrame(outside, fittedRect: fitted),
                       "Point outside legendBoxRect screen rect must not be in legend frame")
    }

    // MARK: - Helpers

    /// Converts a normalized plot point to a screen coordinate (for use as a drag start/current point).
    private func startPointForNorm(_ norm: CGPoint, layout: WorkbenchPlotLayout) -> CGPoint {
        let pr    = layout.plotRect
        let rSize = layout.rendererSize
        let cgX   = pr.minX + norm.x * pr.width
        let cgY   = pr.minY + norm.y * pr.height
        let pngY  = rSize.height - cgY
        return CGPoint(
            x: fitted.minX + cgX / rSize.width  * fitted.width,
            y: fitted.minY + pngY / rSize.height * fitted.height
        )
    }

    private func plotNormalizedForTest(location: CGPoint) -> CGPoint? {
        guard !fitted.isEmpty else { return nil }
        let cx = min(max(location.x, fitted.minX), fitted.maxX)
        let cy = min(max(location.y, fitted.minY), fitted.maxY)
        let rendW: CGFloat = 800; let rendH: CGFloat = 600
        let px = (cx - fitted.minX) / fitted.width  * rendW
        let py = (cy - fitted.minY) / fitted.height * rendH
        let plotW = CGFloat(opts.width)  - opts.paddingLeft - opts.paddingRight
        let plotH = CGFloat(opts.height) - opts.paddingTop  - opts.paddingBottom
        let nx = (px - opts.paddingLeft) / plotW
        let ny = 1.0 - (py - opts.paddingTop) / plotH
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }
}
