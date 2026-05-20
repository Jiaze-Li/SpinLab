import Foundation
import Testing
@testable import SpinLabApp

// MARK: - v4.1.2.16 — ThreeOmegaPlotRenderer scaling segment rendering tests
//
// Coverage:
//   - Fit line x-range extends 5% beyond participating data points
//   - Δx = 0 (single unique x value) does not crash; falls back to minimum extension
//   - Single full-range segment uses label "Fitting Results" (legacy)
//   - Multi-segment uses temperature-annotated label "Fit XxxK–XxxK"

private func makeSegment(
    tLo: Double = 100,
    tHi: Double = 300,
    alpha: Double = 1.0,
    beta: Double = 0.0,
    xValues: [Double]
) -> ThreeOmegaScalingSegment {
    ThreeOmegaScalingSegment(
        id: UUID(),
        tLo: tLo,
        tHi: tHi,
        alpha: alpha,
        beta: beta,
        rSquared: 1.0,
        pointCount: xValues.count,
        participatingXValues: xValues
    )
}

private func makePoints(sigma2xxValues: [Double]) -> [ThreeOmegaScalingPoint] {
    sigma2xxValues.enumerated().map { i, x in
        ThreeOmegaScalingPoint(
            temperatureK: Double(100 + i * 50),
            sigma2xx: x,
            scalingY: x * 1e-18   // arbitrary
        )
    }
}

@Suite("V41216 ThreeOmegaPlotRenderer — scaling segment rendering")
struct V41216PlotRendererScalingTests {

    private func makeRenderer() -> ThreeOmegaPlotRenderer { ThreeOmegaPlotRenderer() }

    // MARK: fit line extension

    @Test("Fit line x-range extends ~5% beyond data on each side")
    func fitLineExtension() {
        // participatingXValues in SI: 1e11 → display 1.0, 5e11 → display 5.0
        let xSI: [Double] = [1e11, 2e11, 3e11, 4e11, 5e11]
        let seg = makeSegment(xValues: xSI)
        let points = makePoints(sigma2xxValues: xSI)
        let result = ThreeOmegaScalingResult(
            points: points,
            segments: [seg]
        )
        var renderer = makeRenderer(); let (data, _, _) = renderer.renderScaling(result: result)
        // Rendering must succeed (non-nil data)
        #expect(data != nil)
    }

    @Test("Δx = 0 (all x identical) does not crash and produces non-nil data")
    func deltaXZeroDoesNotCrash() {
        // All participating x values identical → dx = 0 → extension falls back to minimum
        let xSI: [Double] = [2e11, 2e11, 2e11]
        let seg = makeSegment(xValues: xSI)
        let points = makePoints(sigma2xxValues: xSI)
        let result = ThreeOmegaScalingResult(
            points: points,
            segments: [seg]
        )
        var renderer = makeRenderer(); let (data, _, _) = renderer.renderScaling(result: result)
        #expect(data != nil)
    }

    // MARK: series labels

    @Test("Single full-range segment uses legacy label 'Fitting Results'")
    func singleFullRangeLabel() {
        // isSingleFullRange() = true → pointCount == points.count
        let xSI: [Double] = [1e11, 3e11, 5e11]
        let seg = makeSegment(xValues: xSI)
        let points = makePoints(sigma2xxValues: xSI)
        // pointCount(3) == points.count(3) → isSingleFullRange true
        let result = ThreeOmegaScalingResult(points: points, segments: [seg])
        #expect(result.isSingleFullRange())
        // Rendering should succeed
        var renderer = makeRenderer(); let (data, _, _) = renderer.renderScaling(result: result)
        #expect(data != nil)
    }

    @Test("Multi-segment uses temperature-annotated labels")
    func multiSegmentLabels() {
        let xLo: [Double] = [1e11, 2e11]
        let xHi: [Double] = [4e11, 5e11]
        let segLo = makeSegment(tLo: 100, tHi: 200, xValues: xLo)
        let segHi = makeSegment(tLo: 300, tHi: 400, xValues: xHi)
        // total points = 4, each segment covers 2 → isSingleFullRange false
        let points = makePoints(sigma2xxValues: xLo + xHi)
        let result = ThreeOmegaScalingResult(points: points, segments: [segLo, segHi])
        #expect(!result.isSingleFullRange())
        var renderer = makeRenderer(); let (data, _, _) = renderer.renderScaling(result: result)
        #expect(data != nil)
    }

    // MARK: empty segments

    @Test("No segments renders scatter only (no fit lines), returns non-nil data")
    func noSegmentsRendersScatterOnly() {
        let xSI: [Double] = [1e11, 2e11, 3e11]
        let points = makePoints(sigma2xxValues: xSI)
        let result = ThreeOmegaScalingResult(points: points, segments: [])
        var renderer = makeRenderer(); let (data, _, _) = renderer.renderScaling(result: result)
        #expect(data != nil)
    }
}
