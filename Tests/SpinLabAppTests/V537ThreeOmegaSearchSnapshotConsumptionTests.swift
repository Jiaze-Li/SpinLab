import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.7 3ω SearchSnapshot Consumption — Phase 5A-3.5
///
/// Verifies that 3ω runAnalysis(selectedHitsSnapshot:) consumes the run-scoped
/// selected hits from WorkbenchSelectedHitsSnapshot, with documented fallback
/// to cachedSearchResults + selectedSearchResultIDs when the snapshot is nil
/// (pack/restore paths and legacy call sites).
///
/// Observable boundary: the analysis entry guard fires (analysisMessage set, isAnalyzing=false)
/// when no selected hit is found in the source hits array. Tests exploit this boundary
/// to distinguish which source (snapshot vs cache) was actually consulted, without
/// running the full async render pipeline.
@Suite("V5.3.7 3ω SearchSnapshot Consumption")
struct V537ThreeOmegaSearchSnapshotConsumptionTests {

    // MARK: - Fixtures

    private func makeHit(sidecarPath: String, sampleKey: String = "PN31|b|STO|111") -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: "/tmp/\(sidecarPath).lvm",
            sourceFilePath: "/tmp/\(sidecarPath).lvm",
            workflowID: "3w",
            workflowDisplayName: "3ω",
            workflowCanonicalID: "3w",
            batchID: "PN31",
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    private func makeSelectedHitsSnapshot(selectedHits: [WorkflowMeasurementSearchHit]) -> WorkbenchSelectedHitsSnapshot {
        WorkbenchSelectedHitsSnapshot(
            workflowID: .threeOmega,
            queryText: "PN31",
            selectedIDs: Set(selectedHits.map(\.id)),
            selectedHits: selectedHits,
            sourceHitCount: selectedHits.count,
            selectionSource: .canonicalSnapshot
        )
    }

