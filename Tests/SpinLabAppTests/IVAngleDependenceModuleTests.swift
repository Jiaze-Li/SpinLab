import Foundation
import Testing
@testable import SpinLabApp

@Suite("IVAngleDependence Module")
struct IVAngleDependenceModuleTests {

    /// Free-intercept fit y = a*x + b against a straight-line sweep: current [0,1,2] mA,
    /// voltage = slope*mA + intercept (mV). Slope is a_n for that sweep.
    private func makeSweep(angleDeg: Double?, slope: Double, intercept: Double, label: String = "s") -> IVAngleDependenceSweepInput {
        let currentMA: [Double] = [0, 1, 2]
        let voltageMV = currentMA.map { slope * $0 + intercept }
        return IVAngleDependenceSweepInput(angleDeg: angleDeg, currentMA: currentMA, voltageMV: voltageMV, label: label)
    }

    @Test("Fit mode .none returns an empty, insufficient result with a diagnostic")
    func fitModeNoneIsDisabled() {
        let sweeps = [makeSweep(angleDeg: 0, slope: 2, intercept: 1), makeSweep(angleDeg: 90, slope: 3, intercept: 1)]
        let result = IVAngleDependenceUseCase().execute(sweeps: sweeps, fitMode: .none)

        #expect(result.points.isEmpty)
        #expect(result.isSufficient == false)
        #expect(result.warnings.contains(where: { $0.contains("Fit mode") }))
    }

    @Test("Each sweep's free-intercept slope becomes its a_n(Ψ) point, sorted by angle")
    func slopeExtractionAndSorting() {
        let sweeps = [
            makeSweep(angleDeg: 90, slope: 5, intercept: 100, label: "b"),
            makeSweep(angleDeg: 0, slope: 2, intercept: 1000, label: "a"),
            makeSweep(angleDeg: 45, slope: 3.5, intercept: -50, label: "c")
        ]
        let result = IVAngleDependenceUseCase().execute(sweeps: sweeps, fitMode: .one)

        #expect(result.points.map(\.angleDeg) == [0, 45, 90])
        #expect(result.points.map(\.label) == ["a", "c", "b"])
        for (point, expectedSlope) in zip(result.points, [2.0, 3.5, 5.0]) {
            #expect(abs(point.slope - expectedSlope) < 1e-9)
        }
        #expect(result.isSufficient)
        #expect(result.distinctAngleCount == 3)
    }

    @Test("Sweeps with no resolvable angle are excluded, not crashed on")
    func unresolvedAngleExcluded() {
        let sweeps = [
            makeSweep(angleDeg: 0, slope: 2, intercept: 0),
            makeSweep(angleDeg: nil, slope: 9, intercept: 0),
            makeSweep(angleDeg: 90, slope: 4, intercept: 0)
        ]
        let result = IVAngleDependenceUseCase().execute(sweeps: sweeps, fitMode: .one)

        #expect(result.points.count == 2)
        #expect(result.points.map(\.angleDeg) == [0, 90])
        #expect(result.warnings.contains(where: { $0.contains("no resolvable angle") }))
    }

    @Test("Duplicate angles are never merged — every valid sweep keeps its own point")
    func duplicateAnglesAreNotMerged() {
        let sweeps = [
            makeSweep(angleDeg: 45, slope: 2, intercept: 0, label: "first"),
            makeSweep(angleDeg: 45, slope: 8, intercept: 0, label: "second"),
            makeSweep(angleDeg: 90, slope: 4, intercept: 0, label: "third")
        ]
        let result = IVAngleDependenceUseCase().execute(sweeps: sweeps, fitMode: .one)

        #expect(result.points.count == 3)
        #expect(result.points.filter { $0.angleDeg == 45 }.count == 2)
        #expect(Set(result.points.filter { $0.angleDeg == 45 }.map(\.slope)) == [2.0, 8.0])
        #expect(result.distinctAngleCount == 2)
        #expect(result.warnings.contains(where: { $0.contains("Multiple sweeps share the same angle") }))
    }

