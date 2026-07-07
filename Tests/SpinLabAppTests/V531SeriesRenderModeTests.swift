import XCTest
@testable import SpinLabApp

/// Tests for the isScatter → SeriesRenderMode Codable migration
/// and ChartStyle parsing from styleParams.
final class V531SeriesRenderModeTests: XCTestCase {

    // MARK: - SeriesRenderMode enum

    func testRenderMode_rawValues() {
        XCTAssertEqual(SeriesRenderMode.line.rawValue, "line")
        XCTAssertEqual(SeriesRenderMode.scatter.rawValue, "scatter")
        XCTAssertEqual(SeriesRenderMode.lineAndScatter.rawValue, "lineAndScatter")
    }

    // MARK: - Decode migration: old isScatter → renderMode

    func testDecode_legacyIsScatterTrue_decodesToScatter() throws {
        let json = """
        {"label":"A","x":[1],"y":[2],"isScatter":true,"pointLabels":[],"lineWidth":1.5}
        """
        let series = try JSONDecoder().decode(WorkbenchPlotSeries.self, from: Data(json.utf8))
        XCTAssertEqual(series.renderMode, .scatter)
    }

    func testDecode_legacyIsScatterFalse_decodesToLine() throws {
        let json = """
        {"label":"B","x":[1],"y":[2],"isScatter":false,"pointLabels":[],"lineWidth":1.5}
        """
        let series = try JSONDecoder().decode(WorkbenchPlotSeries.self, from: Data(json.utf8))
        XCTAssertEqual(series.renderMode, .line)
    }

    func testDecode_newRenderMode_takePrecedenceOverIsScatter() throws {
        // Both keys present — renderMode wins
        let json = """
        {"label":"C","x":[],"y":[],"renderMode":"lineAndScatter","isScatter":true,"pointLabels":[],"lineWidth":1.5}
        """
        let series = try JSONDecoder().decode(WorkbenchPlotSeries.self, from: Data(json.utf8))
        XCTAssertEqual(series.renderMode, .lineAndScatter)
    }

    func testDecode_neitherKey_defaultsToLine() throws {
        let json = """
        {"label":"D","x":[],"y":[],"pointLabels":[],"lineWidth":1.5}
        """
        let series = try JSONDecoder().decode(WorkbenchPlotSeries.self, from: Data(json.utf8))
        XCTAssertEqual(series.renderMode, .line)
    }

    // MARK: - Encode: only writes renderMode, never isScatter

