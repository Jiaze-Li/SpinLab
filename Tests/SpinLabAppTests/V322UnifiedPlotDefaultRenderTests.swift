import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.2 Unified Plot Default Render")
struct V322UnifiedPlotDefaultRenderTests {

    // MARK: - BuildAHEPlotPayloadUseCase

    @Test("BuildAHEPlotPayloadUseCase maps ingestion result to payload correctly")
    func buildPayloadMapsIngestionResult() throws {
        let fixture = try PlotFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "f.dat", content: PlotFixtures.variantA_ch1Only)
        let ingestion = try IngestAHESelectionsUseCase().execute(
            selections: [.init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path,
                               channel: .ch1, conditions: ["temperature": "80K"])],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        let payload = BuildAHEPlotPayloadUseCase().execute(
            ingestion: ingestion,
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Test AHE Plot"
        )

        #expect(payload.workflowID == "AHE")
        #expect(payload.title == "Test AHE Plot")
        #expect(payload.axisMapping.xField == "μ₀H (T)")
        #expect(payload.axisMapping.yField == "R_H (\u{03A9})")
        #expect(payload.series.count == 1)
        #expect(payload.series[0].x.count == 3)
        #expect(payload.series[0].y.count == 3)
    }

    // MARK: - WorkbenchChartRenderer

    @Test("renderPNG returns non-empty Data for valid payload")
    func renderPNGReturnsNonEmptyData() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Test",
            axisMapping: WorkbenchAxisMapping(xField: "Magnetic Field (Oe)",
                                              yField: "Bridge 1 Resistance (Ohms)"),
            series: [WorkbenchPlotSeries(
                label: "PN31|o|STO|111 | ch1 | 80K",
                x: [-10000.0, -5000.0, 0.0, 5000.0, 10000.0],
                y: [1.1, 1.05, 1.0, 0.95, 0.9]
            )]
        )

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        #expect(!data.isEmpty)
    }

    @Test("rendered PNG starts with PNG magic bytes")
    func renderedDataStartsWithPNGMagicBytes() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Magic Bytes Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S1", x: [0.0, 1.0, 2.0], y: [0.0, 1.0, 0.5])]
        )

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        // PNG magic: 0x89 0x50 0x4E 0x47
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let header = Array(data.prefix(4))
        #expect(header == pngMagic)
    }

    @Test("renderPNG with empty series produces valid PNG placeholder")
    func renderEmptySeriesProducesValidPNG() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Empty",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: []
        )

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        #expect(Array(data.prefix(4)) == pngMagic)
    }

    @Test("renderPNG multi-series payload renders all series")
    func renderMultiSeriesPayload() throws {
        let series: [WorkbenchPlotSeries] = (1...4).map { i in
            WorkbenchPlotSeries(
                label: "Sample \(i)",
                x: stride(from: -10000.0, through: 10000.0, by: 1000.0).map { $0 },
                y: stride(from: -10000.0, through: 10000.0, by: 1000.0).map { $0 * Double(i) * 0.1 }
            )
        }
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Multi-Series",
            axisMapping: WorkbenchAxisMapping(xField: "Magnetic Field (Oe)",
                                              yField: "Bridge 1 Resistance (Ohms)"),
            series: series
        )

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        #expect(!data.isEmpty)
        #expect(data.count > 1000) // a real PNG with content
    }

    @Test("renderPNG with custom options respects width and height")
    func renderWithCustomOptions() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "Custom Size",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [0.0, 1.0], y: [0.0, 1.0])]
        )
        var opts = WorkbenchChartRenderer.Options()
        opts.width = 400
        opts.height = 300

        let data = try WorkbenchChartRenderer().renderPNG(payload: payload, options: opts)
        #expect(!data.isEmpty)
    }

    // MARK: - End-to-end: ingestion → payload → render

    @Test("full pipeline from dat file to PNG bytes")
    func fullPipelineFromDatFileToPNG() throws {
        let fixture = try PlotFixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "ahe.dat", content: PlotFixtures.variantA_ch1ch2)
        let ingestion = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path,
                      channel: .ch1, conditions: ["temperature": "80K"]),
                .init(sampleKey: "PN31|b|STO|111", sourceFilePath: url.path,
                      channel: .ch2, conditions: ["temperature": "80K"]),
            ],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )
        #expect(ingestion.series.count == 2)

        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE 80K")
        let data = try WorkbenchChartRenderer().renderPNG(payload: payload)
        #expect(!data.isEmpty)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }
}

// MARK: - Fixture helpers

private struct PlotFixture {
    let rootURL: URL
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v322-\(UUID().uuidString)", directoryHint: .isDirectory
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

private enum PlotFixtures {
    static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

    static let variantA_ch1Only = """
    [Header]
    TITLE, test
    BYAPP, Resistivity, 2.1, 1.0
    [Data]
    \(colHeader)
    ,0,4449,80.0,10000.0,0,1.0,500,,,,,,,,,,,25,1.0,,,
    ,1,4449,80.0,5000.0,0,0.9,500,,,,,,,,,,,25,0.9,,,
    ,2,4449,80.0,-5000.0,0,0.8,500,,,,,,,,,,,25,0.8,,,
    """

    static let variantA_ch1ch2 = """
    [Header]
    TITLE, test
    BYAPP, Resistivity, 2.1, 1.0
    [Data]
    \(colHeader)
    ,0,4449,80.0,10000.0,0,1.0,500,2.0,500,,,,,,,,,25,1.0,2.0,,
    ,1,4449,80.0,5000.0,0,0.9,500,1.9,500,,,,,,,,,25,0.9,1.9,,
    ,2,4449,80.0,-5000.0,0,0.8,500,1.8,500,,,,,,,,,25,0.8,1.8,,
    """
}
