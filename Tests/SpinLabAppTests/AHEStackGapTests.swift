import Foundation
import Testing
@testable import SpinLabApp

/// AHE single-tab stack/gap support — AHE joins RT/IV/XYRotation as a CartesianXY
/// stacked-curve workflow while keeping exactly one tab (no tab picker shown).
///
/// Coverage:
///   1. AHEWorkspaceStore default values match RT/IV/XYRotation convention (0.0 / 0.15).
///   2. BuildAHEPlotPayloadUseCase applies vertical offset to displayPayload only —
///      manifestPayload (used for series order / manifest / extraction inputs) stays raw.
///   3. AHEPackConfig round-trips stackOffsetMultiplier/minGapFraction; legacy packs
///      missing the keys decode to the same defaults.
@Suite("AHE stack/gap")
struct AHEStackGapTests {

    // MARK: - Fixtures

    private func makeSeries(label: String, y: [Double]) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(
            label: label,
            x: [0, 1, 2],
            y: y,
            sourceRef: "/tmp/\(label).csv",
            sampleID: label
        )
    }

    private func makeIngestion() -> AHEIngestionResult {
        AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: AHEAxisDetector.displayXField, yField: AHEAxisDetector.displayYField),
            series: [
                makeSeries(label: "bottom", y: [0, 1, 2]),
                makeSeries(label: "top", y: [10, 11, 12])
            ],
            sourceFiles: ["/tmp/bottom.csv", "/tmp/top.csv"],
            warnings: []
        )
    }

    @MainActor
    private func makeStore() -> AHEWorkspaceStore {
        AHEWorkspaceStore(workflowID: "ahe")
    }

    // MARK: - 1. Store defaults

    @Test("AHEWorkspaceStore stack/gap defaults match RT/IV/XYRotation convention")
    @MainActor
    func storeDefaultsMatchConvention() {
        let store = makeStore()
        #expect(store.stackOffsetMultiplier == 0.0)
        #expect(store.minGapFraction == 0.15)
    }

    // MARK: - 2. Display-only offset, extraction/manifest stays raw

    @Test("stacking offset shifts displayPayload but not manifestPayload")
    func stackingOffsetsDisplayOnly() {
        let ingestion = makeIngestion()
        let payloads = BuildAHEPlotPayloadUseCase().executePayloads(
            ingestion: ingestion,
            title: "AHE Test",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15
        )

        // manifestPayload (order/identity source, and what extraction is derived from
        // upstream via ingestion.series — never this payload) keeps raw y-values.
        let manifestY = payloads.manifestPayload.series.map(\.y)
        #expect(manifestY.contains([0, 1, 2]))
        #expect(manifestY.contains([10, 11, 12]))

        // displayPayload (what actually gets rendered) has at least one series shifted.
        let displayY = payloads.displayPayload.series.map(\.y)
        let anyShifted = zip(payloads.displayPayload.series, ["bottom", "top"]).contains { series, _ in
            !manifestY.contains(series.y)
        }
        #expect(anyShifted, "expected at least one series' y-values to differ from raw manifest values under multiplier=1.2")
        #expect(displayY.count == manifestY.count)
    }

    @Test("multiplier=0 (default) produces identical display and manifest y-values")
    func zeroMultiplierIsNoOp() {
        let ingestion = makeIngestion()
        let payloads = BuildAHEPlotPayloadUseCase().executePayloads(
            ingestion: ingestion,
            title: "AHE Test",
            stackOffsetMultiplier: 0.0,
            minGapFraction: 0.15
        )

        let manifestY = Set(payloads.manifestPayload.series.map(\.y))
        let displayYValues = Set(payloads.displayPayload.series.map(\.y))
        #expect(manifestY == displayYValues)
    }

    @Test("extraction reads ingestion series directly, unaffected by stack offset")
    func extractionUnaffectedByStackOffset() throws {
        let ingestion = makeIngestion()
        // Extraction is computed from `ingestion.series` before BuildAHEPlotPayloadUseCase
        // ever runs (see AHEWorkspaceStore._runAnalysisWithPreparedSelections) — assert the
        // raw ingestion series are untouched regardless of what stack config is later applied.
        let rawYBefore = ingestion.series.map(\.y)
        _ = BuildAHEPlotPayloadUseCase().executePayloads(
            ingestion: ingestion,
            title: "AHE Test",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15
        )
        let rawYAfter = ingestion.series.map(\.y)
        #expect(rawYBefore == rawYAfter)
    }

    // MARK: - 3. Pack round-trip

    @Test("AHEPackConfig round-trips stack/gap through encode/decode")
    func packConfigRoundTrips() throws {
        let config = AHEPackConfig(
            titleTemplate: "#tab #device #sample",
            showPlotGrid: true,
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.2
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AHEPackConfig.self, from: data)
        #expect(decoded.stackOffsetMultiplier == 1.2)
        #expect(decoded.minGapFraction == 0.2)
    }

    @Test("legacy AHEPackConfig JSON missing stack/gap keys decodes to defaults")
    func legacyPackDecodesToDefaults() throws {
        let legacyJSON = """
        {
            "titleTemplate": "#tab #device #sample",
            "showPlotGrid": true,
            "legendAnchor": "",
            "seriesRenderMode": "line",
            "chartStyleOverrides": {},
            "tabStates": {},
            "cachedSearchResults": [],
            "selectedSearchResultIDs": [],
            "searchQueryText": ""
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AHEPackConfig.self, from: legacyJSON)
        #expect(decoded.stackOffsetMultiplier == 0.0)
        #expect(decoded.minGapFraction == 0.15)
    }

    // MARK: - 4. Store pack round-trip (buildPackConfig / restoreFromPack)

    @MainActor
    @Test("AHEWorkspaceStore buildPackConfig/restoreFromPack round-trip stack/gap")
    func storePackRoundTrip() {
        let store = makeStore()
        store.stackOffsetMultiplier = 1.4
        store.minGapFraction = 0.25

        let config = store.buildPackConfig()
        #expect(config.stackOffsetMultiplier == 1.4)
        #expect(config.minGapFraction == 0.25)

        let freshStore = makeStore()
        let dummyPack = AnalysisPack(
            label: "test",
            workflowID: "ahe",
            createdAt: .distantPast,
            filePaths: [],
            sampleKeys: [],
            config: Data(),
            result: Data()
        )
        freshStore.restoreFromPack(
            config: config,
            result: AHEPackResult(ingestionResult: nil),
            pack: dummyPack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )
        #expect(freshStore.stackOffsetMultiplier == 1.4)
        #expect(freshStore.minGapFraction == 0.25)
    }
}
