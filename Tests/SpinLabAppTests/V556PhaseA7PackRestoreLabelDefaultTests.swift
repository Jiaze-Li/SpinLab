import Testing
@testable import SpinLabApp

/// Phase 7A diagnosis: proves that restoring an old pack (no stored label override)
/// renders the current vocabulary default, and that a pack carrying an explicit
/// legacy-text override is never silently rewritten — the stored override string
/// flows unchanged into the render pipeline and wins over the vocabulary default.
@Suite("v5.5.6 - Phase 7A pack-restore label default vs. override")
struct V556PhaseA7PackRestoreLabelDefaultTests {

    // MARK: - RT (.temperature)

    @Test("RT: no stored override renders the current vocabulary default")
    func rtNoOverrideUsesVocabularyDefault() throws {
        let payload = RTPlotRenderer().makePayload(results: [makeRTResult()])
        let payload2 = try #require(payload)
        let input = WorkbenchRenderPipeline.Input(payload: payload2)
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.xAxisLabel == "Temperature (K)")
        #expect(output.manifestPayload.axisMapping.xField == "Temperature (K)")
    }

    @Test("RT: a stored legacy override ('T (K)') is respected verbatim, not rewritten to the new default")
    func rtLegacyOverrideIsRespected() throws {
        let payload = RTPlotRenderer().makePayload(results: [makeRTResult()])
        let payload2 = try #require(payload)
        let input = WorkbenchRenderPipeline.Input(payload: payload2, xLabelOverride: "T (K)")
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.xAxisLabel == "T (K)", "explicit override must win over the vocabulary default")
        #expect(output.manifestPayload.axisMapping.xField == "Temperature (K)",
                "manifest must retain the canonical scientific label regardless of the display override")
    }

    @Test("RT: an arbitrary user-typed override is respected verbatim")
    func rtArbitraryOverrideIsRespected() throws {
        let payload = RTPlotRenderer().makePayload(results: [makeRTResult()])
        let payload2 = try #require(payload)
        let input = WorkbenchRenderPipeline.Input(payload: payload2, xLabelOverride: "My Custom X")
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.xAxisLabel == "My Custom X")
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

    @MainActor
    @Test("RT restoreFromPack never rewrites a stored xLabelOverride, old or new")
    func rtRestoreFromPackPreservesStoredOverrideVerbatim() throws {
        let store = RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue)
        let config = RTPackConfig(
            tabStates: ["rtCurve": TabRenderState(xLabelOverride: "T (K)")]
        )
        let result = RTPackResult()
        let pack = try AnalysisPack(
            label: "RT Legacy Override",
            workflowID: "rt",
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        #expect(store.tabs.tabStates[.rtCurve]?.xLabelOverride == "T (K)",
                "restoreFromPack must not silently rewrite a pack's stored override to the new vocabulary default")
    }

    // MARK: - RAHE vs Device (.deviceAngle)

    @Test("RAHE vs Device: no stored override renders the current vocabulary default")
    func raheVsDeviceNoOverrideUsesVocabularyDefault() throws {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let payload = r.makeRAHE1omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        let payload2 = try #require(payload)
        let input = WorkbenchRenderPipeline.Input(payload: payload2)
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.xAxisLabel == "Ψ (deg)")
        #expect(output.manifestPayload.axisMapping.xField == "Ψ (deg)")
    }

    @Test("RAHE vs Device: a stored legacy override ('Device angle (deg)') is respected verbatim, not rewritten")
    func raheVsDeviceLegacyOverrideIsRespected() throws {
        let r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let payload = r.makeRAHE1omegaVsDevicePayload(sweeps: sweeps, device: "0deg", method: .highField)
        let payload2 = try #require(payload)
        let input = WorkbenchRenderPipeline.Input(payload: payload2, xLabelOverride: "Device angle (deg)")
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.layout.xAxisLabel == "Device angle (deg)",
                "explicit override must win over the vocabulary default")
        #expect(output.manifestPayload.axisMapping.xField == "Ψ (deg)",
                "manifest must retain the canonical scientific label regardless of the display override")
    }

    private func makeSweep(device: String, temperatureK: Double, rahe1: Double, rahe3: Double) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
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

    private func makeSweeps() -> [ThreeOmegaFieldSweepResult] {
        [
            makeSweep(device: "30deg", temperatureK: 200, rahe1: 0.30, rahe3: 0.60),
            makeSweep(device: "0deg",  temperatureK: 200, rahe1: 0.10, rahe3: 0.20),
            makeSweep(device: "60deg", temperatureK: 200, rahe1: 0.50, rahe3: 1.00),
        ]
    }
}
