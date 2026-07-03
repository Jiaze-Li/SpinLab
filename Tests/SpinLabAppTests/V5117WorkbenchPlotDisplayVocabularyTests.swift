import Testing
@testable import SpinLabApp

@Suite("v5.11.7 - WorkbenchPlotDisplayVocabulary")
struct V5117WorkbenchPlotDisplayVocabularyTests {

    @Test("current labels are returned verbatim")
    func currentLabels() {
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .plotAxis) == "H (T)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .coerciveField, context: .plotAxis) == #"math:H_{c} (Oe)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .coerciveField, context: .manifestPlainText) == "Hc (Oe)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .coerciveField, context: .uiText) == "Hc (Oe)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .temperature, context: .plotAxis) == "T (K)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .deviceAngle, context: .plotAxis) == "Device angle (deg)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .angleOffset, context: .plotAxis) == "φ (deg)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .plotAxis) == #"math:R^{1ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance3omega, context: .plotAxis) == #"math:R^{3ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe1omega, context: .plotAxis) == #"math:R_{AHE}^{1ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe3omega, context: .plotAxis) == #"math:R_{AHE}^{3ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context: .plotAxis) == #"math:R_{AHE} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .plotAxis) == #"math:R_{xx} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .manifestPlainText) == "Rxx (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rxy, context: .plotAxis) == "Rxy (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .hallResistance, context: .plotAxis) == "R_H (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .sigmaXX, context: .plotAxis) == #"math:σ_{xx} (S/m)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .scalingLawX, context: .plotAxis) == #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .scalingLawY, context: .plotAxis) == #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .temperatureDependenceERatio, context: .plotAxis) == #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .current, context: .plotAxis, currentBasis: .peak) == "Current (mA, peak)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .current, context: .plotAxis, currentBasis: .rms) == "Current (mA, RMS)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .voltage, context: .plotAxis) == "V (V)")
    }

    @Test("identity cases stay distinct")
    func identityCasesStayDistinct() {
        #expect(WorkbenchPhysicalQuantity.deviceAngle != .angleOffset)
        #expect(WorkbenchPhysicalQuantity.scalingLawY != .temperatureDependenceERatio)
        #expect(WorkbenchPhysicalQuantity.externalMagneticField != .coerciveField)
    }
}
