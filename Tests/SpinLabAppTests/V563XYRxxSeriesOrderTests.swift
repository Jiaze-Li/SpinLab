import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.3 XY Rxx Series Order")
struct V563XYRxxSeriesOrderTests {

    private func makeSweep(
        stem: String,
        temperatureK: Double,
        resistanceXX: [Double]
    ) -> XYRotationAngleSweep {
        XYRotationAngleSweep(
            temperatureK: temperatureK,
            stem: stem,
            sourceKind: .lvm,
            angleDeg: [0, 90, 180],
            resistanceXX: resistanceXX,
            resistanceXY: nil,
            defaultPhiOffset: 0,
            measurementFilePath: "/tmp/\(stem).csv",
            sampleMetadata: ["device": "0deg"]
        )
    }

    private func makeSweeps() -> [XYRotationAngleSweep] {
        [
            makeSweep(stem: "bottom", temperatureK: 5, resistanceXX: [0, 1, 2]),
            makeSweep(stem: "middle", temperatureK: 10, resistanceXX: [10, 11, 12]),
            makeSweep(stem: "top", temperatureK: 15, resistanceXX: [20, 21, 22])
        ]
    }

    private func identityOrder(_ series: [WorkbenchPlotSeries]) -> [String] {
        WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series).map(\.identityKey)
    }

    private func reversedRequestedOrder() throws -> [String] {
        let manifest = try #require(XYRotationPlotRenderer().makeRxxVsPhiPayload(
            sweeps: makeSweeps(),
            device: "0deg"
        ))
        return Array(identityOrder(manifest.series).reversed())
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

    @Test("XY Rxx stacked payload consumes full identity-key reorder")
    func fullIdentityKeyReorder() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try reversedRequestedOrder()

        let manifest = try #require(XYRotationPlotRenderer().makeRxxVsPhiPayload(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder
        ))

        #expect(identityOrder(manifest.series) == requestedOrder)
        #expect(manifest.seriesReorderable == true)
        #expect(manifest.reverseSeriesForLegend == false)
    }

    @Test("XY Rxx chips, legend, and display share one identity order")
    func chipLegendDisplayAlignment() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try reversedRequestedOrder()

        let manifest = try #require(XYRotationPlotRenderer().makeRxxVsPhiPayload(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder
        ))
        var renderer = XYRotationPlotRenderer()
        let (_, layout, displayPayload, warnings) = renderer.renderRxxVsPhi(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder
        )
        let chipModel = SeriesControlModel.fromPayload(manifest, currentSeriesOrder: requestedOrder)

        #expect(identityOrder(manifest.series) == requestedOrder)
        #expect(try #require(layout).legendRows.map { $0.identityKey } == requestedOrder)
        #expect(chipModel.items.map { $0.identityKey } == requestedOrder)
        #expect(identityOrder(try #require(displayPayload).series) == requestedOrder)
        #expect(!warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @Test("XY Rxx stacked display keeps descending mean-y order under reordered input")
    func meanYDescendingOrderMatchesVisualOrder() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try reversedRequestedOrder()

        var renderer = XYRotationPlotRenderer()
        let (_, _, displayPayload, warnings) = renderer.renderRxxVsPhi(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder
        )
        let display = try #require(displayPayload)

        #expect(identityOrder(display.series) == requestedOrder)
        #expect(meanYDescendingOrder(display.series) == requestedOrder)
        #expect(!warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @Test("XY Rxx hidden filtering compacts stack and preserves order")
    func hiddenFilteringCompactsStackAndPreservesOrder() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try reversedRequestedOrder()
        let hiddenKey = requestedOrder[1]

        var renderer = XYRotationPlotRenderer()
        let (_, _, displayPayload, warnings) = renderer.renderRxxVsPhi(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder,
            hiddenSeriesKeys: [hiddenKey]
        )
        let display = try #require(displayPayload)

        #expect(identityOrder(display.series) == [requestedOrder[0], requestedOrder[2]])
        #expect(display.series.count == 2)
        #expect(!warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))
    }

    @Test("XY Rxx all-hidden behavior keeps old warning and visible series")
    func allHiddenBehaviorKeepsWarningAndSeries() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try reversedRequestedOrder()

        var renderer = XYRotationPlotRenderer()
        let (_, _, displayPayload, warnings) = renderer.renderRxxVsPhi(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder,
            hiddenSeriesKeys: requestedOrder
        )
        let display = try #require(displayPayload)

        #expect(identityOrder(display.series) == requestedOrder)
        #expect(display.series.count == 3)
        #expect(warnings.contains("series visibility ignored: all series were hidden"))
    }

    @Test("XY Rxx render path emits no seriesOrder mismatch warning")
    func noSeriesOrderMismatchWarning() throws {
        let sweeps = makeSweeps()
        let requestedOrder = try reversedRequestedOrder()
        let manifest = try #require(XYRotationPlotRenderer().makeRxxVsPhiPayload(
            sweeps: sweeps,
            device: "0deg",
            seriesOrder: requestedOrder
        ))
        var input = WorkbenchRenderPipeline.Input(payload: manifest)
        input.seriesOrder = requestedOrder

        let output = try WorkbenchRenderPipeline.render(input)
        #expect(!output.warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
    }

    @MainActor
    @Test("XY Rxx pack restore preserves series order")
    func packRestorePreservesSeriesOrder() async throws {
        let sweeps = makeSweeps()
        let requestedOrder = try reversedRequestedOrder()
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        store.ingestionResult = XYRotationIngestionResult(sweeps: sweeps, device: "0deg", warnings: [])
        store.cachedSearchResults = [
            WorkflowMeasurementSearchHit(
                sidecarPath: "/tmp/xy-pack.csv.spinlab.json",
                measurementFilePath: "/tmp/xy-pack.csv",
                sourceFilePath: "/tmp/xy-pack.csv",
                workflowID: "xy",
                workflowDisplayName: "XY",
                workflowCanonicalID: "xy",
                batchID: "PN31",
                sampleKey: "PN31|b|STO|111",
                sampleSubstrate: "STO111",
                conditions: ["temperature": "5K"],
                channels: ["ch1"],
                appliedAt: .distantPast
            )
        ]
        store.tabs.activeTab = .rxxVsPhi
        store.tabs.tabStates[.rxxVsPhi] = TabRenderState(seriesOrder: requestedOrder)

        let config = XYRotationPackConfig(
            phiOffsetOverrides: [:],
            centerBaseline: false,
            linearDetrend: false,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue,
            titleTemplate: store.titleTemplate,
            stackOffsetMultiplier: store.stackOffsetMultiplier,
            minGapFraction: store.minGapFraction,
            showPlotGrid: store.tabs.showPlotGrid,
            showAuxiliaryLine180: store.showAuxiliaryLine180,
            legendAnchor: store.tabs.legendAnchor,
            seriesRenderMode: store.tabs.seriesRenderMode,
            chartStyleOverrides: store.tabs.chartStyleOverrides,
            tabStates: [XYRotationWorkbenchTab.rxxVsPhi.rawValue: TabRenderState(seriesOrder: requestedOrder)],
            cachedSearchResults: store.cachedSearchResults,
            selectedSearchResultIDs: [],
            searchQueryText: ""
        )
        let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult(sweeps: sweeps, device: "0deg", warnings: []))
        let pack = try AnalysisPack(
            label: "XY Rxx Pack",
            workflowID: "xy",
            filePaths: sweeps.compactMap(\.measurementFilePath),
            sampleKeys: ["PN31|b|STO|111"],
            config: config,
            result: result
        )

        let restored = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)
        restored.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(restored.tabs.state(for: .rxxVsPhi).seriesOrder == requestedOrder)

        for _ in 0..<40 {
            let output = restored.tabs.output(for: .rxxVsPhi)
            if let manifest = output.manifestPayload, let display = output.displayPayload, let layout = output.layout {
                #expect(identityOrder(manifest.series) == requestedOrder)
                #expect(identityOrder(display.series) == requestedOrder)
                #expect(layout.legendRows.map { $0.identityKey } == requestedOrder)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        Issue.record("Timed out waiting for XY Rxx pack restore to preserve series order")
    }
}
