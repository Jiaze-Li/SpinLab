import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.3 AHE Fixed Plot Semantics")
struct V323PlotParameterOverrideTests {

    // MARK: - Fixed semantic axes

    @Test("AHE fixed x axis is H (T) converted from Magnetic Field (Oe)")
    func fixedXAxisIsHInTesla() throws {
        let fixture = try Fixture323()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures323.variantA_ch1Only)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1)]
        )

        #expect(result.series.count == 1)
        #expect(result.defaultAxisMapping.xField == "H (T)")
        #expect(result.series[0].x == [1.0, 0.5, -0.5])
    }

    @Test("AHE fixed y axis is R_H (Ω)")
    func fixedYAxisIsRH() throws {
        let fixture = try Fixture323()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures323.variantA_ch1Only)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1)]
        )

        #expect(result.defaultAxisMapping.yField == "R_H (\u{03A9})")
    }

    @Test("selected ch2 uses Bridge 2 data for R_H")
    func selectedCh2UsesBridge2Data() throws {
        let fixture = try Fixture323()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "PN50_ch2.dat", content: Fixtures323.variantA_ch1ch2)
        let result = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "PN50|b|STO|111", sourceFilePath: url.path, channel: .ch2)]
        )

        #expect(result.series.count == 1)
        #expect(result.series[0].sampleID == "PN50|b|STO|111")
        #expect(result.series[0].y == [2.0, 1.9, 1.8])
    }

    // MARK: - BuildAHEPlotPayloadUseCase semantics

    @Test("payload uses fixed semantic AHE axes")
    func payloadUsesFixedSemanticAxes() throws {
        let fixture = try Fixture323()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures323.variantA_ch1Only)
        let ingestion = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1)]
        )
        let payload = BuildAHEPlotPayloadUseCase().execute(
            ingestion: ingestion,
            title: "Test"
        )

        #expect(payload.axisMapping.xField == "μ₀H (T)")
        #expect(payload.axisMapping.yField == "RAHE (\u{03A9})")
    }

    @Test("payload ignores stale nonsemantic ingestion axis values")
    func payloadIgnoresStaleNonsemanticIngestionAxes() throws {
        let fixture = try Fixture323()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures323.variantA_ch1Only)
        var ingestion = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1)]
        )
        ingestion.defaultAxisMapping = WorkbenchAxisMapping(
            xField: "Temperature (K)",
            yField: "Bridge 1 Resistance (Ohms)"
        )
        let payload = BuildAHEPlotPayloadUseCase().execute(
            ingestion: ingestion,
            title: "Test"
        )

        #expect(payload.axisMapping.xField == "μ₀H (T)")
        #expect(payload.axisMapping.yField == "RAHE (\u{03A9})")
    }

    @Test("styleParams are passed through to payload unchanged")
    func styleParamsPassedThrough() throws {
        let fixture = try Fixture323()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures323.variantA_ch1Only)
        let ingestion = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1)]
        )
        let style: [String: String] = ["showGrid": "true"]
        let payload = BuildAHEPlotPayloadUseCase().execute(
            ingestion: ingestion,
            title: "Test",
            styleParams: style
        )

        #expect(payload.styleParams["showGrid"] == "true")
    }

    // MARK: - Renderer: grid style param

    @Test("renderPNG with showGrid=true produces valid PNG")
    func renderWithGridProducesValidPNG() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Grid Test",
            axisMapping: WorkbenchAxisMapping(xField: "Magnetic Field (Oe)",
                                              yField: "Bridge 1 Resistance (Ohms)"),
            series: [WorkbenchPlotSeries(label: "S1",
                                         x: [-10000.0, 0.0, 10000.0],
                                         y: [1.1, 1.0, 0.9])],
            styleParams: ["showGrid": "true"]
        )

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test("renderPNG without showGrid produces different bytes than with grid")
    func renderWithVsWithoutGridProducesDifferentOutput() throws {
        let makeSeries = { WorkbenchPlotSeries(label: "S", x: [-10000.0, 0.0, 10000.0], y: [1.1, 1.0, 0.9]) }
        let basePayload = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [makeSeries()], styleParams: [:]
        )
        let gridPayload = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [makeSeries()], styleParams: ["showGrid": "true"]
        )

        let dataBase = try WorkbenchChartRenderer().renderPNG(payload: basePayload)
        let dataGrid = try WorkbenchChartRenderer().renderPNG(payload: gridPayload)
        #expect(dataBase != dataGrid)
    }

    // MARK: - Title override

    @Test("title override appears in payload title field")
    func titleOverrideInPayload() throws {
        let fixture = try Fixture323()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: Fixtures323.variantA_ch1Only)
        let ingestion = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "S1", sourceFilePath: url.path, channel: .ch1)]
        )
        let payload = BuildAHEPlotPayloadUseCase().execute(
            ingestion: ingestion,
            title: "Custom Title 80K"
        )

        #expect(payload.title == "Custom Title 80K")
    }
}

// MARK: - Fixtures

private struct Fixture323 {
    let rootURL: URL
    private let fm = FileManager.default
    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v323-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
    func write(name: String, content: String) throws -> URL {
        let url = rootURL.appending(path: name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func cleanup() { try? fm.removeItem(at: rootURL) }
}

private enum Fixtures323 {
    static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

    static let variantA_ch1Only = """
    [Header]
    TITLE, test
    [Data]
    \(colHeader)
    ,0,4449,80.0,10000.0,0,1.0,500,,,,,,,,,,,25,1.0,,,
    ,1,4449,80.0,5000.0,0,0.9,500,,,,,,,,,,,25,0.9,,,
    ,2,4449,80.0,-5000.0,0,0.8,500,,,,,,,,,,,25,0.8,,,
    """

    static let variantA_ch1ch2 = """
    [Header]
    TITLE, test
    [Data]
    \(colHeader)
    ,0,4449,80.0,10000.0,0,1.0,500,2.0,500,,,,,,,,,25,1.0,2.0,,
    ,1,4449,80.0,5000.0,0,0.9,500,1.9,500,,,,,,,,,25,0.9,1.9,,
    ,2,4449,80.0,-5000.0,0,0.8,500,1.8,500,,,,,,,,,25,0.8,1.8,,
    """
}
