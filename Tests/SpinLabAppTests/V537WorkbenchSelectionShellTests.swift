import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

/// V5.3.7 Selection Shell Boundary — Phase 5C-1B
///
/// Locks documented boundaries while workflow-local selection mirror still exists:
/// - canonical search state lives in WorkbenchFeatureStore
/// - selection ops mutate workflow-local selection only
/// - selectAll denominator is workflow-local cachedSearchResults
/// - clearResults is workflow-specific local cleanup, not canonical search mutation
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
        workflow: WorkbenchWorkflowID,
        query: String,
        results: [WorkflowMeasurementSearchHit]
    ) {
        wfs.setSearchQueryText(query, for: workflow)
        wfs.restoreSearchState(results: results, queryText: query, for: workflow)
    }

    @MainActor
    private func canonicalState(_ wfs: WorkbenchFeatureStore, workflow: WorkbenchWorkflowID) -> CanonicalSearchState {
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
        wfs.aheWorkspace.toggleSearchHitSelection(hit.id)
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
        wfs.xyRotationWorkspace.toggleSearchHitSelection(hit.id)
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
        wfs.threeOmegaWorkspace.toggleSearchHitSelection(hit.id)
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
        wfs.aheWorkspace.selectedSearchResultIDs = [hit.id]
        let before = canonicalState(wfs, workflow: .ahe)

        wfs.aheWorkspace.deselectAll()

        #expect(wfs.aheWorkspace.selectedSearchResultIDs.isEmpty)
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
        wfs.xyRotationWorkspace.selectedSearchResultIDs = [hit.id]
        let before = canonicalState(wfs, workflow: .xyRotation)

        wfs.xyRotationWorkspace.deselectAll()

        #expect(wfs.xyRotationWorkspace.selectedSearchResultIDs.isEmpty)
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
        wfs.threeOmegaWorkspace.selectedSearchResultIDs = [hit.id]
        let before = canonicalState(wfs, workflow: .threeOmega)

        wfs.threeOmegaWorkspace.deselectAll()

        #expect(wfs.threeOmegaWorkspace.selectedSearchResultIDs.isEmpty)
        #expect(wfs.threeOmegaWorkspace.cachedSearchResults == [hit])
        #expect(canonicalState(wfs, workflow: .threeOmega).query == before.query)
        #expect(canonicalState(wfs, workflow: .threeOmega).results == before.results)
        #expect(canonicalState(wfs, workflow: .threeOmega).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .threeOmega).message == before.message)
    }

    // MARK: - 3. selectAll uses local mirror as denominator/source

    @MainActor
    @Test("AHE selectAll uses local cachedSearchResults IDs")
    func aheSelectAllUsesLocalMirrorIDs() {
        let wfs = makeWFS()
        let local = [
            makeHit(id: "ahe-local-1", workflowID: "ahe", workflowCanonicalID: "ahe"),
            makeHit(id: "ahe-local-2", workflowID: "ahe", workflowCanonicalID: "ahe", sampleKey: "PN32|o|STO|111")
        ]
        wfs.aheWorkspace.cachedSearchResults = local
        wfs.aheWorkspace.selectedSearchResultIDs = []

        wfs.aheWorkspace.selectAll()

        #expect(wfs.aheWorkspace.selectedSearchResultIDs == Set(local.map(\.id)))
    }

    @MainActor
    @Test("XY selectAll uses local cachedSearchResults IDs")
    func xySelectAllUsesLocalMirrorIDs() {
        let wfs = makeWFS()
        let local = [
            makeHit(id: "xy-local-1", workflowID: "xy", workflowCanonicalID: "xyRotation"),
            makeHit(id: "xy-local-2", workflowID: "xy", workflowCanonicalID: "xyRotation", sampleKey: "PN32|o|STO|111")
        ]
        wfs.xyRotationWorkspace.cachedSearchResults = local
        wfs.xyRotationWorkspace.selectedSearchResultIDs = []

        wfs.xyRotationWorkspace.selectAll()

        #expect(wfs.xyRotationWorkspace.selectedSearchResultIDs == Set(local.map(\.id)))
    }

    @MainActor
    @Test("3ω selectAll uses local cachedSearchResults IDs")
    func threeOmegaSelectAllUsesLocalMirrorIDs() {
        let wfs = makeWFS()
        let local = [
            makeHit(id: "3w-local-1", workflowID: "3w", workflowCanonicalID: "threeOmega"),
            makeHit(id: "3w-local-2", workflowID: "3w", workflowCanonicalID: "threeOmega", sampleKey: "PN32|o|STO|111")
        ]
        wfs.threeOmegaWorkspace.cachedSearchResults = local
        wfs.threeOmegaWorkspace.selectedSearchResultIDs = []

        wfs.threeOmegaWorkspace.selectAll()

        #expect(wfs.threeOmegaWorkspace.selectedSearchResultIDs == Set(local.map(\.id)))
    }

    // MARK: - 4. clearResults behavior is workflow-local

    @MainActor
    @Test("AHE clearResults clears selected IDs and local cache only")
    func aheClearResultsIsLocalOnly() {
        let wfs = makeWFS()
        let hit = makeHit(id: "ahe-clear", workflowID: "ahe", workflowCanonicalID: "ahe")
        seedCanonicalState(wfs, workflow: .ahe, query: "ahe clear", results: [hit])
        let before = canonicalState(wfs, workflow: .ahe)
        wfs.aheWorkspace.cachedSearchResults = [hit]
        wfs.aheWorkspace.selectedSearchResultIDs = [hit.id]

        wfs.aheWorkspace.clearResults()

        #expect(wfs.aheWorkspace.selectedSearchResultIDs.isEmpty)
        #expect(wfs.aheWorkspace.cachedSearchResults.isEmpty)
        #expect(canonicalState(wfs, workflow: .ahe).query == before.query)
        #expect(canonicalState(wfs, workflow: .ahe).results == before.results)
        #expect(canonicalState(wfs, workflow: .ahe).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .ahe).message == before.message)
    }

    @MainActor
    @Test("XY clearResults clears selected IDs and local cache only")
    func xyClearResultsIsLocalOnly() {
        let wfs = makeWFS()
        let hit = makeHit(id: "xy-clear", workflowID: "xy", workflowCanonicalID: "xyRotation")
        seedCanonicalState(wfs, workflow: .xyRotation, query: "xy clear", results: [hit])
        let before = canonicalState(wfs, workflow: .xyRotation)
        wfs.xyRotationWorkspace.cachedSearchResults = [hit]
        wfs.xyRotationWorkspace.selectedSearchResultIDs = [hit.id]

        wfs.xyRotationWorkspace.clearResults()

        #expect(wfs.xyRotationWorkspace.selectedSearchResultIDs.isEmpty)
        #expect(wfs.xyRotationWorkspace.cachedSearchResults.isEmpty)
        #expect(canonicalState(wfs, workflow: .xyRotation).query == before.query)
        #expect(canonicalState(wfs, workflow: .xyRotation).results == before.results)
        #expect(canonicalState(wfs, workflow: .xyRotation).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .xyRotation).message == before.message)
    }

    @MainActor
    @Test("3ω clearResults clears selected IDs/local cache and RT local cleanup")
    func threeOmegaClearResultsIncludesRTCleanupAndKeepsCanonical() {
        let wfs = makeWFS()
        let hit = makeHit(id: "3w-clear", workflowID: "3w", workflowCanonicalID: "threeOmega")
        let rtHit = makeHit(id: "3w-rt", workflowID: "3w", workflowCanonicalID: "threeOmega")

        seedCanonicalState(wfs, workflow: .threeOmega, query: "3w clear", results: [hit])
        let before = canonicalState(wfs, workflow: .threeOmega)

        wfs.threeOmegaWorkspace.cachedSearchResults = [hit]
        wfs.threeOmegaWorkspace.selectedSearchResultIDs = [hit.id]
        wfs.threeOmegaWorkspace.rtQuery = "rt q"
        wfs.threeOmegaWorkspace.rtSearchResults = [rtHit]
        wfs.threeOmegaWorkspace.rtSearchMessage = "rt msg"
        wfs.threeOmegaWorkspace.isRTSearching = true
        wfs.threeOmegaWorkspace.showRTPopover = true
        wfs.threeOmegaWorkspace.selectedRTHit = rtHit

        wfs.threeOmegaWorkspace.clearResults()

        #expect(wfs.threeOmegaWorkspace.selectedSearchResultIDs.isEmpty)
        #expect(wfs.threeOmegaWorkspace.cachedSearchResults.isEmpty)
        #expect(wfs.threeOmegaWorkspace.rtQuery.isEmpty)
        #expect(wfs.threeOmegaWorkspace.rtSearchResults.isEmpty)
        #expect(wfs.threeOmegaWorkspace.rtSearchMessage == nil)
        #expect(wfs.threeOmegaWorkspace.isRTSearching == false)
        #expect(wfs.threeOmegaWorkspace.showRTPopover == false)
        #expect(wfs.threeOmegaWorkspace.selectedRTHit == nil)

        #expect(canonicalState(wfs, workflow: .threeOmega).query == before.query)
        #expect(canonicalState(wfs, workflow: .threeOmega).results == before.results)
        #expect(canonicalState(wfs, workflow: .threeOmega).isRunning == before.isRunning)
        #expect(canonicalState(wfs, workflow: .threeOmega).message == before.message)
    }

    // MARK: - 5. selection does not mutate plot/preservation state

    @MainActor
    @Test("Selection operations do not mutate AHE plot title/axis/legend overrides")
    func selectionDoesNotMutateAHEPlotOverrides() {
        let store = AHEWorkspaceStore()
        let hit = makeHit(id: "ahe-plot-boundary", workflowID: "ahe", workflowCanonicalID: "ahe")

        store.cachedSearchResults = [hit]
        store.updatePlotTitle("Boundary Title")
        store.plotAxisXOverride = "X Custom"
        store.plotAxisYOverride = "Y Custom"
        store.updateLegendPoint(CGPoint(x: 0.3, y: 0.7))

        let titleBefore = store.tabs.activeState.titleOverride
        let xBefore = store.plotAxisXOverride
        let yBefore = store.plotAxisYOverride
        let legendBefore = store.tabs.activeState.legendPoint

        store.toggleSearchHitSelection(hit.id)
        store.selectAll()
        store.deselectAll()

        #expect(store.tabs.activeState.titleOverride == titleBefore)
        #expect(store.plotAxisXOverride == xBefore)
        #expect(store.plotAxisYOverride == yBefore)
        #expect(store.tabs.activeState.legendPoint == legendBefore)
    }
}
