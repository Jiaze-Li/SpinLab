import Foundation
import Testing
@testable import SpinLabApp

/// Regression coverage for the Library browser-vs-drawer selection ownership
/// split: `LibraryFeatureStore` now owns two independent full selection
/// triples (`librarySelected*` for the drawer, `libraryBrowserSelected*` for
/// the browser/preview tree) instead of one shared triple gated by
/// `libraryActiveSelectionSource`.
@MainActor
@Suite("V5.7.0 Library Browser/Drawer Selection Split")
struct V570LibraryBrowserDrawerSelectionSplitTests {

    // MARK: - 1. Selecting a browser preview does not mutate the drawer selection triple

    @Test("selectBrowserSample leaves drawer selection triple untouched")
    func selectBrowserSample_doesNotMutateDrawer() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "s1"

        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "b1"

        _ = store.selectBrowserSample()

        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.librarySelectedBatchId == "B1")
        #expect(store.librarySelectedSampleId == "s1")
        #expect(store.libraryActiveSelectionSource == .browser)
    }

    // MARK: - 2. Selecting a drawer sample does not mutate the browser selection triple

    @Test("selectExistingDrawer leaves browser selection triple untouched")
    func selectExistingDrawer_doesNotMutateBrowser() {
        let store = TestFixtures.makeStore()
        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "b1"

        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B1", samples: [TestFixtures.makeSample(id: "s1", batchId: "B1")])]
        ]

        _ = store.selectExistingDrawer(prefix: "STO", batchId: "B1", sampleId: "s1")

        #expect(store.libraryBrowserSelectedPrefix == "PN20")
        #expect(store.libraryBrowserSelectedBatchId == "PN20-A")
        #expect(store.libraryBrowserSelectedSampleId == "b1")
        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.librarySelectedBatchId == "B1")
        #expect(store.librarySelectedSampleId == "s1")
        #expect(store.libraryActiveSelectionSource == .drawer)
    }

    // MARK: - 3. Drawer reconciliation does not mutate browser selection

    @Test("normalizeLibrarySelection (drawer reconciliation) does not mutate browser selection")
    func normalizeLibrarySelection_doesNotMutateBrowser() {
        let store = TestFixtures.makeStore()
        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "b1"

        // Drawer selection points at a batch that no longer exists — normalization
        // must reset the drawer triple, but must never touch the browser triple.
        store.librarySelectedPrefix = "GONE"
        store.librarySelectedBatchId = "B1"
        store.librarySelectedSampleId = "s1"
        store.libraryExistingGroups = [
            "STO": [LibraryPreviewBatchGroup(batchId: "B2", samples: [TestFixtures.makeSample(id: "s2", batchId: "B2")])]
        ]

        store.normalizeLibrarySelection()

        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.libraryBrowserSelectedPrefix == "PN20")
        #expect(store.libraryBrowserSelectedBatchId == "PN20-A")
        #expect(store.libraryBrowserSelectedSampleId == "b1")
    }

    // MARK: - 4. Browser reconciliation is a pure function isolated from drawer state

    @Test("LibrarySelectionSync.syncBrowserSelection is a pure Input/Output triple with no drawer coupling")
    func syncBrowserSelection_pureFunction_hasNoDrawerCoupling() {
        // The caller (LibraryPrimaryView.syncBrowserSelection) writes this output only
        // into libraryBrowserSelected*, mirroring V226LibrarySelectionSyncTests'
        // drawer-side coverage of the equivalent pure function.
        let output = LibrarySelectionSync.syncBrowserSelection(
            input: .init(selectedPrefix: "GONE", selectedBatchId: "B1", selectedSampleId: "s1"),
            previewGroupsByPrefix: [
                "PN20": [LibraryPreviewBatchGroup(batchId: "PN20-A", samples: [TestFixtures.makeSample(id: "b1", batchId: "PN20-A")])]
            ]
        )
        #expect(output.selectedPrefix == "PN20")
        #expect(output.selectedBatchId == "PN20-A")
        #expect(output.selectedSampleId == "b1")
    }

    // MARK: - 5. Detail focus/source resolves the displayed sample from the correct independent selection

    @Test("currentSelectionSampleId resolves from browser triple when source is .browser")
    func currentSelectionSampleId_browserSource() {
        let store = TestFixtures.makeStore()
        store.libraryActiveSelectionSource = .browser
        store.libraryBrowserSelectedSampleId = "browser-sample"
        store.librarySelectedSampleId = "drawer-sample"
        #expect(store.currentSelectionSampleId == "browser-sample")
    }

    @Test("currentSelectionSampleId resolves from drawer triple when source is .drawer")
    func currentSelectionSampleId_drawerSource() {
        let store = TestFixtures.makeStore()
        store.libraryActiveSelectionSource = .drawer
        store.libraryBrowserSelectedSampleId = "browser-sample"
        store.librarySelectedSampleId = "drawer-sample"
        #expect(store.currentSelectionSampleId == "drawer-sample")
    }

    // MARK: - 6. Interaction snapshot restore/capture keeps the two triples independent,
    //            including legacy (pre-split) snapshot compatibility.

    @Test("restoreInteraction sets browser and drawer triples independently")
    func restoreInteraction_setsIndependentTriples() {
        let store = TestFixtures.makeStore()
        store.restoreInteraction(
            libraryActiveSelectionSource: .drawer,
            librarySelectedPrefix: "STO",
            librarySelectedBatchId: "B001",
            librarySelectedSampleId: "S1",
            libraryBrowserSelectedPrefix: "PN20",
            libraryBrowserSelectedBatchId: "PN20-A",
            libraryBrowserSelectedSampleId: "b1"
        )
        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.librarySelectedBatchId == "B001")
        #expect(store.librarySelectedSampleId == "S1")
        #expect(store.libraryBrowserSelectedPrefix == "PN20")
        #expect(store.libraryBrowserSelectedBatchId == "PN20-A")
        #expect(store.libraryBrowserSelectedSampleId == "b1")
    }

    @Test("restoreInteraction without browser params (legacy snapshot) preserves drawer values and defaults browser to nil")
    func restoreInteraction_legacySnapshotCompatibility() {
        let store = TestFixtures.makeStore()
        store.libraryBrowserSelectedPrefix = "STALE"
        store.libraryBrowserSelectedBatchId = "STALE-B"
        store.libraryBrowserSelectedSampleId = "stale-sample"

        // Simulates restoring from a pre-split on-disk snapshot: the decoded value has
        // no browser keys, so a caller built from it omits the new parameters and they
        // take their nil default — proving the legacy path can't leak a stale browser
        // triple back in disguised as "restored" state.
        store.restoreInteraction(
            libraryActiveSelectionSource: .drawer,
            librarySelectedPrefix: "STO",
            librarySelectedBatchId: "B001",
            librarySelectedSampleId: "S1"
        )

        #expect(store.librarySelectedPrefix == "STO")
        #expect(store.librarySelectedBatchId == "B001")
        #expect(store.librarySelectedSampleId == "S1")
        #expect(store.libraryBrowserSelectedPrefix == nil)
        #expect(store.libraryBrowserSelectedBatchId == nil)
        #expect(store.libraryBrowserSelectedSampleId == nil)
    }

    @Test("captureInteraction writes both triples into the snapshot independently")
    func captureInteraction_writesBothTriples() {
        let store = TestFixtures.makeStore()
        store.librarySelectedPrefix = "STO"
        store.librarySelectedBatchId = "B001"
        store.librarySelectedSampleId = "S1"
        store.libraryBrowserSelectedPrefix = "PN20"
        store.libraryBrowserSelectedBatchId = "PN20-A"
        store.libraryBrowserSelectedSampleId = "b1"

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        #expect(snapshot.librarySelectedPrefix == "STO")
        #expect(snapshot.librarySelectedBatchId == "B001")
        #expect(snapshot.librarySelectedSampleId == "S1")
        #expect(snapshot.libraryBrowserSelectedPrefix == "PN20")
        #expect(snapshot.libraryBrowserSelectedBatchId == "PN20-A")
        #expect(snapshot.libraryBrowserSelectedSampleId == "b1")
    }

    @Test("LibraryInteractionState decodes legacy JSON missing browserSelected* keys without error")
    func libraryInteractionState_legacyJSONDecodeCompatibility() throws {
        let legacyJSON = """
        {
            "selectedPrefix": "STO",
            "selectedBatchId": "B001",
            "selectedSampleId": "S1",
            "isLibrarySettingsExpanded": true,
            "isRegistryWorkspaceExpanded": true,
            "isSearchWorkspaceExpanded": true,
            "isMetadataSectionExpanded": true,
            "searchBatchIdText": "",
            "searchSubstrateText": "",
            "searchKeywordText": "",
            "searchThicknessText": "",
            "searchOxygenText": "",
            "searchTemperatureText": "",
            "searchEnergyText": "",
            "searchThicknessToleranceText": "",
            "searchOxygenToleranceText": "",
            "searchTemperatureToleranceText": "",
            "searchEnergyToleranceText": "",
            "searchHasExecuted": false
        }
        """
        let decoded = try JSONDecoder().decode(LibraryInteractionState.self, from: Data(legacyJSON.utf8))
        #expect(decoded.selectedPrefix == "STO")
        #expect(decoded.selectedBatchId == "B001")
        #expect(decoded.selectedSampleId == "S1")
        #expect(decoded.browserSelectedPrefix == nil)
        #expect(decoded.browserSelectedBatchId == nil)
        #expect(decoded.browserSelectedSampleId == nil)
    }
}

// MARK: - Test fixtures

private enum TestFixtures {
    /// Creates a LibraryFeatureStore with no rootPath set (isolated from disk settings).
    @MainActor
    static func makeStore() -> LibraryFeatureStore {
        let store = LibraryFeatureStore()
        store.librarySettings.rootPath = nil
        return store
    }

    static func makeSample(id: String, batchId: String) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: id,
            batchId: batchId,
            substrateRaw: "",
            substrateDisplay: "",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: Date()
        )
    }
}
