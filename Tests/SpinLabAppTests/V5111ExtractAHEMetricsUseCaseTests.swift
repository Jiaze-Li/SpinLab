import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.11 Extract AHE Metrics UseCase")
struct V5111ExtractAHEMetricsUseCaseTests {

    private func makeAHESeries(
        sampleKey: String,
        hMax: Double = 1.0,
        amplitude: Double = 0.5,
        yOffset: Double = 0.0
    ) -> WorkbenchPlotSeries {
        let xs = [hMax, hMax * 0.5, 0.0, -hMax * 0.5, -hMax, -hMax * 0.5, 0.0, hMax * 0.5, hMax]
        let ys = xs.map { ($0 >= 0 ? amplitude : -amplitude) + yOffset }
        return WorkbenchPlotSeries(label: "\(sampleKey) | ch1", x: xs, y: ys, sampleID: sampleKey)
    }

    @Test("extractAHEMetricsPerSeries keys metrics by sampleKey")
    func extractAHEMetricsPerSeriesKeysBySampleKey() throws {
        let metrics = try ExtractAHEMetricsUseCase.extractAHEMetricsPerSeries(from: [
            makeAHESeries(sampleKey: "SK-B", amplitude: 1.0),
            makeAHESeries(sampleKey: "SK-A", amplitude: 0.5)
        ]).get()

        #expect(Set(metrics.keys) == ["SK-A", "SK-B"])
        #expect(metrics["SK-B"]!.rAHE > metrics["SK-A"]!.rAHE)
    }

    @Test("parseSampleKey trims the first label segment")
    func parseSampleKeyTrimsFirstSegment() {
        #expect(ExtractAHEMetricsUseCase.parseSampleKey(from: "  SK-A  | ch1") == "SK-A")
        #expect(ExtractAHEMetricsUseCase.parseSampleKey(from: "   ") == nil)
    }

    @MainActor
    @Test("updateHcCandidate normalizes raw input in the store")
    func updateHcCandidateNormalizesRawInput() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)

        store.updateHcCandidate(rawValue: "   ", rawReason: "ignored")
        #expect(store.pendingMetricOverride == nil)

        store.updateHcCandidate(rawValue: " 1.25 ", rawReason: "  checked ")
        #expect(store.pendingMetricOverride?.proposedValue == 1.25)
        #expect(store.pendingMetricOverride?.reason == "checked")

        store.updateHcCandidate(rawValue: "invalid", rawReason: "checked")
        #expect(store.pendingMetricOverride == nil)
    }

    @MainActor
    @Test("updateRAHECandidate normalizes raw input in the store")
    func updateRAHECandidateNormalizesRawInput() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)

        store.updateRAHECandidate(rawValue: " 2.5 ", rawReason: "   ")
        #expect(store.pendingRAHEOverride?.proposedValue == 2.5)
        #expect(store.pendingRAHEOverride?.reason == "visual check")

        store.updateRAHECandidate(rawValue: "invalid", rawReason: "checked")
        #expect(store.pendingRAHEOverride == nil)
    }
}
