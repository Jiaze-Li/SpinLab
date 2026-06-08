import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.7 AHE SearchSnapshot Consumption — Phase 5A-3.3
///
/// Verifies that AHE runAnalysis(selectedHitsSnapshot:) consumes run-scoped selected
/// hits from WorkbenchSelectedHitsSnapshot, with a documented fallback to
/// cachedSearchResults when snapshot is nil (pack/restore paths).
///
/// Observable boundary: the analysis entry guard fires (plotMessage set, isPlotRendering=false)
/// when no selected hit is found in the source hits array. Tests exploit this boundary
/// to distinguish which source (selected snapshot vs cache) was actually consulted, without
/// running the full async render pipeline.
@Suite("V5.3.7 AHE SearchSnapshot Consumption")
struct V537AHESearchSnapshotConsumptionTests {

    // MARK: - Fixtures

    private func makeHit(sidecarPath: String, sampleKey: String = "PN31|b|STO|111") -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: "/tmp/\(sidecarPath).dat",
            sourceFilePath: "/tmp/\(sidecarPath).dat",
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe",
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
            workflowID: .ahe,
            queryText: "PN31",
            selectedIDs: Set(selectedHits.map(\.id)),
            selectedHits: selectedHits,
            sourceHitCount: selectedHits.count,
            selectionSource: .canonicalSnapshot
        )
    }

    // MARK: - 1. Selected snapshot hits used when provided

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot:) uses provided selected hits, not stale cachedSearchResults")
    func snapshotResultsUsedWhenProvided() {
        let store = AHEWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")

        // Cache contains hitB only (stale — does NOT include the selected hit)
        store.cachedSearchResults = [hitB]

        // Selected snapshot carries hitA (canonical shell selected-hit surface)
        let snapshot = makeSelectedHitsSnapshot(selectedHits: [hitA])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        // Guard must have passed: hitA found via snapshot → analysis launched
        #expect(store.isPlotRendering == true,
                "Expected analysis to start because selected snapshot contains the selected hit")
        #expect(store.plotMessage == nil,
                "Expected no guard-path message when selected snapshot provides the selected hit")
    }

    // MARK: - 2. selected snapshot path ignores stale cache

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot:) ignores stale cachedSearchResults")
    func selectedSnapshotIgnoresStaleCache() {
        let store = AHEWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")

        // Cache contains hitB only — the selected hit (hitA) is absent
        store.cachedSearchResults = [hitB]

        // Selected snapshot contains hitA, stale cache must be ignored.
        let snapshot = makeSelectedHitsSnapshot(selectedHits: [hitA])
        store.runAnalysis(selectedHitsSnapshot: snapshot)

        #expect(store.isPlotRendering == true,
                "Expected analysis to start: selected snapshot path must ignore stale cache")
        #expect(store.plotMessage == nil,
                "Expected no guard-path message when selected snapshot provides the selected hit")
    }

    // MARK: - 3. nil selected snapshot falls back to cache

    @MainActor
    @Test("runAnalysis(selectedHitsSnapshot: nil) falls back to cachedSearchResults")
    func nilSelectedSnapshotFallsBackToCache() {
        let store = AHEWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        let hitB = makeHit(sidecarPath: "sidecar-B", sampleKey: "PN32|b|STO|111")

        // Simulate WFS: selectionReader says hitA is selected.
        store.selectionReader = { [hitA.id] }
        // Cache contains hitB only — the selected hit (hitA) is absent.
        store.cachedSearchResults = [hitB]

        // nil selected snapshot -> fallback to cache + selectionReader -> hitA not in cache -> guard fires
        store.runAnalysis(selectedHitsSnapshot: nil)

        #expect(store.isPlotRendering == false,
                "Expected guard to fire: nil selected snapshot falls back to stale cache")
        #expect(store.plotMessage == "Select at least one AHE measurement to plot.",
                "Expected guard-path message when fallback cache lacks selected hit")
    }

    // MARK: - 4. No-arg runAnalysis() remains legacy-compatible

    @MainActor
    @Test("runAnalysis() still succeeds via cachedSearchResults fallback for pack/restore paths")
    func noArgRunAnalysisRemainsLegacyCompatible() {
        let store = AHEWorkspaceStore()

        let hitA = makeHit(sidecarPath: "sidecar-A", sampleKey: "PN31|b|STO|111")
        store.cachedSearchResults = [hitA]
        store.runAnalysis()

        #expect(store.isPlotRendering == true,
                "Expected analysis to start: no-arg runAnalysis() uses cached fallback")
        #expect(store.plotMessage == nil,
                "Expected no guard-path message when cache contains selected hit")
    }
}
