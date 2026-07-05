import Testing
@testable import SpinLabApp

@Suite("v5.5.6 - IV label migration regression")
struct V556IVLabelMigrationRegressionTests {

    @Test("1st harmonic payload preserves current plain-text axis labels (peak basis)")
    func firstHarmonicAxisLabelsUnchangedPeak() {
        var renderer = IVPlotRenderer()
        renderer.xCurrentBasis = .peak
        let payload = renderer.makeFirstHarmonicPayload(sweeps: [makeSweep()], device: "device-1")
        #expect(payload?.axisMapping.xField == "Current (mA, peak)")
        #expect(payload?.axisMapping.yField == "V (V)")
    }

    @Test("2nd harmonic payload preserves current plain-text axis labels (RMS basis)")
    func secondHarmonicAxisLabelsUnchangedRMS() {
        var renderer = IVPlotRenderer()
        renderer.xCurrentBasis = .rms
        let payload = renderer.makeSecondHarmonicPayload(sweeps: [makeSweep()], device: "device-1")
        #expect(payload?.axisMapping.xField == "Current (mA, RMS)")
        #expect(payload?.axisMapping.yField == "V (V)")
    }

    @Test("IVCurrentBasis maps to the matching WorkbenchCurrentBasis for vocabulary lookups")
    func currentBasisMapsToWorkbenchBasis() {
        #expect(IVCurrentBasis.peak.workbenchCurrentBasis == .peak)
        #expect(IVCurrentBasis.rms.workbenchCurrentBasis == .rms)
    }

    private func makeSweep() -> IVSweep {
        IVSweep(
            stem: "test.lvm",
            temperatureK: 300,
            fieldT: 0,
            current: [0.001, 0.002, 0.003],
            ch1X: [0.10, 0.20, 0.30],
            ch1Y: [0.01, 0.02, 0.03],
            ch2X: [0.05, 0.10, 0.15],
            ch2Y: [0.005, 0.010, 0.015],
            firstR: nil,
            firstTheta: nil,
            secondR: nil,
            secondTheta: nil,
            firstRH: nil,
            frequencyAfter: nil,
            measurementFilePath: nil,
            sampleMetadata: [:]
        )
    }
}