    private func waitUntilAnalysisCompletes(_ store: ThreeOmegaWorkspaceStore, timeoutMS: UInt64 = 60000) async {
        let intervalNS: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let isAnalyzing = await MainActor.run { store.isAnalyzing }
            if !isAnalyzing { return }
            try? await Task.sleep(nanoseconds: intervalNS)
        }
        Issue.record("Timed out waiting for 3ω analysis to complete.")
    }

    // MARK: - 1. Selected snapshot results used when provided

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot:) uses provided selected hits, not stale cachedSearchResults")
    func selectedSnapshotResultsUsedWhenProvided() async {
        let store = ThreeOmegaWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")
        let stale = makeHit(sidecarPath: "sidecar-stale", sampleKey: "PN33|b|STO|111")

        // Cache contains stale data only; selected snapshot must win.
        store.cachedSearchResults = [stale]
        store.selectedSearchResultIDs = [stale.id]
        store.selectedRTHit = hitB
        store.rtQuery = "PN31 RT"

        // Snapshot carries selected hits in reverse file-path order.
        let snapshot = makeSelectedHitsSnapshot(selectedHits: [hitB, hitA])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        // Guard must have passed: snapshot provided the selected hits → analysis launched
        #expect(store.isAnalyzing == true,
                "Expected analysis to start because selected snapshot contains the selected hits")
        #expect(store.analysisMessage == nil,
                "Expected no guard-path message when selected snapshot provides the selected hits")

        await waitUntilAnalysisCompletes(store)

        #expect(store.cachedInputFiles == [hitA.measurementFilePath, hitB.measurementFilePath],
                "Expected measurementFilePath sorting to apply to selected snapshot input")
        #expect(store.cachedSampleKeys == [hitA.sampleKey, hitB.sampleKey],
                "Expected manifest/cache snapshot to use the same sorted selected hits as analysis")
        #expect(store.cachedRTFilePath == hitB.measurementFilePath,
                "Expected RT secondary selection to remain independent and unchanged")
    }

    // MARK: - 2. Stale cache is ignored when selected snapshot is provided

    @MainActor
    @Test("stale cachedSearchResults are ignored when selectedHitsSnapshot is provided")
    func staleCacheIgnoredWhenSelectedSnapshotProvided() async {
        let store = ThreeOmegaWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let stale = makeHit(sidecarPath: "sidecar-stale", sampleKey: "PN32|b|STO|111")

        // Cache is intentionally stale and does not match the selected snapshot.
        store.cachedSearchResults = [stale]
        store.selectedSearchResultIDs = [stale.id]

        let snapshot = makeSelectedHitsSnapshot(selectedHits: [hitA])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        #expect(store.isAnalyzing == true,
                "Expected analysis to start because selected snapshot bypasses stale cache")
        #expect(store.analysisMessage == nil,
                "Expected no guard-path message when selected snapshot provides the selected hit")

        await waitUntilAnalysisCompletes(store)

        #expect(store.cachedInputFiles == [hitA.measurementFilePath],
                "Expected stale cachedSearchResults to be ignored by the analysis input")
        #expect(store.cachedSampleKeys == [hitA.sampleKey],
                "Expected manifest/cache snapshot to reflect only the snapshot-selected hit")
    }

    // MARK: - 3. nil snapshot falls back to cache

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot: nil) falls back to cachedSearchResults + selectedSearchResultIDs")
    func nilSelectedSnapshotFallsBackToCache() {
        let store = ThreeOmegaWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")

        // Cache contains hitB only — the selected hit (hitA) is absent.
        store.cachedSearchResults = [hitB]
        store.selectedSearchResultIDs = [hitA.id]

        // nil snapshot -> fallback to cache -> hitA missing -> guard fires.
        store.runAnalysis(selectedHitsSnapshot: nil)

        #expect(store.isAnalyzing == false,
                "Expected guard to fire: nil selected snapshot falls back to stale cache")
        #expect(store.analysisMessage == "Select at least one 3w measurement file.",
                "Expected guard-path message when fallback cache lacks the selected hit")
    }

    // MARK: - 4. No-arg runAnalysis() remains legacy-compatible

    @MainActor
    @Test("runAnalysis() still succeeds via cachedSearchResults fallback for pack/restore paths")
    func noArgRunAnalysisRemainsLegacyCompatible() {
        let store = ThreeOmegaWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")

        // Pack-restore path: cache is populated with the selected hit.
        store.cachedSearchResults = [hitA]
        store.selectedSearchResultIDs = [hitA.id]

        store.runAnalysis()

        #expect(store.isAnalyzing == true,
                "Expected analysis to start: no-arg runAnalysis() falls back to cache, which has the selected hit")
        #expect(store.analysisMessage == nil,
                "Expected no guard-path message when cache provides the selected hit")
    }

    // MARK: - 5. searchSnapshot compatibility path remains intact

    @MainActor
    @Test("runAnalysis(searchSnapshot:) still succeeds via snapshot fallback path")
    func searchSnapshotCompatibilityRemainsIntact() {
        let store = ThreeOmegaWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let snapshot = WorkbenchSearchSnapshot(
            workflowID: .threeOmega,
            queryText: "PN31",
            results: [hitA],
            isRunning: false,
            message: nil
        )

        store.cachedSearchResults = []
        store.selectedSearchResultIDs = [hitA.id]
        store.runAnalysis(searchSnapshot: snapshot)

        #expect(store.isAnalyzing == true,
                "Expected analysis to start because the search snapshot contains the selected hit")
        #expect(store.analysisMessage == nil,
                "Expected no guard-path message when the search snapshot provides the selected hit")
    }

    // MARK: - 6. RT secondary search state unaffected

    @MainActor
    @Test("RT secondary search state is not modified by runAnalysis(searchSnapshot:)")
    func rtSearchStateUnaffected() {
        let store = ThreeOmegaWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let rtHit = makeHit(sidecarPath: "sidecar-RT", sampleKey: "PN31|b|STO|111")

        store.cachedSearchResults = [hitA]
        store.selectedSearchResultIDs = [hitA.id]
        store.selectedRTHit = rtHit
        store.rtQuery = "PN31 RT"

        let snapshot = WorkbenchSearchSnapshot(
            workflowID: .threeOmega,
            queryText: "PN31",
            results: [hitA],
            isRunning: false,
            message: nil
        )
        store.runAnalysis(searchSnapshot: snapshot)

        // RT state must survive analysis launch
        #expect(store.selectedRTHit?.id == rtHit.id,
                "Expected selectedRTHit to be unchanged by runAnalysis")
        #expect(store.rtQuery == "PN31 RT",
                "Expected rtQuery to be unchanged by runAnalysis")
    }
}
