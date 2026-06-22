import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

private func makeTestPayload(
    series: [WorkbenchPlotSeries]? = nil
) -> WorkbenchPlotPayload {
    let s = series ?? [WorkbenchPlotSeries(label: "A", x: [0, 1, 2], y: [10, 20, 30])]
    return WorkbenchPlotPayload(
        workflowID: "test",
        workflowDisplayName: "Test",
        title: "Test",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: s
    )
}

// MARK: - WorkbenchChartStyle appearance parsing

@Suite("WorkbenchChartStyle appearance parsing")
struct WorkbenchChartStyleAppearanceTests {

    @Test("lineWidth parses from styleParams")
    func lineWidthParses() {
        let style = WorkbenchChartStyle.from(styleParams: ["lineWidth": "2.5"])
        #expect(style.lineWidth == 2.5)
    }

    @Test("pointRadius parses from styleParams")
    func pointRadiusParses() {
        let style = WorkbenchChartStyle.from(styleParams: ["pointRadius": "4"])
        #expect(style.pointRadius == 4.0)
    }

    @Test("lineWidth defaults to nil (Auto)")
    func lineWidthDefaultsToNil() {
        let style = WorkbenchChartStyle()
        #expect(style.lineWidth == nil)
    }

    @Test("pointRadius defaults to nil (Auto)")
    func pointRadiusDefaultsToNil() {
        let style = WorkbenchChartStyle()
        #expect(style.pointRadius == nil)
    }

    @Test("lineWidth and pointRadius are globalPlotDefaultKeys")
    func keysAreGlobal() {
        #expect(WorkbenchChartStyle.globalPlotDefaultKeys.contains("lineWidth"))
        #expect(WorkbenchChartStyle.globalPlotDefaultKeys.contains("pointRadius"))
    }

    @Test("invalid lineWidth (zero) is rejected")
    func invalidLineWidthRejected() {
        let style = WorkbenchChartStyle.from(styleParams: ["lineWidth": "0"])
        #expect(style.lineWidth == nil)
    }

    @Test("invalid pointRadius (negative) is rejected")
    func invalidPointRadiusRejected() {
        let style = WorkbenchChartStyle.from(styleParams: ["pointRadius": "-1"])
        #expect(style.pointRadius == nil)
    }
}

// MARK: - Renderer uses style.pointRadius

@Suite("WorkbenchChartRenderer pointRadius")
struct WorkbenchChartRendererPointRadiusTests {

    private func makePayload(scatter: Bool = true) -> WorkbenchPlotPayload {
        var s = WorkbenchPlotSeries(label: "A", x: [1, 2, 3], y: [1, 4, 9])
        s.renderMode = scatter ? .scatter : .line
        return makeTestPayload(series: [s])
    }

    @Test("renders scatter without error using default pointRadius")
    func rendersDefaultRadius() throws {
        let renderer = WorkbenchChartRenderer()
        let style = WorkbenchChartStyle()
        let data = try renderer.renderPNG(payload: makePayload(), options: .init(), style: style)
        #expect(!data.isEmpty)
    }

    @Test("renders scatter without error using custom pointRadius")
    func rendersCustomRadius() throws {
        let renderer = WorkbenchChartRenderer()
        var style = WorkbenchChartStyle()
        style.pointRadius = 6.0
        let data = try renderer.renderPNG(payload: makePayload(), options: .init(), style: style)
        #expect(!data.isEmpty)
    }

    @Test("renders with lineWidth from style")
    func rendersCustomLineWidth() throws {
        let renderer = WorkbenchChartRenderer()
        var style = WorkbenchChartStyle()
        style.lineWidth = 3.0
        var s = WorkbenchPlotSeries(label: "A", x: [1, 2, 3], y: [1, 4, 9])
        s.renderMode = .line
        s.lineWidth = 3.0
        let payload = makeTestPayload(series: [s])
        let data = try renderer.renderPNG(payload: payload, options: .init(), style: style)
        #expect(!data.isEmpty)
    }
}

// MARK: - Pipeline applies lineWidth override to unlocked series

@Suite("WorkbenchRenderPipeline lineWidth override")
struct PipelineLineWidthTests {

    private func makeInput(lineWidth: String, locked: Bool = false) -> WorkbenchRenderPipeline.Input {
        var s = WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1])
        s.lineWidth = 2.0
        s.renderModeLocked = locked
        return WorkbenchRenderPipeline.Input(
            payload: makeTestPayload(series: [s]),
            globalPlotDefaults: ["lineWidth": lineWidth]
        )
    }

    @Test("pipeline applies lineWidth from globalPlotDefaults to unlocked series")
    func pipelineAppliesLineWidth() throws {
        let input = makeInput(lineWidth: "3")
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.imageData.isEmpty)
        #expect(output.manifestPayload.series[0].lineWidth == 3.0)
    }

    @Test("pipeline skips lineWidth override for renderModeLocked series")
    func pipelineSkipsLockedSeries() throws {
        var s = WorkbenchPlotSeries(label: "Fit", x: [0, 1], y: [0, 1])
        s.lineWidth = 1.0
        s.renderModeLocked = true
        let input = WorkbenchRenderPipeline.Input(
            payload: makeTestPayload(series: [s]),
            globalPlotDefaults: ["lineWidth": "5"]
        )
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.manifestPayload.series[0].lineWidth == 1.0)
    }
}
