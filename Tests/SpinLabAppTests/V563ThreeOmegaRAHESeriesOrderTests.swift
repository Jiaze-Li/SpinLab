import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.3 ThreeOmega RAHE Series Order")
struct V563ThreeOmegaRAHESeriesOrderTests {

    private func makeCombinedRAHESweeps() -> [ThreeOmegaFieldSweepResult] {
        [
            ThreeOmegaFieldSweepResult(
                temperatureK: 5.0,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample",
                sourceFilePath: "/tmp/sample-5K.csv",
                hField: [-1000, 0, 1000],
                r1omega: [-1, 0, 1],
                r3omega: [-2, 0, 2],
                iRms: 1e-4,
                rahe1omega: 0.4,
                rahe1omegaWA: 0.8,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 0.2e-4,
                v3omegaFit: 0.2e-4
            ),
            ThreeOmegaFieldSweepResult(
                temperatureK: 10.0,
                device: "0deg",
                sampleMetadata: ["device": "0deg"],
                sampleID: "sample",
                sourceFilePath: "/tmp/sample-10K.csv",
                hField: [-1000, 0, 1000],
                r1omega: [-1, 0, 1],
                r3omega: [-2, 0, 2],
                iRms: 1e-4,
                rahe1omega: 0.8,
                rahe1omegaWA: 0.4,
                hc1omega: 0.0,
                hc3omega: 0.0,
                v3omegaWindow: 0.6e-4,
                v3omegaFit: 0.6e-4
            )
        ]
    }

    private func makeIngestionResult() -> ThreeOmegaIngestionResult {
        ThreeOmegaIngestionResult(
            fieldSweeps: makeCombinedRAHESweeps(),
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [5.0: 1e-4, 10.0: 1e-4],
            warnings: []
        )
    }

