import Foundation
import Testing
@testable import SpinLabApp

/// PR 2 — Management / Search separation.
@MainActor
@Suite("PR2 Library Management & Search", .serialized, .rulesGlobalState)
struct PR2LibraryManagementSearchTests {

    // MARK: - Fixtures

    private func sample(_ id: String, batch: String, substrate: String = "", numeric: [String: Double] = [:]) -> LibrarySample {
        LibrarySample(
            id: id, displayName: id, batchId: batch, substrateRaw: substrate, substrateDisplay: substrate,
            substrateTokens: [], substrateTags: [], metadata: [:], numericTags: numeric,
            numericDisplay: [:], updatedAt: Date()
        )
    }

    private func draft(_ text: String) -> LibrarySampleEditDraft {
        LibrarySampleEditDraft(
            sampleId: "PN1-a", batchId: "PN1", baseUpdatedAt: Date(), substrateTagsText: text,
            numericValues: [], metadataValues: []
        )
    }

    private func makeState() -> (SpinLabAppState, LibraryWorkspaceState) {
        let appState = SpinLabAppState()
        let lib = appState.library
        lib.librarySettings.rootPath = nil
        lib.libraryExistingGroups = [
            "PN": [
                LibraryPreviewBatchGroup(batchId: "PN1", samples: [
                    sample("PN1-a", batch: "PN1", substrate: "STO", numeric: ["厚度": 10]),
                    sample("PN1-b", batch: "PN1", substrate: "LAO", numeric: ["厚度": 50])
                ]),
                LibraryPreviewBatchGroup(batchId: "PN2", samples: [sample("PN2-a", batch: "PN2", substrate: "STO")])
            ]
        ]
        appState.selectedArea = .library
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-a"))
        lib.libraryBrowserSelectedPrefix = "PN"
        lib.libraryBrowserSelectedBatchId = "PN2"
        lib.libraryBrowserSelectedSampleId = "PN2-a"
        return (appState, LibraryWorkspaceState())
    }

    private struct Selections: Equatable {
        var drawer: [String?]
        var browser: [String?]
        var source: LibrarySelectionSource
        var draftText: String?
    }

    private func selections(_ s: SpinLabAppState) -> Selections {
        let l = s.library
        return Selections(
            drawer: [l.librarySelectedPrefix, l.librarySelectedBatchId, l.librarySelectedSampleId],
            browser: [l.libraryBrowserSelectedPrefix, l.libraryBrowserSelectedBatchId, l.libraryBrowserSelectedSampleId],
            source: l.libraryActiveSelectionSource,
            draftText: l.librarySampleEditDraft?.substrateTagsText
        )
    }

    // MARK: - Management (AC1/AC2)

    @Test("Management Registry Preview is explicit and cleared on every Library-root entry")
    func managementPreviewFlagLifecycle() {
        let (s, _) = makeState()
        #expect(s.library.isManagementPreviewActive == false)
        s.library.isManagementPreviewActive = true
        s.navigate(to: .librarySearch)
        s.navigate(to: .library)
        #expect(s.library.currentRoute == .management)
        #expect(s.library.isManagementPreviewActive == false)

        // Re-tapping the root while a preview is open returns to Overview.
        s.library.isManagementPreviewActive = true
        s.navigate(to: .library)
        #expect(s.library.isManagementPreviewActive == false)
    }

    @Test("leftover Drawer focus does not surface a Drawer sample in Management")
    func managementDefaultsToOverviewDespiteDrawerSelection() {
        let (s, _) = makeState()
        // Drawer owns focus with PN1-a selected, then the user enters Management.
        s.navigate(to: .library)
        #expect(s.library.libraryActiveSelectionSource == .drawer)
        #expect(s.library.librarySelectedSampleId == "PN1-a")
        #expect(s.library.isManagementPreviewActive == false) // => Overview, not the Drawer sample
    }

