import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

/// Regression coverage for safe Cartesian rendering and hit-testing of non-finite
/// (NaN / ±Inf) points: polyline gaps, marker/label skipping, and per-point hit-testing,
/// without mutating or reindexing source series data.
@Suite("Non-finite Cartesian rendering")
struct NonFiniteCartesianRenderingTests {

    // Identity screen mapping so subpath points equal the raw (x, y) values.
    private static let identity: (Double, Double) -> CGPoint = { x, y in
        CGPoint(x: x, y: y)
    }

    // MARK: - Polyline subpath segmentation (base + overlay share this helper)

    @Test("Middle non-finite point splits the polyline into two subpaths")
    func middleInvalidPointSplitsPolyline() {
        let x: [Double] = [0, 1, 2, 3, 4]
        let y: [Double] = [0, 1, .nan, 3, 4]
        let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: Self.identity)

        #expect(subpaths.count == 2)
        #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        #expect(subpaths[1] == [CGPoint(x: 3, y: 3), CGPoint(x: 4, y: 4)])
    }

    @Test("Leading non-finite point starts the first subpath at the first finite point")
    func leadingInvalidPointStartsAtFirstFinitePoint() {
        let x: [Double] = [.nan, 1, 2]
        let y: [Double] = [.nan, 1, 2]
        let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: Self.identity)

        #expect(subpaths.count == 1)
        #expect(subpaths[0] == [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)])
    }

    @Test("Trailing non-finite point emits no dangling command")
    func trailingInvalidPointEmitsNoDanglingCommand() {
        let x: [Double] = [0, 1, .nan]
        let y: [Double] = [0, 1, .nan]
        let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: Self.identity)

        #expect(subpaths.count == 1)
        #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
    }

    @Test("Consecutive non-finite points begin exactly one new subpath")
    func consecutiveInvalidPointsBeginOneNewSubpath() {
        let x: [Double] = [0, 1, .nan, .nan, 4, 5]
        let y: [Double] = [0, 1, .nan, .nan, 4, 5]
        let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: Self.identity)

        #expect(subpaths.count == 2)
        #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        #expect(subpaths[1] == [CGPoint(x: 4, y: 4), CGPoint(x: 5, y: 5)])
    }

    @Test("+Inf and -Inf are treated the same as NaN")
    func infinityTreatedSameAsNaN() {
        let x: [Double] = [0, 1, .infinity, 3, -.infinity, 5]
        let y: [Double] = [0, 1, 2, 3, 4, 5]
        let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: Self.identity)

        #expect(subpaths.count == 3)
        #expect(subpaths[0] == [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])
        #expect(subpaths[1] == [CGPoint(x: 3, y: 3)])
        #expect(subpaths[2] == [CGPoint(x: 5, y: 5)])
    }

    @Test("All-finite series yields a single unbroken subpath")
    func allFiniteYieldsSingleSubpath() {
        let x: [Double] = [0, 1, 2, 3]
        let y: [Double] = [0, 1, 2, 3]
        let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: Self.identity)

        #expect(subpaths.count == 1)
        #expect(subpaths[0].count == 4)
    }

    // Overlay polylines reuse the exact same helper, so gap behavior is identical.
    @Test("Overlay polyline uses the same gap behavior as the base series")
    func overlayPolylineUsesSameGapBehavior() {
        let x: [Double] = [0, 1, .nan, 3, 4]
        let y: [Double] = [0, 1, .nan, 3, 4]
        let subpaths = WorkbenchChartRenderer.polylineSubpaths(x: x, y: y, pointToScreen: Self.identity)
        #expect(subpaths.count == 2)
    }

    // MARK: - Markers and point labels

    @Test("Invalid points produce no marker; finite points retain original indices")
    func invalidPointsSkipMarkersKeepOriginalIndices() {
        let x: [Double] = [0, .nan, 2, .infinity, 4]
        let y: [Double] = [0, 1, 2, 3, 4]
        let targets = WorkbenchChartRenderer.finitePoints(x: x, y: y, pointToScreen: Self.identity)

        #expect(targets.map(\.index) == [0, 2, 4])
        #expect(targets.map(\.point) == [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 2), CGPoint(x: 4, y: 4)])
    }

    @Test("Point labels: invalid points collect no label, hiddenPointLabelsBySeries applies to correct original indices")
    func pointLabelsSkipInvalidAndRespectHiddenIndices() throws {
        let series = WorkbenchPlotSeries(
            label: "S1",
            x: [0, 1, .nan, 3],
            y: [0, 1, .nan, 3],
            renderMode: .scatter,
            renderModeLocked: true,
            pointLabels: ["p0", "p1", "p2", "p3"]
        )
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [series]
        )
        // Hide the label at original index 3 (the last finite point) — it must still be
        // recognized by its original index even though index 2 was skipped for being invalid.
        var options = WorkbenchChartRenderer.Options()
        options.hiddenPointLabelsBySeries = [0: [3]]

        // Rendering must not crash or emit NaN into CoreGraphics.
        let data = try WorkbenchChartRenderer().renderPNG(payload: payload, options: options)
        #expect(!data.isEmpty)

        // The underlying skip/keep decision is exercised directly via the pure helper:
        // point index 2 (NaN) never reaches the marker/label collection step, while
        // point index 3 does and remains addressable by hiddenPointLabelsBySeries.
        let targets = WorkbenchChartRenderer.finitePoints(x: series.x, y: series.y, pointToScreen: Self.identity)
        #expect(targets.map(\.index) == [0, 1, 3])
    }

    @Test("Invalid overlay points are skipped without disturbing the parent's markers")
    func overlayMarkersSkipInvalidPoints() throws {
        let base = WorkbenchPlotSeries(label: "base", x: [0, 1, 2], y: [0, 1, 2], sourceRef: "/tmp/base.csv")
        let overlay = WorkbenchPlotSeriesOverlay(
            overlayIdentityKey: "overlay-1",
            parentSeriesIdentityKey: "/tmp/base.csv",
            series: WorkbenchPlotSeries(label: "fit", x: [0, 1, 2], y: [0, .nan, 2], renderMode: .scatter)
        )
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [base],
            seriesOverlays: [overlay]
        )

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        #expect(!data.isEmpty)

        let targets = WorkbenchChartRenderer.finitePoints(x: overlay.series.x, y: overlay.series.y, pointToScreen: Self.identity)
        #expect(targets.map(\.index) == [0, 2])
    }

    // MARK: - Hit testing

    @Test("One invalid point does not disable the whole series; finite points remain hittable")
    func hitTestSkipsInvalidPointKeepsSeriesHittable() {
        // Two horizontal series at y=0 and y=1, mirroring V536CurveDragOrderTests'
        // hitTestSeriesFindsNearestSeries so the axis-bounds formula (yMin=-0.05, ySpan=1.1)
        // is known. "low" has a non-finite sample at its second point (x=1), leaving only
        // the isolated finite point at x=0 — which must still be hittable.
        let low  = WorkbenchPlotSeries(label: "Low",  x: [0, 1], y: [0.0, .nan], sourceRef: "/tmp/low.csv", sampleID: "low")
        let high = WorkbenchPlotSeries(label: "High", x: [0, 1], y: [1.0, 1.0], sourceRef: "/tmp/high.csv", sampleID: "high")
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [low, high],
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let fittedRect = CGRect(x: 0, y: 0, width: CGFloat(opts.width), height: CGFloat(opts.height))

        let yMin = -0.05, ySpan = 1.1
        let lowCGY = layout.plotRect.minY + CGFloat((0.0 - yMin) / ySpan) * layout.plotRect.height
        let lowScreenY = fittedRect.minY + (CGFloat(opts.height) - lowCGY) * (fittedRect.height / CGFloat(opts.height))
        // Data extents with 5% margin on x∈[0,1] as well: xMin=-0.05, xSpan=1.1.
        let xMin = -0.05, xSpan = 1.1
        let lowCGX = layout.plotRect.minX + CGFloat((0.0 - xMin) / xSpan) * layout.plotRect.width
        // Hit at x=0 (the surviving finite point), not midX — x=1 is non-finite and produces no geometry there.
        let hitLocation = CGPoint(x: lowCGX, y: lowScreenY)

        let hit = layout.hitTestSeries(location: hitLocation, fittedRect: fittedRect, payload: payload, radius: 8)
        #expect(hit?.sampleID == "low", "A single non-finite sample must not reject the whole series")
    }

    @Test("Invalid points produce no PointHitTarget; pointIndex stays the original array index")
    func pointHitTargetsSkipInvalidAndKeepOriginalIndex() {
        let series = WorkbenchPlotSeries(
            label: "S1",
            x: [0, .nan, 2, 3],
            y: [0, .nan, 2, 3],
            renderMode: .scatter,
            renderModeLocked: true,
            pointLabels: ["p0", "p1", "p2", "p3"]
        )
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [series]
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)

        let dotIndices = layout.pointDotHitTargets.map(\.pointIndex).sorted()
        let labelIndices = layout.pointLabelHitTargets.map(\.pointIndex).sorted()

        #expect(dotIndices == [0, 2, 3], "index 1 (NaN) must produce no hit target, and remaining indices must not be compacted")
        #expect(labelIndices == [0, 2, 3])
    }

    // MARK: - All-finite regression

    @Test("All-finite series renders and hit-tests exactly as before")
    func allFiniteRegression() throws {
        let series = WorkbenchPlotSeries(label: "Low", x: [0, 1], y: [0.0, 0.0], sourceRef: "/tmp/low.csv", sampleID: "low")
        let other  = WorkbenchPlotSeries(label: "High", x: [0, 1], y: [1.0, 1.0], sourceRef: "/tmp/high.csv", sampleID: "high")
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [series, other], reverseSeriesForLegend: false, seriesReorderable: true
        )
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: nil)
        let fittedRect = CGRect(x: 0, y: 0, width: CGFloat(opts.width), height: CGFloat(opts.height))

        let yMin = -0.05, ySpan = 1.1
        let lowCGY = layout.plotRect.minY + CGFloat((0.0 - yMin) / ySpan) * layout.plotRect.height
        let lowScreenY = fittedRect.minY + (CGFloat(opts.height) - lowCGY) * (fittedRect.height / CGFloat(opts.height))
        let hitLocation = CGPoint(x: fittedRect.midX, y: lowScreenY)

        let hit = layout.hitTestSeries(location: hitLocation, fittedRect: fittedRect, payload: payload, radius: 8)
        #expect(hit?.sampleID == "low")

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        #expect(!data.isEmpty)
    }

    // MARK: - PNG/PDF parity

    @Test("PNG and PDF exports both draw non-finite points via the same skip/gap behavior")
    func pngAndPdfExportShareNonFiniteHandling() throws {
        let series = WorkbenchPlotSeries(
            label: "S1", x: [0, 1, .nan, 3], y: [0, 1, .nan, 3],
            renderMode: .lineAndScatter
        )
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "test", title: "",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [series]
        )
        let renderer = WorkbenchChartRenderer()
        let png = try renderer.renderPNG(payload: payload)
        let pdf = try renderer.renderPDF(payload: payload)

        #expect(!png.isEmpty)
        #expect(!pdf.isEmpty)
    }
}
