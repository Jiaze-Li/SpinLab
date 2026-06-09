import Foundation
import Testing
@testable import SpinLabApp

/// V7.3.0 Secondary Input Search — Baseline (Gate 7.3 Step 1)
///
/// Locks current 3ω RT secondary-input behavior before extraction.
/// No production code is changed; these tests establish the behavioral
/// contract that must remain intact through WorkbenchSecondaryInputSearchRuntime extraction.
///
/// Two groups:
///   1. Restore priority chain — selectedRTHit → pendingRTSidecarPath → cachedRTFilePath → unbound
///   2. Isolation guards — RT slot state must not enter Main Search or Selection snapshots
@Suite("V7.3.0 Secondary Input Search — Baseline (Gate 7.3 Step 1)")
struct V730SecondaryInputSearchBaselineTests {

    // MARK: - Fixtures

    private func makeHit(
        id: String = UUID().uuidString,
        sidecarSuffix: String = ".spinlab.json",
        workflowID: String = "3w",
        sampleKey: String = "PN31|b|STO|111"
    ) -> WorkflowMeasurementSearchHit {
        let sidecarPath = "/tmp/\(id)\(sidecarSuffix)"
        return WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: "/tmp/\(id).lvm",
            sourceFilePath: "/tmp/\(id).lvm",
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

    private func makePackConfig(
        selectedRTHit: WorkflowMeasurementSearchHit? = nil,
        rtQuery: String = "",
        rtFilePath: String? = nil,
        cachedSearchResults: [WorkflowMeasurementSearchHit] = [],
        selectedSearchResultIDs: [String] = []
    ) -> ThreeOmegaPackConfig {
        ThreeOmegaPackConfig(
            device: "",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: rtFilePath,
            sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega",
            titleTemplate: "#tab #sample",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: false,
            plotLegendAnchor: "",
            tabStates: [:],
            chartStyleOverrides: [:],
            cachedSearchResults: cachedSearchResults,
            selectedSearchResultIDs: selectedSearchResultIDs,
            selectedRTHit: selectedRTHit,
            rtQuery: rtQuery,
            searchQueryText: ""
        )
    }

    private func makePackResult() -> ThreeOmegaPackResult {
        ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
    }

    private func makePack(config: ThreeOmegaPackConfig) throws -> AnalysisPack {
        try AnalysisPack(
            label: "3ω Baseline Fixture",
            workflowID: "3w",
            filePaths: config.cachedSearchResults.map(\.measurementFilePath),
            sampleKeys: config.cachedSearchResults.map(\.sampleKey),
            config: config,
            result: makePackResult()
        )
    }

    @MainActor
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    // MARK: - 1. Restore Priority Chain

    /// Priority 1: pack encodes a valid selectedRTHit → restoreFromPack applies it directly.
    /// This is the common case after a user selects an RT hit and saves the workspace.
    @MainActor
    @Test("priority 1: selectedRTHit from pack config is applied directly by restoreFromPack")
    func priority1_selectedRTHitFromPackAppliedDirectly() throws {
        let store = ThreeOmegaWorkspaceStore()
        let rtHit = makeHit(id: "rt-hit-pack")
        let config = makePackConfig(selectedRTHit: rtHit, rtQuery: "PN31 RT")
        let pack = try makePack(config: config)

        store.restoreFromPack(
            config: config,
            result: makePackResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.selectedRTHit?.id == rtHit.id,
                "Expected selectedRTHit to be directly applied from pack config")
        #expect(store.rtQuery == "PN31 RT",
                "Expected rtQuery to be restored from pack config")
        #expect(store.pendingRTSidecarPath == nil,
                "Expected no pending sidecar path after direct hit restore")
    }

    /// Priority 2a: pendingRTSidecarPath is set (interaction restore path).
    /// When search completes, WorkbenchMainSearchRuntime calls applyRestoredRTHit(_:),
    /// which promotes the pending sidecar to selectedRTHit and clears the pending path.
    @MainActor
    @Test("priority 2a: applyRestoredRTHit promotes pendingRTSidecarPath to selectedRTHit")
    func priority2a_applyRestoredRTHitPromotesPendingSidecar() {
        let store = ThreeOmegaWorkspaceStore()
        let rtHit = makeHit(id: "rt-pending-resolved")

        // Simulate interaction-restore state: no selected hit, pending sidecar set.
        store.selectedRTHit = nil
        store.pendingRTSidecarPath = "/tmp/rt-pending-resolved.spinlab.json"

        // Simulate search runtime resolving the sidecar to a rebuilt hit.
        store.applyRestoredRTHit(rtHit)

        #expect(store.selectedRTHit?.id == rtHit.id,
                "Expected selectedRTHit to be set by applyRestoredRTHit")
        #expect(store.pendingRTSidecarPath == nil,
                "Expected pendingRTSidecarPath to be cleared after successful resolution")
    }

    /// Priority 2b: pendingRTSidecarPath is set but sidecar no longer exists on disk.
    /// WorkbenchMainSearchRuntime calls clearPendingRTRestore(), which leaves the slot unbound.
    @MainActor
    @Test("priority 2b: clearPendingRTRestore leaves slot unbound when sidecar does not resolve")
    func priority2b_clearPendingRTRestoreLeavesSlotUnbound() {
        let store = ThreeOmegaWorkspaceStore()

        store.selectedRTHit = nil
        store.pendingRTSidecarPath = "/nonexistent/path.spinlab.json"

        // Simulate search runtime failing to resolve the sidecar.
        store.clearPendingRTRestore()

        #expect(store.pendingRTSidecarPath == nil,
                "Expected pendingRTSidecarPath to be cleared after failed resolution")
        #expect(store.selectedRTHit == nil,
                "Expected selectedRTHit to remain nil when sidecar could not be resolved")
    }

    /// Priority 3: pack encodes rtFilePath (measurement file path) but no selectedRTHit.
    /// Current behavior: cachedRTFilePath is always derived from selectedRTHit?.measurementFilePath
    /// by _snapshotAndCacheManifestPayloads() at the end of restoreFromPack. With no selected hit,
    /// cachedRTFilePath is nil after restore — the raw rtFilePath in the pack config is NOT
    /// preserved as a standalone rebuild path. The slot remains unbound.
    /// This documents the current boundary; Gate 7.3 extraction must preserve it.
    @MainActor
    @Test("priority 3: cachedRTFilePath is derived from selectedRTHit — nil when no hit restored")
    func priority3_cachedRTFilePathDerivedFromSelectedRTHit() throws {
        let store = ThreeOmegaWorkspaceStore()
        let config = makePackConfig(selectedRTHit: nil, rtFilePath: "/tmp/rt-measurement.lvm")
        let pack = try makePack(config: config)

        store.restoreFromPack(
            config: config,
            result: makePackResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        // cachedRTFilePath is overwritten by _snapshotAndCacheManifestPayloads() which derives
        // it from selectedRTHit?.measurementFilePath — nil when no hit is selected.
        #expect(store.cachedRTFilePath == nil,
                "Expected cachedRTFilePath nil: it is derived from selectedRTHit, not from config.rtFilePath")
        #expect(store.selectedRTHit == nil,
                "Expected selectedRTHit nil when pack has no selectedRTHit")
        #expect(store.pendingRTSidecarPath == nil,
                "Expected pendingRTSidecarPath nil: restoreFromPack does not set it from rtFilePath")
    }

    /// Priority 4: all RT bridge fields nil — slot stays unbound, no crash.
    /// Covers freshly-created or stripped packs with no RT state.
    @MainActor
    @Test("priority 4: all RT bridge fields nil; slot remains unbound; no crash")
    func priority4_allNilNocrash() throws {
        let store = ThreeOmegaWorkspaceStore()
        let config = makePackConfig(selectedRTHit: nil, rtFilePath: nil)
        let pack = try makePack(config: config)

        // Must not crash.
        store.restoreFromPack(
            config: config,
            result: makePackResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.selectedRTHit == nil,
                "Expected selectedRTHit nil when all RT bridge fields are absent")
        #expect(store.cachedRTFilePath == nil,
                "Expected cachedRTFilePath nil when pack encodes nil rtFilePath")
        #expect(store.pendingRTSidecarPath == nil,
                "Expected pendingRTSidecarPath nil after restoreFromPack with no RT state")
    }

    // MARK: - 2. Isolation Guards

    /// RT search results (rtSearchResults) are a workflow-local field on ThreeOmegaWorkspaceStore.
    /// They must never appear in the canonical WorkbenchSearchSnapshot, which is
    /// built solely from WorkbenchMainSearchRuntime state.
    @MainActor
    @Test("rtSearchResults do not appear in WorkbenchSearchSnapshot.results")
    func guard_rtSearchResultsNotInSearchSnapshot() {
        let wfs = makeWFS()
        let mainHit = makeHit(id: "main-hit", workflowID: "3w")
        let rtHit = makeHit(id: "rt-hit", workflowID: "rt")

        // Seed canonical main search with mainHit only.
        wfs.restoreSearchState(results: [mainHit], queryText: "3w main", for: .threeOmega)

        // Directly set RT-local results on the workspace store (simulates an RT search completion).
        wfs.threeOmegaWorkspace.rtSearchResults = [rtHit]

        let snapshot = wfs.searchSnapshot(for: .threeOmega)

        #expect(snapshot.results.map(\.id) == [mainHit.id],
                "Expected snapshot.results to contain only the canonical main hit")
        #expect(!snapshot.results.map(\.id).contains(rtHit.id),
                "Expected RT search result not to appear in WorkbenchSearchSnapshot")
    }

    /// rtQuery is stored on ThreeOmegaWorkspaceStore independently of the canonical
    /// search query text owned by WorkbenchMainSearchRuntime.
    @MainActor
    @Test("rtQuery does not appear in WorkbenchSearchSnapshot.queryText")
    func guard_rtQueryNotInSearchSnapshot() {
        let wfs = makeWFS()

        wfs.setSearchQueryText("3w main query", for: .threeOmega)
        wfs.threeOmegaWorkspace.rtQuery = "RT override query"

        let snapshot = wfs.searchSnapshot(for: .threeOmega)

        #expect(snapshot.queryText == "3w main query",
                "Expected snapshot.queryText to reflect canonical main search query")
        #expect(snapshot.queryText != "RT override query",
                "Expected rtQuery not to contaminate WorkbenchSearchSnapshot.queryText")
    }

    /// selectedRTHit is an auxiliary slot selection owned by ThreeOmegaWorkspaceStore.
    /// It must not appear in WorkbenchSelectedHitsSnapshot, which is built from
    /// WorkbenchSelectionRuntime selected IDs and main cachedSearchResults.
    @MainActor
    @Test("selectedRTHit does not appear in WorkbenchSelectedHitsSnapshot.selectedHits")
    func guard_selectedRTHitNotInSelectedHitsSnapshot() {
        let wfs = makeWFS()
        let mainHit = makeHit(id: "main-selected", workflowID: "3w")
        let rtHit = makeHit(id: "rt-selected", workflowID: "rt")

        // Seed main selection and results.
        wfs.restoreSearchState(results: [mainHit], queryText: "3w", for: .threeOmega)
        wfs.seedSelection(Set([mainHit.id]), hits: [mainHit], for: .threeOmega)

        // Set RT auxiliary selection independently.
        wfs.threeOmegaWorkspace.selectedRTHit = rtHit

        let snapshot = wfs.selectedHitsSnapshot(for: .threeOmega)

        let snapshotIDs = snapshot.selectedHits.map(\.id)
        #expect(snapshotIDs.contains(mainHit.id),
                "Expected main selected hit to appear in WorkbenchSelectedHitsSnapshot")
        #expect(!snapshotIDs.contains(rtHit.id),
                "Expected selectedRTHit not to appear in WorkbenchSelectedHitsSnapshot")
    }

    /// clearRTSelection() zeros the auxiliary slot selection only.
    /// Main search query text and results must be unchanged.
    @MainActor
    @Test("clearRTSelection does not clear main search query or results")
    func guard_clearRTSelectionDoesNotClearMainSearch() {
        let wfs = makeWFS()
        let mainHit = makeHit(id: "main-hit", workflowID: "3w")
        let rtHit = makeHit(id: "rt-hit", workflowID: "rt")

        wfs.setSearchQueryText("3w main query", for: .threeOmega)
        wfs.restoreSearchState(results: [mainHit], queryText: "3w main query", for: .threeOmega)
        wfs.threeOmegaWorkspace.selectedRTHit = rtHit

        wfs.threeOmegaWorkspace.clearRTSelection()

        #expect(wfs.threeOmegaWorkspace.selectedRTHit == nil,
                "Expected clearRTSelection to clear selectedRTHit")
        #expect(wfs.searchQueryText(for: .threeOmega) == "3w main query",
                "Expected main search query text to be unchanged after clearRTSelection")
        #expect(wfs.searchResultsList(for: .threeOmega).map(\.id) == [mainHit.id],
                "Expected main search results to be unchanged after clearRTSelection")
    }

    /// clearRTSelection() must not mutate WorkbenchSelectionRuntime's selected IDs
    /// for the 3ω workflow (or any other workflow).
    @MainActor
    @Test("clearRTSelection does not clear WorkbenchSelectionRuntime selected IDs")
    func guard_clearRTSelectionDoesNotClearSelectionRuntime() {
        let wfs = makeWFS()
        let mainHit = makeHit(id: "main-selected", workflowID: "3w")
        let rtHit = makeHit(id: "rt-selected", workflowID: "rt")

        // Seed canonical selection with mainHit.
        wfs.seedSelection(Set([mainHit.id]), hits: [mainHit], for: .threeOmega)
        wfs.threeOmegaWorkspace.selectedRTHit = rtHit

        wfs.threeOmegaWorkspace.clearRTSelection()

        let remainingIDs = wfs.selectedSearchResultIDs(for: .threeOmega)
        #expect(remainingIDs.contains(mainHit.id),
                "Expected main selected ID to survive clearRTSelection")
        #expect(wfs.threeOmegaWorkspace.selectedRTHit == nil,
                "Expected selectedRTHit to be cleared by clearRTSelection")
    }
}
