import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.7 Selection Shell Boundary — Phase 5C-1B (Gate 7.2 Step 3)
///
/// Locks documented boundaries after WorkbenchSelectionRuntime promotion:
/// - canonical search state lives in WorkbenchMainSearchRuntime (via WorkbenchFeatureStore facade)
/// - selection ops go through WorkbenchFeatureStore facade → WorkbenchSelectionRuntime
/// - selectAll denominator: canonical search results when available, else workflow cachedSearchResults
/// - clearResults is workflow-specific local cleanup (cache + 3ω RT); selection cleared via facade
@Suite("V5.3.7 Workbench Selection Shell Boundary")
struct V537WorkbenchSelectionShellTests {

    private struct CanonicalSearchState {
        var query: String
        var results: [WorkflowMeasurementSearchHit]
        var isRunning: Bool
        var message: String?
    }

    private func makeHit(
        id: String,
        workflowID: String,
        workflowCanonicalID: String,
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
    private func seedCanonicalState(
        _ wfs: WorkbenchFeatureStore,
        workflow: WorkflowKey,
        query: String,
        results: [WorkflowMeasurementSearchHit]
    ) {
        wfs.setSearchQueryText(query, for: workflow)
        wfs.restoreSearchState(results: results, queryText: query, for: workflow)
    }

    @MainActor
    private func canonicalState(_ wfs: WorkbenchFeatureStore, workflow: WorkflowKey) -> CanonicalSearchState {
        CanonicalSearchState(
            query: wfs.searchQueryText(for: workflow),
            results: wfs.searchResultsList(for: workflow),
            isRunning: wfs.isSearchRunning(for: workflow),
            message: wfs.searchMessage(for: workflow)
        )
    }

    // MARK: - 1. toggle does not mutate canonical search state

    @MainActor
    @Test("AHE toggle selection does not mutate canonical query/results/running/message")
    func aheToggleDoesNotMutateCanonicalState() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-toggle", workflowID: "ahe", workflowCanonicalID: "ahe")
        seedCanonicalState(wfs, workflow: .ahe, query: "ahe q", results: [hit])

        let before = canonicalState(wfs, workflow: .ahe)
        wfs.toggleSearchHitSelection(hit.id, for: .ahe)
        let after = canonicalState(wfs, workflow: .ahe)

        #expect(before.query == after.query)
        #expect(before.results == after.results)
        #expect(before.isRunning == after.isRunning)
        #expect(before.message == after.message)
    }

    @MainActor
    @Test("XY toggle selection does not mutate canonical query/results/running/message")
    func xyToggleDoesNotMutateCanonicalState() {
        let wfs = makeWFS()
        let hit = makeHit(id: "xy-toggle", workflowID: "xy", workflowCanonicalID: "xyRotation")
        seedCanonicalState(wfs, workflow: .xyRotation, query: "xy q", results: [hit])

        let before = canonicalState(wfs, workflow: .xyRotation)
        wfs.toggleSearchHitSelection(hit.id, for: .xyRotation)
        let after = canonicalState(wfs, workflow: .xyRotation)

        #expect(before.query == after.query)
        #expect(before.results == after.results)
        #expect(before.isRunning == after.isRunning)
        #expect(before.message == after.message)
    }

    @MainActor
    @Test("3ω toggle selection does not mutate canonical query/results/running/message")
    func threeOmegaToggleDoesNotMutateCanonicalState() {
        let wfs = makeWFS()
        let hit = makeHit(id: "3w-toggle", workflowID: "3w", workflowCanonicalID: "threeOmega")
        seedCanonicalState(wfs, workflow: .threeOmega, query: "3w q", results: [hit])

        let before = canonicalState(wfs, workflow: .threeOmega)
        wfs.toggleSearchHitSelection(hit.id, for: .threeOmega)
        let after = canonicalState(wfs, workflow: .threeOmega)

        #expect(before.query == after.query)
        #expect(before.results == after.results)
        #expect(before.isRunning == after.isRunning)
        #expect(before.message == after.message)
    }

    // MARK: - 2. deselectAll clears selected IDs only

