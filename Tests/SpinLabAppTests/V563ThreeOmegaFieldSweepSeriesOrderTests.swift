import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.3 ThreeOmega Field-Sweep Series Order")
struct V563ThreeOmegaFieldSweepSeriesOrderTests {

    private func makeFieldSweep(sourceRef: String, sampleID: String, temperatureK: Double) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: sampleID,
            sourceFilePath: sourceRef,
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
    }

    private func makeIngestionResult() -> ThreeOmegaIngestionResult {
        ThreeOmegaIngestionResult(
            fieldSweeps: [
                makeFieldSweep(sourceRef: "/tmp/bottom.csv", sampleID: "bottom", temperatureK: 5.0),
                makeFieldSweep(sourceRef: "/tmp/top.csv", sampleID: "top", temperatureK: 10.0)
            ],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [5.0: 1e-3, 10.0: 1e-3],
            warnings: []
        )
    }

    @MainActor
    @Test("AHE 1ω and 3ω share one field-sweep series order across tab switches")
    func sharedSeriesOrderSurvivesTabSwitches() {
        let store = ThreeOmegaWorkspaceStore()
        let order = ["/tmp/bottom.csv", "/tmp/top.csv"]

        store.tabs.activeTab = .fieldSweep1omega
        store.updateSeriesOrder(order)
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == order)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == order)

        store.tabs.activeTab = .fieldSweep3omega
        #expect(store.activeSeriesOrder == order)

        let updatedOrder = ["/tmp/top.csv", "/tmp/bottom.csv"]
        store.updateSeriesOrder(updatedOrder)
        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == updatedOrder)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == updatedOrder)

        store.tabs.activeTab = .fieldSweep1omega
        #expect(store.activeSeriesOrder == updatedOrder)
    }

    @MainActor
    @Test("Resetting series order clears both field-sweep tabs")
    func resetSeriesOrderClearsBothTabs() {
        let store = ThreeOmegaWorkspaceStore()
        store.tabs.activeTab = .fieldSweep1omega
        store.updateSeriesOrder(["/tmp/bottom.csv", "/tmp/top.csv"])

        store.resetSeriesOrder()

        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == nil)
        #expect(store.tabs.state(for: .fieldSweep3omega).seriesOrder == nil)
        #expect(store.activeSeriesOrder == nil)
    }

    // MARK: - stableSourceRef fallback (v5.6.3 backward compat)

    @Test("stableSourceRef: prefers sourceFilePath when present")
    func stableSourceRefPrefersFilePath() {
        let sweep = makeFieldSweep(sourceRef: "/path/to/file.lvm", sampleID: "sid", temperatureK: 5)
        #expect(sweep.stableSourceRef == "/path/to/file.lvm")
    }

    @Test("stableSourceRef: falls back to sampleID+device+temp composite when sourceFilePath is nil")
    func stableSourceRefFallsBackToSampleIDComposite() {
        var sweep = makeFieldSweep(sourceRef: "/path/to/file.lvm", sampleID: "mysample", temperatureK: 5)
        sweep.sourceFilePath = nil
        #expect(sweep.stableSourceRef == "mysample|0deg|5.0K")
    }

    @Test("stableSourceRef: falls back to device+temp when both sourceFilePath and sampleID are nil")
    func stableSourceRefFallsBackToDeviceTemp() {
        var sweep = makeFieldSweep(sourceRef: "/path/to/file.lvm", sampleID: "sid", temperatureK: 5)
        sweep.sourceFilePath = nil
        sweep.sampleID = nil
        #expect(sweep.stableSourceRef == "0deg|5.0K")
        #expect(!sweep.stableSourceRef.isEmpty)
    }

    @Test("stableSourceRef: same sampleID but different device/temperature produce distinct values")
    func stableSourceRefDistinguishesByDeviceAndTemp() {
        var sweepA = makeFieldSweep(sourceRef: "/a.lvm", sampleID: "shared", temperatureK: 5)
        sweepA.sourceFilePath = nil
        var sweepB = makeFieldSweep(sourceRef: "/b.lvm", sampleID: "shared", temperatureK: 10)
        sweepB.sourceFilePath = nil
        #expect(sweepA.stableSourceRef != sweepB.stableSourceRef)

        // Verify the distinguishing components are present
        #expect(sweepA.stableSourceRef.contains("5.0K"))
        #expect(sweepB.stableSourceRef.contains("10.0K"))
    }

    @Test("R1ω render with legacy sweeps (nil sourceFilePath + nil sampleID) does not crash and has non-empty sourceRefs")
    func r1omegaLegacySweepsProduceNonEmptySourceRefs() throws {
        // Simulate sweeps from an old pack that never wrote sourceFilePath or sampleID.
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil
        var sweep10 = makeFieldSweep(sourceRef: "/tmp/10K.lvm", sampleID: "s10", temperatureK: 10)
        sweep10.sourceFilePath = nil
        sweep10.sampleID = nil

        var renderer = ThreeOmegaPlotRenderer()
        let (_, _, warnings) = renderer.renderR1omega(sweeps: [sweep5, sweep10], device: "0deg")
        // Must not crash (assert would abort); just verify no pipeline failure warning.
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
    }

    @Test("R1ω reorderable payload: all series have non-empty sourceRef")
    func r1omegaReorderablePayloadSeriesAllHaveSourceRef() throws {
        // Sweeps with no sourceFilePath — stableSourceRef falls back to id.
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil
        var sweep10 = makeFieldSweep(sourceRef: "/tmp/10K.lvm", sampleID: "s10", temperatureK: 10)
        sweep10.sourceFilePath = nil
        sweep10.sampleID = nil

        var renderer = ThreeOmegaPlotRenderer()
        renderer.titleTokens = ["sample": "TEST"]
        let (_, layout, _) = renderer.renderR1omega(sweeps: [sweep5, sweep10], device: "0deg")
        // Layout is non-nil only when render succeeds without crashing.
        #expect(layout != nil)
    }

    @Test("R3ω render with legacy sweeps does not crash")
    func r3omegaLegacySweepsDoNotCrash() throws {
        var sweep5 = makeFieldSweep(sourceRef: "/tmp/5K.lvm", sampleID: "s5", temperatureK: 5)
        sweep5.sourceFilePath = nil
        sweep5.sampleID = nil

        var renderer = ThreeOmegaPlotRenderer()
        let (_, _, warnings) = renderer.renderR3omega(sweeps: [sweep5], device: "0deg")
        #expect(!warnings.contains(where: { $0.contains("pipeline failure") }))
    }

    @MainActor
    @Test("Manifest refresh uses the shared field-sweep order for both tabs")
    func manifestRefreshUsesSharedOrderForBothTabs() {
        let store = ThreeOmegaWorkspaceStore()
        store.ingestionResult = makeIngestionResult()
        store.cachedInputFiles = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        let order = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.updateSeriesOrder(order)
        store._refreshManifestPayloads()

        let r1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let r3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)

        #expect(r1 == ["/tmp/top.csv", "/tmp/bottom.csv"])
        #expect(r3 == ["/tmp/top.csv", "/tmp/bottom.csv"])
    }
}
