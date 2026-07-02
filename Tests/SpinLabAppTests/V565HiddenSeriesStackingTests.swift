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

    @Test("3ω stacked field sweeps compact after hidden filtering and keep raw manifest complete")
    func threeOmegaStackCompactsHiddenSeries() {
        var renderer = ThreeOmegaPlotRenderer()
        renderer.stackOffsetMultiplier = 1.2
        renderer.minGapFraction = 0.15

        let bottom = makeThreeOmegaSweep(sourceRef: "/tmp/bottom.csv", sampleID: "bottom", temperatureK: 5, y: [0, 1])
        let middle = makeThreeOmegaSweep(sourceRef: "/tmp/middle.csv", sampleID: "middle", temperatureK: 10, y: [0, 2])
        let top = makeThreeOmegaSweep(sourceRef: "/tmp/top.csv", sampleID: "top", temperatureK: 15, y: [0, 3])
        let sweeps = [bottom, middle, top]

        let raw = try? renderer.makeR1omegaPayload(sweeps: sweeps, device: "0deg")
        #expect(raw?.series.count == 3)

        let (_, _, displayPayload, warnings) = renderer.renderR1omega(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: ["/tmp/middle.csv"]
        )
        guard let display = displayPayload else {
            Issue.record("display payload should not be nil")
            return
        }
        #expect(display.series.count == 2)
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))

        let visibleOffsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: [[0, 1], [0, 3]],
            multiplier: 1.2,
            minGapFraction: 0.15
        )
        let min0 = display.series[0].y.min() ?? .nan
        let min1 = display.series[1].y.min() ?? .nan
        #expect(abs(min0 - visibleOffsets[0]) < 1e-9)
        #expect(abs(min1 - visibleOffsets[1]) < 1e-9)
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

        let (_, _, displayPayload, warnings) = renderer.renderR1omega(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: ["/tmp/bottom.csv", "/tmp/top.csv"]
        )
        guard let display = displayPayload else {
            Issue.record("display payload should not be nil")
            return
        }
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

        let (_, _, displayPayload, warnings) = renderer.renderRxxVsPhi(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: ["/tmp/middle.csv"]
        )
        #expect(displayPayload?.series.count == 2)
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))

        let visibleOffsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: [[0, 1], [0, 3]],
            multiplier: 1.2,
            minGapFraction: 0.15
        )
        guard let display = displayPayload else {
            Issue.record("display payload should not be nil")
            return
        }
        let min0 = display.series[0].y.min() ?? .nan
        let min1 = display.series[1].y.min() ?? .nan
        #expect(abs(min0 - visibleOffsets[0]) < 1e-9)
        #expect(abs(min1 - visibleOffsets[1]) < 1e-9)
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

        let (_, _, displayPayload, warnings) = renderer.renderFirstHarmonicVsCurrent(
            sweeps: sweeps,
            device: "0deg",
            hiddenSeriesKeys: ["/tmp/middle.csv"]
        )
        guard let display = displayPayload else {
            Issue.record("display payload should not be nil")
            return
        }
        #expect(display.series.count == 2)
        #expect(!warnings.contains("series visibility ignored: all series were hidden"))

        let visibleOffsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: [[0, 1], [0, 3]],
            multiplier: 1.2,
            minGapFraction: 0.15
        )
        let min0 = display.series[0].y.min() ?? .nan
        let min1 = display.series[1].y.min() ?? .nan
        #expect(abs(min0 - visibleOffsets[0]) < 1e-9)
        #expect(abs(min1 - visibleOffsets[1]) < 1e-9)
    }
}
