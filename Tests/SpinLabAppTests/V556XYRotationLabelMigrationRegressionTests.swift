import Testing
@testable import SpinLabApp

@Suite("v5.5.6 - XY Rotation label migration regression")
struct V556XYRotationLabelMigrationRegressionTests {

    @Test("Rxx vs φ payload preserves current plain-text axis labels")
    func rxxVsPhiAxisLabelsUnchanged() {
        let payload = XYRotationPlotRenderer().makeRxxVsPhiPayload(sweeps: [makeSweep()], device: "device-1")
        #expect(payload?.axisMapping.xField == "φ (deg)")
        #expect(payload?.axisMapping.yField == "Rxx (Ω)")
    }

    @Test("Rxy vs φ payload preserves current plain-text axis labels")
    func rxyVsPhiAxisLabelsUnchanged() {
        let payload = XYRotationPlotRenderer().makeRxyVsPhiPayload(sweeps: [makeSweep(resistanceXY: [10, 11])], device: "device-1")
        #expect(payload?.axisMapping.xField == "φ (deg)")
        #expect(payload?.axisMapping.yField == "Rxy (Ω)")
    }

    @Test("Rxy vs φ display payload y label uses math:R_{xy} (Ω), not manifest plain text")
    func rxyVsPhiDisplayAxisLabelIsMathFormatted() {
        let display = XYRotationPlotRenderer().makeRxyVsPhiDisplayPayload(sweeps: [makeSweep(resistanceXY: [10, 11])], device: "device-1")
        #expect(display?.payload.axisMapping.xField == "φ (deg)")
        #expect(display?.payload.axisMapping.yField == #"math:R_{xy} (Ω)"#)
    }

    @Test("Rxx vs φ display payload y label uses math:R_{xx} (Ω), not manifest plain text")
    func rxxVsPhiDisplayAxisLabelIsMathFormatted() {
        let display = XYRotationPlotRenderer().makeRxxVsPhiDisplayPayload(sweeps: [makeSweep()], device: "device-1")
        #expect(display?.payload.axisMapping.yField == #"math:R_{xx} (Ω)"#)
    }

    @Test("deviceAngle and angleOffset remain distinct identities")
    func deviceAngleAndAngleOffsetRemainDistinct() {
        #expect(WorkbenchPhysicalQuantity.deviceAngle != .angleOffset)
        #expect(
            WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .angleOffset)
                != WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .deviceAngle)
        )
    }

    private func makeSweep(resistanceXY: [Double]? = nil) -> XYRotationAngleSweep {
        XYRotationAngleSweep(
            temperatureK: 80,
            stem: "test",
            sourceKind: .dat,
            angleDeg: [0, 90],
            resistanceXX: [100, 101],
            resistanceXY: resistanceXY,
            defaultPhiOffset: 0,
            measurementFilePath: nil
        )
    }
}
