import Foundation
import Testing
@testable import SpinLabApp

/// Regression coverage for the series-control refresh transaction refactor:
/// `updateSeriesOrder` / `updateSeriesVisibility` / `updateSeriesLabel` on all
/// five Cartesian workspace stores (RT, IV, AHE, XY Rotation, 3ω) must mutate
/// state only and must NOT dispatch a render themselves. The shared panel's
/// generic `onChange` closure (surfaced here via `rerenderForStyleChange()`,
/// which is what every workflow view's `onChange` callback ultimately calls)
/// remains the sole render trigger, so a committed series-control edit still
/// produces exactly one render dispatch overall.
///
/// Render-dispatch counting strategy:
/// - RT/IV/AHE/XY: `_rerenderActiveTab()` increments the shared, synchronous
///   `PerfCounters.renderCalls` as its first statement, before any async work
///   is spawned — a race-free per-call dispatch counter as long as no `await`
///   separates the "before" snapshot from the "after" assertion.
/// - 3ω: its render-dispatch counter (`PerfCounters.renderCalls`) only
///   increments inside the detached render `Task`, so it is not race-free to
///   observe synchronously. `_renderRevision` is bumped synchronously at the
///   top of `_rerenderActiveTab()` before that Task is spawned and — unlike
///   the other four stores, where it is `private` — is declared with internal
///   access on `ThreeOmegaWorkspaceStore`, so it is used here instead as the
///   equivalent race-free per-call dispatch counter for 3ω only.
@Suite("V5.5.7 Series-Control Refresh Transaction", .serialized)
struct V557SeriesControlRefreshTransactionTests {

    // MARK: - Fixtures

    /// 3ω's `_rerenderActiveTab()` early-returns before bumping `_renderRevision`
    /// when `ingestionResult` is nil, unlike RT/IV/AHE/XY whose render-dispatch
    /// counter increments unconditionally as the first statement. Give the 3ω
    /// store real (minimal) ingestion data so its revision bump is reachable.
    private func makeThreeOmegaIngestionResult() -> ThreeOmegaIngestionResult {
        ThreeOmegaIngestionResult(
            fieldSweeps: [
                ThreeOmegaFieldSweepResult(
                    temperatureK: 5.0,
                    device: "0deg",
                    sampleMetadata: ["device": "0deg"],
                    sampleID: "bottom",
                    sourceFilePath: "/tmp/bottom.csv",
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
                ),
                ThreeOmegaFieldSweepResult(
                    temperatureK: 10.0,
                    device: "0deg",
                    sampleMetadata: ["device": "0deg"],
                    sampleID: "top",
                    sourceFilePath: "/tmp/top.csv",
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
            ],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [5.0: 1e-3, 10.0: 1e-3],
            warnings: []
        )
    }

    // MARK: - RT

    @MainActor
    @Test("RT: updateSeriesOrder/Visibility/Label mutate only; committed transaction renders exactly once")
    func rtSeriesControlTransaction() {
        let store = RTWorkspaceStore(workflowID: WorkflowKey.rt.rawValue)

        var before = PerfCounters.renderCalls
        store.updateSeriesOrder(["a", "b"])
        #expect(PerfCounters.renderCalls == before, "updateSeriesOrder must not dispatch a render on its own")
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1, "the generic onChange pulse must still dispatch exactly one render")

        before = PerfCounters.renderCalls
        store.updateSeriesVisibility(identityKey: "a", isVisible: false)
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)

