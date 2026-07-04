import Testing
@testable import SpinLabApp

@Suite("v5.11.9 - RT label migration regression")
struct V5119RTLabelMigrationRegressionTests {

    @Test("RTPlotRenderer axis labels preserve current plain-text labels")
    func rtPlotRendererAxisLabelsUseVocabulary() {
        let payload = RTPlotRenderer().makePayload(results: [makeRTResult()])
        #expect(payload?.axisMapping.xField == "Temperature (K)")
        #expect(payload?.axisMapping.yField == "Rxx (Ω)")
    }

    @Test("3ω RT render path keeps the current RT axis labels")
    func threeOmegaRTAxisLabelsRemainUnchanged() {
        var renderer = ThreeOmegaPlotRenderer()
        let (_, _, displayPayload, _) = renderer.renderRT(rt: makeThreeOmegaRTResult())
        #expect(displayPayload?.axisMapping.xField == "Temperature (K)")
        #expect(displayPayload?.axisMapping.yField == #"math:R_{xx} (Ω)"#)
    }

    private func makeRTResult() -> RTAnalysisResult {
        RTAnalysisResult(
            workflowID: "RT",
            sourceFilePath: "/tmp/rt.lvm",
            sampleKey: "sample-1",
            format: .lvm,
            device: "0deg",
            temperatureK: [10, 20, 30],
            rxx: [100, 101, 102]
        )
    }

    private func makeThreeOmegaRTResult() -> ThreeOmegaRTResult {
        ThreeOmegaRTResult(
            device: "0deg",
            temperatureK: [10, 20, 30],
            rxx: [100, 101, 102]
        )
    }
}
