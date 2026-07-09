import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.5 Hidden Series Stacking")
struct V565HiddenSeriesStackingTests {

    private func makeThreeOmegaSweep(
        sourceRef: String,
        sampleID: String,
        temperatureK: Double,
        y: [Double]
    ) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: sampleID,
            sourceFilePath: sourceRef,
            hField: [0, 1],
            r1omega: y,
            r3omega: y.map { $0 * 2 },
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
    }

    private func makeXYSweep(
        stem: String,
        temperatureK: Double,
        resistanceXX: [Double],
        resistanceXY: [Double]? = nil
    ) -> XYRotationAngleSweep {
        XYRotationAngleSweep(
            temperatureK: temperatureK,
            stem: stem,
            sourceKind: .lvm,
            angleDeg: [0, 90],
            resistanceXX: resistanceXX,
            resistanceXY: resistanceXY,
            defaultPhiOffset: 0,
            measurementFilePath: "/tmp/\(stem).csv",
            sampleMetadata: ["device": "0deg"]
        )
    }

    private func makeIVSweep(
        id: String,
        temperatureK: Double,
        y: [Double]
    ) -> IVSweep {
        IVSweep(
            stem: id,
            temperatureK: temperatureK,
            fieldT: 0,
            current: [0, 1],
            ch1X: y,
            ch1Y: y.map { $0 * 0.5 },
            ch2X: y.map { $0 * 2 },
            ch2Y: y.map { $0 * 0.25 },
            measurementFilePath: "/tmp/\(id).csv"
        )
    }

    @MainActor
    @Test("3ω stacked field sweeps compact after hidden filtering and keep raw manifest complete")
    func threeOmegaStackCompactsHiddenSeries() throws {
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15

        let bottom = makeThreeOmegaSweep(sourceRef: "/tmp/bottom.csv", sampleID: "bottom", temperatureK: 5, y: [0, 1])
        let middle = makeThreeOmegaSweep(sourceRef: "/tmp/middle.csv", sampleID: "middle", temperatureK: 10, y: [0, 2])
        let top = makeThreeOmegaSweep(sourceRef: "/tmp/top.csv", sampleID: "top", temperatureK: 15, y: [0, 3])
        let sweeps = [bottom, middle, top]

        let raw = try? renderer.makeR1omegaPayload(sweeps: sweeps, device: "0deg")
        #expect(raw?.series.count == 3)
        #expect(raw?.series.first?.metadata["seriesIdentityKey"] == "3w:r1omega-vs-h:sweep:/tmp/bottom.csv")
        let hiddenMiddleKey = raw?.series[1].metadata["seriesIdentityKey"] ?? ""

        let render = ThreeOmegaFieldSweepRenderRoute.renderR1omega(
            renderer: renderer,
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: [hiddenMiddleKey]
        )
        let layout = try #require(render.2)
        let displayPayload = render.3
        let warnings = render.4
        let manifestOrder = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: try #require(raw?.series)).map(\.identityKey)
        guard let display = displayPayload else {
            Issue.record("display payload should not be nil")
            return
        }
        #expect(display.series.count == 2)
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))
        #expect(!warnings.contains(where: { $0.contains("seriesOrder mismatch") }))
        #expect(display.reverseSeriesForLegend == false)
        let displayOrder = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display.series).map(\.identityKey)
        let minima = display.series.map { $0.y.min() ?? .nan }
        #expect(layout.legendRows.map(\.identityKey) == displayOrder)
        #expect(displayOrder == manifestOrder.filter { $0 != hiddenMiddleKey })
        #expect(minima == minima.sorted(by: >))
    }

    @Test("3ω stacked field sweeps ignore hidden filter when every series is hidden")
    func threeOmegaStackIgnoresAllHidden() {
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15

        let sweeps = [
            makeThreeOmegaSweep(sourceRef: "/tmp/bottom.csv", sampleID: "bottom", temperatureK: 5, y: [0, 1]),
            makeThreeOmegaSweep(sourceRef: "/tmp/top.csv", sampleID: "top", temperatureK: 10, y: [0, 2])
        ]

        let raw = try? renderer.makeR1omegaPayload(sweeps: sweeps, device: "0deg")
        #expect(raw?.series.count == 2)
        let hiddenKeys = raw?.series.compactMap { $0.metadata["seriesIdentityKey"] } ?? []

        guard let result = renderer.makeR1omegaDisplayPayload(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: hiddenKeys
        ) else {
            Issue.record("display payload should not be nil")
            return
        }
        let display = result.payload
        let warnings = result.warnings
        #expect(display.series.count == 2)
        #expect(warnings.contains("series visibility ignored: all series were hidden"))
    }

    @Test("XY stacked sweeps compact after hidden filtering")
    func xyStackCompactsHiddenSeries() {
        var renderer = XYRotationPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15

        let sweeps = [
            makeXYSweep(stem: "bottom", temperatureK: 5, resistanceXX: [0, 1]),
            makeXYSweep(stem: "middle", temperatureK: 10, resistanceXX: [0, 2]),
            makeXYSweep(stem: "top", temperatureK: 15, resistanceXX: [0, 3])
        ]

        let raw = renderer.makeRxxVsPhiPayload(sweeps: sweeps, device: "0deg")
        #expect(raw?.series.count == 3)
        #expect(raw?.series.first?.metadata["seriesIdentityKey"] == "XY:rxx-vs-phi:sweep:/tmp/bottom.csv")
        let hiddenMiddleKey = raw?.series[1].metadata["seriesIdentityKey"] ?? ""

        let (_, _, _, displayPayload, warnings) = renderer.renderRxxVsPhi(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: [hiddenMiddleKey]
        )
        #expect(displayPayload?.series.count == 2)
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))

        guard let display = displayPayload else {
            Issue.record("display payload should not be nil")
            return
        }
        let displayOrder = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display.series).map(\.identityKey)
        let minima = display.series.map { $0.y.min() ?? .nan }
        #expect(displayOrder == [raw?.series[0].metadata["seriesIdentityKey"] ?? "", raw?.series[2].metadata["seriesIdentityKey"] ?? ""])
        #expect(minima == minima.sorted(by: >))
    }

    @Test("IV stacked sweeps compact after hidden filtering")
    func ivStackCompactsHiddenSeries() {
        var renderer = IVPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15

        let sweeps = [
            makeIVSweep(id: "bottom", temperatureK: 5, y: [0, 1]),
            makeIVSweep(id: "middle", temperatureK: 10, y: [0, 2]),
            makeIVSweep(id: "top", temperatureK: 15, y: [0, 3])
        ]

        let raw = renderer.makeFirstHarmonicPayload(sweeps: sweeps, device: "0deg")
        #expect(raw?.series.count == 3)
        #expect(raw?.series.first?.metadata["seriesIdentityKey"] == "IV:first-harmonic-vs-current:sweep:/tmp/bottom.csv")
        let hiddenMiddleKey = raw?.series[1].metadata["seriesIdentityKey"] ?? ""

        let (_, _, displayPayload, warnings) = renderer.renderFirstHarmonicVsCurrent(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: [hiddenMiddleKey]
        )
        guard let display = displayPayload else {
            Issue.record("display payload should not be nil")
            return
        }
        #expect(display.series.count == 2)
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))
        let displayOrder = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: display.series).map(\.identityKey)
        let minima = display.series.map { $0.y.min() ?? .nan }
        #expect(displayOrder == [raw?.series[0].metadata["seriesIdentityKey"] ?? "", raw?.series[2].metadata["seriesIdentityKey"] ?? ""])
        #expect(minima == minima.sorted(by: >))
    }
}
