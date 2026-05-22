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
