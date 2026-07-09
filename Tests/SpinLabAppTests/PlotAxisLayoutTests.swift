import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

private func plotAxisLayoutRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpinLabAppTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
}

private func loadPlotAxisSource(_ relativePath: String) throws -> String {
    let url = plotAxisLayoutRepoRoot().appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

private func testNiceTicks(min: Double, max: Double, targetCount: Int = 5) -> (ticks: [Double], step: Double) {
    let result = PlotAxisSpacingCalculator.niceTicks(min: min, max: max, targetCount: targetCount)
    let roundedTicks = result.ticks.map { ($0 * 1e12).rounded() / 1e12 }
    return (roundedTicks, result.step)
}

@Suite("PlotAxisLayout")
struct PlotAxisLayoutTests {

    @Test("PlotTextMeasurer measures stable widths")
    func plotTextMeasurerMeasuresStableWidths() {
        let empty = PlotTextMeasurer.measuredWidth(
            "",
            fontSize: 19,
            fontName: WorkbenchChartStyle().fontName,
            boldFontName: WorkbenchChartStyle().boldFontName
        )
        let short = PlotTextMeasurer.measuredWidth(
            "Y1",
            fontSize: 19,
            fontName: WorkbenchChartStyle().fontName,
            boldFontName: WorkbenchChartStyle().boldFontName
        )
        let long = PlotTextMeasurer.measuredWidth(
            "Y123456789",
            fontSize: 19,
            fontName: WorkbenchChartStyle().fontName,
            boldFontName: WorkbenchChartStyle().boldFontName
        )
        let repeatShort = PlotTextMeasurer.measuredWidth(
            "Y1",
            fontSize: 19,
            fontName: WorkbenchChartStyle().fontName,
            boldFontName: WorkbenchChartStyle().boldFontName
        )

        #expect(empty == 0)
        #expect(long > short)
        #expect(abs(short - repeatShort) < 0.0001)
    }

    @Test("XY and heatmap call the shared measurement helper")
    func xyAndHeatmapUseSharedMeasurementHelper() {
        let style = WorkbenchChartStyle()
        let text = "Intensity (counts)"
        let shared = PlotTextMeasurer.measuredWidth(
            text,
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName,
            boldFontName: style.boldFontName
        )
        let xy = WorkbenchChartRenderer().measureTextWidth(
            text,
            size: style.axisTitleFontSize,
            style: style
        )
        let heatmap = HeatmapPlotLayout.measuredTextWidth(
            text,
            fontSize: style.axisTitleFontSize,
            fontName: style.fontName,
            boldFontName: style.boldFontName
        )

        #expect(abs(shared - xy) < 0.0001)
        #expect(abs(shared - heatmap) < 0.0001)
    }

    @Test("Y-axis lane spacing responds to tick label width")
    func yAxisLaneSpacingRespondsToTickLabelWidth() {
        let style = WorkbenchChartStyle()
        let short = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "Y",
            tickLabels: ["1", "2"],
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80,
            maxSideInset: 220
        )
        let long = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "Y",
            tickLabels: ["12345", "678901234"],
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80,
            maxSideInset: 220
        )
        let empty = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "",
            tickLabels: [],
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80,
            maxSideInset: 220
        )

        #expect(short.maxTickLabelWidth < long.maxTickLabelWidth)
        #expect(short.requiredLeftPadding < long.requiredLeftPadding)
        #expect(short.requiredLeftPadding >= 80)
        #expect(short.titleCenterX < short.tickLabelLaneLeadingX)
        #expect(short.tickLabelLaneTrailingX <= short.requiredLeftPadding)
        #expect(long.titleCenterX < long.tickLabelLaneLeadingX)
        #expect(long.tickLabelLaneTrailingX <= long.requiredLeftPadding)
        #expect(empty.maxTickLabelWidth == 0)
        #expect(empty.axisTitleTextWidth == 0)
        #expect(empty.axisTitleLaneWidth == 0)
        #expect(empty.requiredLeftPadding == 80)
        #expect(empty.titleCenterX >= 0)
    }

    @Test("Heatmap layout uses the shared axis primitive without changing colorbar behavior")
    func heatmapLayoutUsesSharedAxisPrimitive() {
        let payload = HeatmapPlotPayload(
            workflowID: "heatmap",
            title: "PlotAxisLayout",
            xLabel: "X",
            yLabel: "Y axis",
            zLabel: "Intensity (counts)",
            grid: HeatmapGrid(
                xValues: [0.0, 1.0],
                yValues: [12345.0, 67890.0],
                zMatrix: [[0.0, 0.5], [0.5, 1.0]]
            )
        )
        let visible = HeatmapPlotLayout.compute(payload: payload, showColorbar: true)
        let hidden = HeatmapPlotLayout.compute(payload: payload, showColorbar: false)

        #expect(visible.gridRect.width > 0)
        #expect(visible.gridRect.height > 0)
        #expect(visible.yLabelCenter.x < visible.gridRect.minX)
        #expect(visible.yLabelCenter.x >= 0)
        #expect(visible.colorbarRect.minX > visible.gridRect.maxX)
        #expect(visible.colorbarLabelCenter.x < visible.colorbarRect.minX)
        #expect(visible.gridRect.width == hidden.gridRect.width)
        #expect(visible.colorbarTicks.count > 0)
        #expect(!hidden.showColorbar)
        #expect(hidden.colorbarTicks.isEmpty)

        let sharedWidth = PlotTextMeasurer.maxTickLabelWidth(
            HeatmapPlotLayout.sampledYAxisTickEntries(for: payload.grid).map(\.label),
            fontSize: WorkbenchChartStyle().tickLabelFontSize,
            fontName: WorkbenchChartStyle().fontName,
            boldFontName: WorkbenchChartStyle().boldFontName
        )
        #expect(sharedWidth > 0)
    }

    @Test("XY layout uses the shared axis primitive without disturbing legend or point targets")
    func xyLayoutUsesSharedAxisPrimitive() {
        let style = WorkbenchChartStyle()
        let payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY",
            title: "PlotAxisLayout",
            axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R (Ω)"),
            series: [
                WorkbenchPlotSeries(
                    label: "Series A",
                    x: [1.0, 2.0, 3.0],
                    y: [0.1, 0.2, 0.15],
                    pointLabels: ["p0", "p1", "p2"]
                )
            ]
        )
        let renderer = WorkbenchChartRenderer()
        let resolved = renderer.resolvedOptions(payload: payload, base: .init(), style: style)
        let layout = WorkbenchPlotLayout.compute(
            options: resolved,
            payload: payload,
            legendPoint: CGPoint(x: 0.8, y: 0.8),
            style: style
        )

        #expect(layout.plotRect.width > 0)
        #expect(layout.plotRect.height > 0)
        #expect(layout.yLabelCenter.x < layout.yTickHitRect.minX || layout.yTickHitRect.width == 0)
        #expect(!layout.xTicks.isEmpty)
        #expect(!layout.yTicks.isEmpty)
        #expect(layout.xTicks.first?.tickPoint.y == layout.plotRect.minY)
        #expect(layout.xTicks[0].labelPoint.y < layout.plotRect.minY)
        #expect(layout.legendRows.count == payload.series.count)
        #expect(layout.pointDotHitTargets.count == payload.series[0].x.count)
        #expect(layout.pointLabelHitTargets.count == payload.series[0].x.count)
    }

    @Test("X-axis lane spacing responds to tick label width")
    func xAxisLaneSpacingRespondsToTickLabelWidth() {
        let style = WorkbenchChartStyle()
        let short = PlotAxisSpacingCalculator.xAxisLane(
            axisTitleText: "X",
            tickLabels: ["1", "2"],
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseBottomPadding: 88,
            maxSideInset: 220
        )
        let long = PlotAxisSpacingCalculator.xAxisLane(
            axisTitleText: "X",
            tickLabels: ["12345", "678901234"],
            axisTitleFontSize: style.axisTitleFontSize,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: style.tickLabelFontSize,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseBottomPadding: 88,
            maxSideInset: 220
        )

        #expect(short.maxTickLabelWidth < long.maxTickLabelWidth)
        #expect(short.requiredBottomPadding >= 88)
        #expect(short.titleCenterY < short.tickLabelCenterY)
        #expect(long.titleCenterY < long.tickLabelCenterY)
        #expect(short.tickLabelTopY <= short.requiredBottomPadding)
    }

    @Test("PlotAxisLayoutPlan exposes shared x and y ticks")
    func plotAxisLayoutPlanExposesSharedTicks() {
        let style = WorkbenchChartStyle()
        let payload = WorkbenchPlotPayload(
            workflowID: "plan",
            workflowDisplayName: "Plan",
            title: "Plan",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(label: "S", x: [0, 1, 2, 3], y: [1, 2, 1, 3])
            ]
        )
        let opts = WorkbenchChartRenderer.Options()
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: payload, style: style)

        #expect(plan.plotRect.width > 0)
        #expect(plan.plotRect.height > 0)
        #expect(plan.xTicks.count > 0)
        #expect(plan.yTicks.count > 0)
        #expect(plan.xTicks.allSatisfy { !$0.label.isEmpty })
        #expect(plan.yTicks.allSatisfy { !$0.label.isEmpty })
        #expect(plan.xTickHitRect.minY < plan.plotRect.minY)
        #expect(plan.yTickHitRect.minX < plan.plotRect.minX || plan.yTickHitRect.width == 0)
    }

    @Test("niceTicks can select a step of 6 x 10^n (e.g. 60) for a 0-360 range when the target count makes it the best fit")
    func niceTicksCanSelect60ForFullRotationRange() {
        let result5 = PlotAxisSpacingCalculator.niceTicks(min: 0, max: 360, targetCount: 5)
        #expect(result5.step == 60)
        #expect(result5.ticks == [0, 60, 120, 180, 240, 300, 360])

        let result6 = PlotAxisSpacingCalculator.niceTicks(min: 0, max: 360, targetCount: 6)
        #expect(result6.step == 60)
        #expect(result6.ticks == [0, 60, 120, 180, 240, 300, 360])
    }

    @Test("niceTicks still produces reasonable steps for standard ranges")
    func niceTicksStandardRangesStayReasonable() {
        let percent = PlotAxisSpacingCalculator.niceTicks(min: 0, max: 100, targetCount: 5)
        #expect(percent.step == 20)

        let small = PlotAxisSpacingCalculator.niceTicks(min: 0, max: 1, targetCount: 5)
        #expect(small.step == 0.2)

        let negativeToPositive = PlotAxisSpacingCalculator.niceTicks(min: -10, max: 10, targetCount: 5)
        #expect(negativeToPositive.step == 5)
    }

    @Test("Changing the X tick target visibly changes X tick density")
    func changingXTickTargetChangesTickDensity() {
        let sparse = PlotAxisSpacingCalculator.niceTicks(min: 0, max: 360, targetCount: 3)
        let dense = PlotAxisSpacingCalculator.niceTicks(min: 0, max: 360, targetCount: 10)
        #expect(dense.ticks.count > sparse.ticks.count)
        #expect(dense.step < sparse.step)
    }

    @Test("X and Y tick generation route through the same nice-tick candidate logic")
    func xAndYTickGenerationShareCandidateLogic() {
        let style = WorkbenchChartStyle()
        let payload = WorkbenchPlotPayload(
            workflowID: "sharedTickLogic",
            workflowDisplayName: "SharedTickLogic",
            title: "SharedTickLogic",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(label: "S", x: [0, 360], y: [0, 360])
            ]
        )
        let opts = WorkbenchChartRenderer.Options()
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: payload, style: style)

        let directY = PlotAxisSpacingCalculator.niceTicks(min: 0, max: 360, targetCount: style.tickTargetY)
        #expect(plan.yTicks.map(\.value) == directY.ticks)

        let directX = PlotAxisSpacingCalculator.resolvedXTicks(
            min: 0,
            max: 360,
            plotRect: plan.plotRect,
            style: style
        )
        #expect(plan.xTicks.map(\.value) == directX.ticks)
    }

    @Test("PlotAxisLayoutPlan.compute determines plotRect.minX from axis lane, not raw paddingLeft")
    func plotAxisLayoutPlanDeterminesPlotRectFromAxisLane() {
        var opts = WorkbenchChartRenderer.Options()
        opts.paddingLeft = 10  // intentionally small to force the computed lane to dominate

        let payload = WorkbenchPlotPayload(
            workflowID: "plan",
            workflowDisplayName: "Plan",
            title: "AxisLaneOwnership",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(label: "S", x: [0, 1], y: [2.0e-4, 2.5e-4])
            ]
        )
        let plan = PlotAxisLayoutPlan.compute(options: opts, payload: payload)

        // The Y-lane must expand beyond paddingLeft=10 to accommodate tick labels + axis title.
        #expect(plan.plotRect.minX > opts.paddingLeft,
                "plotRect.minX must come from the computed Y axis lane, not from raw paddingLeft")
        #expect(plan.yAxisLane.requiredLeftPadding == plan.plotRect.minX)
    }

    @Test("Rotated Y-axis title: long label does not increase requiredLeftPadding beyond font line height")
    func rotatedYTitleLongLabelDoesNotInflatePadding() {
        let style = WorkbenchChartStyle()
        let shortLabel = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "R(3ω) (Ω)",
            tickLabels: ["-1.0", "0.0", "1.0"],
            axisTitleFontSize: 25,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: 24,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80
        )
        let longLabel = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "E(3ω)_AHE / (E³_x · σ_xx) × 10² (V⁻² · S⁻¹ · m⁻¹)",
            tickLabels: ["-1.0", "0.0", "1.0"],
            axisTitleFontSize: 25,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: 24,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80
        )

        // The long Y title is much wider as text, but requiredLeftPadding must not grow with it.
        #expect(longLabel.axisTitleTextWidth > shortLabel.axisTitleTextWidth,
                "Long label must have greater text width (precondition)")
        #expect(abs(longLabel.requiredLeftPadding - shortLabel.requiredLeftPadding) < 4,
                "requiredLeftPadding must not grow significantly with Y title text length")
        // The lane width is derived from font line height, not text width.
        #expect(longLabel.axisTitleLaneWidth < longLabel.axisTitleTextWidth,
                "axisTitleLaneWidth (horizontal footprint) must be smaller than text width for a rotated title")
    }

    @Test("Rotated Y-axis title: wider tick labels still increase requiredLeftPadding")
    func rotatedYTitleWiderTickLabelsIncreaseLeftPadding() {
        let style = WorkbenchChartStyle()
        let narrowTicks = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "E(3ω)_AHE / (E³_x · σ_xx) × 10²",
            tickLabels: ["0", "1", "2"],
            axisTitleFontSize: 25,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: 24,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80
        )
        let wideTicks = PlotAxisSpacingCalculator.yAxisLane(
            axisTitleText: "E(3ω)_AHE / (E³_x · σ_xx) × 10²",
            tickLabels: ["-1.2345e-4", "0.00000", "1.2345e-4"],
            axisTitleFontSize: 25,
            axisTitleFontName: style.fontName,
            axisTitleBold: false,
            axisTitleBoldFontName: style.boldFontName,
            tickLabelFontSize: 24,
            tickLabelFontName: style.fontName,
            tickLabelBold: false,
            tickLabelBoldFontName: style.boldFontName,
            minimumAxisTitleLane: 24,
            titleToTickGap: 4,
            tickToPlotGap: 5,
            baseLeftPadding: 80
        )

        #expect(wideTicks.maxTickLabelWidth > narrowTicks.maxTickLabelWidth,
                "Wide tick labels must be wider (precondition)")
        #expect(wideTicks.requiredLeftPadding > narrowTicks.requiredLeftPadding,
                "requiredLeftPadding must grow when tick labels widen")
    }

    @Test("Rotated Y-axis title: long scaling-law label does not collapse plotRect on 800px canvas")
    func rotatedYTitleLongLabelDoesNotCollapseplotRect() {
        let style = WorkbenchChartStyle()
        let longYPayload = WorkbenchPlotPayload(
            workflowID: "scaling",
            workflowDisplayName: "Scaling",
            title: "Scaling Law",
            axisMapping: WorkbenchAxisMapping(
                xField: "E_x (V/m)",
                yField: "E(3ω)_AHE / (E³_x · σ_xx) × 10² (V⁻² · S⁻¹ · m⁻¹)"
            ),
            series: [
                WorkbenchPlotSeries(
                    label: "Series A",
                    x: [1.0, 2.0, 3.0],
                    y: [0.1, 0.2, 0.15],
                    pointLabels: ["p0", "p1", "p2"]
                )
            ]
        )
        var opts = WorkbenchChartRenderer.Options()
        opts.width = 800
        opts.height = 600
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: longYPayload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: longYPayload, style: style)

        // plotRect.minX must remain reasonable — not collapse to nearly all of canvas width.
        #expect(plan.plotRect.minX <= 220,
                "plotRect.minX must stay ≤ 220 px on an 800px canvas with long Y label (got \(plan.plotRect.minX))")
        // plotRect must occupy more than half the canvas width.
        #expect(plan.plotRect.width > 400,
                "plotRect.width must exceed 400 px on an 800px canvas (got \(plan.plotRect.width))")
        // Y label hit rect must not overlap y tick hit rect.
        let yLabelRight = plan.yLabelHitRect.maxX
        let yTickLeft = plan.yTickHitRect.minX
        #expect(yLabelRight <= yTickLeft + 2,
                "Y label hit rect must not overlap Y tick hit rect (yLabelRight=\(yLabelRight), yTickLeft=\(yTickLeft))")
        // Y tick hit rect must not overlap plotRect.
        #expect(plan.yTickHitRect.maxX <= plan.plotRect.minX + 2,
                "Y tick hit rect must not overlap plotRect")
    }

    @Test("Rotated Y-axis title: short label no overlap between y label, ticks, and plotRect")
    func rotatedYTitleShortLabelNoOverlap() {
        let style = WorkbenchChartStyle()
        let shortYPayload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY",
            title: "Short Y Label",
            axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R(3ω) (Ω)"),
            series: [
                WorkbenchPlotSeries(
                    label: "S",
                    x: [1.0, 2.0, 3.0],
                    y: [0.1, 0.2, 0.15],
                    pointLabels: ["p0", "p1", "p2"]
                )
            ]
        )
        var opts = WorkbenchChartRenderer.Options()
        opts.width = 800
        opts.height = 600
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: shortYPayload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: shortYPayload, style: style)

        #expect(plan.plotRect.width > 0)
        #expect(plan.plotRect.height > 0)
        let yLabelRight = plan.yLabelHitRect.maxX
        let yTickLeft = plan.yTickHitRect.minX
        #expect(yLabelRight <= yTickLeft + 2,
                "Y label hit rect must not overlap Y tick hit rect")
        #expect(plan.yTickHitRect.maxX <= plan.plotRect.minX + 2,
                "Y tick hit rect must not overlap plotRect")
    }

    @Test("Y tick labels with mixed widths do not overlap the y-axis title lane")
    func yTickLabelsDoNotOverlapTitleLane() {
        let style = WorkbenchChartStyle()
        let payload = WorkbenchPlotPayload(
            workflowID: "scaling",
            workflowDisplayName: "Scaling",
            title: "Scaling Law",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(label: "S", x: [0, 1, 2], y: [-0.005, 0.0, 0.010])
            ]
        )
        var opts = WorkbenchChartRenderer.Options()
        opts.width = 800
        opts.height = 600
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: payload, style: style)

        // The title lane must sit strictly to the left of the tick label lane, with no overlap.
        let titleLaneRight = plan.yAxisLane.titleCenterX + plan.yAxisLane.axisTitleLaneWidth / 2
        #expect(titleLaneRight <= plan.yAxisLane.tickLabelLaneLeadingX,
                "Y-axis title lane must not overlap the tick label lane")
        #expect(plan.yLabelHitRect.maxX <= plan.yTickHitRect.minX + 2,
                "Y label hit rect must not overlap Y tick hit rect")
    }

    @Test("X label hit rect does not overlap x tick hit rect")
    func xLabelHitRectDoesNotOverlapXTickHitRect() {
        let style = WorkbenchChartStyle()
        let payload = WorkbenchPlotPayload(
            workflowID: "scaling",
            workflowDisplayName: "Scaling",
            title: "Scaling Law",
            axisMapping: WorkbenchAxisMapping(xField: "E_x (V/m)", yField: "Y"),
            series: [
                WorkbenchPlotSeries(label: "S", x: [0, 1, 2], y: [0.1, 0.2, 0.15])
            ]
        )
        var opts = WorkbenchChartRenderer.Options()
        opts.width = 800
        opts.height = 600
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: payload, style: style)

        #expect(plan.xLabelHitRect.maxY <= plan.xTickHitRect.minY + 2,
                "X label hit rect must not overlap X tick hit rect")
    }

    @Test("Y label hit rect does not overlap y tick hit rect")
    func yLabelHitRectDoesNotOverlapYTickHitRect() {
        let style = WorkbenchChartStyle()
        let payload = WorkbenchPlotPayload(
            workflowID: "scaling",
            workflowDisplayName: "Scaling",
            title: "Scaling Law",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y (large units)"),
            series: [
                WorkbenchPlotSeries(label: "S", x: [0, 1, 2], y: [-0.005, 0.0, 0.010])
            ]
        )
        var opts = WorkbenchChartRenderer.Options()
        opts.width = 800
        opts.height = 600
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts, style: style)
        let plan = PlotAxisLayoutPlan.compute(options: resolved, payload: payload, style: style)

        #expect(plan.yLabelHitRect.maxX <= plan.yTickHitRect.minX + 2,
                "Y label hit rect must not overlap Y tick hit rect")
    }

    @Test("Shared axis-spacing logic stays out of RSM-owned sources")
    func axisSpacingLogicStaysOutOfRSM() throws {
        let rsmDirectory = plotAxisLayoutRepoRoot()
            .appendingPathComponent("Sources/SpinLabApp/Workbench/V3/Heatmap/RSM")
        let files = try FileManager.default.contentsOfDirectory(
            at: rsmDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "swift" }

        for url in files {
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.contains("PlotAxisSpacingCalculator"))
            #expect(!source.contains("PlotTextMeasurer"))
        }
    }

    @Test("Source uses the shared helper from both render paths")
    func sourceUsesSharedHelper() throws {
        let plotAxisSource = try loadPlotAxisSource("Sources/SpinLabApp/Workbench/V3/PlotAxisLayout.swift")
        let xyRendererSource = try loadPlotAxisSource("Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift")
        let xyLayoutSource = try loadPlotAxisSource("Sources/SpinLabApp/Workbench/V3/WorkbenchPlotLayout.swift")
        let heatmapLayoutSource = try loadPlotAxisSource("Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapPlotLayout.swift")

        // Axis spacing is owned by PlotAxisLayout, not by the renderer.
        #expect(!xyRendererSource.contains("maxYTickLabelWidth"))
        #expect(plotAxisSource.contains("PlotTextMeasurer.maxTickLabelWidth"))
        #expect(plotAxisSource.contains("PlotAxisSpacingCalculator.yAxisLane"))
        #expect(plotAxisSource.contains("PlotAxisSpacingCalculator.xAxisLane"))
        #expect(plotAxisSource.contains("struct PlotAxisLayoutPlan"))
        #expect(xyLayoutSource.contains("PlotAxisLayoutPlan.compute"))
        #expect(heatmapLayoutSource.contains("PlotAxisSpacingCalculator.yAxisLane"))
        #expect(heatmapLayoutSource.contains("PlotTextMeasurer.measuredWidth"))
        #expect(!heatmapLayoutSource.contains("CTLineCreateWithAttributedString"))
    }
}
