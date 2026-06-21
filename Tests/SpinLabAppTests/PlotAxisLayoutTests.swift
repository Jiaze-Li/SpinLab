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
    guard max > min, targetCount > 0 else { return ([min, max], max - min) }
    let range = max - min
    let roughStep = range / Double(targetCount)
    let magnitude = pow(10.0, floor(log10(abs(roughStep))))
    let normalized = roughStep / magnitude
    let niceNorm: Double
    if normalized < 1.5      { niceNorm = 1 }
    else if normalized < 3.5 { niceNorm = 2 }
    else if normalized < 7.5 { niceNorm = 5 }
    else                     { niceNorm = 10 }
    let step = niceNorm * magnitude
    let firstTick = ceil(min / step) * step
    var ticks: [Double] = []
    var tick = firstTick
    while tick <= max + step * 0.5 {
        ticks.append((tick * 1e12).rounded() / 1e12)
        tick += step
    }
    return (ticks, step)
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

        let allY = payload.series.flatMap(\.y)
        let yRawMin = allY.min() ?? 0
        let yRawMax = allY.max() ?? 0
        let yRawSpan = yRawMax == yRawMin ? 1.0 : yRawMax - yRawMin
        let preYMin = yRawMin - yRawSpan * 0.05
        let preYMax = yRawMax + yRawSpan * 0.05
        let (preYTicks, preYStep) = testNiceTicks(min: preYMin, max: preYMax, targetCount: style.tickTargetY)
        let expectedMax = PlotTextMeasurer.maxTickLabelWidth(
            preYTicks.map { renderer.formatTick($0, step: preYStep) },
            fontSize: style.tickLabelFontSize,
            fontName: style.fontName,
            boldFontName: style.boldFontName
        )
        #expect(abs(resolved.maxYTickLabelWidth - expectedMax) < 0.0001)
        #expect(layout.plotRect.width > 0)
        #expect(layout.plotRect.height > 0)
        #expect(layout.yLabelCenter.x < layout.yTickHitRect.minX || layout.yTickHitRect.width == 0)
        #expect(layout.legendRows.count == payload.series.count)
        #expect(layout.pointDotHitTargets.count == payload.series[0].x.count)
        #expect(layout.pointLabelHitTargets.count == payload.series[0].x.count)
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
        let xyRendererSource = try loadPlotAxisSource("Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift")
        let xyLayoutSource = try loadPlotAxisSource("Sources/SpinLabApp/Workbench/V3/WorkbenchPlotLayout.swift")
        let heatmapLayoutSource = try loadPlotAxisSource("Sources/SpinLabApp/Workbench/V3/Heatmap/HeatmapPlotLayout.swift")

        #expect(xyRendererSource.contains("PlotTextMeasurer.maxTickLabelWidth"))
        #expect(xyLayoutSource.contains("PlotAxisSpacingCalculator.yAxisLane"))
        #expect(heatmapLayoutSource.contains("PlotAxisSpacingCalculator.yAxisLane"))
        #expect(heatmapLayoutSource.contains("PlotTextMeasurer.measuredWidth"))
        #expect(!heatmapLayoutSource.contains("CTLineCreateWithAttributedString"))
    }
}
