import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.7 Search Mirror Boundary — Phase 5A-3.1
///
/// Documents and locks the current two-copy search state model while the bridge exists:
///   - canonical owner: WorkbenchFeatureStore.searchResults[workflowID]
///   - workflow-local mirror: {workflow}WorkspaceStore.cachedSearchResults
///
/// Invariants locked here:
///   1. clearWorkflowMeasurementSearch clears BOTH copies for AHE / XY / 3ω.
///   2. workflow-local clearResults() clears only the local copy — WFS canonical is untouched.
///      This documents that clearResults is NOT the canonical SearchShell reset.
///   3. restoreSearchState keeps WFS canonical and local copy consistent for XY and 3ω.
///   4. isAllSelected reads workflow-local cachedSearchResults as the denominator, not WFS canonical.
///   5. searchResultsList(for:) reads from WFS canonical, not the workflow-local copy.
///
/// When cachedSearchResults is eventually removed, tests 1–3 simplify (single source) and
/// tests 4–5 collapse (same source for both). Until then these tests are regression gates.
@Suite("V5.3.7 Workbench Search Mirror Boundary")
struct V537WorkbenchSearchMirrorTests {

    // MARK: - Helpers

    private func makeHit(
        id: String = "hit-1",
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
        return WorkbenchFeatureStore(
            libraryRepository: LibraryRepository(persistence: persistence)
        )
    }

    // MARK: - 1. clearWorkflowMeasurementSearch clears BOTH copies

