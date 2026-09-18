import Foundation
import Testing
@testable import SpinLabApp

/// Phase 1A (AFM common architecture gate) — generic single-selection workflow semantics.
///
/// RSM is the only workflow wired to `.single` today (AFM joins it once registered). These
/// tests exercise the policy entirely through the shared `WorkbenchFeatureStore` facade, so
/// they also cover AFM automatically once `WorkbenchWorkflowKind.selectionMode` grows an
/// `.afm -> .single` case.
@Suite("Single-selection workflow semantics")
struct WorkbenchSingleSelectionModeTests {

    private func makeHit(id: String, workflowID: String) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowID,
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    @MainActor
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    // MARK: - Replacement A -> B

    @MainActor
    @Test("selecting B while A is selected replaces A, basket stays at 1")
    func singleSelectionReplacesPreviousHit() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "rsm-A", workflowID: "rsm")
        let hitB = makeHit(id: "rsm-B", workflowID: "rsm")
        wfs.restoreSearchState(results: [hitA, hitB], queryText: "q", for: .rsm)

        wfs.toggleSearchHitSelection(hitA.id, for: .rsm)
        #expect(wfs.selectedSearchResultIDs(for: .rsm) == [hitA.id])

        wfs.toggleSearchHitSelection(hitB.id, for: .rsm)
        #expect(wfs.selectedSearchResultIDs(for: .rsm) == [hitB.id],
                "selecting a second hit must replace, not add to, a single-selection basket")
        #expect(wfs.basketSelectedCount(for: .rsm) == 1)
    }

    // MARK: - Deselect current

    @MainActor
    @Test("clicking the currently selected hit again deselects it")
    func singleSelectionTogglesOff() {
        let wfs = makeWFS()
        let hit = makeHit(id: "rsm-A", workflowID: "rsm")
        wfs.restoreSearchState(results: [hit], queryText: "q", for: .rsm)

        wfs.toggleSearchHitSelection(hit.id, for: .rsm)
        #expect(wfs.basketSelectedCount(for: .rsm) == 1)

        wfs.toggleSearchHitSelection(hit.id, for: .rsm)
        #expect(wfs.basketSelectedCount(for: .rsm) == 0)
        #expect(wfs.selectedSearchResultIDs(for: .rsm).isEmpty)
    }

    // MARK: - Select All is not actionable

    @MainActor
    @Test("selectAll is a no-op for single-selection workflows")
    func selectAllIsNoOpForSingleSelection() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "rsm-A", workflowID: "rsm")
        let hitB = makeHit(id: "rsm-B", workflowID: "rsm")
        wfs.restoreSearchState(results: [hitA, hitB], queryText: "q", for: .rsm)

        wfs.selectAll(for: .rsm)
        #expect(wfs.basketSelectedCount(for: .rsm) == 0,
                "selectAll must not populate a single-selection basket")
    }

    @MainActor
    @Test("selectionMode reports .single for RSM")
    func selectionModeIsSingleForRSM() {
        let wfs = makeWFS()
        #expect(wfs.selectionMode(for: .rsm) == .single)
    }

    // MARK: - Multi-select workflows unchanged

    @MainActor
    @Test("selecting a second hit for a multi-select workflow adds to the basket")
    func multiSelectionUnchanged() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "ahe-A", workflowID: "ahe")
        let hitB = makeHit(id: "ahe-B", workflowID: "ahe")
        wfs.restoreSearchState(results: [hitA, hitB], queryText: "q", for: .ahe)

        wfs.toggleSearchHitSelection(hitA.id, for: .ahe)
        wfs.toggleSearchHitSelection(hitB.id, for: .ahe)
        #expect(wfs.basketSelectedCount(for: .ahe) == 2)
        #expect(wfs.selectionMode(for: .ahe) == .multiple)

        wfs.selectAll(for: .ahe)
        #expect(wfs.isAllSelected(for: .ahe))
    }

    // MARK: - Legacy restore with >1 persisted ID resolves deterministically

    @MainActor
    @Test("seedRestoredSelection caps a legacy multi-ID RSM pack to exactly one deterministic winner")
    func legacyMultiIDRestoreResolvesDeterministically() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "rsm-A", workflowID: "rsm")
        let hitB = makeHit(id: "rsm-B", workflowID: "rsm")

        wfs.seedRestoredSelection([hitA.id, hitB.id], availableHits: [hitA, hitB], for: .rsm)

        let restored = wfs.selectedSearchResultIDs(for: .rsm)
        #expect(restored.count == 1, "single-selection restore must never keep more than one hit")
        #expect(restored == [hitA.id], "winner must be the lexicographically-first ID, not Set iteration order")
    }

    @MainActor
    @Test("seedRestoredSelection deterministic winner is stable across repeated calls")
    func legacyMultiIDRestoreIsStableAcrossCalls() {
        let hitA = makeHit(id: "rsm-A", workflowID: "rsm")
        let hitB = makeHit(id: "rsm-B", workflowID: "rsm")
        var winners: Set<String> = []
        for _ in 0..<5 {
            let wfs = makeWFS()
            wfs.seedRestoredSelection([hitA.id, hitB.id], availableHits: [hitA, hitB], for: .rsm)
            winners.formUnion(wfs.selectedSearchResultIDs(for: .rsm))
        }
        #expect(winners == [hitA.id], "the resolved winner must not vary run to run")
    }

    @MainActor
    @Test("seedSelection also caps a programmatically-seeded multi-ID single-selection basket")
    func seedSelectionCapsSingleSelectionBasket() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "rsm-A", workflowID: "rsm")
        let hitB = makeHit(id: "rsm-B", workflowID: "rsm")

        wfs.seedSelection([hitA.id, hitB.id], hits: [hitA, hitB], for: .rsm)

        #expect(wfs.selectedSearchResultIDs(for: .rsm).count == 1)
    }

    // MARK: - RSM defensively rejects a structurally-impossible >1 hit snapshot

    @MainActor
    @Test("RSMWorkspaceStore.runAnalysis rejects a >1-hit snapshot instead of silently using .first")
    func rsmRunAnalysisRejectsMultiHitSnapshot() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        let hitA = makeHit(id: "rsm-A", workflowID: "rsm")
        let hitB = makeHit(id: "rsm-B", workflowID: "rsm")
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: "rsm",
            queryText: "",
            selectedIDs: [hitA.id, hitB.id],
            selectedHits: [hitA, hitB],
            sourceHitCount: 2,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)

        #expect(store.analysisMessage != nil, "a >1-hit snapshot must produce a rejection message, not a silent .first analysis")
        #expect(!store.isAnalyzing, "analysis must not have started for a rejected snapshot")
    }

    @MainActor
    @Test("RSMWorkspaceStore.runAnalysis treats zero selected hits as the normal empty-selection state")
    func rsmRunAnalysisZeroHitsIsNormalEmptyState() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        let snapshot = WorkbenchSelectedHitsSnapshot(
            workflowID: "rsm",
            queryText: "",
            selectedIDs: [],
            selectedHits: [],
            sourceHitCount: 0,
            selectionSource: .canonicalSnapshot
        )

        store.runAnalysis(selectedHitsSnapshot: snapshot)

        #expect(store.analysisMessage == "No files selected.")
    }
}
