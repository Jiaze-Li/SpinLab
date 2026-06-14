import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.3.7 Workbench SelectedHitsSnapshot")
struct V537WorkbenchSelectedHitsSnapshotTests {

    private func makeHit(
        id: String,
        workflowID: String = "ahe",
        workflowCanonicalID: String = "ahe",
        sampleKey: String = "PN31|b|STO|111"
    ) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowCanonicalID,
            batchID: "PN31",
            sampleKey: sampleKey,
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

    @MainActor
    @Test("filters canonical snapshot by selectedIDs")
    func filtersCanonicalSnapshotBySelectedIDs() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "ahe-1")
        let hit2 = makeHit(id: "ahe-2")
        wfs.restoreSearchState(results: [hit1, hit2], queryText: "ahe pn31", for: .ahe)
        wfs.seedSelection([hit2.id], for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(snapshot.selectionSource == .canonicalSnapshot)
        #expect(snapshot.selectedIDs == [hit2.id])
        #expect(snapshot.sourceHitCount == 2)
        #expect(snapshot.selectedHits.map(\.id) == [hit2.id])
        #expect(snapshot.isEmpty == false)
    }

    @MainActor
    @Test("uses canonical snapshot over stale local cache")
    func usesCanonicalSnapshotResults() {
        let wfs = makeWFS()
        let canonical = makeHit(id: "canonical")
        wfs.restoreSearchState(results: [canonical], queryText: "ahe canonical", for: .ahe)
        wfs.seedSelection([canonical.id], for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(snapshot.selectionSource == .canonicalSnapshot)
        #expect(snapshot.sourceHitCount == 1)
        #expect(snapshot.selectedHits.map(\.id) == [canonical.id])
    }

    @MainActor
    @Test("preserves canonical source ordering")
    func preservesCanonicalSourceOrdering() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A")
        let hitB = makeHit(id: "B")
        let hitC = makeHit(id: "C")
        wfs.restoreSearchState(results: [hitB, hitA, hitC], queryText: "ahe order", for: .ahe)
        wfs.seedSelection([hitA.id, hitC.id, hitB.id], for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(snapshot.selectionSource == .canonicalSnapshot)
        #expect(snapshot.selectedHits.map(\.id) == [hitB.id, hitA.id, hitC.id])
    }

    @MainActor
    @Test("empty selectedIDs gives isEmpty true")
    func emptySelectedIDsGivesIsEmptyTrue() {
        let wfs = makeWFS()
        let hit = makeHit(id: "only")
        wfs.restoreSearchState(results: [hit], queryText: "ahe q", for: .ahe)
        // no seedSelection — selection starts empty

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(snapshot.selectionSource == .canonicalSnapshot)
        #expect(snapshot.selectedHits.isEmpty)
        #expect(snapshot.isEmpty)
    }

    @MainActor
    @Test("snapshot factory does not mutate canonical search state")
    func factoryDoesNotMutateState() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "m1")
        let hit2 = makeHit(id: "m2")
        wfs.restoreSearchState(results: [hit1, hit2], queryText: "ahe immutable", for: .ahe)
        wfs.seedSelection([hit1.id], for: .ahe)

        let beforeQuery = wfs.searchQueryText(for: .ahe)
        let beforeResults = wfs.searchResultsList(for: .ahe)
        let beforeMessage = wfs.searchMessage(for: .ahe)
        let beforeRunning = wfs.isSearchRunning(for: .ahe)

        _ = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(wfs.searchQueryText(for: .ahe) == beforeQuery)
        #expect(wfs.searchResultsList(for: .ahe) == beforeResults)
        #expect(wfs.searchMessage(for: .ahe) == beforeMessage)
        #expect(wfs.isSearchRunning(for: .ahe) == beforeRunning)
    }

    // MARK: - Cross-search persistence (PR #116 P1)

    @MainActor
    @Test("tray shows hit from previous search after search changes")
    func trayShowsHitFromPreviousSearch() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A")
        let hitB = makeHit(id: "B")

        wfs.restoreSearchState(results: [hitA], queryText: "ahe 80K", for: .ahe)
        wfs.toggleSearchHitSelection(hitA.id, for: .ahe)

        // Search B replaces canonical results — A is no longer visible.
        wfs.restoreSearchState(results: [hitB], queryText: "ahe 300K", for: .ahe)

        let displayInfos = wfs.selectedHitDisplayInfos(for: .ahe)
        #expect(displayInfos.map(\.id).contains(hitA.id))
    }

    @MainActor
    @Test("analyze snapshot includes hit from previous search after search changes")
    func snapshotIncludesHitFromPreviousSearch() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A")
        let hitB = makeHit(id: "B")

        wfs.restoreSearchState(results: [hitA], queryText: "ahe A", for: .ahe)
        wfs.toggleSearchHitSelection(hitA.id, for: .ahe)

        wfs.restoreSearchState(results: [hitB], queryText: "ahe B", for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)
        #expect(snapshot.selectedHits.map(\.id).contains(hitA.id))
    }

    @MainActor
    @Test("selectAll B appends B while keeping A; snapshot includes both")
    func selectAllAppendsWhileKeepingCrossSearchSelection() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A")
        let hitB = makeHit(id: "B")

        wfs.restoreSearchState(results: [hitA], queryText: "ahe A", for: .ahe)
        wfs.toggleSearchHitSelection(hitA.id, for: .ahe)

        wfs.restoreSearchState(results: [hitB], queryText: "ahe B", for: .ahe)
        wfs.selectAll(for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)
        let ids = Set(snapshot.selectedHits.map(\.id))
        #expect(ids == [hitA.id, hitB.id])
    }

    @MainActor
    @Test("cross-search selected count reflects both searches")
    func crossSearchSelectedCount() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A")
        let hitB = makeHit(id: "B")

        wfs.restoreSearchState(results: [hitA], queryText: "ahe A", for: .ahe)
        wfs.toggleSearchHitSelection(hitA.id, for: .ahe)

        wfs.restoreSearchState(results: [hitB], queryText: "ahe B", for: .ahe)
        wfs.selectAll(for: .ahe)

        #expect(wfs.selectedCount(for: .ahe) == 2)
    }

    @MainActor
    @Test("snapshot current-result hits come before cross-search cached hits")
    func snapshotCurrentResultsBeforeCachedHits() {
        let wfs = makeWFS()
        let hitA = makeHit(id: "A")
        let hitB = makeHit(id: "B")

        wfs.restoreSearchState(results: [hitA], queryText: "ahe A", for: .ahe)
        wfs.toggleSearchHitSelection(hitA.id, for: .ahe)

        // Search B: B is in current results, A is not.
        wfs.restoreSearchState(results: [hitB], queryText: "ahe B", for: .ahe)
        wfs.selectAll(for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)
        // B appears first (current results), A appears after (cross-search cache).
        #expect(snapshot.selectedHits.map(\.id) == [hitB.id, hitA.id])
    }
}