    @MainActor
    @Test("clearWorkflowMeasurementSearch clears WFS canonical AND AHE local cache")
    func clearSearchClearsBothCopiesForAHE() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "ahe-clear", workflowID: "ahe", workflowCanonicalID: "ahe")]

        wfs.restoreSearchState(results: hits, queryText: "ahe pn31", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = hits

        #expect(wfs.searchResultsList(for: .ahe).count == 1)
        #expect(wfs.aheWorkspace.cachedSearchResults.count == 1)

        wfs.clearWorkflowMeasurementSearch(workflowID: .ahe)

        #expect(wfs.searchResultsList(for: .ahe).isEmpty,
                "WFS canonical must be empty after clearWorkflowMeasurementSearch")
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty,
                "AHE local cache must be empty after clearWorkflowMeasurementSearch")
    }

    @MainActor
    @Test("clearWorkflowMeasurementSearch clears WFS canonical AND XY local cache")
    func clearSearchClearsBothCopiesForXY() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "xy-clear", workflowID: "xy", workflowCanonicalID: "xyRotation")]

        wfs.restoreSearchState(results: hits, queryText: "xy pn31", for: .xyRotation)
        wfs.xyRotationWorkspace.cachedSearchResults = hits

        #expect(wfs.searchResultsList(for: .xyRotation).count == 1)
        #expect(wfs.xyRotationWorkspace.cachedSearchResults.count == 1)

        wfs.clearWorkflowMeasurementSearch(workflowID: .xyRotation)

        #expect(wfs.searchResultsList(for: .xyRotation).isEmpty,
                "WFS canonical must be empty after clearWorkflowMeasurementSearch")
        #expect(wfs.xyRotationWorkspace.cachedSearchResults.isEmpty,
                "XY local cache must be empty after clearWorkflowMeasurementSearch")
    }

    @MainActor
    @Test("clearWorkflowMeasurementSearch clears WFS canonical AND 3ω local cache")
    func clearSearchClearsBothCopiesForThreeOmega() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "3w-clear", workflowID: "3w", workflowCanonicalID: "threeOmega")]

        wfs.restoreSearchState(results: hits, queryText: "3w pn31", for: .threeOmega)
        wfs.threeOmegaWorkspace.cachedSearchResults = hits

        #expect(wfs.searchResultsList(for: .threeOmega).count == 1)
        #expect(wfs.threeOmegaWorkspace.cachedSearchResults.count == 1)

        wfs.clearWorkflowMeasurementSearch(workflowID: .threeOmega)

        #expect(wfs.searchResultsList(for: .threeOmega).isEmpty,
                "WFS canonical must be empty after clearWorkflowMeasurementSearch")
        #expect(wfs.threeOmegaWorkspace.cachedSearchResults.isEmpty,
                "3ω local cache must be empty after clearWorkflowMeasurementSearch")
    }

    // MARK: - 2. clearResults() alone does NOT clear WFS canonical

    /// clearResults() is workflow-local cleanup: it clears the local cache and selection,
    /// but leaves WFS canonical searchResults untouched. It is NOT the canonical SearchShell
    /// reset — that is clearWorkflowMeasurementSearch. The UI "Clear" button calls both.
    @MainActor
    @Test("AHE clearResults alone clears local cache but leaves WFS canonical intact")
    func aheLocalClearResultsDoesNotClearWFSCanonical() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "ahe-local-clear")]

        wfs.restoreSearchState(results: hits, queryText: "ahe pn31", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = hits

        wfs.aheWorkspace.clearResults()

        #expect(wfs.searchResultsList(for: .ahe).count == 1,
                "WFS canonical must NOT be cleared by workflow-local clearResults()")
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty,
                "AHE local cache IS cleared by clearResults()")
    }

    @MainActor
    @Test("XY clearResults alone clears local cache but leaves WFS canonical intact")
    func xyLocalClearResultsDoesNotClearWFSCanonical() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "xy-local-clear", workflowID: "xy", workflowCanonicalID: "xyRotation")]

        wfs.restoreSearchState(results: hits, queryText: "xy pn31", for: .xyRotation)
        wfs.xyRotationWorkspace.cachedSearchResults = hits

        wfs.xyRotationWorkspace.clearResults()

        #expect(wfs.searchResultsList(for: .xyRotation).count == 1,
                "WFS canonical must NOT be cleared by workflow-local clearResults()")
        #expect(wfs.xyRotationWorkspace.cachedSearchResults.isEmpty,
                "XY local cache IS cleared by clearResults()")
    }

    @MainActor
    @Test("3ω clearResults alone clears local cache but leaves WFS canonical intact")
    func threeOmegaLocalClearResultsDoesNotClearWFSCanonical() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "3w-local-clear", workflowID: "3w", workflowCanonicalID: "threeOmega")]

        wfs.restoreSearchState(results: hits, queryText: "3w pn31", for: .threeOmega)
        wfs.threeOmegaWorkspace.cachedSearchResults = hits

        wfs.threeOmegaWorkspace.clearResults()

        #expect(wfs.searchResultsList(for: .threeOmega).count == 1,
                "WFS canonical must NOT be cleared by workflow-local clearResults()")
        #expect(wfs.threeOmegaWorkspace.cachedSearchResults.isEmpty,
                "3ω local cache IS cleared by clearResults()")
    }

    // MARK: - 3. restoreSearchState keeps both copies consistent

    @MainActor
    @Test("restoreSearchState keeps WFS canonical and XY local copy consistent")
    func restoreSearchStateConsistencyForXY() {
        let wfs = makeWFS()
        let hits = [
            makeHit(id: "xy-r1", workflowID: "xy", workflowCanonicalID: "xyRotation"),
            makeHit(id: "xy-r2", workflowID: "xy", workflowCanonicalID: "xyRotation",
                    sampleKey: "PN32|o|STO|111"),
        ]

        wfs.restoreSearchState(results: hits, queryText: "xy pn31", for: .xyRotation)
        wfs.xyRotationWorkspace.cachedSearchResults = hits

        #expect(wfs.searchResultsList(for: .xyRotation) == wfs.xyRotationWorkspace.cachedSearchResults,
                "WFS canonical and XY local cache must be equal after restore")
        #expect(wfs.searchResultsList(for: .xyRotation).count == 2)
    }

    @MainActor
    @Test("restoreSearchState keeps WFS canonical and 3ω local copy consistent")
    func restoreSearchStateConsistencyForThreeOmega() {
        let wfs = makeWFS()
        let hits = [
            makeHit(id: "3w-r1", workflowID: "3w", workflowCanonicalID: "threeOmega"),
            makeHit(id: "3w-r2", workflowID: "3w", workflowCanonicalID: "threeOmega",
                    sampleKey: "PN33|o|GaAs|001"),
        ]

        wfs.restoreSearchState(results: hits, queryText: "3w pn31", for: .threeOmega)
        wfs.threeOmegaWorkspace.cachedSearchResults = hits

        #expect(wfs.searchResultsList(for: .threeOmega) == wfs.threeOmegaWorkspace.cachedSearchResults,
                "WFS canonical and 3ω local cache must be equal after restore")
        #expect(wfs.searchResultsList(for: .threeOmega).count == 2)
    }

    // MARK: - 4. isAllSelected uses workflow-local cachedSearchResults as denominator

    /// isAllSelected reads cachedSearchResults.count from the workflow-local store,
    /// not from WFS canonical searchResults. When the two copies hold different counts,
    /// isAllSelected reflects the local count.
    ///
    /// Migration direction: once cachedSearchResults is removed and runAnalysis() receives
    /// a snapshot, isAllSelected will derive from the same canonical source as searchResultsList.
    @MainActor
    @Test("isAllSelected denominator is workflow-local cachedSearchResults, not WFS canonical")
    func isAllSelectedUsesLocalCacheDenominator() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "h1")
        let hit2 = makeHit(id: "h2", sampleKey: "PN32|o|STO|111")

        // WFS canonical has 2 hits; local cache intentionally set to 1.
        wfs.restoreSearchState(results: [hit1, hit2], queryText: "ahe pn31", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = [hit1]

        wfs.aheWorkspace.selectAll()

        // isAllSelected uses local count (1), selectedIDs now has 1 ID.
        #expect(wfs.aheWorkspace.isAllSelected,
                "isAllSelected reflects local cache count (1), so selectAll on 1 hit → isAllSelected")
        #expect(wfs.aheWorkspace.selectedSearchResultIDs == [hit1.id])

        // WFS canonical still has 2 — isAllSelected ignores this.
        #expect(wfs.searchResultsList(for: .ahe).count == 2,
                "WFS canonical still has 2 hits; isAllSelected did not consult it")
    }

    // MARK: - 5. searchResultsList reads from WFS canonical, not local cache

    /// The shell hit-list (WorkflowWorkspaceShell) calls searchResultsList(for:) which
    /// reads WorkbenchFeatureStore.searchResults[wf] — the canonical copy. Workflow-local
    /// cachedSearchResults is NOT consulted for display.
    ///
    /// This test documents the split: shell display source ≠ analysis input source (today).
    @MainActor
    @Test("searchResultsList reads WFS canonical, independent of workflow-local cachedSearchResults")
    func searchResultsListReadsWFSCanonical() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "wfs-h1")
        let hit2 = makeHit(id: "wfs-h2", sampleKey: "PN32|o|STO|111")

        // Seed WFS canonical with 2 hits.
        wfs.restoreSearchState(results: [hit1, hit2], queryText: "ahe pn31", for: .ahe)
        // Local cache set to 1 hit to create intentional drift.
        wfs.aheWorkspace.cachedSearchResults = [hit1]

        #expect(wfs.searchResultsList(for: .ahe).count == 2,
                "Shell-facing searchResultsList reads WFS canonical (2 hits)")
        #expect(wfs.aheWorkspace.cachedSearchResults.count == 1,
                "Local cache has 1 hit — a different value from the canonical source")
        #expect(wfs.searchResultsList(for: .ahe) != wfs.aheWorkspace.cachedSearchResults,
                "When drifted, shell display source and analysis input source are not equal")
    }

    // MARK: - 6. SearchSnapshot Read Surface (Phase 5A-3.2)

    @MainActor
    @Test("searchSnapshot reads canonical query, results, isRunning, message")
    func snapshotReadsCanonicalState() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "snap-h1"), makeHit(id: "snap-h2", sampleKey: "PN32|o|STO|111")]

        wfs.restoreSearchState(results: hits, queryText: "ahe pn31", for: .ahe)

        let snap = wfs.searchSnapshot(for: .ahe)

        #expect(snap.workflowID == .ahe)
        #expect(snap.queryText == "ahe pn31")
        #expect(snap.results == hits)
        #expect(snap.isRunning == false)
        #expect(snap.message == "Restored from analysis pack (2 hit(s)).")
    }

    @MainActor
    @Test("searchSnapshot results are independent of workflow-local cachedSearchResults")
    func snapshotIsIndependentOfLocalCache() {
        let wfs = makeWFS()
        let hit1 = makeHit(id: "snap-ind-h1")
        let hit2 = makeHit(id: "snap-ind-h2", sampleKey: "PN32|o|STO|111")

        // WFS canonical has 2 hits; local cache intentionally set to 1 to create drift.
        wfs.restoreSearchState(results: [hit1, hit2], queryText: "ahe pn31", for: .ahe)
        wfs.aheWorkspace.cachedSearchResults = [hit1]

        let snap = wfs.searchSnapshot(for: .ahe)

        #expect(snap.results.count == 2,
                "Snapshot reads WFS canonical (2), not local cache (1)")
        #expect(snap.results != wfs.aheWorkspace.cachedSearchResults,
                "Snapshot and local cache hold different values when drifted")
    }

    @MainActor
    @Test("searchSnapshot reflects empty state after canonical clear")
    func snapshotUpdatesAfterCanonicalClear() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "snap-clear-h1")]

        wfs.restoreSearchState(results: hits, queryText: "ahe pn31", for: .ahe)
        wfs.clearWorkflowMeasurementSearch(workflowID: .ahe)

        let snap = wfs.searchSnapshot(for: .ahe)

        #expect(snap.results.isEmpty,
                "Snapshot results must be empty after clearWorkflowMeasurementSearch")
        #expect(snap.message == nil,
                "Snapshot message must be nil after clearWorkflowMeasurementSearch")
        #expect(snap.isRunning == false)
    }

    @MainActor
    @Test("searchSnapshot does not mutate search state")
    func snapshotDoesNotMutateSearchState() {
        let wfs = makeWFS()
        let hits = [makeHit(id: "snap-nomut-h1")]

        wfs.restoreSearchState(results: hits, queryText: "ahe pn31", for: .ahe)

        let resultsBefore = wfs.searchResultsList(for: .ahe)
        let queryBefore = wfs.searchQueryText(for: .ahe)
        let messageBefore = wfs.searchMessage(for: .ahe)
        let runningBefore = wfs.isSearchRunning(for: .ahe)

        _ = wfs.searchSnapshot(for: .ahe)

        #expect(wfs.searchResultsList(for: .ahe) == resultsBefore,
                "searchSnapshot must not change WFS canonical results")
        #expect(wfs.searchQueryText(for: .ahe) == queryBefore,
                "searchSnapshot must not change query text")
        #expect(wfs.searchMessage(for: .ahe) == messageBefore,
                "searchSnapshot must not change message")
        #expect(wfs.isSearchRunning(for: .ahe) == runningBefore,
                "searchSnapshot must not change running flag")
    }
}
