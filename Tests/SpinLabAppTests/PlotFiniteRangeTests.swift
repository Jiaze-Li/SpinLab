import Foundation
import Testing
@testable import SpinLabApp

/// Characterization + regression tests for `PlotFiniteRange.compute`, the shared
/// finite-min/max helper used by both `PlotAxisBounds.resolve` (Cartesian) and
/// `DualAxisPlotLayout.dataRange` (Dual Axis).
///
/// Before this consolidation, Cartesian used a raw `values.min()`/`.max()` reduction,
/// which is order-dependent in the presence of NaN: a NaN first in the array poisons the
/// whole reduction (Swift comparisons against NaN are always false), while a NaN anywhere
/// else is silently skipped. Dual Axis already filtered `.isFinite` before reducing. This
/// file pins the shared helper's behavior and confirms both consumers now agree.
@Suite("PlotFiniteRange")
struct PlotFiniteRangeTests {

    // MARK: - PlotFiniteRange.compute characterization matrix

    @Test("finite-only values: returns exact min/max")
    func finiteOnly() {
        let result = PlotFiniteRange.compute([3.0, 1.0, 2.0])
        #expect(result?.min == 1.0)
        #expect(result?.max == 3.0)
    }

    @Test("NaN first: does not poison the reduction (unlike raw Array.min/max)")
    func nanFirst() {
        let result = PlotFiniteRange.compute([.nan, 1.0, 3.0, -2.0])
        #expect(result?.min == -2.0)
        #expect(result?.max == 3.0)
    }

    @Test("NaN last: reduction remains correct")
    func nanLast() {
        let result = PlotFiniteRange.compute([1.0, 3.0, -2.0, .nan])
        #expect(result?.min == -2.0)
        #expect(result?.max == 3.0)
    }

    @Test("mixed finite/NaN interspersed: all NaN ignored")
    func mixedFiniteAndNaN() {
        let result = PlotFiniteRange.compute([1.0, .nan, -5.0, .nan, 4.0])
        #expect(result?.min == -5.0)
        #expect(result?.max == 4.0)
    }

    @Test("+Infinity present: wins max as IEEE ordering predicts")
    func positiveInfinity() {
        let result = PlotFiniteRange.compute([1.0, .infinity, 3.0, -2.0])
        #expect(result?.min == -2.0)
        // Infinity itself is not finite, so it must be filtered out, not returned as max.
        #expect(result?.max == 3.0)
    }

    @Test("-Infinity present: excluded from min, not returned")
    func negativeInfinity() {
        let result = PlotFiniteRange.compute([1.0, -.infinity, 3.0, -2.0])
        #expect(result?.min == -2.0)
        #expect(result?.max == 3.0)
    }

    @Test("all non-finite: returns nil")
    func allNonFinite() {
        let result = PlotFiniteRange.compute([.nan, .infinity, -.infinity, .nan])
        #expect(result == nil)
    }

    @Test("empty array: returns nil")
    func emptyArray() {
        let result = PlotFiniteRange.compute([])
        #expect(result == nil)
    }

    // MARK: - Cartesian regression: PlotAxisBounds ignores non-finite values

