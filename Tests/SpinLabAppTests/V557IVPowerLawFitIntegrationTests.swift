import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.5.7 IV Power-Law Fit Integration")
struct V557IVPowerLawFitIntegrationTests {

    private func makeSweep(id: String, current: [Double], ch1X: [Double]) -> IVSweep {
        IVSweep(
            stem: id,
            temperatureK: 5,
            fieldT: 0,
            current: current,
            ch1X: ch1X,
            ch1Y: ch1X.map { $0 * 0.5 },
            ch2X: ch1X.map { $0 * 2 },
            ch2Y: ch1X.map { $0 * 0.25 },
            measurementFilePath: "/tmp/\(id).csv"
        )
    }

    // MARK: - None: mA/mV, no overlay, no transform

    @Test("Fit mode .none plots plain current (mA) vs voltage (mV) and emits no overlay")
    func noneModeIsUntransformedMAAndMV() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .none
        // current_A -> mA via peak scaleFactor (x1000): [0, 1000, 2000]
        // ch1X (V) -> mV (x1000): [0, 2000, 4000]
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [0, 2, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        #expect(manifest.seriesOverlays.isEmpty)
        let base = try #require(manifest.series.first)
        #expect(base.x == [0, 1000, 2000])
        #expect(base.y == [0, 2000, 4000])
    }

    // MARK: - Transformed measurement coordinates

    @Test("Fit mode .one keeps X as plain current (mA) and Y in mV")
    func fitOneKeepsLinearCurrent() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [0, 2, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        let base = try #require(manifest.series.first)
        #expect(base.x == [0, 1000, 2000])
        #expect(base.y == [0, 2000, 4000])
    }

    @Test("Fit mode .two transforms the measurement X to I^2 (mA^2), Y stays mV")
    func fitTwoTransformsMeasurementXToSquare() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .two
        // mA = [0, 1000, 2000] -> squared = [0, 1_000_000, 4_000_000]
        // ch1X (V) -> mV: [0, 1000, 4000] (chosen collinear with mA^2 for a clean fit)
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [0, 1, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        let base = try #require(manifest.series.first)
        #expect(base.x == [0, 1_000_000, 4_000_000])
        #expect(base.y == [0, 1000, 4000])
    }

    @Test("Fit mode .three transforms the measurement X to I^3 (mA^3)")
    func fitThreeTransformsMeasurementXToCube() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .three
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [0, 1, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        let base = try #require(manifest.series.first)
        // mA = [0, 1000, 2000] -> cubed = [0, 1e9, 8e9]
        #expect(base.x == [0, 1_000_000_000, 8_000_000_000])
    }

    // MARK: - Overlay shares the same transformed coordinate space as the measurement

