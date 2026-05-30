import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.7 XY Rotation SelectedHitsSnapshot Consumption — Phase 5C-2.3
///
/// Verifies that XY Rotation runAnalysis(selectedHitsSnapshot:) consumes the
/// run-scoped selected hits from WorkbenchSelectedHitsSnapshot, with documented
/// fallback to cachedSearchResults + selectedSearchResultIDs when the snapshot is nil.
///
/// Observable boundary: the analysis entry guard fires (analysisMessage set, isAnalyzing=false)
/// when no selected hit is found in the source hits array. Tests exploit this boundary
/// to distinguish which source was actually consulted, without running the full async render pipeline.
@Suite("V5.3.7 XY Rotation SelectedHitsSnapshot Consumption")
struct V537XYSearchSnapshotConsumptionTests {

    // MARK: - Fixtures

    private func makeHit(sidecarPath: String, sampleKey: String = "PN31|b|STO|111") -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: "/tmp/\(sidecarPath).lvm",
            sourceFilePath: "/tmp/\(sidecarPath).lvm",
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            workflowCanonicalID: "xyRotation",
            batchID: "PN31",
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: [],
            appliedAt: .distantPast
        )
    }

    private func makeSelectedHitsSnapshot(selectedHits: [WorkflowMeasurementSearchHit]) -> WorkbenchSelectedHitsSnapshot {
        WorkbenchSelectedHitsSnapshot(
            workflowID: .xyRotation,
            queryText: "PN31",
            selectedIDs: Set(selectedHits.map(\.id)),
            selectedHits: selectedHits,
            sourceHitCount: selectedHits.count,
            selectionSource: .canonicalSnapshot
        )
    }

    private func waitUntilAnalysisCompletes(_ store: XYRotationWorkspaceStore, timeoutMS: UInt64 = 500) async {
        let intervalNS: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let isAnalyzing = await MainActor.run { store.isAnalyzing }
            if !isAnalyzing {
                return
            }
            try? await Task.sleep(nanoseconds: intervalNS)
        }
        Issue.record("Timed out waiting for XY analysis to complete.")
    }

    // MARK: - 1. Selected snapshot results used when provided

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot:) uses provided selected hits, not stale cachedSearchResults")
    func selectedSnapshotResultsUsedWhenProvided() async {
        let store = XYRotationWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")
        let stale = makeHit(sidecarPath: "sidecar-stale", sampleKey: "PN33|b|STO|111")

        // Cache contains stale data only; selected snapshot must win.
        store.cachedSearchResults = [stale]
        store.selectedSearchResultIDs = [stale.id]

        // Snapshot carries selected hits in reverse file-path order.
        let snapshot = makeSelectedHitsSnapshot(selectedHits: [hitB, hitA])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        #expect(store.isAnalyzing == true,
                "Expected analysis to start because snapshot contains selected hits")
        #expect(store.analysisMessage == nil,
                "Expected no guard-path message when snapshot provides selected hits")

        await waitUntilAnalysisCompletes(store)

        #expect(store.cachedInputFiles == [hitA.measurementFilePath, hitB.measurementFilePath],
                "Expected measurementFilePath sort order to apply to selected snapshot input")
        #expect(store.cachedSampleKeys == [hitA.sampleKey, hitB.sampleKey],
                "Expected selected snapshot inputs to populate cached sample keys")
    }

    // MARK: - 2. nil selected snapshot falls back to cache

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot: nil) falls back to cachedSearchResults + selectedSearchResultIDs")
    func nilSelectedSnapshotFallsBackToCache() {
        let store = XYRotationWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")

        // Cache contains hitB only — the selected hit (hitA) is absent.
        store.cachedSearchResults = [hitB]
        store.selectedSearchResultIDs = [hitA.id]

        // nil snapshot → must fall back to cachedSearchResults → hitA not found → guard fires.
        store.runAnalysis(selectedHitsSnapshot: nil)

        #expect(store.isAnalyzing == false,
                "Expected guard to fire: nil selected snapshot falls back to stale cache that lacks the selected hit")
        #expect(store.analysisMessage == "No files selected.",
                "Expected guard-path message when cache does not contain the selected hit")
    }

    // MARK: - 3. No-arg runAnalysis() remains legacy-compatible

    @MainActor
    @Test("runAnalysis() still succeeds via cachedSearchResults fallback for pack/restore paths")
    func noArgRunAnalysisRemainsLegacyCompatible() {
        let store = XYRotationWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")

        // Pack-restore path: cache is populated with the selected hit.
        store.cachedSearchResults = [hitA]
        store.selectedSearchResultIDs = [hitA.id]

        // No-arg call (pack restore, legacy) → runAnalysis(searchSnapshot: nil) → cache used → guard passes.
        store.runAnalysis()

        #expect(store.isAnalyzing == true,
                "Expected analysis to start: no-arg runAnalysis() falls back to cache, which has the selected hit")
        #expect(store.analysisMessage == nil,
                "Expected no guard-path message when cache provides the selected hit")
    }

    // MARK: - 4. searchSnapshot compatibility path remains intact

    @MainActor
    @Test("runAnalysis(searchSnapshot:) still succeeds via snapshot fallback path")
    func searchSnapshotCompatibilityRemainsIntact() {
        let store = XYRotationWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let snapshot = WorkbenchSearchSnapshot(
            workflowID: .xyRotation,
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
}