    @Test("Fewer than 2 distinct angles is reported as insufficient")
    func insufficientDistinctAngles() {
        let sweeps = [
            makeSweep(angleDeg: 45, slope: 2, intercept: 0),
            makeSweep(angleDeg: 45, slope: 8, intercept: 0)
        ]
        let result = IVAngleDependenceUseCase().execute(sweeps: sweeps, fitMode: .one)

        #expect(result.distinctAngleCount == 1)
        #expect(result.isSufficient == false)
        #expect(result.warnings.contains(where: { $0.contains("needs at least") }))
        // Points are still plotted — sufficiency only gates the *toggle*, not the payload.
        #expect(result.points.count == 2)
    }

    @Test("countDistinctValidAngles is a cheap gating helper independent of fitting")
    func countDistinctValidAnglesHelper() {
        #expect(IVAngleDependenceUseCase.countDistinctValidAngles([0, 45, 90]) == 3)
        #expect(IVAngleDependenceUseCase.countDistinctValidAngles([0, 0, nil, 90]) == 2)
        #expect(IVAngleDependenceUseCase.countDistinctValidAngles([nil, nil]) == 0)
        #expect(IVAngleDependenceUseCase.minimumDistinctAngles == 2)
    }
}

@Suite("IVAngleDependence Projection legend labels")
struct IVAngleDependenceProjectionLegendLabelTests {

    @Test("1ω legend label reuses the yAxisLabel fraction, math-prefixed for the canvas, plain for manifest")
    func oneOmegaLegendLabel() {
        let math = IVAngleDependenceProjection.legendLabel(mode: .one, component: .x, context: .plotAxis)
        let plain = IVAngleDependenceProjection.legendLabel(mode: .one, component: .x, context: .manifestPlainText)

        #expect(math == "math:V_{x}^{ω}/I_x^{ω}")
        #expect(plain == "V(1ω)/I^1")
        #expect(MathMarkupRenderer.isMathLabel(math))
        #expect(!MathMarkupRenderer.isMathLabel(plain))
    }

    @Test("2ω legend label reuses the yAxisLabel fraction")
    func twoOmegaLegendLabel() {
        let math = IVAngleDependenceProjection.legendLabel(mode: .two, component: .y, context: .plotAxis)
        let plain = IVAngleDependenceProjection.legendLabel(mode: .two, component: .y, context: .manifestPlainText)

        #expect(math == "math:V_{y}^{2ω}/(I_x^{ω})^{2}")
        #expect(plain == "V(2ω)/I^2")
    }

    @Test("3ω legend label reuses the yAxisLabel fraction")
    func threeOmegaLegendLabel() {
        let math = IVAngleDependenceProjection.legendLabel(mode: .three, component: .x, context: .plotAxis)
        let plain = IVAngleDependenceProjection.legendLabel(mode: .three, component: .x, context: .manifestPlainText)

        #expect(math == "math:V_{x}^{3ω}/(I_x^{ω})^{3}")
        #expect(plain == "V(3ω)/I^3")
    }

    @Test("legendLabel numerator/denominator never drifts from yAxisLabel's fraction")
    func legendLabelMatchesYAxisLabelFraction() {
        for mode: PowerLawFitMode in [.one, .two, .three] {
            for component: IVSignalComponent in [.x, .y] {
                let legend = IVAngleDependenceProjection.legendLabel(mode: mode, component: component, context: .plotAxis)
                let yAxis = IVAngleDependenceProjection.yAxisLabel(mode: mode, component: component, context: .plotAxis)
                let fraction = String(legend.dropFirst(MathMarkupRenderer.mathPrefix.count))
                #expect(yAxis.hasPrefix("math:\(fraction) ("))
            }
        }
    }

    @Test("Fallback legend label (no fit order) is a plain, non-math name for manifest and math-prefixed for canvas")
    func fallbackLegendLabelWhenModeIsNone() {
        let math = IVAngleDependenceProjection.legendLabel(mode: .none, component: .x, context: .plotAxis)
        let plain = IVAngleDependenceProjection.legendLabel(mode: .none, component: .x, context: .manifestPlainText)

        #expect(math == "math:a_{n}(Ψ)")
        #expect(plain == "a_n(Ψ)")
        #expect(MathMarkupRenderer.isMathLabel(math))
        #expect(!MathMarkupRenderer.isMathLabel(plain))
    }
}
