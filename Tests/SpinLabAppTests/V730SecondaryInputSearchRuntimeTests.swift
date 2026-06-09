import Foundation
import Testing
@testable import SpinLabApp

/// V7.3.0 Secondary Input Search — Runtime Extraction (Gate 7.3 Step 2)
///
/// Proves that the five 3ω RT session-state fields (query, results, running,
/// message, popover) now live in WorkbenchSecondaryInputSearchRuntime and
/// remain fully isolated from WorkbenchMainSearchRuntime, WorkbenchSearchSnapshot,
/// and WorkbenchSelectionRuntime.
///
/// selectedRTHit remains workflow-owned (ThreeOmegaWorkspaceStore) — not tested here.
/// cachedRTFilePath is derived output only — deferred debt, not in scope.
@Suite("V7.3.0 Secondary Input Search — Runtime Extraction (Gate 7.3 Step 2)")
struct V730SecondaryInputSearchRuntimeTests {

    // MARK: - Fixtures

    private func makeHit(
        id: String = UUID().uuidString,
        workflowID: String = "3w"
    ) -> WorkflowMeasurementSearchHit {
        let sidecarPath = "/tmp/\(id).spinlab.json"
        return WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: "/tmp/\(id).lvm",
            sourceFilePath: "/tmp/\(id).lvm",
            workflowID: workflowID,
            workflowDisplayName: workflowID.uppercased(),
            workflowCanonicalID: workflowID,
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: [:],
            channels: [],
            appliedAt: .distantPast
        )
    }

    @MainActor
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    // MARK: - 1. State ownership: secondary runtime is canonical

    /// setQuery on the runtime is immediately reflected by query(forSlot:).
    @MainActor
    @Test("secondary runtime owns rtQuery: set and read round-trip via runtime")
    func rtQueryLivesInRuntime() {
        let wfs = makeWFS()
        let rt = wfs.secondaryInputRuntime

        rt.setQuery("PN31 RT scan", forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        #expect(
            rt.query(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == "PN31 RT scan",
            "Expected runtime to own rtQuery"
        )
    }

    /// setResults on the runtime is immediately reflected by results(forSlot:).
    @MainActor
    @Test("secondary runtime owns rtSearchResults: set and read round-trip via runtime")
    func rtSearchResultsLiveInRuntime() {
        let wfs = makeWFS()
        let rt = wfs.secondaryInputRuntime
        let hit = makeHit(id: "rt-runtime-hit")

        rt.setResults([hit], forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        let stored = rt.results(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(stored.map(\.id) == [hit.id], "Expected runtime to own rtSearchResults")
    }

    /// setIsSearching on the runtime is reflected by isSearching(forSlot:).
    @MainActor
    @Test("secondary runtime owns isRTSearching: set and read round-trip via runtime")
    func isRTSearchingLivesInRuntime() {
        let wfs = makeWFS()
        let rt = wfs.secondaryInputRuntime

        rt.setIsSearching(true, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(rt.isSearching(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == true)

        rt.setIsSearching(false, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(rt.isSearching(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == false)
    }

    /// setMessage on the runtime is reflected by message(forSlot:).
    @MainActor
    @Test("secondary runtime owns rtSearchMessage: set and read round-trip via runtime")
    func rtSearchMessageLivesInRuntime() {
        let wfs = makeWFS()
        let rt = wfs.secondaryInputRuntime

        rt.setMessage("RT found 3 file(s).", forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(
            rt.message(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == "RT found 3 file(s).",
            "Expected runtime to own rtSearchMessage"
        )

        rt.setMessage(nil, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(rt.message(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == nil)
    }

    /// setPopoverVisible on the runtime is reflected by isPopoverVisible(forSlot:).
    @MainActor
    @Test("secondary runtime owns showRTPopover: set and read round-trip via runtime")
    func showRTPopoverLivesInRuntime() {
        let wfs = makeWFS()
        let rt = wfs.secondaryInputRuntime

        rt.setPopoverVisible(true, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(rt.isPopoverVisible(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == true)

        rt.setPopoverVisible(false, forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(rt.isPopoverVisible(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == false)
    }

    // MARK: - 2. Workspace forwarding: ThreeOmegaWorkspaceStore reads/writes through runtime

    /// When secondary runtime is injected, workspace.rtQuery reads from the runtime.
    @MainActor
    @Test("workspace.rtQuery forwards to secondary runtime when runtime is wired")
    func workspaceRtQueryForwardsToRuntime() {
        let wfs = makeWFS()
        let rt = wfs.secondaryInputRuntime

        rt.setQuery("forwarded query", forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        #expect(
            wfs.threeOmegaWorkspace.rtQuery == "forwarded query",
            "Expected workspace.rtQuery to forward reads from secondary runtime"
        )
    }

    /// Writing workspace.rtQuery routes to the secondary runtime.
    @MainActor
    @Test("workspace.rtQuery = x routes write to secondary runtime")
    func workspaceRtQueryWriteRoutesToRuntime() {
        let wfs = makeWFS()

        wfs.threeOmegaWorkspace.rtQuery = "written via workspace"

        #expect(
            wfs.secondaryInputRuntime.query(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID) == "written via workspace",
            "Expected workspace write to rtQuery to be reflected in secondary runtime"
        )
    }

    /// Writing workspace.rtSearchResults routes to the secondary runtime.
    @MainActor
    @Test("workspace.rtSearchResults = x routes write to secondary runtime")
    func workspaceRtSearchResultsWriteRoutesToRuntime() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ws-write-rt")

        wfs.threeOmegaWorkspace.rtSearchResults = [hit]

        let runtimeResults = wfs.secondaryInputRuntime.results(forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        #expect(
            runtimeResults.map(\.id) == [hit.id],
            "Expected workspace write to rtSearchResults to be reflected in secondary runtime"
        )
    }

    // MARK: - 3. Isolation: RT slot state does not enter main search or selection

    /// RT results written to secondary runtime do not appear in WorkbenchSearchSnapshot.
    @MainActor
    @Test("RT results in secondary runtime do not appear in WorkbenchSearchSnapshot")
    func rtResultsNotInSearchSnapshot() {
        let wfs = makeWFS()
        let mainHit = makeHit(id: "main-snap-hit")
        let rtHit   = makeHit(id: "rt-snap-hit")

        wfs.restoreSearchState(results: [mainHit], queryText: "3w main", for: .threeOmega)
        wfs.secondaryInputRuntime.setResults([rtHit], forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        let snapshot = wfs.searchSnapshot(for: .threeOmega)

        #expect(snapshot.results.map(\.id) == [mainHit.id],
                "Expected snapshot to contain only main search results")
        #expect(!snapshot.results.map(\.id).contains(rtHit.id),
                "Expected RT result to be absent from WorkbenchSearchSnapshot")
    }

    /// RT query in secondary runtime does not contaminate WorkbenchSearchSnapshot.queryText.
    @MainActor
    @Test("RT query in secondary runtime does not appear in WorkbenchSearchSnapshot.queryText")
    func rtQueryNotInSearchSnapshot() {
        let wfs = makeWFS()

        wfs.setSearchQueryText("canonical main query", for: .threeOmega)
        wfs.secondaryInputRuntime.setQuery("rt override query", forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        let snapshot = wfs.searchSnapshot(for: .threeOmega)

        #expect(snapshot.queryText == "canonical main query",
                "Expected snapshot.queryText to reflect canonical main query")
        #expect(snapshot.queryText != "rt override query",
                "Expected RT query not to contaminate WorkbenchSearchSnapshot.queryText")
    }

    /// RT running/message state in secondary runtime does not affect WorkbenchSearchSnapshot.
    @MainActor
    @Test("RT running/message state in secondary runtime does not affect WorkbenchSearchSnapshot")
    func rtRunningMessageNotInSearchSnapshot() {
        let wfs = makeWFS()

        wfs.secondaryInputRuntime.setIsSearching(true,   forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)
        wfs.secondaryInputRuntime.setMessage("RT active", forSlot: WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        let snapshot = wfs.searchSnapshot(for: .threeOmega)

        #expect(snapshot.isRunning == false,
                "Expected main search snapshot isRunning unaffected by RT running state")
        #expect(snapshot.message != "RT active",
                "Expected main search snapshot message unaffected by RT message")
    }

    // MARK: - 4. clearSlot: clears only RT slot state

    /// clearSlot("rt") zeros all five RT session fields and does not touch main search.
    @MainActor
    @Test("clearSlot clears all five RT session fields")
    func clearSlotClearsRTSessionFields() {
        let wfs = makeWFS()
        let rt  = wfs.secondaryInputRuntime
        let hit = makeHit(id: "rt-clear")
        let slotID = WorkbenchSecondaryInputSearchRuntime.rtSlotID

        rt.setQuery("PN31 RT",    forSlot: slotID)
        rt.setResults([hit],      forSlot: slotID)
        rt.setIsSearching(true,   forSlot: slotID)
        rt.setMessage("searching", forSlot: slotID)
        rt.setPopoverVisible(true, forSlot: slotID)

        rt.clearSlot(slotID)

        #expect(rt.query(forSlot: slotID).isEmpty,       "Expected query cleared")
        #expect(rt.results(forSlot: slotID).isEmpty,     "Expected results cleared")
        #expect(rt.isSearching(forSlot: slotID) == false,"Expected running cleared")
        #expect(rt.message(forSlot: slotID) == nil,      "Expected message cleared")
        #expect(rt.isPopoverVisible(forSlot: slotID) == false, "Expected popover cleared")
    }

    /// clearSlot("rt") does not modify main search query or results.
    @MainActor
    @Test("clearSlot does not touch main search query or results")
    func clearSlotDoesNotTouchMainSearch() {
        let wfs = makeWFS()
        let mainHit = makeHit(id: "main-clear")

        wfs.setSearchQueryText("main query", for: .threeOmega)
        wfs.restoreSearchState(results: [mainHit], queryText: "main query", for: .threeOmega)

        wfs.secondaryInputRuntime.clearSlot(WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        #expect(wfs.searchQueryText(for: .threeOmega) == "main query",
                "Expected clearSlot not to affect main search query")
        #expect(wfs.searchResultsList(for: .threeOmega).map(\.id) == [mainHit.id],
                "Expected clearSlot not to affect main search results")
    }

    /// clearSlot("rt") does not touch WorkbenchSelectionRuntime selected IDs.
    @MainActor
    @Test("clearSlot does not touch WorkbenchSelectionRuntime selected IDs")
    func clearSlotDoesNotTouchSelectionRuntime() {
        let wfs = makeWFS()
        let mainHit = makeHit(id: "main-sel")

        wfs.restoreSearchState(results: [mainHit], queryText: "3w", for: .threeOmega)
        wfs.seedSelection(Set([mainHit.id]), hits: [mainHit], for: .threeOmega)

        wfs.secondaryInputRuntime.clearSlot(WorkbenchSecondaryInputSearchRuntime.rtSlotID)

        #expect(wfs.selectedSearchResultIDs(for: .threeOmega).contains(mainHit.id),
                "Expected main selection to survive clearSlot")
    }

    // MARK: - 5. Slot metadata

    /// Static slot descriptor has expected id and displayLabel.
    @Test("rtSlot has id 'rt' and display label 'RT / Rxx(T)'")
    func rtSlotDescriptor() {
        let slot = WorkbenchSecondaryInputSearchRuntime.rtSlot
        #expect(slot.id == "rt")
        #expect(slot.displayLabel == "RT / Rxx(T)")
    }
}
