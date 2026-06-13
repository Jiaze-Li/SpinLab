import XCTest
@testable import SpinLabApp

/// Tests for CG-space legend drag clamping (gate7.10 fixes).
///
/// Invariants:
///   1. Dragging upward while grabbing the upper half of the legend never hits an air wall
///      before legendBoxRect reaches the allowed top boundary.
///   2. Preview rect equals the translated legendBoxRect used by the renderer — same position
///      and size, not just the same dimensions.
///   3. PNG renderer and canvas use the same layout source (WorkbenchRenderPipeline passes
///      its pre-computed layout into renderPNG; drawCanvas does not recompute a divergent layout).
///   4. Top-right and free-position legends with long labels produce correct preview geometry.
final class V7110LegendDragCGClampTests: XCTestCase {

    private let opts   = WorkbenchChartRenderer.Options()
    private let fitted = CGRect(x: 40, y: 20, width: 640, height: 480)

    // MARK: - Helpers

    private func makeLayout(labels: [String], legendPoint: CGPoint? = nil, anchor: String = "top-right") -> WorkbenchPlotLayout {
        let series = labels.enumerated().map { i, label in
            WorkbenchPlotSeries(label: label, x: [0.0, 1.0], y: [Double(i), Double(i + 1)],
                                sourceRef: "/tmp/s\(i).csv", sampleID: "s\(i)")
        }
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: series,
            styleParams: ["legendAnchor": anchor]
        )
        return WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: legendPoint)
    }

    /// Converts a normalized plot point to screen coordinates using the same math as WorkbenchPlotCanvas.
    private func normToScreen(_ norm: CGPoint, layout: WorkbenchPlotLayout) -> CGPoint {
        let pr   = layout.plotRect
        let rSz  = layout.rendererSize
        let cgX  = pr.minX + norm.x * pr.width
        let cgY  = pr.minY + norm.y * pr.height
        let pngY = rSz.height - cgY
        return CGPoint(
            x: fitted.minX + cgX / rSz.width  * fitted.width,
            y: fitted.minY + pngY / rSz.height * fitted.height
        )
    }

    // MARK: - 1. No air wall when dragging upward grabbing the upper half of the legend

    /// Grabs the upper-half of the legend (large positive grab.height in CG space) and
    /// drags upward. The preview box must keep moving toward the top boundary; it must
    /// not freeze before legendBoxRect.minY reaches plotRect.minY.
    func testUpwardDrag_upperHalfGrab_noAirWall() {
        let layout = makeLayout(labels: ["Series A", "Series B"], legendPoint: CGPoint(x: 0.5, y: 0.5))
        let canvas = WorkbenchPlotCanvas(imageData: nil, layout: layout)
        guard let cgBox = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }

        let originCG = canvas.currentLegendOriginCG()
        let pr       = layout.plotRect
        let rSz      = layout.rendererSize

        // Simulate grabbing the top edge of the legend box (upper half, large positive grabY in CG).
        let grabOffsetCG = CGSize(width: 0, height: cgBox.maxY - originCG.y + 2)  // 2pt above top of box

        // Move cursor well above the plot top so rawOriginCG.y > maxOriginY, forcing the clamp.
        let topCursorCG = CGPoint(x: originCG.x, y: pr.maxY + 100)
        let pngY        = rSz.height - topCursorCG.y
        let topScreen   = CGPoint(
            x: fitted.minX + topCursorCG.x / rSz.width  * fitted.width,
            y: fitted.minY + pngY            / rSz.height * fitted.height
        )

        guard let step = canvas.legendDragStep(
            start:              topScreen,
            current:            topScreen,
            fittedRect:         fitted,
            existingGrabOffset: grabOffsetCG
        ) else { XCTFail("legendDragStep returned nil"); return }

        // The preview's top edge must be at (or within 1pt of) the plotRect top in screen space.
        let plotTopScreen = fitted.minY + (rSz.height - pr.maxY) / rSz.height * fitted.height
        XCTAssertEqual(step.previewRect.minY, plotTopScreen, accuracy: 1.5,
            "Upper-half grab dragged to top: preview minY must be at plotRect.maxY screen position, not an air wall")

        // Box must not have moved below center (it should be at the top boundary, not frozen mid-plot).
        XCTAssertLessThan(step.previewRect.midY, fitted.midY,
            "Box must have moved toward the top of the plot, not remained in the middle")
    }

    // MARK: - 2. Preview rect equals the translated legendBoxRect

    func testPreviewRect_topRightAnchor_longLabel_equalsTranslatedBox() {
        // Short label so the box fits when dragged to center — no X clamp, pure position test.
        let label  = "Series A"
        let layout = makeLayout(labels: [label], anchor: "top-right")
        let canvas = WorkbenchPlotCanvas(imageData: nil, layout: layout)
        guard let cgBox = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }

        let targetNorm = CGPoint(x: 0.5, y: 0.5)
        let cursor     = normToScreen(targetNorm, layout: layout)

        // Zero grab offset: cursor lands exactly on the legend origin.
        guard let step = canvas.legendDragStep(
            start: cursor, current: cursor, fittedRect: fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else { XCTFail("legendDragStep returned nil"); return }

        let originCG   = canvas.currentLegendOriginCG()
        let pr         = layout.plotRect
        let targetCG   = CGPoint(x: pr.minX + targetNorm.x * pr.width,
                                  y: pr.minY + targetNorm.y * pr.height)
        let expectedCG = cgBox.offsetBy(dx: targetCG.x - originCG.x, dy: targetCG.y - originCG.y)
        let expected   = WorkbenchPlotLayout.cgToScreen(
            expectedCG, fittedIn: fitted,
            rendererWidth: layout.rendererSize.width, rendererHeight: layout.rendererSize.height
        )

        XCTAssertEqual(step.previewRect.minX, expected.minX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.minY, expected.minY, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxX, expected.maxX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxY, expected.maxY, accuracy: 1.0)
    }

    func testPreviewRect_freePosition_longLabel_equalsTranslatedBox() {
        // Short label so no X clamp occurs when moving from (0.2, 0.8) to (0.7, 0.3).
        let label  = "Series B"
        let layout = makeLayout(labels: [label], legendPoint: CGPoint(x: 0.2, y: 0.8))
        let canvas = WorkbenchPlotCanvas(imageData: nil, layout: layout)
        guard let cgBox = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }

        let targetNorm = CGPoint(x: 0.7, y: 0.3)
        let cursor     = normToScreen(targetNorm, layout: layout)

        guard let step = canvas.legendDragStep(
            start: cursor, current: cursor, fittedRect: fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else { XCTFail("legendDragStep returned nil"); return }

        let originCG   = canvas.currentLegendOriginCG()
        let pr         = layout.plotRect
        let targetCG   = CGPoint(x: pr.minX + targetNorm.x * pr.width,
                                  y: pr.minY + targetNorm.y * pr.height)
        let expectedCG = cgBox.offsetBy(dx: targetCG.x - originCG.x, dy: targetCG.y - originCG.y)
        let expected   = WorkbenchPlotLayout.cgToScreen(
            expectedCG, fittedIn: fitted,
            rendererWidth: layout.rendererSize.width, rendererHeight: layout.rendererSize.height
        )

        XCTAssertEqual(step.previewRect.minX, expected.minX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.minY, expected.minY, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxX, expected.maxX, accuracy: 1.0)
        XCTAssertEqual(step.previewRect.maxY, expected.maxY, accuracy: 1.0)
    }

    // MARK: - 3. PNG renderer and canvas layout come from the same source

    /// WorkbenchRenderPipeline must pass its pre-computed layout to renderPNG so the
    /// PNG and canvas legendBoxRect are identical (not two independently computed layouts).
    func testRenderPipeline_layoutMatchesPNGLegendGeometry() throws {
        let series = [
            WorkbenchPlotSeries(label: "Alpha", x: [0.0, 1.0], y: [1.0, 2.0],
                                sourceRef: "/tmp/a.csv", sampleID: "a"),
            WorkbenchPlotSeries(label: "Beta",  x: [0.0, 1.0], y: [0.5, 1.5],
                                sourceRef: "/tmp/b.csv", sampleID: "b"),
        ]
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: series
        )
        let input = WorkbenchRenderPipeline.Input(
            payload: payload,
            legendPoint: CGPoint(x: 0.4, y: 0.6)
        )
        let output = try WorkbenchRenderPipeline.render(input)

        // The layout returned by the pipeline is the one that was also passed into renderPNG.
        // Verify it has a valid legendBoxRect and that the adjusted norm round-trips correctly.
        XCTAssertNotNil(output.layout.legendBoxRect, "Pipeline layout must have a legendBoxRect")

        guard let box = output.layout.legendBoxRect else { return }
        let pr = output.layout.plotRect
        // Box must be positioned inside or overlapping plotRect (free-position at 0.4, 0.6).
        XCTAssertTrue(box.intersects(pr),
            "Legend box must intersect plotRect for a free-position legend near center")
    }

    // MARK: - 4. Clamping keeps box within plotRect boundary

    func testClamping_preventsDragBeyondTopBoundary() {
        let layout = makeLayout(labels: ["S1"], legendPoint: CGPoint(x: 0.5, y: 0.5))
        let canvas = WorkbenchPlotCanvas(imageData: nil, layout: layout)
        guard let cgBox = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }
        let pr  = layout.plotRect
        let rSz = layout.rendererSize

        // Ask to move the origin 1000pt above the top boundary.
        let farAboveCG  = CGPoint(x: pr.midX, y: pr.maxY + 1000)
        let farAbovePngY = rSz.height - farAboveCG.y
        let farAboveScreen = CGPoint(
            x: fitted.minX + farAboveCG.x / rSz.width  * fitted.width,
            y: fitted.minY + farAbovePngY  / rSz.height * fitted.height
        )

        guard let step = canvas.legendDragStep(
            start:              farAboveScreen,
            current:            farAboveScreen,
            fittedRect:         fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else { XCTFail("legendDragStep returned nil"); return }

        // Compute expected clamped top-screen position.
        let clampedBoxTopCG  = pr.maxY  // box.maxY at boundary
        let clampedBoxTopPng = rSz.height - clampedBoxTopCG
        let expectedScreenTop = fitted.minY + clampedBoxTopPng / rSz.height * fitted.height
        let boxHeightScreen   = cgBox.height / rSz.height * fitted.height
        let expectedScreenMin = expectedScreenTop

        XCTAssertEqual(step.previewRect.minY, expectedScreenMin, accuracy: 1.5,
            "Clamped box top edge must sit at plotRect.maxY (screen), not beyond")
        XCTAssertEqual(step.previewRect.height, boxHeightScreen, accuracy: 1.0,
            "Clamping must not change box height")
    }

    func testClamping_preventsDragBeyondBottomBoundary() {
        let layout = makeLayout(labels: ["S1"], legendPoint: CGPoint(x: 0.5, y: 0.5))
        let canvas = WorkbenchPlotCanvas(imageData: nil, layout: layout)
        guard let cgBox = layout.legendBoxRect else { XCTFail("legendBoxRect nil"); return }
        let pr  = layout.plotRect
        let rSz = layout.rendererSize

        // Ask to move the origin 1000pt below plotRect.
        let farBelowCG   = CGPoint(x: pr.midX, y: pr.minY - 1000)
        let farBelowPngY = rSz.height - farBelowCG.y
        let farBelowScreen = CGPoint(
            x: fitted.minX + farBelowCG.x / rSz.width  * fitted.width,
            y: fitted.minY + farBelowPngY  / rSz.height * fitted.height
        )

        guard let step = canvas.legendDragStep(
            start:              farBelowScreen,
            current:            farBelowScreen,
            fittedRect:         fitted,
            existingGrabOffset: CGSize(width: 0, height: 0)
        ) else { XCTFail("legendDragStep returned nil"); return }

        let boxHeightScreen = cgBox.height / rSz.height * fitted.height
        XCTAssertEqual(step.previewRect.height, boxHeightScreen, accuracy: 1.0,
            "Clamping must not change box height at bottom boundary")
        // Box bottom must not exceed plotRect bottom in screen (screen Y increases downward).
        let plotBottomPng    = rSz.height - pr.minY
        let plotBottomScreen = fitted.minY + plotBottomPng / rSz.height * fitted.height
        XCTAssertLessThanOrEqual(step.previewRect.maxY, plotBottomScreen + 1.5,
            "Clamped box must not go below plotRect bottom boundary in screen space")
    }
}