    private func identityOrder(_ series: [WorkbenchPlotSeries]) -> [String] {
        WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series).map(\.identityKey)
    }

    private func makePayloads(
        seriesOrder: [String]? = nil,
        rahe1Method: ThreeOmegaV3Method = .window,
        rahe3Method: ThreeOmegaV3Method = .highField
    ) throws -> (manifest: WorkbenchPlotPayload, requestedOrder: [String]) {
        let sweeps = makeCombinedRAHESweeps()
        let manifest = try #require(ThreeOmegaPlotRenderer().makeRAHEPayload(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: seriesOrder,
            rahe1Method: rahe1Method,
            rahe3Method: rahe3Method
        ))
        let requestedOrder = seriesOrder ?? identityOrder(manifest.series)
        return (manifest, requestedOrder)
    }

    private func reversedDefaultOrder() throws -> [String] {
        let manifest = try #require(ThreeOmegaPlotRenderer().makeRAHEPayload(
            sweeps: makeCombinedRAHESweeps(),
            device: "0deg",
            rahe1Method: .window,
            rahe3Method: .highField
        ))
        return Array(identityOrder(manifest.series).reversed())
    }

    @Test("RAHE combined payload consumes full identity-key reorder")
    func fullIdentityKeyReorder() throws {
        let sweeps = makeCombinedRAHESweeps()
        let requestedOrder = try reversedDefaultOrder()

        let manifest = try #require(ThreeOmegaPlotRenderer().makeRAHEPayload(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder,
            rahe1Method: .window,
            rahe3Method: .highField
        ))

        #expect(identityOrder(manifest.series) == requestedOrder)
        #expect(manifest.seriesReorderable == true)
        #expect(manifest.reverseSeriesForLegend == false)
    }

    @MainActor
    @Test("RAHE chips, legend, and display share one identity order")
    func chipLegendDisplayAlignment() throws {
        let result = try makePayloads(seriesOrder: try reversedDefaultOrder())
        var input = WorkbenchRenderPipeline.Input(payload: result.manifest)
        input.seriesOrder = result.requestedOrder

        let output = try WorkbenchRenderPipeline.render(input)
        let (_, _, _, displayPayload, _) = ThreeOmegaSharedRenderRoute.render(
            payload: result.manifest,
            tab: .rahe,
            seriesOrder: result.requestedOrder
        )
        let chipModel = SeriesControlModel.fromPayload(
            output.manifestPayload,
            currentSeriesOrder: result.requestedOrder
        )

        #expect(identityOrder(output.manifestPayload.series) == result.requestedOrder)
        #expect(output.layout.legendRows.map { $0.identityKey } == result.requestedOrder)
        #expect(chipModel.items.map { $0.identityKey } == result.requestedOrder)
        #expect(identityOrder(output.manifestPayload.series) == identityOrder(try #require(displayPayload).series))
    }

    @MainActor
    @Test("RAHE hidden filtering preserves visual order")
    func hiddenFilteringPreservesVisualOrder() throws {
        let result = try makePayloads(seriesOrder: try reversedDefaultOrder())
        let hiddenKey = try #require(result.requestedOrder.first)

        let sweeps = makeCombinedRAHESweeps()
        let manifest = try #require(ThreeOmegaPlotRenderer().makeRAHEPayload(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: result.requestedOrder,
            rahe1Method: .window,
            rahe3Method: .highField
        ))
        let (_, _, layout, _, warnings) = ThreeOmegaSharedRenderRoute.render(
            payload: manifest,
            tab: .rahe,
            seriesOrder: result.requestedOrder,
            hiddenSeriesKeys: [hiddenKey]
        )

        #expect(identityOrder(manifest.series) == result.requestedOrder)
        #expect(try #require(layout).legendRows.map { $0.identityKey } == Array(result.requestedOrder.dropFirst()))
        #expect(warnings.allSatisfy { !$0.contains("seriesOrder mismatch") })
    }

    @Test("RAHE render path emits no seriesOrder mismatch warning")
    func noSeriesOrderMismatchWarning() throws {
        let result = try makePayloads(seriesOrder: try reversedDefaultOrder())
        var input = WorkbenchRenderPipeline.Input(payload: result.manifest)
        input.seriesOrder = result.requestedOrder

        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @MainActor
    @Test("RAHE pack restore preserves series order")
    func packRestorePreservesSeriesOrder() async throws {
        let sweeps = makeCombinedRAHESweeps()
        let requestedOrder = try reversedDefaultOrder()

        let sourceStore = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        sourceStore.ingestionResult = makeIngestionResult()
        sourceStore.tabs.activeTab = .rahe
        sourceStore.tabs.tabStates[.rahe] = TabRenderState(seriesOrder: requestedOrder)
        sourceStore.cachedSearchResults = [
            WorkflowMeasurementSearchHit(
                sidecarPath: "/tmp/sample-5K.csv.spinlab.json",
                measurementFilePath: "/tmp/sample-5K.csv",
                sourceFilePath: "/tmp/sample-5K.csv",
                workflowID: "3w",
                workflowDisplayName: "3ω",
                workflowCanonicalID: "3w",
                batchID: "PN31",
                sampleKey: "sample-key",
                sampleSubstrate: "STO111",
                conditions: ["temperature": "5K"],
                channels: ["ch1", "ch2"],
                appliedAt: .distantPast
            )
        ]

        let config = sourceStore._buildPackConfig()
        let result = ThreeOmegaPackResult(ingestionResult: makeIngestionResult(), scalingResult: nil)
        let pack = try AnalysisPack(
            label: "3w RAHE Pack",
            workflowID: "3w",
            filePaths: sweeps.compactMap(\.sourceFilePath),
            sampleKeys: ["sample-key"],
            config: config,
            result: result
        )

        let restoredStore = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        restoredStore.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(restoredStore.tabs.state(for: .rahe).seriesOrder == requestedOrder)

        for _ in 0..<40 {
            let output = restoredStore.tabs.output(for: .rahe)
            if let display = output.displayPayload, let layout = output.layout {
                #expect(identityOrder(try #require(output.manifestPayload).series) == requestedOrder)
                #expect(identityOrder(display.series) == requestedOrder)
                #expect(layout.legendRows.map { $0.identityKey } == requestedOrder)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        Issue.record("Timed out waiting for 3ω RAHE pack restore to preserve series order")
    }
}