    @Test("Overlay is anchored to its parent series and shares its transformed coordinate space")
    func overlaySharesTransformedCoordinateSpaceWithMeasurement() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [0, 2, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        #expect(manifest.seriesOverlays.count == 1)
        let overlay = try #require(manifest.seriesOverlays.first)
        let parentKey = try #require(
            WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: manifest.series).first?.identityKey
        )
        #expect(overlay.parentSeriesIdentityKey == parentKey)
        #expect(overlay.series.renderModeLocked == true)
        #expect(overlay.series.x.count == overlay.series.y.count)

        let minX = try #require(overlay.series.x.min())
        let maxX = try #require(overlay.series.x.max())
        #expect(abs(minX - 0) < 1e-6)
        #expect(abs(maxX - 2000) < 1e-6)
        let yAtMinX = overlay.series.y[overlay.series.x.firstIndex(of: minX)!]
        let yAtMaxX = overlay.series.y[overlay.series.x.firstIndex(of: maxX)!]
        // mV, same units as the (now also mV) measurement — no /1000 back to V.
        #expect(abs(yAtMinX - 0) < 1e-6)
        #expect(abs(yAtMaxX - 4000.0) < 1e-6)
    }

    @Test("Overlays never join the base series list, so legend/reorder/stacking stay untouched")
    func overlaysDoNotJoinBaseSeries() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .two
        let sweep = makeSweep(id: "a", current: [0, 1, 2, 3], ch1X: [0, 1, 4, 9])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        #expect(manifest.series.count == 1)
        #expect(manifest.seriesOverlays.count == 1)
        #expect(manifest.seriesReorderable == true)
    }

    // MARK: - Zero at I=0: fit once, subtract the same intercept from both curves

    @Test("Zero at I=0 subtracts the fitted intercept from both the measurement points and the fit line")
    func zeroAtOriginSubtractsInterceptFromBothCurves() throws {
        // ch1X (V) chosen so the raw fit has a nonzero intercept: mV = [1000, 3000, 5000],
        // slope 2, intercept 1000.
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [1, 3, 5])

        var withIntercept = IVPlotRenderer()
        withIntercept.fitMode = .one
        withIntercept.zeroAtCurrentOrigin = false
        let withInterceptResult = withIntercept.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifestWithIntercept = try #require(withInterceptResult)
        let baseWithIntercept = try #require(manifestWithIntercept.series.first)
        #expect(baseWithIntercept.y == [1000, 3000, 5000])
        let overlayWithIntercept = try #require(manifestWithIntercept.seriesOverlays.first)
        let yAtZeroWithIntercept = try #require(
            overlayWithIntercept.series.x.firstIndex(of: 0).map { overlayWithIntercept.series.y[$0] }
        )
        #expect(abs(yAtZeroWithIntercept - 1000.0) < 1e-6)

        var zeroed = IVPlotRenderer()
        zeroed.fitMode = .one
        zeroed.zeroAtCurrentOrigin = true
        let zeroedResult = zeroed.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifestZeroed = try #require(zeroedResult)

        // Measurement points themselves are shifted by -intercept, not just the fit line.
        let baseZeroed = try #require(manifestZeroed.series.first)
        #expect(baseZeroed.y.count == 3)
        for (got, want) in zip(baseZeroed.y, [0.0, 2000.0, 4000.0]) {
            #expect(abs(got - want) < 1e-6)
        }

        let overlayZeroed = try #require(manifestZeroed.seriesOverlays.first)
        let yAtZeroZeroed = try #require(
            overlayZeroed.series.x.firstIndex(of: 0).map { overlayZeroed.series.y[$0] }
        )
        #expect(abs(yAtZeroZeroed - 0.0) < 1e-6)
        let yAtMaxZeroed = try #require(
            overlayZeroed.series.x.max().flatMap { max in overlayZeroed.series.x.firstIndex(of: max).map { overlayZeroed.series.y[$0] } }
        )
        #expect(abs(yAtMaxZeroed - 4000.0) < 1e-6)
    }

    // MARK: - Zero at I=0 disabled/cleared when Fit is None

    @MainActor
    @Test("Setting Fit to None clears Zero at I=0")
    func updateFitModeToNoneClearsZeroAtOrigin() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        store.updateFitMode(.two)
        store.zeroAtCurrentOrigin = true

        store.updateFitMode(.none)

        #expect(store.fitMode == .none)
        #expect(store.zeroAtCurrentOrigin == false)
    }

    @MainActor
    @Test("Pack restore normalizes Zero at I=0 to false when the restored fit mode is None")
    func restoreFromPackNormalizesZeroAtOriginForNoneFitMode() {
        let config = IVPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            fitMode: .none,
            zeroAtCurrentOrigin: true
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
        #expect(store.zeroAtCurrentOrigin == false)
    }

    // MARK: - Axis labels

    @Test("X/Y axis labels update per fit mode while staying IV-owned")
    func axisLabelsUpdatePerFitMode() {
        #expect(IVPowerLawFitAdapter.yAxisLabel(mode: .none, component: .x, context: .manifestPlainText) == "V (mV)")

        #expect(IVPowerLawFitAdapter.xAxisLabel(mode: .one, basis: .peak, context: .manifestPlainText) == "I_x^{ω} (mA)")
        #expect(IVPowerLawFitAdapter.xAxisLabel(mode: .two, basis: .peak, context: .manifestPlainText) == "(I_x^{ω})^{2} ((mA)^{2})")
        #expect(IVPowerLawFitAdapter.xAxisLabel(mode: .three, basis: .peak, context: .manifestPlainText) == "(I_x^{ω})^{3} ((mA)^{3})")

        #expect(IVPowerLawFitAdapter.yAxisLabel(mode: .one, component: .x, context: .manifestPlainText) == "V(1ω) (mV)")
        #expect(IVPowerLawFitAdapter.yAxisLabel(mode: .two, component: .y, context: .manifestPlainText) == "V(2ω) (mV)")

        // .none keeps the existing current-basis vocabulary text — unchanged from before this feature.
        #expect(
            IVPowerLawFitAdapter.xAxisLabel(mode: .none, basis: .peak, context: .manifestPlainText)
                == WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .current, currentBasis: .peak)
        )

        // Plot-axis context carries chart markup.
        #expect(IVPowerLawFitAdapter.xAxisLabel(mode: .two, basis: .peak, context: .plotAxis).hasPrefix("math:"))
        #expect(IVPowerLawFitAdapter.yAxisLabel(mode: .two, component: .x, context: .plotAxis).hasPrefix("math:"))
    }

    @Test("Manifest payload axis labels reflect the active fit mode")
    func manifestPayloadUsesFitModeAxisLabels() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .two
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [0, 1, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)

        #expect(manifest.axisMapping.xField == "(I_x^{ω})^{2} ((mA)^{2})")
        #expect(manifest.axisMapping.yField == "V(2ω) (mV)")
    }

    // MARK: - Pack compatibility

    @Test("IVPackConfig decodes fitMode/zeroAtCurrentOrigin defaults from legacy payloads missing those keys")
    func packConfigBackwardCompatibleDefaults() throws {
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
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let config = try JSONDecoder().decode(IVPackConfig.self, from: Data(legacyJSON.utf8))
        #expect(config.fitMode == .none)
        #expect(config.zeroAtCurrentOrigin == false)
    }

    @Test("IVPackConfig round-trips fitMode/zeroAtCurrentOrigin through encode/decode")
    func packConfigRoundTripsFitState() throws {
        var config = IVPackConfig(titleTemplate: "#tab", showPlotGrid: true)
        config.fitMode = .three
        config.zeroAtCurrentOrigin = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(IVPackConfig.self, from: data)
        #expect(decoded.fitMode == .three)
        #expect(decoded.zeroAtCurrentOrigin == true)
    }
}
