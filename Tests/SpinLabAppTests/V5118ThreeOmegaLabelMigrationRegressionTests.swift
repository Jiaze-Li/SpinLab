import Testing
@testable import SpinLabApp

@Suite("v5.11.8 - ThreeOmega label migration regression")
struct V5118ThreeOmegaLabelMigrationRegressionTests {

    @Test("renderer axis-label constants are unchanged after vocabulary migration")
    func rendererAxisLabelsUnchanged() {
        // These remain the current visible labels; Phase 2 only rerouted where they are sourced from.
        #expect(ThreeOmegaPlotRenderer.fieldAxisLabel == "H (T)")
        #expect(ThreeOmegaPlotRenderer.temperatureAxisLabel == "Temperature (K)")
        #expect(ThreeOmegaPlotRenderer.deviceAngleAxisLabel == "Ψ (deg)")
        #expect(ThreeOmegaPlotRenderer.r1AxisLabel == #"math:R^{1ω} (Ω)"#)
        #expect(ThreeOmegaPlotRenderer.r3AxisLabel == #"math:R^{3ω} (Ω)"#)
        #expect(ThreeOmegaPlotRenderer.rAHE1AxisLabel == #"math:R_{AHE}^{1ω} (Ω)"#)
        #expect(ThreeOmegaPlotRenderer.rAHE3AxisLabel == #"math:R_{AHE}^{3ω} (Ω)"#)
        #expect(ThreeOmegaPlotRenderer.hcAxisLabel == #"math:H_{c} (Oe)"#)
        #expect(ThreeOmegaPlotRenderer.rxxAxisLabel == #"math:R_{xx} (Ω)"#)
        #expect(ThreeOmegaPlotRenderer.sigmaXXAxisLabel == #"math:σ_{xx} (S/m)"#)
        #expect(ThreeOmegaPlotRenderer.eAHEOverE3AxisLabel == #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#)
        #expect(ThreeOmegaPlotRenderer.rAHEAxisLabel == #"math:R_{AHE} (Ω)"#)
        #expect(ThreeOmegaPlotRenderer.scalingXAxisLabel == #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#)
        #expect(ThreeOmegaPlotRenderer.scalingYAxisLabel == #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#)
    }

    @Test("legend-style constants remain untouched (not part of this migration)")
    func legendLabelsUnchanged() {
        #expect(ThreeOmegaPlotRenderer.rAHE1LegendLabel == #"math:R_{AHE}^{1ω}"#)
        #expect(ThreeOmegaPlotRenderer.rAHE3LegendLabel == #"math:R_{AHE}^{3ω}"#)
        #expect(ThreeOmegaPlotRenderer.hc1LegendLabel == #"math:H_{c}^{1ω}"#)
        #expect(ThreeOmegaPlotRenderer.hc3LegendLabel == #"math:H_{c}^{3ω}"#)
        #expect(ThreeOmegaPlotRenderer.rxxLegendLabel == #"math:R_{xx}"#)
        #expect(ThreeOmegaPlotRenderer.eAHEOverE3LegendLabel == #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#)
        #expect(ThreeOmegaPlotRenderer.sigmaXXLegendLabel == #"math:σ_{xx}"#)
    }

    @Test("manifest plain-text vocabulary outputs match the previous hardcoded manifest strings")
    func manifestPlainTextLabelsMatchPreviousHardcodedStrings() {
        // These remain the manifest-cache labels for the current migration boundary.
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .manifestPlainText) == "H (T)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .temperature, context: .manifestPlainText) == "Temperature (K)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .deviceAngle, context: .manifestPlainText) == "Ψ (deg)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .manifestPlainText) == "R(1ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance3omega, context: .manifestPlainText) == "R(3ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe1omega, context: .manifestPlainText) == "RAHE(1ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe3omega, context: .manifestPlainText) == "RAHE(3ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .coerciveField, context: .manifestPlainText) == "Hc (Oe)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .manifestPlainText) == "Rxx (Ω)")
    }
}
