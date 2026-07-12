import Foundation
import Testing
@testable import SpinLabApp

@Suite("IVAngleDependence IV Integration")
struct IVAngleDependenceIntegrationTests {

    private func makeSweep(
        id: String,
        angleDeg: Double?,
        current: [Double],
        ch1X: [Double]
    ) -> IVSweep {
        IVSweep(
            stem: id,
            temperatureK: 5,
            fieldT: 0,
            current: current,
            ch1X: ch1X,
            ch1Y: ch1X.map { $0 * 0.5 },
            ch2X: ch1X.map { $0 * 2 },
            ch2Y: ch1X.map { $0 * 0.25 },
            measurementFilePath: "/tmp/\(id).csv",
            sampleMetadata: angleDeg.map { ["device": "\($0)deg"] }
        )
    }

    // MARK: - Renderer: off path unchanged

    @Test("Angular plot off leaves the existing V-vs-I^n payload unchanged")
    func angularPlotOffLeavesExistingViewUnchanged() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        renderer.angularPlotEnabled = false
        let sweep = makeSweep(id: "a", angleDeg: 0, current: [0, 1, 2], ch1X: [0, 2, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        let base = try #require(manifest.series.first)
        #expect(base.x == [0, 1000, 2000])
        #expect(base.y == [0, 2000, 4000])
        #expect(manifest.seriesOverlays.count == 1)
        // Ordinary (non-Angular-Plot) legend labels are untouched by this feature.
        #expect(!MathMarkupRenderer.isMathLabel(base.label))
    }

    // MARK: - Renderer: on path builds one point per angle

    @Test("Angular plot on replaces the tab payload with one point per angle")
    func angularPlotOnBuildsAnglePayload() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        renderer.angularPlotEnabled = true
        // current_A [0,1,2] -> mA [0,1000,2000]; ch1X (V) -> mV [0,2000,4000] or [0,5000,10000].
        // a_n = slope of mV vs mA: sweep a -> 2000/1000 = 2.0 mV/mA; sweep b -> 5000/1000 = 5.0 mV/mA.
        let sweeps = [
            makeSweep(id: "b", angleDeg: 90, current: [0, 1, 2], ch1X: [0, 5, 10]),   // slope 5.0 mV/mA
            makeSweep(id: "a", angleDeg: 0, current: [0, 1, 2], ch1X: [0, 2, 4])      // slope 2.0 mV/mA
        ]
        let payloads = renderer.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let result = try #require(payloads)
        let manifest = result.manifestPayload
        let display = result.displayPayload

        #expect(manifest.series.count == 1)
        let series = try #require(manifest.series.first)
        #expect(series.x == [0, 90])
        #expect(series.y.count == 2)
        #expect(abs(series.y[0] - 2.0) < 1e-6)
        #expect(abs(series.y[1] - 5.0) < 1e-6)
        #expect(series.renderMode == .scatter)
        #expect(manifest.seriesOverlays.isEmpty)
        #expect(manifest.axisMapping.xField == "Ψ (deg)")
        #expect(manifest.axisMapping.yField.contains("mV/mA"))

        // Legend label: through the existing "math:" Plot System path, reusing the
        // yAxisLabel fraction (no unit) — plain text for manifest, math for the canvas.
        #expect(series.label == "V(1ω)/I^1")
        #expect(!MathMarkupRenderer.isMathLabel(series.label))
        let displaySeries = try #require(display.series.first)
        #expect(displaySeries.label == "math:V_{x}^{ω}/I_x^{ω}")
        #expect(MathMarkupRenderer.isMathLabel(displaySeries.label))
    }

    @Test("Angular plot on with insufficient distinct angles reports an empty/insufficient payload, not a crash")
    func angularPlotOnWithInsufficientAnglesDegradesGracefully() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        renderer.angularPlotEnabled = true
        let sweeps = [
            makeSweep(id: "a", angleDeg: 45, current: [0, 1, 2], ch1X: [0, 2, 4]),
            makeSweep(id: "b", angleDeg: 45, current: [0, 1, 2], ch1X: [0, 3, 6])
        ]
        let payloads = renderer.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let result = try #require(payloads)

