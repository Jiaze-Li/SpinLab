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
}