    private func series(_ x: [Double], _ y: [Double]) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(label: "S", x: x, y: y)
    }

    private func payload(_ series: [WorkbenchPlotSeries]) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "finite-range",
            workflowDisplayName: "FiniteRange",
            title: "FiniteRange",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: series
        )
    }

    @Test("Cartesian bounds: a leading NaN no longer poisons the whole axis range")
    func cartesianBoundsIgnoreLeadingNaN() {
        let poisoned = payload([series([.nan, 1, 2, 3], [.nan, 10, 20, 30])])
        let clean = payload([series([1, 2, 3], [10, 20, 30])])

        let poisonedBounds = PlotAxisBounds.resolve(payload: poisoned, options: .init())
        let cleanBounds = PlotAxisBounds.resolve(payload: clean, options: .init())

        #expect(poisonedBounds.xMin == cleanBounds.xMin)
        #expect(poisonedBounds.xMax == cleanBounds.xMax)
        #expect(poisonedBounds.yMin == cleanBounds.yMin)
        #expect(poisonedBounds.yMax == cleanBounds.yMax)
        #expect(!poisonedBounds.xMin.isNaN)
        #expect(!poisonedBounds.xMax.isNaN)
    }

    @Test("Cartesian bounds: ±Infinity is excluded from the padded range")
    func cartesianBoundsExcludeInfinity() {
        let withInf = payload([series([1, 2, .infinity], [10, 20, -.infinity])])
        let clean = payload([series([1, 2], [10, 20])])

        let infBounds = PlotAxisBounds.resolve(payload: withInf, options: .init())
        let cleanBounds = PlotAxisBounds.resolve(payload: clean, options: .init())

        #expect(infBounds.xMin == cleanBounds.xMin)
        #expect(infBounds.xMax == cleanBounds.xMax)
        #expect(infBounds.yMin == cleanBounds.yMin)
        #expect(infBounds.yMax == cleanBounds.yMax)
    }

    @Test("Cartesian bounds: all-non-finite series falls back like empty data (0, 1) before padding")
    func cartesianBoundsAllNonFiniteFallsBackLikeEmpty() {
        let allNaN = payload([series([.nan, .nan], [.infinity, -.infinity])])
        let empty = payload([series([], [])])

        let allNaNBounds = PlotAxisBounds.resolve(payload: allNaN, options: .init())
        let emptyBounds = PlotAxisBounds.resolve(payload: empty, options: .init())

        #expect(allNaNBounds.xMin == emptyBounds.xMin)
        #expect(allNaNBounds.xMax == emptyBounds.xMax)
        #expect(allNaNBounds.yMin == emptyBounds.yMin)
        #expect(allNaNBounds.yMax == emptyBounds.yMax)
    }

    // MARK: - Existing padding/fixed-bound behavior unaffected by the shared helper

    @Test("Cartesian bounds: ordinary finite data still gets exact 5% padding via shared helper")
    func cartesianOrdinaryDataUnaffected() {
        let bounds = PlotAxisBounds.resolve(payload: payload([series([0, 10], [0, 100])]), options: .init())
        #expect(bounds.xMin == -0.5)
        #expect(bounds.xMax == 10.5)
        #expect(bounds.yMin == -5.0)
        #expect(bounds.yMax == 105.0)
    }

    @Test("Cartesian bounds: fixed bounds still bypass the finite-range computation entirely")
    func cartesianFixedBoundsUnaffectedByNaN() {
        var options = WorkbenchChartRenderer.Options()
        options.fixedXMin = 0
        options.fixedXMax = 360
        let bounds = PlotAxisBounds.resolve(
            payload: payload([series([.nan, 100, 200], [.nan, 1, 2])]),
            options: options
        )
        #expect(bounds.xMin == 0)
        #expect(bounds.xMax == 360)
        #expect(!bounds.yMin.isNaN)
        #expect(!bounds.yMax.isNaN)
    }

    // MARK: - Dual Axis regression: dataRange behavior unchanged

    @Test("Dual Axis dataRange: NaN-filtering behavior unchanged after sharing the helper")
    func dualAxisDataRangeUnchanged() {
        let (lo, hi) = DualAxisPlotLayout.dataRange(from: [.nan, 2.0, .infinity, 5.0, -.infinity])
        #expect(lo == 2.0)
        #expect(hi == 5.0)
    }

    @Test("Dual Axis dataRange: empty input still falls back to (0, 1)")
    func dualAxisDataRangeEmptyUnchanged() {
        let (lo, hi) = DualAxisPlotLayout.dataRange(from: [])
        #expect(lo == 0)
        #expect(hi == 1)
    }

    @Test("Dual Axis dataRange: single value still falls back to ±1 degenerate span")
    func dualAxisDataRangeSingleValueUnchanged() {
        let (lo, hi) = DualAxisPlotLayout.dataRange(from: [3.0])
        #expect(lo == 2.0)
        #expect(hi == 4.0)
    }
}