        #expect(result.manifestPayload.series.first?.x.count == 2)
        #expect(result.warnings.contains(where: { $0.contains("needs at least") }))
    }

    // MARK: - Store: gating

    @MainActor
    @Test("canEnableAngularPlot requires an active Fit mode and >=2 distinct angles")
    func canEnableAngularPlotGating() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        store.ingestionResult = IVIngestionResult(
            sweeps: [
                makeSweep(id: "a", angleDeg: 0, current: [0, 1, 2], ch1X: [0, 2, 4]),
                makeSweep(id: "b", angleDeg: 90, current: [0, 1, 2], ch1X: [0, 3, 6])
            ],
            device: "d"
        )

        store.updateFitMode(.none)
        #expect(store.canEnableAngularPlot == false)

        store.updateFitMode(.one)
        #expect(store.canEnableAngularPlot == true)

        store.ingestionResult = IVIngestionResult(
            sweeps: [
                makeSweep(id: "a", angleDeg: 0, current: [0, 1, 2], ch1X: [0, 2, 4]),
                makeSweep(id: "b", angleDeg: 0, current: [0, 1, 2], ch1X: [0, 3, 6])
            ],
            device: "d"
        )
        #expect(store.canEnableAngularPlot == false)
    }

    // MARK: - Store: Fit None clears Angular Plot like Zero at I=0

    @MainActor
    @Test("Setting Fit to None clears Angular Plot")
    func updateFitModeToNoneClearsAngularPlot() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        store.ingestionResult = IVIngestionResult(
            sweeps: [
                makeSweep(id: "a", angleDeg: 0, current: [0, 1, 2], ch1X: [0, 2, 4]),
                makeSweep(id: "b", angleDeg: 90, current: [0, 1, 2], ch1X: [0, 3, 6])
            ],
            device: "d"
        )
        store.updateFitMode(.two)
        store.updateAngularPlotEnabled(true)
        #expect(store.angularPlotEnabled == true)

        store.updateFitMode(.none)

        #expect(store.fitMode == .none)
        #expect(store.angularPlotEnabled == false)
    }

    // MARK: - Store: toggling clears stale axis label overrides

    @MainActor
    @Test("Toggling Angular Plot resets x/y label overrides on both tabs")
    func toggleAngularPlotClearsAxisLabelOverrides() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        store.ingestionResult = IVIngestionResult(
            sweeps: [
                makeSweep(id: "a", angleDeg: 0, current: [0, 1, 2], ch1X: [0, 2, 4]),
                makeSweep(id: "b", angleDeg: 90, current: [0, 1, 2], ch1X: [0, 3, 6])
            ],
            device: "d"
        )
        store.updateFitMode(.one)
        var voltageState = TabRenderState()
        voltageState.xLabelOverride = "My Custom X"
        voltageState.yLabelOverride = "My Custom Y"
        store.tabs.tabStates[.voltage] = voltageState

        store.updateAngularPlotEnabled(true)

        #expect(store.tabs.tabStates[.voltage]?.xLabelOverride == "")
        #expect(store.tabs.tabStates[.voltage]?.yLabelOverride == "")
    }

    // MARK: - Pack round-trip / restore

    @Test("IVPackConfig decodes angularPlotEnabled default from legacy payloads missing the key")
    func packConfigBackwardCompatibleDefault() throws {
        let legacyJSON = """
        {
          "activeTab": "voltage",
          "titleTemplate": "#tab",
          "stackOffsetMultiplier": 0,
          "minGapFraction": 0.15,
          "showPlotGrid": true,
          "legendAnchor": "",
          "seriesRenderMode": "line",
          "chartStyleOverrides": {},
          "ch1Component": "X",
          "ch2Component": "X",
          "xCurrentBasis": "peak",
          "fitMode": 1,
          "zeroAtCurrentOrigin": false,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let config = try JSONDecoder().decode(IVPackConfig.self, from: Data(legacyJSON.utf8))
        #expect(config.angularPlotEnabled == false)
    }

    @Test("IVPackConfig round-trips angularPlotEnabled through encode/decode")
    func packConfigRoundTripsAngularPlotEnabled() throws {
        var config = IVPackConfig(titleTemplate: "#tab", showPlotGrid: true)
        config.fitMode = .two
        config.angularPlotEnabled = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(IVPackConfig.self, from: data)
        #expect(decoded.angularPlotEnabled == true)
    }

    @MainActor
    @Test("Pack restore normalizes Angular Plot to false when the restored fit mode is None")
    func restoreFromPackNormalizesAngularPlotForNoneFitMode() {
        let config = IVPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            fitMode: .none,
            angularPlotEnabled: true
        )
        let result = IVPackResult(ingestionResult: IVIngestionResult())
        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/iv.csv.spinlab.json",
            measurementFilePath: "/tmp/iv.csv",
            sourceFilePath: "/tmp/iv.csv",
            workflowID: "iv",
            workflowDisplayName: "IV",
            workflowCanonicalID: "iv",
            batchID: "B",
            sampleKey: "B|b|S|1",
            sampleSubstrate: "S1",
            conditions: [:],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
        let pack = try! AnalysisPack(
            label: "IV Pack",
            workflowID: "iv",
            filePaths: [],
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

        #expect(store.fitMode == .none)
        #expect(store.angularPlotEnabled == false)
    }
}