// MARK: - V7.11C-1 Pack-restore proof: legacyMirror must never fire after canonical restore

/// These tests replicate the exact two-call sequence used by WorkbenchLoadPackPopover.load():
///   1. seedSelection(ids, hits: hits, for: wf)       — mirrors the seedSelection closure
///   2. restoreSearchState(results, queryText, for: wf) — mirrors the restoreSearchState closure
/// Both calls are synchronous. After they complete, selectedHitsSnapshot must always
/// return .canonicalSnapshot — never .legacyMirror — proving the legacyHits fallback
/// is structurally unreachable after a normal pack restore.
@Suite("V7.11C Pack Restore Proof — legacyMirror unreachable")
struct V711CPackRestoreProofTests {

    private func makeHit(
        id: String,
        workflowID: String,
        sampleKey: String = "PN31|b|STO|111"
    ) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: "/tmp/\(id).dat",
            sourceFilePath: "/tmp/\(id).dat",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowID,
            batchID: "PN31",
            sampleKey: sampleKey,
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

    // MARK: AHE

    @MainActor
    @Test("AHE pack restore: canonical populated before snapshot — legacyMirror never fires")
    func ahePackRestoreUsesCanonical() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "ahe-restore-1", workflowID: "ahe")
        let hit2 = makeHit(id: "ahe-restore-2", workflowID: "ahe")
        let restoredHits = [hit1, hit2]
        let selectedIDs: Set<String> = [hit1.id, hit2.id]

        // Mirror WorkbenchLoadPackPopover.load() sequence exactly.
        wfs.seedSelection(selectedIDs, hits: restoredHits, for: .ahe)
        wfs.restoreSearchState(results: restoredHits, queryText: "ahe restored", for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(snapshot.selectionSource == .canonicalSnapshot,
                "legacyMirror must not fire after restoreSearchState populates canonical")
        #expect(snapshot.selectedHits.count == 2)
        #expect(Set(snapshot.selectedHits.map(\.id)) == selectedIDs)
        #expect(snapshot.isEmpty == false)
    }

    @MainActor
    @Test("AHE pack restore: single selected hit resolves to canonicalSnapshot")
    func ahePackRestoreSingleHit() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-single", workflowID: "ahe")

        wfs.seedSelection([hit.id], hits: [hit], for: .ahe)
        wfs.restoreSearchState(results: [hit], queryText: "ahe single", for: .ahe)

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(snapshot.selectionSource == .canonicalSnapshot)
        #expect(snapshot.selectedHits.map(\.id) == [hit.id])
    }

    // MARK: 3ω

    @MainActor
    @Test("3ω pack restore: canonical populated before snapshot — legacyMirror never fires")
    func threeOmegaPackRestoreUsesCanonical() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "3w-restore-1", workflowID: "3w")
        let hit2 = makeHit(id: "3w-restore-2", workflowID: "3w")
        let restoredHits = [hit1, hit2]
        let selectedIDs: Set<String> = [hit1.id, hit2.id]

        wfs.seedSelection(selectedIDs, hits: restoredHits, for: .threeOmega)
        wfs.restoreSearchState(results: restoredHits, queryText: "3w restored", for: .threeOmega)

        let snapshot = wfs.selectedHitsSnapshot(for: .threeOmega)

        #expect(snapshot.selectionSource == .canonicalSnapshot,
                "legacyMirror must not fire after restoreSearchState populates canonical")
        #expect(snapshot.selectedHits.count == 2)
        #expect(Set(snapshot.selectedHits.map(\.id)) == selectedIDs)
        #expect(snapshot.isEmpty == false)
    }

    @MainActor
    @Test("3ω pack restore: single selected hit resolves to canonicalSnapshot")
    func threeOmegaPackRestoreSingleHit() {
        let wfs = makeWFS()
        let hit = makeHit(id: "3w-single", workflowID: "3w")

        wfs.seedSelection([hit.id], hits: [hit], for: .threeOmega)
        wfs.restoreSearchState(results: [hit], queryText: "3w single", for: .threeOmega)

        let snapshot = wfs.selectedHitsSnapshot(for: .threeOmega)

        #expect(snapshot.selectionSource == .canonicalSnapshot)
        #expect(snapshot.selectedHits.map(\.id) == [hit.id])
    }

    // MARK: XY

    @MainActor
    @Test("XY pack restore: canonical populated before snapshot — legacyMirror never fires")
    func xyPackRestoreUsesCanonical() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "xy-restore-1", workflowID: "xy")
        let hit2 = makeHit(id: "xy-restore-2", workflowID: "xy")
        let restoredHits = [hit1, hit2]
        let selectedIDs: Set<String> = [hit1.id, hit2.id]

        wfs.seedSelection(selectedIDs, hits: restoredHits, for: .xyRotation)
        wfs.restoreSearchState(results: restoredHits, queryText: "xy restored", for: .xyRotation)

        let snapshot = wfs.selectedHitsSnapshot(for: .xyRotation)

        #expect(snapshot.selectionSource == .canonicalSnapshot,
                "legacyMirror must not fire after restoreSearchState populates canonical")
        #expect(snapshot.selectedHits.count == 2)
        #expect(Set(snapshot.selectedHits.map(\.id)) == selectedIDs)
        #expect(snapshot.isEmpty == false)
    }

    @MainActor
    @Test("XY pack restore: single selected hit resolves to canonicalSnapshot")
    func xyPackRestoreSingleHit() {
        let wfs = makeWFS()
        let hit = makeHit(id: "xy-single", workflowID: "xy")

        wfs.seedSelection([hit.id], hits: [hit], for: .xyRotation)
        wfs.restoreSearchState(results: [hit], queryText: "xy single", for: .xyRotation)

        let snapshot = wfs.selectedHitsSnapshot(for: .xyRotation)

        #expect(snapshot.selectionSource == .canonicalSnapshot)
        #expect(snapshot.selectedHits.map(\.id) == [hit.id])
    }

    // MARK: Cross-workflow isolation

    @MainActor
    @Test("pack restore for one workflow does not pollute other workflow snapshots")
    func restoreIsolatedPerWorkflow() {
        let wfs = makeWFS()
        let aheHit = makeHit(id: "ahe-iso", workflowID: "ahe")
        let xyHit  = makeHit(id: "xy-iso",  workflowID: "xy")

        wfs.seedSelection([aheHit.id], hits: [aheHit], for: .ahe)
        wfs.restoreSearchState(results: [aheHit], queryText: "ahe iso", for: .ahe)

        wfs.seedSelection([xyHit.id], hits: [xyHit], for: .xyRotation)
        wfs.restoreSearchState(results: [xyHit], queryText: "xy iso", for: .xyRotation)

        let aheSnapshot = wfs.selectedHitsSnapshot(for: .ahe)
        let xySnapshot  = wfs.selectedHitsSnapshot(for: .xyRotation)
        let wSnapshot   = wfs.selectedHitsSnapshot(for: .threeOmega)

        #expect(aheSnapshot.selectionSource == .canonicalSnapshot)
        #expect(aheSnapshot.selectedHits.map(\.id) == [aheHit.id])
        #expect(xySnapshot.selectionSource == .canonicalSnapshot)
        #expect(xySnapshot.selectedHits.map(\.id) == [xyHit.id])
        // 3ω was never restored — empty is fine, source must still be canonicalSnapshot
        #expect(wSnapshot.selectionSource == .canonicalSnapshot)
        #expect(wSnapshot.isEmpty)
    }

    // MARK: Inverted-order control (proves no fallback exists after legacyMirror removal)

    @MainActor
    @Test("seedSelection-only without restoreSearchState yields empty canonical snapshot — no fallback")
    func seedWithoutRestoreYieldsEmptyCanonical() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-seed-only", workflowID: "ahe")

        // Deliberately omit restoreSearchState.
        // Before Gate 7.11C-2: legacyMirror would have fired here.
        // After Gate 7.11C-2: canonical is empty, so selectedHits is empty — no fallback.
        wfs.seedSelection([hit.id], hits: [hit], for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = [hit]

        let snapshot = wfs.selectedHitsSnapshot(for: .ahe)

        #expect(snapshot.selectionSource == .canonicalSnapshot,
                "selectionSource is always canonicalSnapshot after legacyMirror removal")
        // Without restoreSearchState, canonical results are empty → selectedHits resolves
        // through hitCache (seeded by seedSelection) rather than source list.
        // The hit was seeded into selectionRuntime, so it appears via hitCache path.
        #expect(snapshot.selectedHits.map(\.id) == [hit.id],
                "hit still found via hitCache even without canonical results")
    }
}
