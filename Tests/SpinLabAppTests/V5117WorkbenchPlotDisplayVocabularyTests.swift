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
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .temperature, context: .plotAxis) == "Temperature (K)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .deviceAngle, context: .plotAxis) == "Ψ (deg)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .angleOffset, context: .plotAxis) == "φ (deg)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .plotAxis) == #"math:R^{1ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .manifestPlainText) == "R(1ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .uiText) == "R(1ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance3omega, context: .plotAxis) == #"math:R^{3ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance3omega, context: .manifestPlainText) == "R(3ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe1omega, context: .plotAxis) == #"math:R_{AHE}^{1ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe1omega, context: .manifestPlainText) == "RAHE(1ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe3omega, context: .plotAxis) == #"math:R_{AHE}^{3ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe3omega, context: .manifestPlainText) == "RAHE(3ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context: .plotAxis) == #"math:R_{AHE} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .plotAxis) == #"math:R_{xx} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .manifestPlainText) == "Rxx (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.plotLabel(for: .rxy) == #"math:R_{xy} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .rxy) == "Rxy (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.plotLabel(for: .hallResistance) == #"math:R_{H} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .hallResistance) == "R_H (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .sigmaXX, context: .plotAxis) == #"math:σ_{xx} × 10^{3} (S cm^{-1})"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .scalingLawX, context: .plotAxis) == #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .scalingLawY, context: .plotAxis) == #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .temperatureDependenceERatio, context: .plotAxis) == #"math:E_{AHE}^{3ω} / E_{xx}^{3} × 10^{2} (μm^{2} V^{-2})"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .current, context: .plotAxis, currentBasis: .peak) == "Current (mA, peak)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .current, context: .plotAxis, currentBasis: .rms) == "Current (mA, RMS)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .voltage, context: .plotAxis) == "V (V)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .reciprocalH, context: .plotAxis) == "H (r.l.u.)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .reciprocalK, context: .plotAxis) == "K (r.l.u.)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .reciprocalL, context: .plotAxis) == "L (r.l.u.)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .diffractionIntensity, context: .plotAxis) == "Intensity (counts)")
    }

    @Test("same physical quantity can expose different labels by display context")
    func labelsVaryByDisplayContext() {
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .plotAxis) == #"math:R^{1ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance1omega, context: .manifestPlainText) == "R(1ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance3omega, context: .plotAxis) == #"math:R^{3ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .resistance3omega, context: .manifestPlainText) == "R(3ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe1omega, context: .plotAxis) == #"math:R_{AHE}^{1ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe1omega, context: .manifestPlainText) == "RAHE(1ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe3omega, context: .plotAxis) == #"math:R_{AHE}^{3ω} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .rahe3omega, context: .manifestPlainText) == "RAHE(3ω) (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.plotLabel(for: .rxy) == #"math:R_{xy} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .rxy) == "Rxy (Ω)")
        #expect(WorkbenchPlotDisplayVocabulary.plotLabel(for: .hallResistance) == #"math:R_{H} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .hallResistance) == "R_H (Ω)")
    }

    @Test("identity cases stay distinct")
    func identityCasesStayDistinct() {
        #expect(WorkbenchPhysicalQuantity.deviceAngle != .angleOffset)
        #expect(WorkbenchPhysicalQuantity.scalingLawY != .temperatureDependenceERatio)
        #expect(WorkbenchPhysicalQuantity.externalMagneticField != .coerciveField)
        #expect(WorkbenchPhysicalQuantity.rxx != .hallResistance)
        #expect(WorkbenchPhysicalQuantity.resistance1omega != .rahe1omega)
        #expect(WorkbenchPhysicalQuantity.resistance3omega != .rahe3omega)
    }

    @Test("future migration targets still return current legacy labels")
    func futureMigrationTargetsStillUseLegacyLabels() {
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .plotAxis) == "H (T)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .coerciveField, context: .plotAxis) == #"math:H_{c} (Oe)"#)
    }
}