    func testEncode_writesRenderMode_notIsScatter() throws {
        let series = WorkbenchPlotSeries(label: "E", x: [1], y: [2], renderMode: .scatter)
        let data = try JSONEncoder().encode(series)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["renderMode"] as? String, "scatter")
        XCTAssertNil(dict["isScatter"], "isScatter must not appear in encoded output")
    }

    func testThreeOmegaPackConfig_roundTripsLineAndScatter() throws {
        let config = ThreeOmegaPackConfig(
            device: "device",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "sample",
            activeTab: ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey,
            titleTemplate: "title",
            stackOffsetMultiplier: 1.0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            plotLegendAnchor: "",
            seriesRenderMode: .lineAndScatter
        )

        let decoded = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.seriesRenderMode, .lineAndScatter)
    }

    @MainActor
    func testThreeOmegaRestoreFromPack_appliesLineAndScatter() throws {
        let config = ThreeOmegaPackConfig(
            device: "device",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "sample",
            activeTab: ThreeOmegaWorkbenchTab.fieldSweep1omega.stableKey,
            titleTemplate: "title",
            stackOffsetMultiplier: 1.0,
            minGapFraction: 0.15,
            showPlotGrid: true,
            plotLegendAnchor: "",
            seriesRenderMode: .lineAndScatter
        )
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "device"),
            scalingResult: nil
        )
        let pack = try AnalysisPack(
            label: "3ω",
            workflowID: WorkflowKey.threeOmega.rawValue,
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        let vault = AnalysisVault()
        vault.add(pack)
        store.vault = vault

        store.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        XCTAssertEqual(store.tabs.seriesRenderMode, .lineAndScatter)
    }

    // MARK: - renderMode primary init

    func testConvenienceInit_isScatterTrue_mapsToScatter() {
        let s = WorkbenchPlotSeries(label: "F", x: [], y: [], renderMode: .scatter)
        XCTAssertEqual(s.renderMode, .scatter)
    }

    func testConvenienceInit_isScatterFalse_mapsToLine() {
        let s = WorkbenchPlotSeries(label: "G", x: [], y: [], renderMode: .line)
        XCTAssertEqual(s.renderMode, .line)
    }

    // MARK: - ChartStyle defaults

    func testChartStyle_defaults() {
        let s = WorkbenchChartStyle()
        XCTAssertEqual(s.titleFontSize, 25)
        XCTAssertEqual(s.titleBold, false)
        XCTAssertEqual(s.axisTitleFontSize, 20)
        XCTAssertEqual(s.tickLabelFontSize, 19)
        XCTAssertEqual(s.legendFontSize, 18)
        XCTAssertEqual(s.tickTargetX, 6)
        XCTAssertEqual(s.tickTargetY, 5)
    }

    // MARK: - ChartStyle from styleParams

    func testChartStyle_fromStyleParams_overridesProvided() {
        let params: [String: String] = [
            "titleFontSize": "28",
            "titleBold": "true",
            "axisTitleFontSize": "22",
            "tickLabelFontSize": "16",
            "legendFontSize": "14",
            "tickTargetX": "8",
            "tickTargetY": "4",
        ]
        let s = WorkbenchChartStyle.from(styleParams: params)
        XCTAssertEqual(s.titleFontSize, 28)
        XCTAssertEqual(s.titleBold, true)
        XCTAssertEqual(s.axisTitleFontSize, 22)
        XCTAssertEqual(s.tickLabelFontSize, 16)
        XCTAssertEqual(s.legendFontSize, 14)
        XCTAssertEqual(s.tickTargetX, 8)
        XCTAssertEqual(s.tickTargetY, 4)
    }

    func testChartStyle_fromEmptyParams_returnsDefaults() {
        let s = WorkbenchChartStyle.from(styleParams: [:])
        XCTAssertEqual(s.titleFontSize, 25)
        XCTAssertEqual(s.titleBold, false)
        XCTAssertEqual(s.tickTargetX, 6)
    }

    // MARK: - PlotLayout: axis labels centered on plotRect

    func testPlotLayout_xLabelCenteredOnPlotRect() {
        let opts = WorkbenchChartRenderer.Options()
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test",
            title: "T", axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "s", x: [0, 1], y: [0, 1])]
        )
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts)
        let layout = WorkbenchPlotLayout.compute(options: resolved, payload: payload, legendPoint: nil)

        let plotMidX = layout.plotRect.midX
        XCTAssertEqual(layout.xLabelCenter.x, plotMidX, accuracy: 0.01,
                       "X axis label must be centered on plotRect, not full image width")
    }

    func testPlotLayout_yLabelCenteredOnPlotRect() {
        let opts = WorkbenchChartRenderer.Options()
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test",
            title: "T", axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "s", x: [0, 1], y: [0, 1])]
        )
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts)
        let layout = WorkbenchPlotLayout.compute(options: resolved, payload: payload, legendPoint: nil)

        let plotMidY = layout.plotRect.midY
        XCTAssertEqual(layout.yLabelCenter.y, plotMidY, accuracy: 0.01,
                       "Y axis label must be centered on plotRect, not full image height")
    }

    // MARK: - PlotLayout stores plotRect and rendererSize

    func testPlotLayout_storesPlotRectAndRendererSize() {
        let opts = WorkbenchChartRenderer.Options()
        let payload = WorkbenchPlotPayload(
            workflowID: "test", workflowDisplayName: "Test",
            title: "T", axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "s", x: [0, 1], y: [0, 1])]
        )
        let resolved = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: opts)
        let layout = WorkbenchPlotLayout.compute(options: resolved, payload: payload, legendPoint: nil)

        XCTAssertEqual(layout.rendererSize.width, CGFloat(opts.width))
        XCTAssertEqual(layout.rendererSize.height, CGFloat(opts.height))
        XCTAssertGreaterThan(layout.plotRect.width, 0)
        XCTAssertGreaterThan(layout.plotRect.height, 0)
        XCTAssertEqual(layout.plotRect.minX, resolved.paddingLeft)
        XCTAssertEqual(layout.plotRect.minY, resolved.paddingBottom)
    }
}
