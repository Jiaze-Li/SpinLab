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
        XCTAssertEqual(output.layout.legendRows.count, 2)
    }

    // MARK: - Axis mapping preservation

    func testRender_manifestPayloadPreservesOriginalAxisMapping() throws {
        let input = WorkbenchRenderPipeline.Input(
            payload: makePayload(xField: "Magnetic Field (Oe)", yField: "R_H (Ω)"),
            xLabelOverride: "H (Oe)",
            yLabelOverride: "R"
        )
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.layout.xAxisLabel, "H (Oe)",
                       "xLabelOverride must win over the default vocabulary label in the render path")
        XCTAssertEqual(output.layout.yAxisLabel, "R",
                       "yLabelOverride must win over the default vocabulary label in the render path")
        XCTAssertEqual(output.manifestPayload.axisMapping.xField, "Magnetic Field (Oe)",
                       "Manifest must preserve original data column name")
        XCTAssertEqual(output.manifestPayload.axisMapping.yField, "R_H (Ω)",
                       "Manifest must preserve original data column name")
    }

    // MARK: - Render mode override (manifest contract: original series state is preserved)

    /// styleParams/renderMode/label mutations are render-only (post-81e953f) — they apply
    /// to the internal render payload used for image/layout, never to manifestPayload.
    func testRender_manifestPayloadPreservesOriginalSeriesRenderMode() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.seriesRenderMode = .scatter
        let output = try WorkbenchRenderPipeline.render(input)
        for series in output.manifestPayload.series {
            XCTAssertEqual(series.renderMode, .line, "manifestPayload must retain the original series renderMode")
        }
    }

    // MARK: - Chart style overrides merge (render-only; excluded from manifest)

    func testRender_manifestPayloadExcludesChartStyleOverrides() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.chartStyleOverrides = ["titleFontSize": "28", "tickTargetX": "10"]
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertNil(output.manifestPayload.styleParams["titleFontSize"],
                      "chartStyleOverrides are render-only and must not persist to manifestPayload")
        XCTAssertNil(output.manifestPayload.styleParams["tickTargetX"],
                      "chartStyleOverrides are render-only and must not persist to manifestPayload")
    }

    // MARK: - Style params patch (render-only; excluded from manifest)

    func testRender_manifestPayloadExcludesStyleParamsPatch() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.styleParamsPatch = ["showGrid": "true", "auxVerticalX": "180"]
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertNil(output.manifestPayload.styleParams["showGrid"],
                      "styleParamsPatch is render-only and must not persist to manifestPayload")
        XCTAssertNil(output.manifestPayload.styleParams["auxVerticalX"],
                      "styleParamsPatch is render-only and must not persist to manifestPayload")
    }

    // MARK: - Series label overrides (render-only; excluded from manifest)

    func testRender_manifestPayloadPreservesOriginalSeriesLabels() throws {
        // Baseline render (no label override) establishes the legend's natural measured width
        // for series 0's original label, so we can show the override changed the render path
        // without asserting on manifestPayload (which must stay untouched).
        let baselineOutput = try WorkbenchRenderPipeline.render(WorkbenchRenderPipeline.Input(payload: makePayload()))
        let baselineWidth = baselineOutput.layout.legendRows[0].measuredLabelWidth

        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.seriesLabelOverrides = [0: "Custom Renamed Label"]
        let output = try WorkbenchRenderPipeline.render(input)

        XCTAssertEqual(output.manifestPayload.series[0].label, "S1",
                        "manifestPayload must retain the original series label")
        XCTAssertEqual(output.manifestPayload.series[1].label, "S2",
                        "manifestPayload must retain the original series label")
        XCTAssertNotEqual(output.layout.legendRows[0].measuredLabelWidth, baselineWidth,
                           "the label override must still affect the render/layout path")
    }

    func testRender_manifestPayloadPreservesOriginalLabelsForDuplicateSampleIDSeries() throws {
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

        let baselineOutput = try WorkbenchRenderPipeline.render(WorkbenchRenderPipeline.Input(payload: payload))
        let baselineWidth = baselineOutput.layout.legendRows[target.originalIndex].measuredLabelWidth

        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesLabelOverrides = toIndexedOverrides([target.identityKey: "Renamed 60deg With Much Longer Text"], series: payload.series)

        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertEqual(output.manifestPayload.series[target.originalIndex].label, "60deg",
                        "manifestPayload must retain the original series label")
        XCTAssertEqual(output.manifestPayload.series[0].label, "0deg")
        XCTAssertEqual(output.manifestPayload.series[1].label, "30deg")
        XCTAssertNotEqual(output.layout.legendRows[target.originalIndex].measuredLabelWidth, baselineWidth,
                           "the label override must still affect the render/layout path for the target series")
    }

    // MARK: - Hidden series filtering (render-only; manifest keeps the full series set)

    func testRender_manifestPayloadKeepsFullUnfilteredSeriesWhenHiddenSeriesApplied() throws {
        let payload = makePayload(series: [
            WorkbenchPlotSeries(label: "S1", x: [0, 1, 2], y: [0, 1, 0]),
            WorkbenchPlotSeries(label: "S2", x: [0, 1, 2], y: [1, 2, 1]),
            WorkbenchPlotSeries(label: "S3", x: [0, 1, 2], y: [2, 3, 2]),
        ])
        let hiddenKeys = WorkbenchSeriesOrderKeyResolver.resolveIdentityKeys(for: payload.series)
        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.hiddenSeriesKeys = [hiddenKeys[1]]

        let output = try WorkbenchRenderPipeline.render(input)

        XCTAssertEqual(output.manifestPayload.series.count, payload.series.count,
                        "manifestPayload must retain the full, unfiltered series set")
        XCTAssertFalse(output.imageData.isEmpty)
        XCTAssertGreaterThan(output.layout.plotRect.width, 0)
        XCTAssertGreaterThan(output.layout.plotRect.height, 0)
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

    // MARK: - Series order mismatch check must not false-positive on reversed stacks

    /// input.seriesOrder is canonical visual (legend/chip) order. Payloads that reverse
    /// their internal series for bottom-to-top stacking legitimately have renderer-internal
    /// order that differs from visual order, so no mismatch warning should fire.
    func testRender_noSeriesOrderMismatchWarningWhenReversedForLegend() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sampleID: "A"),
                WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sampleID: "B"),
            ],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        let identityKeys = WorkbenchSeriesOrderKeyResolver.resolveIdentityKeys(for: payload.series)

        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesOrder = [identityKeys[1], identityKeys[0]]

        let output = try WorkbenchRenderPipeline.render(input)

        XCTAssertFalse(output.warnings.contains { $0.contains("seriesOrder mismatch") },
                        "reversed-for-legend payloads must not trigger a false series-order mismatch warning")
    }

    // MARK: - Empty series

    func testRender_emptySeriesStillProducesImage() throws {
        let payload = makePayload(series: [])
        let input = WorkbenchRenderPipeline.Input(payload: payload)
        let output = try WorkbenchRenderPipeline.render(input)
        XCTAssertFalse(output.imageData.isEmpty, "Even with no series, PNG should be produced (No Data placeholder)")
    }
}
