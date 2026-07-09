import Testing
@testable import SpinLabApp

/// v5.5.6 — 3ω Temperature Dependence special display convention.
///
/// Implements the approved target from docs/architecture/workbench/PLOT_DISPLAY_SPEC.md §4
/// (approved 2026-07-03): left axis `E_AHE^{3ω} / E_xx^3 × 10² (μm² V⁻²)` (SI ×1e14), right axis
/// `σxx × 10³ (S cm⁻¹)` (SI ×1e-5). Scope is this plot only — Scaling Law and the magnetic-field
/// (H/Hc) display policy must be provably unaffected.
@Suite("v5.5.6 - Temperature Dependence display convention")
struct V556TemperatureDependenceDisplayConventionTests {

    private func makeResult() -> ThreeOmegaScalingResult {
        ThreeOmegaScalingResult(
            points: [
                ThreeOmegaScalingPoint(temperatureK: 10, sigma2xx: 4.0, scalingY: 3.0),   // sigmaXX=2, leftY_SI=6
                ThreeOmegaScalingPoint(temperatureK: 20, sigma2xx: 9.0, scalingY: 1.0)     // sigmaXX=3, leftY_SI=9
            ],
            segments: []
        )
    }

    @Test("x label remains Temperature (K)")
    func xLabelUnchanged() {
        let renderer = ThreeOmegaPlotRenderer()
        let payload = renderer.makeTemperatureDependencePayload(result: makeResult())
        #expect(payload?.xLabel == "Temperature (K)")
    }

    @Test("left y label matches documented target")
    func leftYLabelMatchesTarget() {
        let renderer = ThreeOmegaPlotRenderer()
        let payload = renderer.makeTemperatureDependencePayload(result: makeResult())
        #expect(payload?.leftYLabel == #"math:E_{AHE}^{3ω} / E_{xx}^{3} × 10^{2} (μm^{2} V^{-2})"#)
    }

    @Test("right y label matches documented target")
    func rightYLabelMatchesTarget() {
        let renderer = ThreeOmegaPlotRenderer()
        let payload = renderer.makeTemperatureDependencePayload(result: makeResult())
        #expect(payload?.rightYLabel == #"math:σ_{xx} × 10^{3} (S cm^{-1})"#)
    }

    @Test("left y numeric transform is SI × 1e14")
    func leftYTransformIsCorrect() throws {
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeTemperatureDependencePayload(result: makeResult()))
        let leftY = try #require(payload.leftSeries.first?.y)
        // point 1: scalingY=3, sigmaXX=sqrt(4)=2 → SI leftY=3*2=6 → displayed 6e14
        // point 2: scalingY=1, sigmaXX=sqrt(9)=3 → SI leftY=1*3=3 → displayed 3e14
        #expect(leftY.count == 2)
        #expect(abs(leftY[0] - 6e14) < 1e2)
        #expect(abs(leftY[1] - 3e14) < 1e2)
    }

    @Test("right y numeric transform is SI × 1e-5")
    func rightYTransformIsCorrect() throws {
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeTemperatureDependencePayload(result: makeResult()))
        let rightY = try #require(payload.rightSeries.first?.y)
        // point 1: sigmaXX=2 → displayed 2e-5; point 2: sigmaXX=3 → displayed 3e-5
        #expect(rightY.count == 2)
        #expect(abs(rightY[0] - 2e-5) < 1e-12)
        #expect(abs(rightY[1] - 3e-5) < 1e-12)
    }

    @Test("ThreeOmegaPlotRenderer display-scale constants match the documented factors")
    func displayScaleConstantsMatchDocumentedFactors() {
        #expect(ThreeOmegaPlotRenderer.temperatureDependenceLeftYDisplayScale == 1e14)
        #expect(ThreeOmegaPlotRenderer.temperatureDependenceRightYDisplayScale == 1e-5)
    }

    // MARK: - Scaling Law must be provably unaffected

    @Test("Scaling Law labels are unchanged")
    func scalingLawLabelsUnchanged() {
        #expect(ThreeOmegaPlotRenderer.scalingXAxisLabel == #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#)
        #expect(ThreeOmegaPlotRenderer.scalingYAxisLabel == #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#)
    }

    @Test("Scaling Law numeric conversion is unchanged (×1e-11 / ×1e20)")
    func scalingLawValuesUnchanged() throws {
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeScalingPayload(result: makeResult()))
        let series = try #require(payload.series.first { $0.label == "Experiment Data" })
        // point 1: sigma2xx=4 → x=4e-11; scalingY=3 → y=3e20
        // point 2: sigma2xx=9 → x=9e-11; scalingY=1 → y=1e20
        #expect(series.x == [4e-11, 9e-11])
        #expect(series.y == [3e20, 1e20])
    }

    // MARK: - Magnetic field (H/Hc) must be provably unaffected

    @Test("Magnetic field H/Hc labels are unchanged by this migration")
    func magneticFieldLabelsUnchanged() {
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(
            for: .externalMagneticField, context: .plotAxis, unit: .tesla
        ) == "μ₀H (T)")
        #expect(ThreeOmegaPlotRenderer.hcAxisLabel == "μ₀Hc (mT)")
    }

    // MARK: - Old-pack default path: new labels apply unless an explicit override is present

    @Test("renderTemperatureDependence uses new default labels when no override is set")
    func defaultLabelsApplyWithoutOverride() {
        var renderer = ThreeOmegaPlotRenderer()
        let (_, _, payload, _) = renderer.renderTemperatureDependence(result: makeResult())
        #expect(payload?.leftYLabel == #"math:E_{AHE}^{3ω} / E_{xx}^{3} × 10^{2} (μm^{2} V^{-2})"#)
    }

    @Test("renderTemperatureDependence honors an explicit yLabelOverride over the new default")
    func explicitOverrideStillWins() {
        var renderer = ThreeOmegaPlotRenderer()
        renderer.yLabelOverride = "Custom Left Label"
        let (_, _, payload, _) = renderer.renderTemperatureDependence(result: makeResult())
        #expect(payload?.leftYLabel == "Custom Left Label")
    }
}
