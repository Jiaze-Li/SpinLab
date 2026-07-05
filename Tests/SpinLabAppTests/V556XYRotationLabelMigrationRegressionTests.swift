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

    @Test("deviceAngle and angleOffset remain distinct identities")
    func deviceAngleAndAngleOffsetRemainDistinct() {
        #expect(WorkbenchPhysicalQuantity.deviceAngle != .angleOffset)
        #expect(
            WorkbenchPlotDisplayVocabulary.label(for: .angleOffset, context: .manifestPlainText)
                != WorkbenchPlotDisplayVocabulary.label(for: .deviceAngle, context: .manifestPlainText)
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
