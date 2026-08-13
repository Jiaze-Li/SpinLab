import Foundation
import Testing
@testable import SpinLabApp

/// V7.2.2 Selected Hits Tray — Gate 7.2 follow-up
///
/// Covers:
/// - isAllSelected uses current-result subset semantics, not count equality
/// - Changing search results after selection does not clear selected IDs
/// - Select All is additive (appends, never drops previous selections)
/// - Deselect All (scoped) removes only current search result IDs
/// - Tray display data remains available after search results change
/// - Row remove removes exactly one hit
/// - Tray Clear removes entire basket
@Suite("V7.2.2 Selected Hits Tray")
struct V722SelectedHitsTrayTests {

    private func makeHit(
        id: String,
        workflowID: String = "ahe",
        workflowCanonicalID: String = "ahe",
        displayName: String = "AHE",
        sampleKey: String = "PN31|b|STO|111",
        conditions: [String: String] = ["temperature": "80K"],
        filename: String? = nil
    ) -> WorkflowMeasurementSearchHit {
        let path = filename.map { "/data/\($0)" } ?? "/data/\(id).dat"
        return WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: path,
            sourceFilePath: path,
            workflowID: workflowID,
            workflowDisplayName: displayName,
            workflowCanonicalID: workflowCanonicalID,
            batchID: "PN31",
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: conditions,
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    @MainActor
    private func makeWFS() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    // MARK: - 1. isAllSelected uses subset semantics

    @MainActor
    @Test("isAllSelected is false when only a subset of current results is selected")
    func isAllSelectedSubsetSemanticsPartial() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "s1")
        let h2 = makeHit(id: "s2")
        wfs.aheWorkspace.cachedSearchResults = [h1, h2]

        wfs.toggleSearchHitSelection(h1.id, for: .ahe)

