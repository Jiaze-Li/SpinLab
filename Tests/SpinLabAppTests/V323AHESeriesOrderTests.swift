import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.3 AHE Series Order Migration")
struct V323AHESeriesOrderTests {

    private struct Fixture {
        let rootURL: URL
        let fm = FileManager.default

        init() throws {
            rootURL = fm.temporaryDirectory.appending(
                path: "spinlab-v323-ahe-\(UUID().uuidString)",
                directoryHint: .isDirectory
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

    private enum Fixtures {
        static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

        static let ch1ch2 = """
        [Header]
        TITLE, test
        [Data]
        \(colHeader)
        ,0,4449,80.0,10000.0,0,1.0,500,2.0,500,,,,,,,,,25,1.0,2.0,,
        ,1,4449,80.0,5000.0,0,0.9,500,1.9,500,,,,,,,,,25,0.9,1.9,,
        ,2,4449,80.0,-5000.0,0,0.8,500,1.8,500,,,,,,,,,25,0.8,1.8,,
        """
    }

    private func makeIngestion() throws -> AHEIngestionResult {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let url = try fixture.write(name: "ahe.dat", content: Fixtures.ch1ch2)
        return try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch1),
                .init(sampleKey: "PN31|b|STO|111", sourceFilePath: url.path, channel: .ch2)
            ],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )
    }

    private func identityOrder(_ series: [WorkbenchPlotSeries]) -> [String] {
        WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series).map(\.identityKey)
    }

    private func makePayloads(
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) throws -> (ingestion: AHEIngestionResult, payloads: AHEPlotPayloads, requestedOrder: [String]) {
        let ingestion = try makeIngestion()
        let requestedOrder = seriesOrder ?? Array(identityOrder(ingestion.series).reversed())
        let payloads = BuildAHEPlotPayloadUseCase().executePayloads(
            ingestion: ingestion,
            title: "AHE 80K",
            seriesOrder: requestedOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        )
        return (ingestion, payloads, requestedOrder)
    }

    @Test("AHE planner consumes full identity-key reorder")
    func fullIdentityKeyReorder() throws {
        let result = try makePayloads()
        #expect(identityOrder(result.payloads.manifestPayload.series) == result.requestedOrder)
        #expect(identityOrder(result.payloads.displayPayload.series) == result.requestedOrder)
        #expect(result.payloads.manifestPayload.seriesReorderable == true)
        #expect(result.payloads.manifestPayload.reverseSeriesForLegend == false)
        #expect(result.payloads.warnings.isEmpty)
    }

    @Test("AHE chips, legend, and display share one identity order")
    func chipLegendDisplayAlignment() throws {
        let result = try makePayloads()
        var input = WorkbenchRenderPipeline.Input(payload: result.payloads.manifestPayload)
        input.seriesOrder = result.requestedOrder

        let output = try WorkbenchRenderPipeline.render(input)
        let chipModel = SeriesControlModel.fromPayload(
            output.manifestPayload,
            currentSeriesOrder: result.requestedOrder
        )

        #expect(identityOrder(output.manifestPayload.series) == result.requestedOrder)
        #expect(output.layout.legendRows.map(\.identityKey) == result.requestedOrder)
        #expect(chipModel.items.map(\.identityKey) == result.requestedOrder)
        #expect(WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: output.manifestPayload.series).map(\.identityKey) == result.requestedOrder)
    }

    @Test("AHE hidden filtering preserves visual order")
    func hiddenFilteringPreservesVisualOrder() throws {
        let result = try makePayloads()
        let hiddenKey = try #require(result.requestedOrder.first)

        let hidden = BuildAHEPlotPayloadUseCase().executePayloads(
            ingestion: result.ingestion,
            title: "AHE 80K",
            seriesOrder: result.requestedOrder,
            hiddenSeriesKeys: [hiddenKey]
        )
        #expect(identityOrder(hidden.displayPayload.series) == Array(result.requestedOrder.dropFirst()))

        var input = WorkbenchRenderPipeline.Input(payload: hidden.manifestPayload)
        input.seriesOrder = result.requestedOrder
        input.hiddenSeriesKeys = [hiddenKey]

        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.legendRows.map(\.identityKey) == Array(result.requestedOrder.dropFirst()))
        #expect(identityOrder(output.manifestPayload.series) == result.requestedOrder)
    }

    @Test("AHE render path emits no seriesOrder mismatch warning")
    func noSeriesOrderMismatchWarning() throws {
        let result = try makePayloads()
        var input = WorkbenchRenderPipeline.Input(payload: result.payloads.manifestPayload)
        input.seriesOrder = result.requestedOrder

        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @MainActor
    @Test("AHE pack restore preserves series order")
    func packRestorePreservesSeriesOrder() async throws {
        let result = try makePayloads()
        let hiddenKey = try #require(result.requestedOrder.first)
        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/ahe-pack.spinlab.json",
            measurementFilePath: "/tmp/ahe-pack.dat",
            sourceFilePath: "/tmp/ahe-pack.dat",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe",
            batchID: "PN31",
            sampleKey: "PN31|o|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1", "ch2"],
            appliedAt: .distantPast
        )
        let config = AHEPackConfig(
            titleTemplate: "#tab #sample",
            showPlotGrid: false,
            tabStates: [
                AHEWorkbenchTab.ahe.rawValue: TabRenderState(
                    hiddenSeriesKeys: [hiddenKey],
                    seriesOrder: result.requestedOrder
                )
            ],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id],
            searchQueryText: "ahe pack"
        )
        let resultPayload = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R_H (Ω)"),
            series: result.ingestion.series,
            sourceFiles: [hit.measurementFilePath],
            warnings: []
        )
        let pack = try AnalysisPack(
            label: "AHE Pack",
            workflowID: "ahe",
            filePaths: [hit.measurementFilePath],
            sampleKeys: [hit.sampleKey],
            config: config,
            result: AHEPackResult(ingestionResult: resultPayload)
        )
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)

        store.restoreFromPack(
            config: config,
            result: AHEPackResult(ingestionResult: resultPayload),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.tabs.activeState.seriesOrder == result.requestedOrder)
        #expect(store.tabs.activeState.hiddenSeriesKeys == [hiddenKey])

        for _ in 0..<40 {
            if let order = store.tabs.activeOutput.seriesControlModel?.items.map(\.identityKey),
               order == result.requestedOrder {
                #expect(store.tabs.activeManifestPayload?.series.count == result.ingestion.series.count)
                #expect(store.tabs.activeOutput.seriesControlModel?.items.map(\.identityKey) == result.requestedOrder)
                #expect(store.tabs.activeLayout?.legendRows.map(\.identityKey) == Array(result.requestedOrder.dropFirst()))
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        Issue.record("Timed out waiting for AHE restore rerender to preserve series order")
    }
}
