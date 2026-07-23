import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

/// Characterization + regression tests for the canonical Cartesian axis-bounds
/// consolidation (`PlotAxisBounds`).
///
/// `PlotAxisLayoutPlan`, `WorkbenchChartRenderer`, and `WorkbenchPlotLayout` used to
/// each independently recompute raw min/max, span, and ±5% padding. This file pins:
///   1. The exact `PlotAxisBounds.resolve` formula for the required scenario matrix.
///   2. That all three Cartesian consumers agree on the same resolved bounds.
///
/// Before this consolidation, PlotAxisLayoutPlan left X completely unpadded (only Y was
/// padded) while WorkbenchChartRenderer/WorkbenchPlotLayout already padded X by 5% — a
/// real pre-existing misalignment between tick marks and plotted data points on the X
/// axis of every auto-ranged Cartesian chart. Canonicalizing on one shared bounds value
/// necessarily resolves that inconsistency in favor of "5% padding on both axes unless a
/// bound is fixed," which is what the majority of call sites, and the product
/// requirement, already expected.
@Suite("Cartesian axis bounds consolidation")
struct CartesianAxisBoundsConsolidationTests {

    private func series(_ x: [Double], _ y: [Double]) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(label: "S", x: x, y: y)
    }

    private func payload(_ series: [WorkbenchPlotSeries]) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "bounds",
            workflowDisplayName: "Bounds",
            title: "Bounds",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: series
        )
    }

    // MARK: - PlotAxisBounds.resolve formula matrix

    @Test("ordinary positive data: 5% padding both axes")
    func ordinaryPositiveData() {
        let p = payload([series([10, 20, 30], [100, 200, 300])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: .init())
        // xSpan = 20, pad = 1 -> [9, 31]; ySpan = 200, pad = 10 -> [90, 310]
        #expect(bounds.xMin == 9)
        #expect(bounds.xMax == 31)
        #expect(bounds.yMin == 90)
        #expect(bounds.yMax == 310)
    }

    @Test("ordinary negative data: 5% padding both axes")
    func ordinaryNegativeData() {
        let p = payload([series([-30, -20, -10], [-300, -200, -100])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: .init())
        #expect(bounds.xMin == -31)
        #expect(bounds.xMax == -9)
        #expect(bounds.yMin == -310)
        #expect(bounds.yMax == -90)
    }

    @Test("data crossing zero: padding does not force zero into range")
    func dataCrossingZero() {
        let p = payload([series([-10, 0, 10], [-5, 5, 15])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: .init())
        // xSpan = 20, pad 1 -> [-11, 11]; ySpan = 20, pad 1 -> [-6, 16]
        #expect(bounds.xMin == -11)
        #expect(bounds.xMax == 11)
        #expect(bounds.yMin == -6)
        #expect(bounds.yMax == 16)
    }

    @Test("single-point data: degenerate span fallback of 1.0, absolute ±0.05 pad")
    func singlePointData() {
        let p = payload([series([5], [7])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: .init())
        #expect(bounds.xMin == 4.95)
        #expect(bounds.xMax == 5.05)
        #expect(bounds.yMin == 6.95)
        #expect(bounds.yMax == 7.05)
    }

    @Test("constant-valued series: degenerate span fallback of 1.0, same as single point")
    func constantValuedSeries() {
        let p = payload([series([1, 2, 3], [42, 42, 42])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: .init())
        // x is non-degenerate: span=2, pad=0.1 -> [0.9, 3.1]
        #expect(bounds.xMin == 0.9)
        #expect(bounds.xMax == 3.1)
        // y is degenerate (all 42): span fallback 1.0, pad 0.05 -> [41.95, 42.05]
        #expect(bounds.yMin == 41.95)
        #expect(bounds.yMax == 42.05)
    }

    @Test("empty series: falls back to default (0,1) raw extent before padding")
    func emptySeriesFallback() {
        let p = payload([])
        let bounds = PlotAxisBounds.resolve(payload: p, options: .init())
        // rawMin=0, rawMax=1, span=1, pad=0.05
        #expect(bounds.xMin == -0.05)
        #expect(bounds.xMax == 1.05)
        #expect(bounds.yMin == -0.05)
        #expect(bounds.yMax == 1.05)
    }

    @Test("hidden series (excluded upstream) behave like a smaller payload")
    func hiddenSeriesExcludedUpstreamMatchesSmallerPayload() {
        // WorkbenchRenderPipeline.applySeriesVisibility drops hidden series from
        // payload.series before any bounds calculation ever sees them — PlotAxisBounds
        // itself has no visibility concept, it just sees whatever series remain.
        let full = payload([series([1, 2], [1, 2]), series([100, 200], [100, 200])])
        let withSecondHiddenUpstream = payload([series([1, 2], [1, 2])])
        let boundsFull = PlotAxisBounds.resolve(payload: full, options: .init())
        let boundsFiltered = PlotAxisBounds.resolve(payload: withSecondHiddenUpstream, options: .init())
        #expect(boundsFull.xMax > boundsFiltered.xMax)
        #expect(boundsFiltered.xMax == 2.05)
    }

    @Test("fixed lower bound only: opposite bound uses padded automatic value from the pure data span")
    func fixedLowerBoundOnly() {
        var opts = WorkbenchChartRenderer.Options()
        opts.fixedXMin = 5
        opts.fixedYMin = 50
        let p = payload([series([10, 20, 30], [100, 200, 300])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: opts)
        #expect(bounds.xMin == 5)
        // xMax uses the padded automatic value computed from the *pure data span* (30-10=20),
        // not a span re-derived using the fixed 5 as one endpoint.
        #expect(bounds.xMax == 31)
        #expect(bounds.yMin == 50)
        #expect(bounds.yMax == 310)
    }

    @Test("fixed upper bound only: opposite bound uses padded automatic value from the pure data span")
    func fixedUpperBoundOnly() {
        var opts = WorkbenchChartRenderer.Options()
        opts.fixedXMax = 35
        opts.fixedYMax = 350
        let p = payload([series([10, 20, 30], [100, 200, 300])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: opts)
        #expect(bounds.xMin == 9)
        #expect(bounds.xMax == 35)
        #expect(bounds.yMin == 90)
        #expect(bounds.yMax == 350)
    }

    @Test("both fixed bounds: no padding applied, raw data ignored entirely")
    func bothFixedBounds() {
        var opts = WorkbenchChartRenderer.Options()
        opts.fixedXMin = 0
        opts.fixedXMax = 100
        opts.fixedYMin = -1
        opts.fixedYMax = 1
        let p = payload([series([10, 20, 30], [100, 200, 300])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: opts)
        #expect(bounds.xMin == 0)
        #expect(bounds.xMax == 100)
        #expect(bounds.yMin == -1)
        #expect(bounds.yMax == 1)
    }

    @Test("XY Rotation fixed x lower bound (0...360 convention): Y stays auto-padded")
    func xyRotationFixedXConvention() {
        var opts = WorkbenchChartRenderer.Options()
        opts.fixedXMin = 0 // mirrors XYRotationPlotRenderer's fixedXMin = 0 convention
        let p = payload([series([0.5, 90, 180, 270, 350], [1.0, 2.0, 1.5, 0.5, 1.2])])
        let bounds = PlotAxisBounds.resolve(payload: p, options: opts)
        #expect(bounds.xMin == 0)
        // xRawSpan (pure data) = 350 - 0.5 = 349.5; pad = 17.475 -> xMax = 367.475
        #expect(abs(bounds.xMax - 367.475) < 1e-9)
        #expect(bounds.yMin < 0.5)
        #expect(bounds.yMax > 2.0)
    }

    // MARK: - Cross-consumer regression: canonical bounds shared by all three Cartesian paths

    @Test("layout bounds equal renderer coordinate bounds")
    func layoutBoundsEqualRendererBounds() {
        let p = payload([series([10, 20, 30], [100, 200, 300])])
        let opts = WorkbenchChartRenderer.Options()
        let plan = PlotAxisLayoutPlan.compute(options: opts, payload: p)
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: p, legendPoint: nil)
        let bounds = PlotAxisBounds.resolve(payload: p, options: opts)

        // PlotAxisLayoutPlan's xTicks/yTicks pixel positions are mapped using the same
        // canonical bounds: reconstruct the min/span used from two known tick values to
        // prove the plan did not use a different denominator than the canonical bounds.
        #expect(layout.axisXMin == bounds.xMin)
        #expect(layout.axisXMax == bounds.xMax)
        #expect(layout.axisYMin == bounds.yMin)
        #expect(layout.axisYMax == bounds.yMax)
        #expect(plan.plotRect == layout.plotRect)
    }

    @Test("renderer bounds equal hit-test bounds")
    func rendererBoundsEqualHitTestBounds() {
        let p = payload([series([10, 20, 30], [100, 200, 300])])
        let opts = WorkbenchChartRenderer.Options()
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: p, legendPoint: nil)
        let bounds = PlotAxisBounds.resolve(payload: p, options: opts)

        // hitTestSeries uses layout.axisXMin/axisXMax/axisYMin/axisYMax directly (source read,
        // not re-derived) — assert those stored fields equal the canonical resolved bounds,
        // which is what both the renderer's point-plotting and the hit-tester read from.
        #expect(layout.axisXMin == bounds.xMin)
        #expect(layout.axisXMax == bounds.xMax)
        #expect(layout.axisYMin == bounds.yMin)
        #expect(layout.axisYMax == bounds.yMax)
    }

    @Test("PlotAxisLayoutPlan tick pixel mapping uses the same denominator as data-point pixel mapping")
    func tickAndPointPixelMappingAgree() throws {
        // This is the concrete regression for the pre-existing X-axis misalignment bug:
        // before consolidation, PlotAxisLayoutPlan's ticks used raw unpadded X for BOTH
        // tick-value selection AND pixel mapping, while WorkbenchChartRenderer's pt() and
        // WorkbenchPlotLayout's hit-test axis already padded X by 5%. A data point sitting
        // exactly at the raw max would render at a different pixel X than a tick placed at
        // that same data value.
        //
        // Derive PlotAxisLayoutPlan's actual pixel-mapping denominator from two known tick
        // values placed by `plan.xTicks`, rather than reading `layout.axisXMin/axisXMax`
        // directly — this must independently reconstruct what PlotAxisLayoutPlan itself
        // used internally, not just compare two copies of the same precomputed field.
        let p = payload([series([10, 20, 30], [100, 200, 300])])
        let opts = WorkbenchChartRenderer.Options()
        let plan = PlotAxisLayoutPlan.compute(options: opts, payload: p)
        let bounds = PlotAxisBounds.resolve(payload: p, options: opts)

        let ticks = plan.xTicks
        try #require(ticks.count >= 2)
        let t0 = ticks[0], t1 = ticks[1]
        // tickPoint.x = plotRect.minX + (value - xMin)/xSpan * plotRect.width
        // Solve two known (value, pixel) pairs for the implied xMin/xSpan actually used.
        let impliedSlope = (t1.tickPoint.x - t0.tickPoint.x) / CGFloat(t1.value - t0.value)
        let impliedXMin = t0.value - Double((t0.tickPoint.x - plan.plotRect.minX) / impliedSlope)
        let canonicalSlope = plan.plotRect.width / CGFloat(bounds.xMax - bounds.xMin)

        #expect(abs(impliedSlope - canonicalSlope) < 0.01)
        #expect(abs(impliedXMin - bounds.xMin) < 0.01)
    }

    @Test("no duplicate ±5% padding formula remains outside PlotAxisBounds")
    func noDuplicatePaddingFormulaRemains() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift",
            "Sources/SpinLabApp/Workbench/V3/WorkbenchPlotLayout.swift",
        ]
        for relative in files {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            #expect(!source.contains("* 0.05"),
                    "\(relative) must not recompute ±5% padding independently; it must consume PlotAxisBounds")
        }
        let planSource = try String(
            contentsOf: root.appendingPathComponent("Sources/SpinLabApp/Workbench/V3/PlotAxisLayout.swift"),
            encoding: .utf8
        )
        // PlotAxisLayoutPlan is allowed exactly one owner of the "* 0.05" padding formula:
        // PlotAxisBounds.resolve, which has 4 occurrences (xMin, xMax, yMin, yMax pad terms).
        // PlotAxisLayoutPlan.compute itself must not recompute padding independently.
        let occurrences = planSource.components(separatedBy: "* 0.05").count - 1
        #expect(occurrences == 4, "expected exactly 4 occurrences of \"* 0.05\" (all inside PlotAxisBounds.resolve), found \(occurrences)")
    }
}
