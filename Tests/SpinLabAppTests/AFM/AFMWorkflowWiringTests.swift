import Foundation
import Testing
@testable import SpinLabApp

@Suite("AFM workflow wiring (Phase 4A)")
struct AFMWorkflowWiringTests {

    @MainActor
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    @MainActor
    @Test("workflowKind resolves .afm for the AFM workspace's own workflow id")
    func workflowKindResolvesAFM() {
        let wfs = makeWFS()
        #expect(wfs.workflowKind(for: wfs.afmWorkspace.workflowID) == .afm)
    }

    @MainActor
    @Test("AFM selection mode is .single")
    func afmSelectionModeIsSingle() {
        let wfs = makeWFS()
        #expect(wfs.selectionMode(for: wfs.afmWorkspace.workflowID) == .single)
    }

    @MainActor
    @Test("AFM search results project into afmWorkspace.cachedSearchResults")
    func afmSearchResultsProject() {
        let wfs = makeWFS()
        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/a.spinlab.json", measurementFilePath: "/tmp/a.ibw", sourceFilePath: "/tmp/a.ibw",
            workflowID: wfs.afmWorkspace.workflowID, workflowDisplayName: "AFM", workflowCanonicalID: "afm",
            batchID: "PN1", sampleKey: "PN1|b|STO|111", sampleSubstrate: "STO111",
            conditions: [:], channels: [], appliedAt: .distantPast
        )
        wfs.restoreSearchState(results: [hit], queryText: "afm", for: wfs.afmWorkspace.workflowID)
        #expect(wfs.afmWorkspace.cachedSearchResults.map(\.id) == [hit.id])
    }
}
