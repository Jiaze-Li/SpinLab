import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.5 IV Series Order")
struct V565IVSeriesOrderTests {

    private func makeSweep(
        id: String,
        temperatureK: Double,
        y: [Double]
    ) -> IVSweep {
        IVSweep(
            stem: id,
            temperatureK: temperatureK,
            fieldT: 0,
            current: [0, 1, 2],
            ch1X: y,
            ch1Y: y.map { $0 * 0.5 },
            ch2X: y.map { $0 * 2 },
            ch2Y: y.map { $0 * 0.25 },
            measurementFilePath: "/tmp/\(id).csv"
        )
    }

    private func makeSweeps() -> [IVSweep] {
        [
            makeSweep(id: "bottom", temperatureK: 5, y: [0, 1, 2]),
            makeSweep(id: "middle", temperatureK: 10, y: [10, 11, 12]),
            makeSweep(id: "top", temperatureK: 15, y: [20, 21, 22])
        ]
    }

    private func identityOrder(_ series: [WorkbenchPlotSeries]) -> [String] {
        WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series).map(\.identityKey)
    }

    private func meanYDescendingOrder(_ series: [WorkbenchPlotSeries]) -> [String] {
        series.enumerated()
            .map { index, series in
                (
                    identity: WorkbenchSeriesOrderKeyResolver.resolve(for: series, originalIndex: index),
                    mean: series.y.reduce(0.0, +) / Double(series.y.count)
                )
            }
            .sorted { $0.mean > $1.mean }
            .map(\.identity)
    }

    private func requestedOrder() throws -> [String] {
        var renderer = IVPlotRenderer()
        guard let manifest = renderer.makeFirstHarmonicPayload(
            sweeps: makeSweeps(),
            device: "0deg"
        ) else {
            Issue.record("Expected IV manifest payload for requested-order derivation")
            return []
        }
        return Array(identityOrder(manifest.series).reversed())
    }

    @Test("IV stacked payload consumes full identity-key reorder")
    func fullIdentityKeyReorder() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try requestedOrder()

        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.seriesOrder = requestedOrder

        let manifest = renderer.makeFirstHarmonicPayload(
            sweeps: sweeps,
            device: "0deg"
        )
        guard let manifest else {
            Issue.record("Expected IV manifest payload for reorder test")
            return
        }

        #expect(identityOrder(manifest.series) == requestedOrder)
        #expect(manifest.seriesReorderable == true)
        #expect(manifest.reverseSeriesForLegend == false)
    }

    @MainActor
    @Test("IV chips, legend, and display share one identity order")
    func chipLegendDisplayAlignment() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try requestedOrder()

        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.seriesOrder = requestedOrder

        let manifest = renderer.makeFirstHarmonicPayload(
            sweeps: sweeps,
            device: "0deg"
        )
        guard let manifest else {
            Issue.record("Expected IV manifest payload for alignment test")
            return
        }
        let (_, layout, displayPayload, warnings) = IVRenderRoute.renderFirstHarmonicVsCurrentViaSharedRoute(
            renderer: renderer,
            sweeps: sweeps,
            device: "0deg"
        )
        let chipModel = SeriesControlModel.fromPayload(manifest, currentSeriesOrder: requestedOrder)

        #expect(identityOrder(manifest.series) == requestedOrder)
        #expect(try #require(layout).legendRows.map(\.identityKey) == requestedOrder)
        #expect(chipModel.items.map(\.identityKey) == requestedOrder)
        #expect(identityOrder(try #require(displayPayload).series) == requestedOrder)
        #expect(!warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @MainActor
    @Test("IV stacked display keeps descending mean-y order under reordered input")
    func meanYDescendingOrderMatchesVisualOrder() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try requestedOrder()

        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.seriesOrder = requestedOrder

        let (_, _, displayPayload, warnings) = IVRenderRoute.renderFirstHarmonicVsCurrentViaSharedRoute(
            renderer: renderer,
            sweeps: sweeps,
            device: "0deg"
        )
        let display = try #require(displayPayload)

        #expect(identityOrder(display.series) == requestedOrder)
        #expect(meanYDescendingOrder(display.series) == requestedOrder)
        #expect(!warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @MainActor
    @Test("IV hidden filtering compacts stack and preserves order")
    func hiddenFilteringCompactsStackAndPreservesOrder() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try requestedOrder()
        let hiddenKey = requestedOrder[1]

        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.seriesOrder = requestedOrder

        let (_, _, displayPayload, warnings) = IVRenderRoute.renderFirstHarmonicVsCurrentViaSharedRoute(
            renderer: renderer,
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: [hiddenKey]
        )
        let display = try #require(displayPayload)

        #expect(identityOrder(display.series) == [requestedOrder[0], requestedOrder[2]])
        #expect(display.series.count == 2)
        #expect(!warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))
    }

    @MainActor
    @Test("IV all-hidden behavior keeps old warning and visible series")
    func allHiddenBehaviorKeepsWarningAndSeries() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try requestedOrder()

        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.seriesOrder = requestedOrder

        let (_, _, displayPayload, warnings) = IVRenderRoute.renderFirstHarmonicVsCurrentViaSharedRoute(
            renderer: renderer,
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: requestedOrder
        )
        let display = try #require(displayPayload)

        #expect(identityOrder(display.series) == requestedOrder)
        #expect(display.series.count == 3)
        #expect(warnings.contains("series visibility ignored: all series were hidden"))
    }

    @Test("IV render path emits no seriesOrder mismatch warning")
    func noSeriesOrderMismatchWarning() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try requestedOrder()

        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15
        renderer.seriesOrder = requestedOrder

        let manifest = renderer.makeFirstHarmonicPayload(
            sweeps: sweeps,
            device: "0deg"
        )
        guard let manifest else {
            Issue.record("Expected IV manifest payload for mismatch-warning test")
            return
        }
        var input = WorkbenchRenderPipeline.Input(payload: manifest)
        input.seriesOrder = requestedOrder

        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @MainActor
    @Test("IV pack restore preserves series order")
    func packRestorePreservesSeriesOrder() async throws {
        let sweeps = makeSweeps()
        let requestedOrder = try requestedOrder()
        let ingestion = IVIngestionResult(sweeps: sweeps, device: "0deg", warnings: [])
        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/iv-pack.csv.spinlab.json",
            measurementFilePath: "/tmp/iv-pack.csv",
            sourceFilePath: "/tmp/iv-pack.csv",
            workflowID: "iv",
            workflowDisplayName: "IV",
            workflowCanonicalID: "iv",
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "5K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
        let config = IVPackConfig(
            titleTemplate: "#tab #sample",
            activeTab: IVWorkbenchTab.voltage.rawValue,
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: false,
            legendAnchor: "",
            seriesRenderMode: .line,
            chartStyleOverrides: [:],
            ch1Component: IVSignalComponent.x.rawValue,
            ch2Component: IVSignalComponent.x.rawValue,
            xCurrentBasis: .peak,
            tabStates: [
                IVWorkbenchTab.voltage.rawValue: TabRenderState(
                    seriesOrder: requestedOrder
                )
            ],
            cachedSearchResults: [hit],
            selectedSearchResultIDs: [hit.id],
            searchQueryText: "iv pack"
        )
        let result = IVPackResult(ingestionResult: ingestion)
        let pack = try AnalysisPack(
            label: "IV Pack",
            workflowID: "iv",
            filePaths: sweeps.compactMap(\.measurementFilePath),
            sampleKeys: [hit.sampleKey],
            config: config,
            result: result
        )
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)

        store.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.tabs.state(for: .voltage).seriesOrder == requestedOrder)

        for _ in 0..<40 {
            let output = store.tabs.output(for: .voltage)
            if let manifest = output.manifestPayload,
               let display = output.displayPayload,
               let layout = output.layout {
                #expect(identityOrder(manifest.series) == requestedOrder)
                #expect(identityOrder(display.series) == requestedOrder)
                #expect(layout.legendRows.map(\.identityKey) == requestedOrder)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        Issue.record("Timed out waiting for IV pack restore to preserve series order")
    }
}