        before = PerfCounters.renderCalls
        store.updateSeriesLabel(identityKey: "a", newLabel: "renamed")
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)
    }

    // MARK: - IV

    @MainActor
    @Test("IV: updateSeriesOrder/Visibility/Label mutate only; committed transaction renders exactly once")
    func ivSeriesControlTransaction() {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)

        var before = PerfCounters.renderCalls
        store.updateSeriesOrder(["a", "b"])
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)

        before = PerfCounters.renderCalls
        store.updateSeriesVisibility(identityKey: "a", isVisible: false)
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)

        before = PerfCounters.renderCalls
        store.updateSeriesLabel(identityKey: "a", newLabel: "renamed")
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)
    }

    // MARK: - AHE

    @MainActor
    @Test("AHE: updateSeriesOrder/Visibility/Label mutate only; committed transaction renders exactly once")
    func aheSeriesControlTransaction() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)

        var before = PerfCounters.renderCalls
        store.updateSeriesOrder(["a", "b"])
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)

        before = PerfCounters.renderCalls
        store.updateSeriesVisibility(identityKey: "a", isVisible: false)
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)

        before = PerfCounters.renderCalls
        store.updateSeriesLabel(identityKey: "a", newLabel: "renamed")
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)
    }

    // MARK: - XY Rotation

    @MainActor
    @Test("XY Rotation: updateSeriesOrder/Visibility/Label mutate only; committed transaction renders exactly once")
    func xyRotationSeriesControlTransaction() {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)

        var before = PerfCounters.renderCalls
        store.updateSeriesOrder(["a", "b"])
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)

        before = PerfCounters.renderCalls
        store.updateSeriesVisibility(identityKey: "a", isVisible: false)
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)

        before = PerfCounters.renderCalls
        store.updateSeriesLabel(identityKey: "a", newLabel: "renamed")
        #expect(PerfCounters.renderCalls == before)
        store.rerenderForStyleChange()
        #expect(PerfCounters.renderCalls == before + 1)
    }

    // MARK: - 3ω

    @MainActor
    @Test("3ω: updateSeriesOrder/Visibility/Label mutate only; committed transaction renders exactly once")
    func threeOmegaSeriesControlTransaction() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeThreeOmegaIngestionResult()
        store.cachedInputFiles = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        var before = store._renderRevision
        store.updateSeriesOrder(["a", "b"])
        #expect(store._renderRevision == before, "updateSeriesOrder must not dispatch a render on its own")
        store.rerenderForStyleChange()
        #expect(store._renderRevision == before + 1, "the generic onChange pulse must still dispatch exactly one render")

        before = store._renderRevision
        store.updateSeriesVisibility(identityKey: "a", isVisible: false)
        #expect(store._renderRevision == before)
        store.rerenderForStyleChange()
        #expect(store._renderRevision == before + 1)

        before = store._renderRevision
        store.updateSeriesLabel(identityKey: "a", newLabel: "renamed")
        #expect(store._renderRevision == before)
        store.rerenderForStyleChange()
        #expect(store._renderRevision == before + 1)
    }

    @MainActor
    @Test("3ω: updateSeriesOrder normalized no-op skips mutation and manifest refresh, and still doesn't self-render")
    func threeOmegaNormalizedNoOpSkipsMutation() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.tabs.activeTab = .fieldSweep1omega
        store.updateSeriesOrder(["/tmp/bottom.csv", "/tmp/top.csv"])
        let orderAfterFirstCommit = store.tabs.state(for: .fieldSweep1omega).seriesOrder

        // Same raw order, re-submitted: normalizes to an identical token list, so
        // the internal `guard fieldSweepSeriesOrder != nextOrder` short-circuit
        // must still fire and skip both the mutation and `_refreshManifestPayloads()`.
        let revisionBefore = store._renderRevision
        store.updateSeriesOrder(["/tmp/bottom.csv", "/tmp/top.csv"])

        #expect(store.tabs.state(for: .fieldSweep1omega).seriesOrder == orderAfterFirstCommit)
        #expect(store._renderRevision == revisionBefore, "no-op guard must still short-circuit before any render dispatch")
    }

    @MainActor
    @Test("3ω: updateSeriesOrder still synchronously refreshes manifest payloads after the render call is stripped")
    func threeOmegaManifestRefreshStillSynchronous() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeThreeOmegaIngestionResult()
        store.cachedInputFiles = ["/tmp/bottom.csv", "/tmp/top.csv"]
        store.tabs.activeTab = .fieldSweep1omega

        store.updateSeriesOrder(["/tmp/top.csv", "/tmp/bottom.csv"])

        let r1 = store.tabs.output(for: .fieldSweep1omega).manifestPayload?.series.compactMap(\.sourceRef)
        let r3 = store.tabs.output(for: .fieldSweep3omega).manifestPayload?.series.compactMap(\.sourceRef)
        #expect(r1 == ["/tmp/top.csv", "/tmp/bottom.csv"], "manifest refresh must not depend on the removed render call")
        #expect(r3 == ["/tmp/top.csv", "/tmp/bottom.csv"])
    }
}