        #expect(!wfs.isAllSelected(for: .ahe),
                "selecting one of two current results must not satisfy isAllSelected")
    }

    @MainActor
    @Test("isAllSelected is true only when all current result IDs are selected")
    func isAllSelectedSubsetSemanticsAll() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "a1")
        let h2 = makeHit(id: "a2")
        wfs.aheWorkspace.cachedSearchResults = [h1, h2]

        wfs.toggleSearchHitSelection(h1.id, for: .ahe)
        wfs.toggleSearchHitSelection(h2.id, for: .ahe)

        #expect(wfs.isAllSelected(for: .ahe))
    }

    @MainActor
    @Test("isAllSelected is true when selected set is superset of current results")
    func isAllSelectedSupersetOfCurrentResults() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "sup1")
        let h2 = makeHit(id: "sup2")
        let h3 = makeHit(id: "sup3")
        // Select all three first
        wfs.aheWorkspace.cachedSearchResults = [h1, h2, h3]
        wfs.selectAll(for: .ahe)
        // Now narrow denominator to just h1 and h2
        wfs.aheWorkspace.cachedSearchResults = [h1, h2]

        // All current results (h1, h2) are in selected set — should be true
        #expect(wfs.isAllSelected(for: .ahe))
    }

    // MARK: - 2. Changing search results does not clear selection

    @MainActor
    @Test("Changing search results after selection does not clear selected IDs")
    func searchResultChangeDoesNotClearSelection() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "persist1")
        wfs.aheWorkspace.cachedSearchResults = [h1]
        wfs.toggleSearchHitSelection(h1.id, for: .ahe)

        // Simulate search returning different results
        let h2 = makeHit(id: "new-result")
        wfs.aheWorkspace.cachedSearchResults = [h2]

        #expect(wfs.selectedSearchResultIDs(for: .ahe).contains(h1.id),
                "previously selected ID must survive a search result change")
    }

    // MARK: - 3. Select All is additive

    @MainActor
    @Test("Select All appends current result IDs without dropping previously selected IDs")
    func selectAllIsAdditive() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "prev1")
        let h2 = makeHit(id: "next1")

        // Select h1 from first search
        wfs.aheWorkspace.cachedSearchResults = [h1]
        wfs.toggleSearchHitSelection(h1.id, for: .ahe)

        // Switch to second search and Select All
        wfs.aheWorkspace.cachedSearchResults = [h2]
        wfs.selectAll(for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe).contains(h1.id),
                "Select All must not drop previously selected h1")
        #expect(wfs.selectedSearchResultIDs(for: .ahe).contains(h2.id),
                "Select All must add new h2")
    }

    // MARK: - 4. Deselect Current Results removes only current search result IDs

    @MainActor
    @Test("deselectCurrentResults removes only current result IDs, keeps previous selections")
    func deselectCurrentResultsIsScopedToCurrentResults() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "keep1")
        let h2 = makeHit(id: "remove1")

        // Select h1 from first search
        wfs.aheWorkspace.cachedSearchResults = [h1]
        wfs.toggleSearchHitSelection(h1.id, for: .ahe)

        // Now current search = h2, select it
        wfs.aheWorkspace.cachedSearchResults = [h2]
        wfs.toggleSearchHitSelection(h2.id, for: .ahe)

        // Deselect current results (h2 only)
        wfs.deselectCurrentResults(for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe).contains(h1.id),
                "h1 from previous search must survive deselectCurrentResults")
        #expect(!wfs.selectedSearchResultIDs(for: .ahe).contains(h2.id),
                "h2 (current result) must be removed")
    }

    // MARK: - 5. Tray display data survives search result change

    @MainActor
    @Test("Tray display info remains available after search results change")
    func trayDisplayInfoSurvivesSearchChange() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "tray1", displayName: "AHE", filename: "run_001.dat")
        wfs.aheWorkspace.cachedSearchResults = [h1]
        wfs.toggleSearchHitSelection(h1.id, for: .ahe)

        // Simulate search returning different results (h1 no longer in denominator)
        let h2 = makeHit(id: "tray-new")
        wfs.aheWorkspace.cachedSearchResults = [h2]

        let infos = wfs.selectedHitDisplayInfos(for: .ahe)
        #expect(infos.count == 1)
        #expect(infos.first?.id == h1.id)
        #expect(infos.first?.shortFilename == "run_001.dat")
        #expect(infos.first?.workflowDisplayName == "AHE")
    }

    // MARK: - 6. Row remove removes exactly one hit

    @MainActor
    @Test("Toggle (row remove) removes only the targeted hit from selection")
    func rowRemoveRemovesOneHit() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "row1")
        let h2 = makeHit(id: "row2")
        wfs.aheWorkspace.cachedSearchResults = [h1, h2]
        wfs.toggleSearchHitSelection(h1.id, for: .ahe)
        wfs.toggleSearchHitSelection(h2.id, for: .ahe)

        wfs.toggleSearchHitSelection(h1.id, for: .ahe)

        #expect(!wfs.selectedSearchResultIDs(for: .ahe).contains(h1.id),
                "h1 must be removed")
        #expect(wfs.selectedSearchResultIDs(for: .ahe).contains(h2.id),
                "h2 must still be selected")
    }

    // MARK: - 7. Tray Clear clears entire basket

    @MainActor
    @Test("deselectAll clears all selected hits for the workflow")
    func trayClearClearsEntireBasket() {
        let wfs = makeWFS()
        let h1 = makeHit(id: "clear1")
        let h2 = makeHit(id: "clear2")
        wfs.aheWorkspace.cachedSearchResults = [h1, h2]
        wfs.toggleSearchHitSelection(h1.id, for: .ahe)
        wfs.toggleSearchHitSelection(h2.id, for: .ahe)

        wfs.deselectAll(for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe).isEmpty)
        #expect(wfs.selectedHitDisplayInfos(for: .ahe).isEmpty)
    }

    @MainActor
    @Test("deselectAll does not affect selection in other workflows")
    func trayClearIsWorkflowScoped() {
        let wfs = makeWFS()
        let aheHit = makeHit(id: "ahe-basket")
        let xyHit = makeHit(id: "xy-basket", workflowID: "xy", workflowCanonicalID: "xyRotation", displayName: "XY")
        wfs.aheWorkspace.cachedSearchResults = [aheHit]
        wfs.xyRotationWorkspace.cachedSearchResults = [xyHit]
        wfs.toggleSearchHitSelection(aheHit.id, for: .ahe)
        wfs.toggleSearchHitSelection(xyHit.id, for: .xyRotation)

        wfs.deselectAll(for: .ahe)

        #expect(wfs.selectedSearchResultIDs(for: .ahe).isEmpty)
        #expect(wfs.selectedSearchResultIDs(for: .xyRotation).contains(xyHit.id),
                "XY selection must be unaffected by AHE clear")
    }

    // MARK: - 8. Full cross-search basket regression sequence

    @MainActor
    @Test("Selected Hits basket survives a search replacement end to end")
    func crossSearchBasketFullSequence() {
        let wfs = makeWFS()
        let a1 = makeHit(id: "A1")
        let a2 = makeHit(id: "A2")
        let b1 = makeHit(id: "B1")
        let b2 = makeHit(id: "B2")

        // 1-2. Search A returns A1, A2; select both.
        wfs.aheWorkspace.cachedSearchResults = [a1, a2]
        wfs.toggleSearchHitSelection(a1.id, for: .ahe)
        wfs.toggleSearchHitSelection(a2.id, for: .ahe)

        // 3. basket count = 2, tray visible, rows = A1, A2
        #expect(wfs.basketSelectedCount(for: .ahe) == 2)
        #expect(Set(wfs.selectedHitDisplayInfos(for: .ahe).map(\.id)) == [a1.id, a2.id])

        // 4. Search B returns B1, B2 — nothing selected from B yet.
        wfs.aheWorkspace.cachedSearchResults = [b1, b2]

        // 5. Before selecting anything from B: basket unchanged, current-result count is 0,
        //    tray stays visible with the same rows.
        #expect(wfs.basketSelectedCount(for: .ahe) == 2,
                "basket count must survive a search replacement even with zero overlap")
        #expect(wfs.selectedSearchResultIDs(for: .ahe).isDisjoint(with: [b1.id, b2.id]),
                "no B results are selected yet")
        #expect(Set(wfs.selectedHitDisplayInfos(for: .ahe).map(\.id)) == [a1.id, a2.id],
                "tray rows must still be A1, A2")

        // 6. Select B1, B2.
        wfs.toggleSearchHitSelection(b1.id, for: .ahe)
        wfs.toggleSearchHitSelection(b2.id, for: .ahe)

        // 7. basket count = 4, tray rows = A1, A2, B1, B2
        #expect(wfs.basketSelectedCount(for: .ahe) == 4)
        #expect(Set(wfs.selectedHitDisplayInfos(for: .ahe).map(\.id)) == [a1.id, a2.id, b1.id, b2.id])

        // 8. Deselect All on the current B search.
        wfs.deselectCurrentResults(for: .ahe)

        // 9. B1/B2 removed, A1/A2 remain, basket count = 2, tray remains visible.
        #expect(wfs.basketSelectedCount(for: .ahe) == 2)
        #expect(Set(wfs.selectedSearchResultIDs(for: .ahe)) == [a1.id, a2.id])

        // 10. Clear Selected.
        wfs.deselectAll(for: .ahe)

        // 11. basket empty, tray disappears (basketSelectedCount == 0 drives tray visibility).
        #expect(wfs.basketSelectedCount(for: .ahe) == 0)
        #expect(wfs.selectedHitDisplayInfos(for: .ahe).isEmpty)
    }
}
