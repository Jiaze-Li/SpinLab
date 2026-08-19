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

    /// Awaits the real `analysisTask` launched by `runAnalysis` directly, rather than
    /// polling `isAnalyzing` against a fixed deadline. Under full-suite parallel load the
    /// detached analysis work can legitimately take longer than any fixed timeout budget,
    /// which made the polling version flake; awaiting the actual Task handle has no
    /// timeout to outrun and is deterministic regardless of system load.
    private func waitUntilAnalysisCompletes(_ store: XYRotationWorkspaceStore) async {
        await store.analysisTask?.value
    }

    // MARK: - 1. Selected snapshot results used when provided

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot:) uses provided selected hits, not stale cachedSearchResults")
    func selectedSnapshotResultsUsedWhenProvided() async {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")
        let stale = makeHit(sidecarPath: "sidecar-stale", sampleKey: "PN33|b|STO|111")

        // Cache contains stale data only; selected snapshot must win.
        store.cachedSearchResults = [stale]

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

    // MARK: - 2. Empty snapshot never falls back to live cache
    //
    // Phase 5C-2: runAnalysis(selectedHitsSnapshot:) is now the sole, non-optional Analyze
    // entry point — there is no more nil-snapshot / no-arg / searchSnapshot: live-state
    // fallback path. An empty snapshot must fire the guard even when cachedSearchResults
    // would otherwise resolve a hit; the run must not reach past the snapshot it was handed.

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot:) with an empty snapshot fires the guard, ignoring cachedSearchResults")
    func emptySelectedSnapshotNeverFallsBackToCache() {
        let store = XYRotationWorkspaceStore(workflowID: WorkflowKey.xyRotation.rawValue)

        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")

        // Cache contains hitB, but the snapshot handed to runAnalysis carries no hits.
        store.cachedSearchResults = [hitB]

        let emptySnapshot = makeSelectedHitsSnapshot(selectedHits: [])
        store.runAnalysis(selectedHitsSnapshot: emptySnapshot)

        #expect(store.isAnalyzing == false,
                "Expected guard to fire: empty snapshot must not fall back to cachedSearchResults")
        #expect(store.analysisMessage == "No files selected.",
                "Expected guard-path message when the snapshot itself has no selected hits")
    }
}