    @MainActor
    @Test("AHE deselectAll clears selected IDs only")
    func aheDeselectAllClearsOnlySelection() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-deselect", workflowID: "ahe", workflowCanonicalID: "ahe")
        seedCanonicalState(wfs, workflow: .ahe, query: "ahe q", results: [hit])
        wfs.aheWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .ahe)
        let before = canonicalState(wfs, workflow: .ahe)

        wfs.deselectAll(for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe).isEmpty)
        #expect(wfs.aheWorkspace.cachedSearchResults == [hit])
        #expect(canonicalState(wfs, workflow: .ahe).query == before.query)
        #expect(canonicalState(wfs, workflow: .ahe).results == before.results)
        #expect(canonicalState(wfs, workflow: .ahe).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .ahe).message == before.message)
    }

    @MainActor
    @Test("XY deselectAll clears selected IDs only")
    func xyDeselectAllClearsOnlySelection() {
        let wfs = makeWFS()
        let hit = makeHit(id: "xy-deselect", workflowID: "xy", workflowCanonicalID: "xyRotation")
        seedCanonicalState(wfs, workflow: .xyRotation, query: "xy q", results: [hit])
        wfs.xyRotationWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .xyRotation)
        let before = canonicalState(wfs, workflow: .xyRotation)

        wfs.deselectAll(for: .xyRotation)

        #expect(wfs.selectedSearchResultIDs(for: .xyRotation).isEmpty)
        #expect(wfs.xyRotationWorkspace.cachedSearchResults == [hit])
        #expect(canonicalState(wfs, workflow: .xyRotation).query == before.query)
        #expect(canonicalState(wfs, workflow: .xyRotation).results == before.results)
        #expect(canonicalState(wfs, workflow: .xyRotation).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .xyRotation).message == before.message)
    }

    @MainActor
    @Test("3ω deselectAll clears selected IDs only")
    func threeOmegaDeselectAllClearsOnlySelection() {
        let wfs = makeWFS()
        let hit = makeHit(id: "3w-deselect", workflowID: "3w", workflowCanonicalID: "threeOmega")
        seedCanonicalState(wfs, workflow: .threeOmega, query: "3w q", results: [hit])
        wfs.threeOmegaWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .threeOmega)
        let before = canonicalState(wfs, workflow: .threeOmega)

        wfs.deselectAll(for: .threeOmega)

        #expect(wfs.selectedSearchResultIDs(for: .threeOmega).isEmpty)
        #expect(wfs.threeOmegaWorkspace.cachedSearchResults == [hit])
        #expect(canonicalState(wfs, workflow: .threeOmega).query == before.query)
        #expect(canonicalState(wfs, workflow: .threeOmega).results == before.results)
        #expect(canonicalState(wfs, workflow: .threeOmega).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .threeOmega).message == before.message)
    }

    // MARK: - 3. selectAll uses canonical/local denominator

    @MainActor
    @Test("AHE selectAll uses cachedSearchResults as denominator when canonical is empty")
    func aheSelectAllUsesLocalMirrorIDs() {
        let wfs = makeWFS()
        let local = [
            makeHit(id: "ahe-local-1", workflowID: "ahe", workflowCanonicalID: "ahe"),
            makeHit(id: "ahe-local-2", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN32|o|STO|111")
        ]
        wfs.aheWorkspace.cachedSearchResults = local

        wfs.selectAll(for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe) == Set(local.map(\.id)))
    }

    @MainActor
    @Test("XY selectAll uses cachedSearchResults as denominator when canonical is empty")
    func xySelectAllUsesLocalMirrorIDs() {
        let wfs = makeWFS()
        let local = [
            makeHit(id: "xy-local-1", workflowID: "xy", workflowCanonicalID: "xyRotation"),
            makeHit(id: "xy-local-2", workflowID: "xy", workflowCanonicalID: "xyRotation", sampleKey: "PN32|o|STO|111")
        ]
        wfs.xyRotationWorkspace.cachedSearchResults = local

        wfs.selectAll(for: .xyRotation)

        #expect(wfs.selectedSearchResultIDs(for: .xyRotation) == Set(local.map(\.id)))
    }

    @MainActor
    @Test("3ω selectAll uses cachedSearchResults as denominator when canonical is empty")
    func threeOmegaSelectAllUsesLocalMirrorIDs() {
        let wfs = makeWFS()
        let local = [
            makeHit(id: "3w-local-1", workflowID: "3w", workflowCanonicalID: "threeOmega"),
            makeHit(id: "3w-local-2", workflowID: "3w", workflowCanonicalID: "threeOmega", sampleKey: "PN32|o|STO|111")
        ]
        wfs.threeOmegaWorkspace.cachedSearchResults = local

        wfs.selectAll(for: .threeOmega)

        #expect(wfs.selectedSearchResultIDs(for: .threeOmega) == Set(local.map(\.id)))
    }

    // MARK: - 4. clearResults behavior is workflow-local (cache only, not selection or canonical)

    @MainActor
    @Test("AHE clearResults clears local cache only; selection and canonical unaffected")
    func aheClearResultsIsLocalOnly() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-clear", workflowID: "ahe", workflowCanonicalID: "ahe")
        seedCanonicalState(wfs, workflow: .ahe, query: "ahe clear", results: [hit])
        let before = canonicalState(wfs, workflow: .ahe)
        wfs.aheWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .ahe)

        wfs.aheWorkspace.clearResults()

        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
        // Selection is NOT cleared by clearResults — it lives in WorkbenchSelectionRuntime
        #expect(wfs.selectedSearchResultIDs(for: .ahe) == [hit.id])
        #expect(canonicalState(wfs, workflow: .ahe).query == before.query)
        #expect(canonicalState(wfs, workflow: .ahe).results == before.results)
        #expect(canonicalState(wfs, workflow: .ahe).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .ahe).message == before.message)
    }

    @MainActor
    @Test("XY clearResults clears local cache only; selection and canonical unaffected")
    func xyClearResultsIsLocalOnly() {
        let wfs = makeWFS()
        let hit = makeHit(id: "xy-clear", workflowID: "xy", workflowCanonicalID: "xyRotation")
        seedCanonicalState(wfs, workflow: .xyRotation, query: "xy clear", results: [hit])
        let before = canonicalState(wfs, workflow: .xyRotation)
        wfs.xyRotationWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .xyRotation)

        wfs.xyRotationWorkspace.clearResults()

        #expect(wfs.xyRotationWorkspace.cachedSearchResults.isEmpty)
        #expect(wfs.selectedSearchResultIDs(for: .xyRotation) == [hit.id])
        #expect(canonicalState(wfs, workflow: .xyRotation).query == before.query)
        #expect(canonicalState(wfs, workflow: .xyRotation).results == before.results)
        #expect(canonicalState(wfs, workflow: .xyRotation).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .xyRotation).message == before.message)
    }

    @MainActor
    @Test("3ω clearResults clears local cache and RT state; selection and canonical unaffected")
    func threeOmegaClearResultsIncludesRTCleanupAndKeepsCanonical() {
        let wfs = makeWFS()
        let hit = makeHit(id: "3w-clear", workflowID: "3w", workflowCanonicalID: "threeOmega")
        let rtHit = makeHit(id: "3w-rt", workflowID: "3w", workflowCanonicalID: "threeOmega")

        seedCanonicalState(wfs, workflow: .threeOmega, query: "3w clear", results: [hit])
        let before = canonicalState(wfs, workflow: .threeOmega)

        wfs.threeOmegaWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .threeOmega)
        wfs.threeOmegaWorkspace.rtQuery = "rt q"
        wfs.threeOmegaWorkspace.rtSearchResults = [rtHit]
        wfs.threeOmegaWorkspace.rtSearchMessage = "rt msg"
        wfs.threeOmegaWorkspace.isRTSearching = true
        wfs.threeOmegaWorkspace.showRTPopover = true
        wfs.threeOmegaWorkspace.selectedRTHit = rtHit

        wfs.threeOmegaWorkspace.clearResults()

        #expect(wfs.threeOmegaWorkspace.cachedSearchResults.isEmpty)
        // RT-side cleanup stays in 3ω workflow store
        #expect(wfs.threeOmegaWorkspace.rtQuery.isEmpty)
        #expect(wfs.threeOmegaWorkspace.rtSearchResults.isEmpty)
        #expect(wfs.threeOmegaWorkspace.rtSearchMessage == nil)
        #expect(wfs.threeOmegaWorkspace.isRTSearching == false)
        #expect(wfs.threeOmegaWorkspace.showRTPopover == false)
        #expect(wfs.threeOmegaWorkspace.selectedRTHit == nil)
        // Selection NOT cleared by clearResults
        #expect(wfs.selectedSearchResultIDs(for: .threeOmega) == [hit.id])

        #expect(canonicalState(wfs, workflow: .threeOmega).query == before.query)
        #expect(canonicalState(wfs, workflow: .threeOmega).results == before.results)
        #expect(canonicalState(wfs, workflow: .threeOmega).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .threeOmega).message == before.message)
    }

    // MARK: - 5a. toggleSearchHitSelection mutates selectedSearchResultIDs correctly

    @MainActor
    @Test("AHE toggleSearchHitSelection adds hit ID on first call")
    func aheToggleAddsID() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-toggle-add", workflowID: "ahe", workflowCanonicalID: "ahe")
        wfs.aheWorkspace.cachedSearchResults = [hit]

        wfs.toggleSearchHitSelection(hit.id, for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe) == [hit.id],
                "toggleSearchHitSelection must add the hit ID when it was not selected")
    }

    @MainActor
    @Test("AHE toggleSearchHitSelection removes hit ID on second call")
    func aheToggleRemovesID() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-toggle-remove", workflowID: "ahe", workflowCanonicalID: "ahe")
        wfs.aheWorkspace.cachedSearchResults = [hit]
        wfs.toggleSearchHitSelection(hit.id, for: .ahe)

        wfs.toggleSearchHitSelection(hit.id, for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe).isEmpty,
                "toggleSearchHitSelection must remove the hit ID when it was already selected")
    }

    @MainActor
    @Test("XY toggleSearchHitSelection adds hit ID on first call")
    func xyToggleAddsID() {
        let wfs = makeWFS()
        let hit = makeHit(id: "xy-toggle-add", workflowID: "xy", workflowCanonicalID: "xyRotation")
        wfs.xyRotationWorkspace.cachedSearchResults = [hit]

        wfs.toggleSearchHitSelection(hit.id, for: .xyRotation)

        #expect(wfs.selectedSearchResultIDs(for: .xyRotation) == [hit.id],
                "XY toggleSearchHitSelection must add the hit ID when it was not selected")
    }

    @MainActor
    @Test("3ω toggleSearchHitSelection adds hit ID on first call")
    func threeOmegaToggleAddsID() {
        let wfs = makeWFS()
        let hit = makeHit(id: "3w-toggle-add", workflowID: "3w", workflowCanonicalID: "threeOmega")
        wfs.threeOmegaWorkspace.cachedSearchResults = [hit]

        wfs.toggleSearchHitSelection(hit.id, for: .threeOmega)

        #expect(wfs.selectedSearchResultIDs(for: .threeOmega) == [hit.id],
                "3ω toggleSearchHitSelection must add the hit ID when it was not selected")
    }

    // MARK: - 5b. selection isolated across workflows

    @MainActor
    @Test("Selection for one workflow does not affect other workflows")
    func selectionIsPerWorkflow() {
        let wfs = makeWFS()
        let aheHit = makeHit(id: "ahe-iso", workflowID: "ahe", workflowCanonicalID: "ahe")
        let xyHit  = makeHit(id: "xy-iso",  workflowID: "xy",  workflowCanonicalID: "xyRotation")
        wfs.aheWorkspace.cachedSearchResults = [aheHit]
        wfs.xyRotationWorkspace.cachedSearchResults = [xyHit]

        wfs.toggleSearchHitSelection(aheHit.id, for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe) == [aheHit.id])
        #expect(wfs.selectedSearchResultIDs(for: .xyRotation).isEmpty)
        #expect(wfs.selectedSearchResultIDs(for: .threeOmega).isEmpty)
    }

    // MARK: - 6. selection does not mutate plot/preservation state

    @MainActor
    @Test("Selection operations do not mutate AHE plot title/label/legend overrides")
    func selectionDoesNotMutateAHEPlotOverrides() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-plot-boundary", workflowID: "ahe", workflowCanonicalID: "ahe")

        wfs.aheWorkspace.cachedSearchResults = [hit]
        wfs.aheWorkspace.updatePlotTitle("Boundary Title")
        wfs.aheWorkspace.updateXAxisLabel("X Custom")
        wfs.aheWorkspace.updateYAxisLabel("Y Custom")
        wfs.aheWorkspace.updateLegendPoint(CGPoint(x: 0.3, y: 0.7))

        let titleBefore = wfs.aheWorkspace.tabs.activeState.titleOverride
        let xBefore = wfs.aheWorkspace.tabs.activeState.xLabelOverride
        let yBefore = wfs.aheWorkspace.tabs.activeState.yLabelOverride
        let legendBefore = wfs.aheWorkspace.tabs.activeState.legendPoint

        wfs.toggleSearchHitSelection(hit.id, for: .ahe)
        wfs.selectAll(for: .ahe)
        wfs.deselectAll(for: .ahe)

        #expect(wfs.aheWorkspace.tabs.activeState.titleOverride == titleBefore)
        #expect(wfs.aheWorkspace.tabs.activeState.xLabelOverride == xBefore)
        #expect(wfs.aheWorkspace.tabs.activeState.yLabelOverride == yBefore)
        #expect(wfs.aheWorkspace.tabs.activeState.legendPoint == legendBefore)
    }
}
