import Testing
@testable import SpinLabApp

@Suite("v5.11.9 - RT label migration regression")
struct V5119RTLabelMigrationRegressionTests {

    @Test("RTPlotRenderer manifest payload keeps plain-text labels")
    func rtPlotRendererManifestAxisLabelsAreVocabularyPlainText() {
        let payload = RTPlotRenderer().makePayload(results: [makeRTResult()])
        #expect(payload?.axisMapping.xField == "Temperature (K)")
        #expect(payload?.axisMapping.yField == "Rxx (Ω)")
    }

    @Test("RTPlotRenderer display payload y label uses math:R_{xx} (Ω)")
    func rtPlotRendererDisplayAxisLabelsAreMathFormatted() {
        let payloads = RTPlotRenderer().makePayloads(results: [makeRTResult()])
        #expect(payloads?.displayPayload.axisMapping.xField == "Temperature (K)")
        #expect(payloads?.displayPayload.axisMapping.yField == #"math:R_{xx} (Ω)"#)
    }

    @Test("3ω RT render path keeps the current RT axis labels")
    func threeOmegaRTAxisLabelsRemainUnchanged() {
        let renderer = ThreeOmegaPlotRenderer()
        let payload = renderer.makeRTPayload(rt: makeThreeOmegaRTResult())
        #expect(payload?.axisMapping.xField == "Temperature (K)")
        #expect(payload?.axisMapping.yField == #"math:R_{xx} (Ω)"#)
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