    @Test("Management and Search do not mount the legacy page; Sample Workspace has its own page (PR3)")
    func pageSplitStructure() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let primary = try String(contentsOf: root.appendingPathComponent("Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift"), encoding: .utf8)
        #expect(!primary.contains("existingDrawerSampleSection"))
        #expect(!primary.contains(".sampleWorkspace"))
        #expect(!primary.contains("searchWorkspaceSection"))
        let content = try String(contentsOf: root.appendingPathComponent("Sources/SpinLabApp/App/AppPrimaryContent.swift"), encoding: .utf8)
        #expect(content.contains("LibraryPrimaryView(state: libraryState, mode: .management)"))
        #expect(content.contains("LibrarySampleWorkspacePrimaryView(state: libraryState)"))
    }

    @Test("Browser-focused Registry Preview is read-only; mutations stay gated on Drawer focus")
    func registryPreviewIsReadOnly() {
        let (s, _) = makeState()
        s.navigate(to: .library)
        s.library.libraryActiveSelectionSource = .browser
        s.library.isManagementPreviewActive = true
        #expect(s.library.canMutateLibraryDetailSelection == false)
        #expect(s.library.canEditSelectedLibrarySample == false)
    }

    @Test("Registry Preview keeps a dirty Drawer draft untouched")
    func registryPreviewKeepsDraft() {
        let (s, _) = makeState()
        s.library.libraryState.sampleEditOriginalDraft = draft("clean")
        s.library.librarySampleEditDraft = draft("dirty")
        let before = selections(s)
        #expect(s.navigate(to: .library) == .deferred) // leaving the editor is guarded
        #expect(selections(s) == before)
    }

    // MARK: - Search (AC3-AC6)

    private func searchState(_ s: SpinLabAppState, _ w: LibraryWorkspaceState, batch: String = "", substrate: String = "", thickness: String = "", tol: String = "") {
        w.searchBatchIdText = batch
        w.searchSubstrateText = substrate
        w.searchThicknessText = thickness
        w.searchThicknessToleranceText = tol
    }

    @Test("Search results equal the legacy matcher applied to the same sorted sample list")
    func searchEquivalence() {
        let (s, w) = makeState()
        let service = LibraryViewComputationService()
        let cases: [(String, String, String, String)] = [
            ("", "", "", ""), ("PN1", "", "", ""), ("", "sto", "", ""),
            ("", "", "10", "1"), ("", "", "30", "25"), ("PN1", "LAO", "50", "0"), ("zzz", "", "", "")
        ]
        for c in cases {
            searchState(s, w, batch: c.0, substrate: c.1, thickness: c.2, tol: c.3)
            w.executeSearch(appState: s)
            let expected = w.allExistingDrawerSamples(s).filter {
                service.matchesSearch(sample: $0.sample, filters: w.searchFilters)
            }
            #expect(w.searchMatchedResults == expected, "case \(c)")
            #expect(w.searchHasExecuted)
        }
        // AND semantics: PN1 + STO only matches PN1-a.
        searchState(s, w, batch: "PN1", substrate: "STO")
        w.executeSearch(appState: s)
        #expect(w.searchMatchedResults.map(\.sample.id) == ["PN1-a"])
        // Tolerance: 30 ± 25 matches thickness 10? |10-30|=20<=25 yes; 50 yes.
        searchState(s, w, thickness: "30", tol: "25")
        w.executeSearch(appState: s)
        #expect(Set(w.searchMatchedResults.map(\.sample.id)) == ["PN1-a", "PN1-b"])
    }

    @Test("Clear resets filters, results, executed flag and preview")
    func clearSemantics() {
        let (s, w) = makeState()
        searchState(s, w, batch: "PN")
        w.executeSearch(appState: s)
        w.selectSearchPreview(w.searchMatchedResults[0])
        w.clearSearchFilters()
        #expect(w.searchBatchIdText.isEmpty && w.searchMatchedResults.isEmpty)
        #expect(w.searchHasExecuted == false && w.searchPreviewTarget == nil)
    }

    @Test("selecting a Search result changes neither Drawer nor Browser selection, focus, draft or route")
    func previewIsolation() {
        let (s, w) = makeState()
        s.navigate(to: .librarySearch)
        searchState(s, w, batch: "PN2")
        w.executeSearch(appState: s)
        let before = selections(s)
        let route = s.library.currentRoute
        w.selectSearchPreview(w.searchMatchedResults[0])
        #expect(selections(s) == before)
        #expect(s.library.currentRoute == route)
        #expect(w.resolvedSearchPreviewSample(s)?.id == "PN2-a")
        #expect(s.library.libraryBrowserSelectedSampleId == "PN2-a") // untouched pre-existing value
    }

    @Test("preview with a dirty Drawer draft leaves the draft untouched")
    func previewKeepsDraft() {
        let (s, w) = makeState()
        s.library.libraryState.sampleEditOriginalDraft = draft("clean")
        s.library.librarySampleEditDraft = draft("dirty")
        searchState(s, w, batch: "PN2")
        w.executeSearch(appState: s)
        let before = selections(s)
        w.selectSearchPreview(w.searchMatchedResults[0])
        #expect(selections(s) == before)
        #expect(s.library.librarySampleEditIsDirty)
    }

    @Test("Open Sample goes through the navigation transaction; dirty draft defers, discard commits exact target")
    func openSampleTransaction() {
        let (s, w) = makeState()
        s.navigate(to: .librarySearch) // clean at this point
        searchState(s, w, batch: "PN2")
        w.executeSearch(appState: s)
        w.selectSearchPreview(w.searchMatchedResults[0])
        s.library.libraryState.sampleEditOriginalDraft = draft("clean")
        s.library.librarySampleEditDraft = draft("dirty")
        let t = w.searchPreviewTarget!
        let outcome = s.navigate(to: .libraryDrawer(prefix: t.prefix, batchId: t.batchId, sampleId: t.sampleId))
        // Search is read-only so leaving it for another sample with a live draft is guarded.
        #expect(outcome == .deferred)
        #expect(s.library.currentRoute == .search)
        #expect(s.library.librarySelectedSampleId == "PN1-a")
        s.library.cancelPendingSelectionChange()
        #expect(s.library.librarySampleEditDraft?.substrateTagsText == "dirty")

        s.library.librarySampleEditDraft = nil
        s.library.libraryState.sampleEditOriginalDraft = nil
        #expect(s.navigate(to: .libraryDrawer(prefix: t.prefix, batchId: t.batchId, sampleId: t.sampleId)) == .committed)
        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))
        #expect(s.library.librarySelectedSampleId == "PN2-a")
        #expect(s.library.libraryActiveSelectionSource == .drawer)
    }

    @Test("a vanished or no-longer-matching result clears the preview and never selects another sample")
    func previewInvalidation() {
        let (s, w) = makeState()
        searchState(s, w, batch: "PN1")
        w.executeSearch(appState: s)
        w.selectSearchPreview(w.searchMatchedResults.first { $0.sample.id == "PN1-b" }!)
        #expect(w.resolvedSearchPreviewSample(s)?.id == "PN1-b")

        // Filter change that excludes it.
        searchState(s, w, batch: "PN1", substrate: "STO")
        w.executeSearch(appState: s)
        #expect(w.searchPreviewTarget == nil)
        #expect(w.resolvedSearchPreviewSample(s) == nil)

        // Data refresh removes the sample while the target is held.
        searchState(s, w, batch: "PN1")
        w.executeSearch(appState: s)
        w.selectSearchPreview(w.searchMatchedResults.first { $0.sample.id == "PN1-a" }!)
        s.library.libraryExistingGroups["PN"] = [
            LibraryPreviewBatchGroup(batchId: "PN1", samples: [sample("PN1-b", batch: "PN1", substrate: "LAO")])
        ]
        #expect(w.resolvedSearchPreviewSample(s) == nil) // stale match, missing in live data
        w.executeSearch(appState: s)
        #expect(w.searchPreviewTarget == nil)
    }

    @Test("empty result set is a valid executed state with nothing to preview")
    func emptyResults() {
        let (s, w) = makeState()
        searchState(s, w, batch: "nope")
        w.executeSearch(appState: s)
        #expect(w.searchHasExecuted && w.searchMatchedResults.isEmpty)
        #expect(w.resolvedSearchPreviewSample(s) == nil)
    }

    @Test("returning to Search rebuilds matches from preserved filters")
    func returnToSearch() {
        let (s, w) = makeState()
        s.navigate(to: .librarySearch)
        searchState(s, w, batch: "PN1")
        w.executeSearch(appState: s)
        let first = w.searchMatchedResults
        s.navigate(to: .library)
        s.navigate(to: .librarySearch)
        #expect(w.searchBatchIdText == "PN1" && w.searchHasExecuted)
        w.executeSearch(appState: s) // what the Search page does on appear
        #expect(w.searchMatchedResults == first)
    }

    // MARK: - Sidebar (AC6)

    @Test("sidebar highlight distinguishes Management, Search, Batch and Workflow independent of stale Drawer selection")
    func sidebarHighlight() {
        let (s, _) = makeState() // Drawer selection PN/PN1/PN1-a is set
        #expect(SidebarMenuNodeID.selectedLibraryNodeIDs(for: .management) == [SidebarMenuNodeID.area(.library)])
        #expect(SidebarMenuNodeID.selectedLibraryNodeIDs(for: .search) == [SidebarMenuNodeID.librarySearch()])
        #expect(SidebarMenuNodeID.selectedLibraryNodeIDs(for: .sampleWorkspace(prefix: "PN", batchId: "PN2"))
                == [SidebarMenuNodeID.libraryBatch(prefix: "PN", batchID: "PN2")])
        #expect(SidebarMenuNodeID.selectedLibraryNodeIDs(for: .workflowGallery(workflowID: "3w"))
                == [SidebarMenuNodeID.libraryWorkflowGallery("3w")])
        _ = s
    }

    @Test("Search sidebar node exists first under Library and routes to the Search route; deep link unchanged")
    func sidebarSearchNode() {
        let (s, _) = makeState()
        let menu = SpinLabSidebarMenuProvider().makeMenu(appState: s, selectedArea: .library)
        let library = menu.first { $0.kind == .area(.library) }!
        #expect(library.children.first?.kind == .librarySearch)
        #expect(library.children.first?.isSelectable == true)
        #expect(AppRouter().routePath(for: .librarySearch) == .librarySearch)
        #expect(AppRouter().deepLink(for: .librarySearch) == "library/search")
    }

    @Test("Search filters round-trip through the existing interaction snapshot schema")
    func snapshotCompat() {
        let (s, w) = makeState()
        w.searchBatchIdText = "PN1"; w.searchThicknessText = "10"; w.searchHasExecuted = true
        let snap = w.interactionSnapshot(appState: s)
        #expect(snap.searchBatchIdText == "PN1" && snap.searchThicknessText == "10" && snap.searchHasExecuted)
    }

    @Test("Search routes to its own pages; Search page has no Drawer/Browser selection writes")
    func searchPageStructure() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let views = try String(contentsOf: root.appendingPathComponent("Sources/SpinLabApp/Features/Library/LibrarySearchViews.swift"), encoding: .utf8)
        for forbidden in ["librarySelected", "libraryBrowserSelected", "selectExistingDrawer", "selectBrowserSample", "beginEditing", "libraryActiveSelectionSource"] {
            #expect(!views.contains(forbidden), "\(forbidden)")
        }
        #expect(views.contains("appState.navigate(to: .libraryDrawer("))
    }
}
