import Foundation
import Testing
@testable import SpinLabApp

@Suite("ThreeOmega scaling-law math labels")
struct ThreeOmegaScalingMathLabelTests {

    private let expectedScalingXLabel = "σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"
    private let expectedScalingYLabel = "E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"

    @Test("Scaling-law X label uses math prefix")
    func scalingLawXLabelUsesMathPrefix() {
        let fullLabel = ThreeOmegaPlotRenderer.scalingXAxisLabel
        #expect(MathMarkupRenderer.isMathLabel(fullLabel))
        #expect(MathMarkupRenderer.extractMathMarkup(fullLabel) == expectedScalingXLabel)
    }

    @Test("Scaling-law Y label uses math prefix")
    func scalingLawYLabelUsesMathPrefix() {
        let fullLabel = ThreeOmegaPlotRenderer.scalingYAxisLabel
        #expect(MathMarkupRenderer.isMathLabel(fullLabel))
        #expect(MathMarkupRenderer.extractMathMarkup(fullLabel) == expectedScalingYLabel)
        #expect(!fullLabel.contains("(3ω)"))
        #expect(!fullLabel.contains("\\frac"))
    }

    @Test("Scaling-law render path still produces output")
    func renderScalingProducesOutput() {
        let result = ThreeOmegaScalingResult(
            points: [
                ThreeOmegaScalingPoint(
                    temperatureK: 300,
                    sigma2xx: 1.25e12,
                    scalingY: 3.5e-4
                )
            ],
            segments: []
        )

        var renderer = ThreeOmegaPlotRenderer()
        let (data, _, layout, _, warnings) = renderer.renderScaling(result: result)
        #expect(data != nil)
        #expect(layout != nil)
        #expect(warnings.isEmpty)
    }
}
