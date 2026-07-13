import Foundation
import Testing
@testable import SpinLabApp

@Suite("IV Angular Fit Integration")
struct IVAngularFitIntegrationTests {

    private func makeSweep(
        id: String,
        angleDeg: Double,
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
            sampleMetadata: ["device": "\(angleDeg)deg"]
        )
    }

    /// Slopes (mV/mA) sampled from y(Ψ) = 5 + 3cos(Ψ) - 2sin(Ψ), Ψ in degrees,
    /// so the Angular fit has a known closed-form answer to check against.
    private func makeHarmonicSweeps() -> [IVSweep] {
        let c0 = 5.0, a = 3.0, b = -2.0
        let angles: [Double] = [0, 60, 120, 180, 240, 300]
        return angles.map { angle in
            let psi = angle * .pi / 180.0
            let slope = c0 + a * cos(psi) + b * sin(psi)
            // mV/mA slope is invariant to the A→mA/V→mV *1000 scaling on both sides, so
            // ch1X (V) = slope * current (A) reproduces the target slope exactly.
            return makeSweep(id: "s\(Int(angle))", angleDeg: angle, current: [0, 1, 2], ch1X: [0, slope, slope * 2])
        }
    }

    // MARK: - None: byte-for-byte unchanged scatter-only payload

    @Test("Angular fit None emits no overlay, leaving the scatter payload byte-for-byte unchanged")
    func angularFitNoneLeavesPayloadUnchanged() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        renderer.angularPlotEnabled = true
        renderer.angularFitMode = .none
        let sweeps = makeHarmonicSweeps()
        let payloads = renderer.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let result = try #require(payloads)

        #expect(result.manifestPayload.series.count == 1)
        #expect(result.manifestPayload.seriesOverlays.isEmpty)
        #expect(result.displayPayload.seriesOverlays.isEmpty)
        let series = try #require(result.manifestPayload.series.first)
        #expect(series.renderMode == .scatter)
        #expect(series.x == sweeps.map(\.angleDeg).compactMap { $0 }.sorted())
    }

    // MARK: - Harmonic: overlay appears, scatter series untouched

    @Test("Angular fit Harmonic appends a fit-line overlay without altering the scatter series")
    func angularFitHarmonicAppendsOverlay() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        renderer.angularPlotEnabled = true
        renderer.angularFitMode = .harmonic
        renderer.angularFitFold = 1
        let sweeps = makeHarmonicSweeps()

        var baseline = IVPlotRenderer()
        baseline.fitMode = .one
        baseline.angularPlotEnabled = true
        baseline.angularFitMode = .none
        let baselineRaw = baseline.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let baselinePayloads = try #require(baselineRaw)

        let raw = renderer.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let payloads = try #require(raw)

        // Scatter series, axis labels, and legend label are identical to the None case.
        #expect(payloads.manifestPayload.series == baselinePayloads.manifestPayload.series)
        #expect(payloads.manifestPayload.axisMapping.xField == baselinePayloads.manifestPayload.axisMapping.xField)
        #expect(payloads.manifestPayload.axisMapping.yField == baselinePayloads.manifestPayload.axisMapping.yField)

        #expect(payloads.manifestPayload.seriesOverlays.count == 1)
        let overlay = try #require(payloads.manifestPayload.seriesOverlays.first)
        let parentKey = try #require(
            WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payloads.manifestPayload.series).first?.identityKey
        )
        #expect(overlay.parentSeriesIdentityKey == parentKey)
        #expect(overlay.series.renderModeLocked == true)
        #expect(overlay.series.renderMode == .line)
        #expect(overlay.series.x.count == overlay.series.y.count)
        #expect(overlay.series.x.count > 2)
    }

    @Test("Angular fit overlay recovers the known harmonic coefficients through the full IV pipeline")
    func angularFitOverlayRecoversKnownCoefficients() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        renderer.angularPlotEnabled = true
        renderer.angularFitMode = .harmonic
        renderer.angularFitFold = 1
        let sweeps = makeHarmonicSweeps()
        let raw = renderer.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let payloads = try #require(raw)
        let overlay = try #require(payloads.manifestPayload.seriesOverlays.first)

        // y(0) = c0 + a = 5 + 3 = 8; y(180) = c0 - a = 2.
        let yAt0 = try #require(overlay.series.x.firstIndex(where: { abs($0 - 0) < 1e-6 }).map { overlay.series.y[$0] })
        #expect(abs(yAt0 - 8.0) < 1e-3)
    }

    // MARK: - Fold selection changes the fitted overlay

    @Test("Fold selection changes which harmonic the overlay fits against")
    func angularFitFoldSelectsHarmonic() throws {
        // Sweeps encode a pure fold-2 signal sampled evenly over a full 360° period, where
        // cos(Ψ)/sin(Ψ) are orthogonal to cos(2Ψ): a fold-1 fit collapses to a near-flat
        // (c0-only) line, while a fold-2 fit recovers the full oscillation.
        let c0 = 4.0, a2 = 6.0
        let angles: [Double] = [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330]
        let sweeps = angles.map { angle -> IVSweep in
            let psi = angle * .pi / 180.0
            let slope = c0 + a2 * cos(2 * psi)
            return makeSweep(id: "s\(Int(angle))", angleDeg: angle, current: [0, 1, 2], ch1X: [0, slope, slope * 2])
        }

        var foldOne = IVPlotRenderer()
        foldOne.fitMode = .one
        foldOne.angularPlotEnabled = true
        foldOne.angularFitMode = .harmonic
        foldOne.angularFitFold = 1
        let foldOneRaw = foldOne.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let foldOnePayloads = try #require(foldOneRaw)
        let foldOneOverlay = try #require(foldOnePayloads.manifestPayload.seriesOverlays.first)
        let foldOneRange = (foldOneOverlay.series.y.max() ?? 0) - (foldOneOverlay.series.y.min() ?? 0)

        var foldTwo = IVPlotRenderer()
        foldTwo.fitMode = .one
        foldTwo.angularPlotEnabled = true
        foldTwo.angularFitMode = .harmonic
        foldTwo.angularFitFold = 2
        let foldTwoRaw = foldTwo.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let foldTwoPayloads = try #require(foldTwoRaw)
        let foldTwoOverlay = try #require(foldTwoPayloads.manifestPayload.seriesOverlays.first)
        let foldTwoRange = (foldTwoOverlay.series.y.max() ?? 0) - (foldTwoOverlay.series.y.min() ?? 0)

        // Fold 1 sees only the DC-ish projection of a pure cos(2Ψ) signal (near-flat fit);
        // Fold 2 recovers the full 2·a2 peak-to-peak swing.
        #expect(foldTwoRange > foldOneRange)
        #expect(abs(foldTwoRange - 2 * a2) < 1e-2)
    }

    // MARK: - Line control reaches the harmonic fit overlay's rendered width

    @Test("Changing the standard Line control changes the harmonic fit overlay's rendered width")
    func lineControlChangesOverlayWidth() throws {
        var renderer = IVPlotRenderer()
        renderer.fitMode = .one
        renderer.angularPlotEnabled = true
        renderer.angularFitMode = .harmonic
        renderer.angularFitFold = 1
        let sweeps = makeHarmonicSweeps()
        let raw = renderer.makeFirstHarmonicPayloads(sweeps: sweeps, device: "d")
        let payloads = try #require(raw)

        let defaultOutput = try WorkbenchRenderPipeline.render(
            WorkbenchRenderPipeline.Input(payload: payloads.manifestPayload)
        )
        let defaultOverlay = try #require(defaultOutput.displayPayload.seriesOverlays.first)

        let widenedOutput = try WorkbenchRenderPipeline.render(
            WorkbenchRenderPipeline.Input(
                payload: payloads.manifestPayload,
                globalPlotDefaults: ["lineWidth": "4.5"]
            )
        )
        let widenedOverlay = try #require(widenedOutput.displayPayload.seriesOverlays.first)

        #expect(widenedOverlay.series.lineWidth == 4.5)
        #expect(widenedOverlay.series.lineWidth != defaultOverlay.series.lineWidth)
    }

    // MARK: - Pack round-trip

    @Test("IVPackConfig round-trips angularFitMode/angularFitFold through encode/decode")
    func packConfigRoundTripsAngularFitState() throws {
        var config = IVPackConfig(titleTemplate: "#tab", showPlotGrid: true)
        config.fitMode = .one
        config.angularPlotEnabled = true
        config.angularFitMode = .harmonic
        config.angularFitFold = 3
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(IVPackConfig.self, from: data)
        #expect(decoded.angularFitMode == .harmonic)
        #expect(decoded.angularFitFold == 3)
    }

    @Test("IVPackConfig decodes angularFitMode/angularFitFold defaults from legacy payloads missing those keys")
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
          "fitMode": 1,
          "zeroAtCurrentOrigin": false,
          "angularPlotEnabled": true,
          "tabStates": {},
          "cachedSearchResults": [],
          "selectedSearchResultIDs": [],
          "searchQueryText": ""
        }
        """
        let config = try JSONDecoder().decode(IVPackConfig.self, from: Data(legacyJSON.utf8))
        #expect(config.angularFitMode == .none)
        #expect(config.angularFitFold == 1)
    }

    // MARK: - Store: Fold persists while fit is None; fit resets with Angular Plot fit mode

    @MainActor
    @Test("Fold persists in the store even when Angular fit mode is None")
    func angularFitFoldPersistsWhileModeIsNone() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        store.angularFitFold = 3
        store.angularFitMode = .none

        #expect(store.angularFitFold == 3)
        #expect(store.angularFitMode == .none)
    }

    @MainActor
    @Test("Pack restore normalizes angularFitMode to None (but keeps Fold) when the restored fit mode is None")
    func restoreFromPackNormalizesAngularFitModeForNoneFitMode() {
        let config = IVPackConfig(
            titleTemplate: "#tab",
            showPlotGrid: true,
            fitMode: .none,
            angularPlotEnabled: true,
            angularFitMode: .harmonic,
            angularFitFold: 4
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

        #expect(store.angularFitMode == .none)
        #expect(store.angularFitFold == 4)
    }
}
