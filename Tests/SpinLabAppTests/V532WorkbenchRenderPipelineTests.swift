import XCTest
@testable import SpinLabApp

/// Tests for the unified WorkbenchRenderPipeline (v5.3.2).
final class V532WorkbenchRenderPipelineTests: XCTestCase {

    private func makePayload(
        title: String = "Test",
        xField: String = "X",
        yField: String = "Y",
        series: [WorkbenchPlotSeries] = [
            WorkbenchPlotSeries(label: "S1", x: [0, 1, 2], y: [0, 1, 0]),
            WorkbenchPlotSeries(label: "S2", x: [0, 1, 2], y: [1, 2, 1]),
        ]
    ) -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
            series: series
        )
    }

    // MARK: - Basic render

    func testRender_producesImageAndLayout() throws {
        let input = WorkbenchRenderPipeline.Input(payload: makePayload())
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertFalse(output.imageData.isEmpty)
        XCTAssertGreaterThan(output.layout.plotRect.width, 0)
        XCTAssertGreaterThan(output.layout.plotRect.height, 0)
    }

    // MARK: - Axis mapping preservation

    func testRender_manifestPayloadPreservesOriginalAxisMapping() throws {
        let input = WorkbenchRenderPipeline.Input(
            payload: makePayload(xField: "Magnetic Field (Oe)", yField: "R_H (Ω)"),
            xLabelOverride: "H (Oe)",
            yLabelOverride: "R"
        )
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.manifestPayload.axisMapping.xField, "Magnetic Field (Oe)",
                       "Manifest must preserve original data column name")
        XCTAssertEqual(output.manifestPayload.axisMapping.yField, "R_H (Ω)",
                       "Manifest must preserve original data column name")
    }

    // MARK: - Render mode override

    func testRender_appliesSeriesRenderMode() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.seriesRenderMode = .scatter
        let output = try WorkbenchRenderPipeline.render(input)
        for series in output.manifestPayload.series {
            XCTAssertEqual(series.renderMode, .scatter)
        }
    }

    // MARK: - Chart style overrides merge

    func testRender_mergesChartStyleOverrides() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.chartStyleOverrides = ["titleFontSize": "28", "tickTargetX": "10"]
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.manifestPayload.styleParams["titleFontSize"], "28")
        XCTAssertEqual(output.manifestPayload.styleParams["tickTargetX"], "10")
    }

    // MARK: - Style params patch

    func testRender_appliesStyleParamsPatch() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.styleParamsPatch = ["showGrid": "true", "auxVerticalX": "180"]
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.manifestPayload.styleParams["showGrid"], "true")
        XCTAssertEqual(output.manifestPayload.styleParams["auxVerticalX"], "180")
    }

    // MARK: - Series label overrides

    func testRender_appliesSeriesLabelOverrides() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.seriesLabelOverrides = [0: "Custom"]
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.manifestPayload.series[0].label, "Custom")
        XCTAssertEqual(output.manifestPayload.series[1].label, "S2", "Unoverridden series should keep original label")
    }

    func testRender_appliesSeriesLabelOverridesToOneDuplicateSampleIDSeries() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(label: "0deg", x: [0, 1], y: [0, 1], sampleID: "PN80 STO001", metadata: ["angle": "0deg", "current": "1mA"]),
                WorkbenchPlotSeries(label: "30deg", x: [0, 1], y: [1, 2], sampleID: "PN80 STO001", metadata: ["angle": "30deg", "current": "1mA"]),
                WorkbenchPlotSeries(label: "60deg", x: [0, 1], y: [2, 3], sampleID: "PN80 STO001", metadata: ["angle": "60deg", "current": "1mA"])
            ],
            seriesReorderable: true
        )
        let rows = WorkbenchSeriesOrderPanel.makeRows(payload: payload, currentSeriesOrder: nil)
        let target = rows.first(where: { $0.label == "60deg" })!
        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesLabelOverrides = toIndexedOverrides([target.identityKey: "Renamed 60deg"], series: payload.series)

        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.manifestPayload.series[target.originalIndex].label, "Renamed 60deg")
        XCTAssertEqual(output.manifestPayload.series[0].label, "0deg")
        XCTAssertEqual(output.manifestPayload.series[1].label, "30deg")
    }

    func testRender_layoutUsesOriginalLabelsForLegendRows() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.seriesLabelOverrides = [0: "Override"]
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.layout.legendRows[0].originalLabel, "S1",
                       "Layout legend row must use pre-override label")
    }

    // MARK: - Title override

    func testRender_appliesTitleOverride() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload(title: "Original"))
        input.titleOverride = "Overridden"
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.layout.chartTitle, "Overridden")
    }

    // MARK: - Empty series

    func testRender_emptySeriesStillProducesImage() throws {
        let payload = makePayload(series: [])
        let input = WorkbenchRenderPipeline.Input(payload: payload)
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertFalse(output.imageData.isEmpty, "Even with no series, PNG should be produced (No Data placeholder)")
    }
}
