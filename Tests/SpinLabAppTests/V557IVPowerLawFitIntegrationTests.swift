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

    @Test("Fit mode .none emits no overlays")
    func fitDisabledEmitsNoOverlays() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .none
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [0, 2, 4])
        let result = renderer.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifest = try #require(result)
        #expect(manifest.seriesOverlays.isEmpty)
    }

    @Test("Fit mode .one projects a linear overlay anchored to its parent series, in matching V units")
    func linearFitProjectsOverlayInBaseUnits() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        // current_A -> mA via peak scaleFactor (x1000): [0, 1000, 2000]
        // ch1X (V) -> mV (x1000): [0, 2000, 4000] => slope 2 mV/mA, intercept 0
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

        // Overlay is expressed in the same V-scale as the base series (not left in mV).
        let minX = try #require(overlay.series.x.min())
        let maxX = try #require(overlay.series.x.max())
        #expect(abs(minX - 0) < 1e-6)
        #expect(abs(maxX - 2000) < 1e-6)
        let yAtMinX = overlay.series.y[overlay.series.x.firstIndex(of: minX)!]
        let yAtMaxX = overlay.series.y[overlay.series.x.firstIndex(of: maxX)!]
        #expect(abs(yAtMinX - 0) < 1e-6)
        #expect(abs(yAtMaxX - 4.0) < 1e-6)
    }

    @Test("Zero at I=0 drops the fit intercept so the overlay passes through zero at I=0")
    func zeroAtOriginDropsIntercept() throws {
        // ch1X (V) chosen so the raw fit has a nonzero intercept: mV = [1000, 3000, 5000]
        let sweep = makeSweep(id: "a", current: [0, 1, 2], ch1X: [1, 3, 5])

        var withIntercept = IVPlotRenderer()
        withIntercept.fitMode = .one
        withIntercept.zeroAtCurrentOrigin = false
        let withInterceptResult = withIntercept.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifestWithIntercept = try #require(withInterceptResult)
        let overlayWithIntercept = try #require(manifestWithIntercept.seriesOverlays.first)
        let yAtZeroWithIntercept = try #require(
            overlayWithIntercept.series.x.firstIndex(of: 0).map { overlayWithIntercept.series.y[$0] }
        )
        #expect(abs(yAtZeroWithIntercept - 1.0) < 1e-6)

        var zeroed = IVPlotRenderer()
        zeroed.fitMode = .one
        zeroed.zeroAtCurrentOrigin = true
        let zeroedResult = zeroed.makeFirstHarmonicPayload(sweeps: [sweep], device: "d")
        let manifestZeroed = try #require(zeroedResult)
        let overlayZeroed = try #require(manifestZeroed.seriesOverlays.first)
        let yAtZeroZeroed = try #require(
            overlayZeroed.series.x.firstIndex(of: 0).map { overlayZeroed.series.y[$0] }
        )
        #expect(abs(yAtZeroZeroed - 0.0) < 1e-6)
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
