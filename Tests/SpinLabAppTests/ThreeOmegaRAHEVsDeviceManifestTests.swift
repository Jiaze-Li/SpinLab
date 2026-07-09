import Testing
@testable import SpinLabApp

@Suite("ThreeOmega RAHE vs Device — manifest payload")
struct ThreeOmegaRAHEVsDeviceManifestTests {

    // MARK: - Semantic params in renderer display payload

    @Test("rahe1omegaVsDevice display payload has correct workflowID and tabKey")
    func rahe1DevSemanticParams() {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = [makeSweep(device: "0deg", rahe1: 0.1, rahe3: 0.2)]
        let display = r.makeRAHE1omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        #expect(display?.workflowID == "3w")
        #expect(display?.semanticParams["tabKey"] == "rahe1omegaVsDevice")
        #expect(display?.semanticParams["v3method"] == "HFE")
    }

    @Test("rahe3omegaVsDevice display payload has correct tabKey and v3method WA")
    func rahe3DevSemanticParamsWA() {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = [makeSweep(device: "30deg", rahe1: 0.3, rahe3: 0.6)]
        let display = r.makeRAHE3omegaVsDevicePayload(sweeps: sweeps, device: "30deg", method: .window)
        #expect(display?.semanticParams["tabKey"] == "rahe3omegaVsDevice")
        #expect(display?.semanticParams["v3method"] == "WA")
    }

    @Test("x axis label is 'Device angle (deg)' for both new tabs")
    func xAxisLabel() {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = [makeSweep(device: "0deg", rahe1: 0.1, rahe3: 0.2)]
        let display1 = r.makeRAHE1omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        let display3 = r.makeRAHE3omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        #expect(display1?.axisMapping.xField == "Ψ (deg)")
        #expect(display3?.axisMapping.xField == "Ψ (deg)")
    }

    @Test("y axis label for 1ω tab is 'RAHE(1ω) (Ω)'")
    func yAxisLabel1() {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = [makeSweep(device: "0deg", rahe1: 0.1, rahe3: 0.2)]
        let display = r.makeRAHE1omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        #expect(display?.axisMapping.yField == #"math:R_{AHE}^{1ω} (Ω)"#)
    }

    @Test("y axis label for 3ω tab is 'RAHE(3ω) (Ω)'")
    func yAxisLabel3() {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = [makeSweep(device: "0deg", rahe1: 0.1, rahe3: 0.2)]
        let display = r.makeRAHE3omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        #expect(display?.axisMapping.yField == #"math:R_{AHE}^{3ω} (Ω)"#)
    }

    // MARK: - RAHE-vs-device tabs both render

    @MainActor
    @Test("rahe1omegaVsDevice and rahe3omegaVsDevice both render image data and display payloads")
    func bothDeviceTabsRender() {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = [makeSweep(device: "0deg", rahe1: 0.1, rahe3: 0.2)]
        let payload1 = r.makeRAHE1omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        let payload3 = r.makeRAHE3omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        let (data1, _, _, display1, _) = ThreeOmegaSharedRenderRoute.render(payload: payload1, tab: .rahe1omegaVsDevice)
        let (data3, _, _, display3, _) = ThreeOmegaSharedRenderRoute.render(payload: payload3, tab: .rahe3omegaVsDevice)
        #expect(data1 != nil, "rahe1omegaVsDevice should be rendered")
        #expect(data3 != nil, "rahe3omegaVsDevice should be rendered")
        #expect(display1 != nil)
        #expect(display3 != nil)
    }

    @Test("device tab stable keys are distinct from vs-T keys")
    func distinctFromVsTKeys() {
        let vsT1 = ThreeOmegaWorkbenchTab.rahe1omegaVsT.stableKey
        let vsT3 = ThreeOmegaWorkbenchTab.rahe3omegaVsT.stableKey
        let devKey1 = ThreeOmegaWorkbenchTab.rahe1omegaVsDevice.stableKey
        let devKey3 = ThreeOmegaWorkbenchTab.rahe3omegaVsDevice.stableKey
        #expect(devKey1 != vsT1)
        #expect(devKey1 != vsT3)
        #expect(devKey3 != vsT1)
        #expect(devKey3 != vsT3)
    }

    // MARK: - helpers

    private func makeSweep(device: String, rahe1: Double, rahe3: Double) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: 200,
            device: device,
            hField: [-100, 0, 100],
            r1omega: [0, 0, 0],
            r3omega: [0, 0, 0],
            iRms: 1e-4,
            rahe1omega: rahe1,
            rahe1omegaWA: rahe1 * 0.98,
            hc1omega: nil, hc3omega: nil,
            v3omegaWindow: rahe3 * 1e-4,
            v3omegaFit: rahe3 * 1e-4
        )
    }
}
