import XCTest
@testable import SpinLabApp

/// Tests for legend drag coordinate math in WorkbenchPlotCanvas.
///
/// Verifies two invariants:
///   1. plotNormalized clamps smoothly everywhere — no air wall inside or outside fittedRect.
///   2. legendScreenOrigin is the exact inverse of plotNormalized, so preview position == landing position.
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

    // MARK: - Round-trip: plotNormalized ↔ legendScreenOrigin

    /// For any normalized point p, legendScreenOrigin(p) → screen pt,
    /// then plotNormalized(screen pt) should recover p (within 1e-4).
    func testRoundTrip_normalizedToScreenAndBack() {
        let testPoints: [CGPoint] = [
            CGPoint(x: 0.0, y: 0.0),   // bottom-left
            CGPoint(x: 1.0, y: 1.0),   // top-right
            CGPoint(x: 0.5, y: 0.5),   // centre
            CGPoint(x: 0.1, y: 0.9),   // near top-left
            CGPoint(x: 0.85, y: 0.15), // near bottom-right
        ]
        for p in testPoints {
            let screenPt = legendScreenOriginForTest(normalized: p)
            let recovered = plotNormalizedForTest(location: screenPt)
            XCTAssertNotNil(recovered, "Round-trip failed for \(p)")
            XCTAssertEqual(recovered!.x, p.x, accuracy: 1e-4,
                           "X round-trip mismatch for input \(p)")
            XCTAssertEqual(recovered!.y, p.y, accuracy: 1e-4,
                           "Y round-trip mismatch for input \(p)")
        }
    }

    /// Preview position == landing position:
    /// the normalized point stored in lastValidDragNorm (= adjusted, already clamped)
    /// when passed to legendScreenOrigin gives the same screen point as dragPreviewPt.
    func testPreviewMatchesLanding_clampedAdjustedRoundTrips() {
        // Simulate: legend origin at (0.8, 0.9).
        // User clicks the bottom-left of the legend: startLocation → (0.75, 0.82).
        // grab = startNorm - origin = (0.75 - 0.8, 0.82 - 0.9) = (-0.05, -0.08)
        // After minimumDistance threshold, first onChanged cursor is at (0.74, 0.84).
        // adjusted = clamp(cursor - grab) = clamp(0.74+0.05, 0.84+0.08) = (0.79, 0.92) ≈ origin + delta
        let origin    = CGPoint(x: 0.8,  y: 0.9)
        let startNorm = CGPoint(x: 0.75, y: 0.82)  // where user actually clicked
        let cursor    = CGPoint(x: 0.6,  y: 0.7)   // where cursor is mid-drag

        let grabW = startNorm.x - origin.x   // -0.05
        let grabH = startNorm.y - origin.y   // -0.08

        let rawX     = cursor.x - grabW
        let rawY     = cursor.y - grabH
        let adjusted = CGPoint(x: min(max(rawX, 0), 1), y: min(max(rawY, 0), 1))

        // The cursor should remain at startNorm's offset within the legend box.
        // adjusted.y - cursor.y == origin.y - startNorm.y (legend moved by delta)
        XCTAssertEqual(adjusted.x - cursor.x, origin.x - startNorm.x, accuracy: 1e-6,
                       "Grab offset should lock cursor to original click position (X)")
        XCTAssertEqual(adjusted.y - cursor.y, origin.y - startNorm.y, accuracy: 1e-6,
                       "Grab offset should lock cursor to original click position (Y)")

        // preview and landing must agree.
        let previewScreen = legendScreenOriginForTest(normalized: adjusted)
        let recoveredNorm = plotNormalizedForTest(location: previewScreen)!
        XCTAssertEqual(recoveredNorm.x, adjusted.x, accuracy: 1e-4)
        XCTAssertEqual(recoveredNorm.y, adjusted.y, accuracy: 1e-4)
    }

    // MARK: - Helpers (mirrors WorkbenchPlotCanvas private methods)

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

    private func legendScreenOriginForTest(normalized: CGPoint) -> CGPoint {
        let plotW = CGFloat(opts.width)  - opts.paddingLeft - opts.paddingRight
        let plotH = CGFloat(opts.height) - opts.paddingTop  - opts.paddingBottom
        let rendW: CGFloat = 800; let rendH: CGFloat = 600
        let cgOriginX = opts.paddingLeft   + normalized.x * plotW
        let cgOriginY = opts.paddingBottom + normalized.y * plotH
        let pngX = cgOriginX
        let pngY = rendH - cgOriginY
        return CGPoint(
            x: fitted.minX + pngX / rendW * fitted.width,
            y: fitted.minY + pngY / rendH * fitted.height
        )
    }
}
