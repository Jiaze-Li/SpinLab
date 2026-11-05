import Foundation
import Testing
@testable import SpinLabApp

/// PR 1 / Phase 2 — Explicit Library routes and the unified
/// Request → Guard → Defer/Commit navigation transaction.
@MainActor
@Suite("PR1 Library Navigation Transaction", .serialized, .rulesGlobalState)
struct PR1LibraryNavigationTransactionTests {

    // MARK: - Fixtures

    private func sample(_ id: String, batch: String) -> LibrarySample {
        LibrarySample(
            id: id, displayName: id, batchId: batch, substrateRaw: "", substrateDisplay: "",
            substrateTokens: [], substrateTags: [], metadata: [:], numericTags: [:],
            numericDisplay: [:], updatedAt: Date()
        )
    }

    private func draft(_ text: String) -> LibrarySampleEditDraft {
        LibrarySampleEditDraft(
            sampleId: "PN1-a", batchId: "PN1", baseUpdatedAt: Date(), substrateTagsText: text,
            numericValues: [], metadataValues: []
        )
    }

    /// Library with PN/{PN1:[a,b], PN2:[a]} and a "/"-bearing key, Drawer on PN1-a.
    private func makeState(dirty: Bool = false, source: LibrarySelectionSource = .drawer) -> SpinLabAppState {
        let appState = SpinLabAppState()
        let lib = appState.library
        lib.librarySettings.rootPath = nil
        lib.libraryExistingGroups = [
            "PN": [
                LibraryPreviewBatchGroup(batchId: "PN1", samples: [sample("PN1-a", batch: "PN1"), sample("PN1-b", batch: "PN1")]),
                LibraryPreviewBatchGroup(batchId: "PN2", samples: [sample("PN2-a", batch: "PN2")]),
                LibraryPreviewBatchGroup(batchId: "PN3", samples: [sample("PN3/x|y", batch: "PN3")])
            ]
        ]
        appState.selectedArea = .library
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-a"))
        lib.libraryBrowserSelectedPrefix = "PN"
        lib.libraryBrowserSelectedBatchId = "PN2"
        lib.libraryBrowserSelectedSampleId = "PN2-a"
        if dirty {
            lib.libraryState.sampleEditOriginalDraft = draft("clean")
            lib.librarySampleEditDraft = draft("dirty")
        }
        lib.libraryActiveSelectionSource = source
        return appState
    }

    private struct Snapshot: Equatable {
        var area: AppArea
        var route: LibraryRoute
        var prefix: String?
        var batch: String?
        var sample: String?
        var source: LibrarySelectionSource
        var draftText: String?
        var browserSample: String?
    }

    private func snap(_ s: SpinLabAppState) -> Snapshot {
        Snapshot(
            area: s.selectedArea, route: s.library.currentRoute,
            prefix: s.library.librarySelectedPrefix, batch: s.library.librarySelectedBatchId,
            sample: s.library.librarySelectedSampleId, source: s.library.libraryActiveSelectionSource,
            draftText: s.library.librarySampleEditDraft?.substrateTagsText,
            browserSample: s.library.libraryBrowserSelectedSampleId
        )
    }

    // MARK: - AC4: route identity

    @Test("each navigation target has its own explicit Library route identity")
    func routeIdentity() {
        let s = makeState()
        #expect(s.navigate(to: .library) == .committed)
        #expect(s.library.currentRoute == .management)
        #expect(s.navigate(to: .librarySearch) == .committed)
        #expect(s.library.currentRoute == .search)
        #expect(s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a")) == .committed)
        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))
        #expect(s.navigate(to: .libraryWorkflowGallery(id: "3w")) == .committed)
        #expect(s.library.currentRoute == .workflowGallery(workflowID: "3w"))
        #expect(s.selectedArea == .library)
    }

    @Test("Management / Sample Workspace / Search share one legacy page (no remount); Gallery does not")
    func legacyPageSharedAcrossThreeRoutes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["AppPrimaryContent", "AppDetailContent"] {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/SpinLabApp/App/\(file).swift"), encoding: .utf8)
            #expect(text.contains("case .management, .sampleWorkspace, .search:"), "\(file)")
        }
    }

    // MARK: - A: clean navigation commits Route + Selection + Focus atomically

    @Test("clean Sample jump from another area commits area, route, selection and focus together")
    func cleanAtomicCommit() {
        let s = makeState()
        s.selectedArea = .inbox
        s.library.libraryActiveSelectionSource = .browser

        let outcome = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: nil))

        #expect(outcome == .committed)
        #expect(s.selectedArea == .library)
        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))
        #expect(s.library.librarySelectedBatchId == "PN2")
        #expect(s.library.librarySelectedSampleId == "PN2-a", "nil sample resolves to the batch's first sample")
        #expect(s.library.libraryActiveSelectionSource == .drawer)
        #expect(s.library.currentSelectionSampleId == "PN2-a", "Detail focus follows the committed target")
    }

    // MARK: - B: dirty Drawer → other sample

    @Test("dirty Drawer sample → other sample is deferred and changes nothing")
    func dirtySampleToSampleDeferred() {
        let s = makeState(dirty: true)
        let before = snap(s)

        let outcome = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))

        #expect(outcome == .deferred)
        #expect(snap(s) == before, "Route, Selection, Focus and Draft untouched before the user decides")
        #expect(s.library.hasPendingSelectionChange())
        #expect(s.library.libraryState.pendingNavigation?.target == .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))
        #expect(s.library.libraryPendingSelectionChangePrompt != nil)
    }

    @Test("Cancel keeps page, selection and draft; no pending navigation remains")
    func cancelKeepsEverything() {
        let s = makeState(dirty: true)
        let before = snap(s)
        _ = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))

        s.library.cancelPendingSelectionChange()

        #expect(snap(s) == before)
        #expect(!s.library.hasPendingSelectionChange())
    }

    @Test("Discard drops the bound draft and then commits the pending navigation")
    func discardThenCommit() {
        let s = makeState(dirty: true)
        _ = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))

        s.discardAndContinuePendingLibrarySelectionChange()

        #expect(!s.library.librarySampleEditIsDirty)
        #expect(s.library.librarySelectedBatchId == "PN2")
        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))
        #expect(!s.library.hasPendingSelectionChange())
    }

    @Test("Save failure runs no pending navigation and keeps Route, Selection, Focus and Draft")
    func saveFailureKeepsState() {
        let s = makeState(dirty: true)
        let before = snap(s)
        _ = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))

        s.saveAndContinuePendingLibrarySelectionChange() // no Library root → save fails

        #expect(snap(s) == before)
        #expect(s.library.librarySampleEditIsDirty)
        #expect(s.library.librarySampleEditError != nil, "the editor presents the failure")
        #expect(s.library.libraryNavigationFailureMessage == nil, "no second popup while the editor is on screen")
        #expect(s.library.hasPendingSelectionChange(), "request kept for retry until the user cancels")
    }

    @Test("Save failure on the Gallery route (no editor on screen) raises the host alert")
    func saveFailureOnGalleryRaisesHostAlert() {
        let s = makeState(dirty: true, source: .browser)
        _ = s.navigate(to: .libraryWorkflowGallery(id: "3w"))
        s.library.libraryActiveSelectionSource = .drawer
        _ = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))
        s.saveAndContinuePendingLibrarySelectionChange()
        #expect(s.library.currentRoute == .workflowGallery(workflowID: "3w"))
        #expect(s.library.libraryNavigationFailureMessage != nil)
        #expect(s.library.librarySampleEditIsDirty)
    }

    @Test("after a successful save the pending navigation commits")
    func saveSuccessCommits() {
        let s = makeState(dirty: true)
        _ = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))
        // A successful save clears the draft (exercised end-to-end in V570 dirty-guard tests).
        s.library.librarySampleEditDraft = nil
        s.library.libraryState.sampleEditOriginalDraft = nil

        s.continuePendingNavigation()

        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))
        #expect(s.library.librarySelectedSampleId == "PN2-a")
        #expect(!s.library.hasPendingSelectionChange())
    }

    @Test("a stale request (selection moved under the prompt) never discards a different draft")
    func staleRequestDoesNotDiscard() {
        let s = makeState(dirty: true)
        _ = s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))
        s.library.librarySelectedSampleId = "PN1-b" // identity moved after the prompt was raised

        s.discardAndContinuePendingLibrarySelectionChange()

        #expect(s.library.librarySampleEditDraft?.substrateTagsText == "dirty", "draft untouched")
        #expect(!s.library.hasPendingSelectionChange())
        #expect(s.library.currentRoute != .sampleWorkspace(prefix: "PN", batchId: "PN2"))
    }

    @Test("repeated clicks never overwrite a waiting target; the same target is idempotent")
    func repeatedClicksDoNotOverwrite() {
        let s = makeState(dirty: true)
        let first = AppRoutePath.libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a")
        #expect(s.navigate(to: first) == .deferred)
        let id = s.library.libraryState.pendingNavigation?.id

        #expect(s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-b")) == .blockedByPendingRequest)
        #expect(s.navigate(to: .inbox) == .blockedByPendingRequest)
        #expect(s.library.libraryState.pendingNavigation?.target == first)
        #expect(s.library.libraryState.pendingNavigation?.id == id)

        #expect(s.navigate(to: first) == .deferred)
        #expect(s.library.libraryState.pendingNavigation?.id == id, "identical repeat keeps the same request")
    }

    @Test("re-opening the sample being edited is allowed")
    func sameIdentityAllowed() {
        let s = makeState(dirty: true)
        #expect(s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-a")) == .committed)
        #expect(s.library.librarySampleEditDraft?.substrateTagsText == "dirty")
    }

    // MARK: - C: leaving the editing workspace

    @Test("dirty Drawer → Management / Search / Gallery / Inbox / Workbench all defer")
    func dirtyLeavingEditingWorkspaceDefers() {
        let targets: [AppRoutePath] = [
            .library, .librarySearch, .libraryWorkflowGallery(id: "3w"),
            .inbox, .workbench, .workbenchWorkflow(id: "3w")
        ]
        for target in targets {
            let s = makeState(dirty: true)
            s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-a"))
            let before = snap(s)
            let outcome = s.navigate(to: target)
            #expect(outcome == .deferred, "\(target)")
            #expect(snap(s) == before, "\(target) must not mutate anything before the decision")
            #expect(s.library.libraryState.pendingNavigation?.target == target, "\(target)")
        }
    }

    @Test("Save/Discard on a deferred Workbench jump leaves Library only after the decision")
    func deferredWorkbenchJump() {
        let s = makeState(dirty: true)
        #expect(s.navigate(to: .workbench) == .deferred)
        #expect(s.selectedArea == .library)
        s.discardAndContinuePendingLibrarySelectionChange()
        #expect(s.selectedArea == .workbench)
        #expect(!s.library.librarySampleEditIsDirty)
    }

    // MARK: - D / E / F: Registry Browser preview

    @Test("Registry Browser read-only preview never prompts and keeps the Drawer draft")
    func browserPreviewKeepsDraft() {
        let s = makeState(dirty: true)
        let outcome = s.library.selectBrowserSample()
        guard case .appliedBrowser = outcome else {
            Issue.record("expected browser apply, got \(outcome)")
            return
        }
        #expect(!s.library.hasPendingSelectionChange())
        #expect(s.library.librarySelectedSampleId == "PN1-a")
        #expect(s.library.librarySampleEditDraft?.substrateTagsText == "dirty")
        #expect(!s.library.canMutateLibraryDetailSelection, "preview focus stays read-only")
    }

    @Test("Browser preview → read-only Library page keeps the background draft and Drawer identity")
    func browserPreviewToReadOnlyPage() {
        for target in [AppRoutePath.library, .librarySearch, .libraryWorkflowGallery(id: "3w")] {
            let s = makeState(dirty: true, source: .browser)
            #expect(s.navigate(to: target) == .committed, "\(target)")
            #expect(s.library.librarySelectedSampleId == "PN1-a")
            #expect(s.library.librarySelectedBatchId == "PN1")
            #expect(s.library.librarySampleEditDraft?.substrateTagsText == "dirty")
            #expect(s.library.libraryActiveSelectionSource == .browser)
        }
    }

    @Test("Browser preview → leaving Library still defers; Browser preview → other Drawer sample defers")
    func browserPreviewLeavingOrDrawerDefers() {
        let a = makeState(dirty: true, source: .browser)
        #expect(a.navigate(to: .inbox) == .deferred)
        #expect(a.selectedArea == .library)

        let b = makeState(dirty: true, source: .browser)
        #expect(b.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a")) == .deferred)
        #expect(b.library.librarySelectedSampleId == "PN1-a")
        #expect(b.library.libraryActiveSelectionSource == .browser)
    }

    // MARK: - Invalid targets

    @Test("unknown batch or sample degrades to Management and selects nothing else")
    func invalidTargetFallsBack() {
        for target in [
            AppRoutePath.libraryDrawer(prefix: "PN", batchId: "NOPE", sampleId: nil),
            .libraryDrawer(prefix: "XX", batchId: "PN1", sampleId: "PN1-a"),
            .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "missing")
        ] {
            let s = makeState()
            let before = s.library.librarySelectedSampleId
            #expect(s.navigate(to: target) == .committed)
            #expect(s.library.currentRoute == .management)
            #expect(s.library.librarySelectedSampleId == before)
            #expect(s.selectedArea == .library)
        }
    }

    // MARK: - Cross-area entry points

    @Test("requestAreaChange follows the same guard and only runs prepare after it clears")
    func areaChangeGuard() {
        let dirty = makeState(dirty: true)
        var prepared = false
        #expect(dirty.requestAreaChange(to: .workbench) { prepared = true; return true } == .deferred)
        #expect(!prepared)
        #expect(dirty.selectedArea == .library)

        let clean = makeState()
        #expect(clean.requestAreaChange(to: .workbench) { prepared = true; return true } == .committed)
        #expect(prepared)
        #expect(clean.selectedArea == .workbench)

        let vetoed = makeState()
        #expect(vetoed.requestAreaChange(to: .workbench) { false } == .committed)
        #expect(vetoed.selectedArea == .library, "a vetoed prepare leaves the area unchanged")
    }

    // MARK: - Deep links

    @Test("deep link commits only the terminal route: no intermediate page, no per-segment guard")
    func deepLinkTerminalOnly() {
        let s = makeState()
        s.selectedArea = .inbox
        s.library.selectManagement()
        #expect(s.openDeepLink("library/PN/PN2/PN2-a"))
        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))

        let stack = AppRouter().deepLinkToRouteStack("library/PN/PN2/PN2-a")
        #expect(stack?.terminalPath == .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))
    }

    @Test("dirty deep link defers once and commits nothing (not even the leading /library hop)")
    func dirtyDeepLinkDefers() {
        let s = makeState(dirty: true)
        let before = snap(s)
        #expect(s.openDeepLink("library/PN/PN2/PN2-a"))
        #expect(snap(s) == before)
        #expect(s.library.libraryState.pendingNavigation?.target == .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))
    }

    @Test("legacy deep links keep working; new search/management links parse")
    func legacyAndNewDeepLinks() {
        let r = AppRouter()
        #expect(r.deepLinkToRouteStack("inbox")?.terminalPath == .inbox)
        #expect(r.deepLinkToRouteStack("workbench")?.terminalPath == .workbench)
        #expect(r.deepLinkToRouteStack("workbench/3w")?.terminalPath == .workbenchWorkflow(id: "3w"))
        #expect(r.deepLinkToRouteStack("library")?.terminalPath == .library)
        #expect(r.deepLinkToRouteStack("library/P/B001")?.terminalPath == .libraryDrawer(prefix: "P", batchId: "B001", sampleId: nil))
        #expect(r.deepLinkToRouteStack("library/P/B001/S1")?.terminalPath == .libraryDrawer(prefix: "P", batchId: "B001", sampleId: "S1"))
        #expect(r.deepLinkToRouteStack("library/workflows/3w")?.terminalPath == .libraryWorkflowGallery(id: "3w"))
        #expect(r.deepLinkToRouteStack("library/search")?.terminalPath == .librarySearch)
        #expect(r.deepLinkToRouteStack("library/management")?.terminalPath == .library)
        #expect(r.deepLinkToRouteStack("nonsense") == nil)
        #expect(r.deepLinkToRouteStack("") == nil)
    }

    @Test("Sample/Batch keys containing '/' round-trip as one segment; raw extra segments are rejected")
    func slashKeysRoundTrip() {
        let r = AppRouter()
        let routes: [AppRoutePath] = [
            .libraryDrawer(prefix: "PN", batchId: "PN3", sampleId: "PN3/x|y"),
            .libraryDrawer(prefix: "PN", batchId: "PN/SRO2", sampleId: "a/b/c"),
            .libraryDrawer(prefix: "P%N", batchId: "B 1", sampleId: "100%/x"),
            .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: nil),
            .libraryWorkflowGallery(id: "a/b"),
            .workbenchWorkflow(id: "w/1")
        ]
        for route in routes {
            let link = r.deepLink(for: route)
            #expect(r.deepLinkToRouteStack(link)?.terminalPath == route, "\(link)")
        }
        // A raw (unescaped) slash in a sample key is ambiguous → refused, never truncated.
        #expect(r.deepLinkToRouteStack("library/PN/PN3/PN3/x|y/extra") == nil)
        #expect(r.deepLinkToRouteStack("library/PN/PN3/PN3") != nil)
        #expect(r.deepLinkToRouteStack("library/PN/PN3/PN3/x") == nil, "five raw segments: ambiguous")
        // The encoded link selects the exact sample.
        let s = makeState()
        #expect(s.openDeepLink(r.deepLink(for: .libraryDrawer(prefix: "PN", batchId: "PN3", sampleId: "PN3/x|y"))))
        #expect(s.library.librarySelectedSampleId == "PN3/x|y")
        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN3"))
    }

    // MARK: - Gallery jump, search jump

    @Test("Gallery Open Sample with a dirty draft defers on the Gallery route and commits after Discard")
    func galleryJumpDirty() {
        let s = makeState(dirty: true, source: .drawer)
        // Gallery is a read-only page: reach it from a browser-preview focus, then jump.
        s.library.libraryActiveSelectionSource = .browser
        #expect(s.navigate(to: .libraryWorkflowGallery(id: "3w")) == .committed)
        var asked = false
        WorkflowGalleryDetailView.requestJumpToSample(sampleKey: "PN2-a", in: s) { asked = true }
        #expect(asked)
        #expect(s.library.currentRoute == .workflowGallery(workflowID: "3w"))
        #expect(s.library.librarySelectedSampleId == "PN1-a")

        s.discardAndContinuePendingLibrarySelectionChange()
        #expect(s.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))
        #expect(s.library.librarySelectedSampleId == "PN2-a")
    }

    @Test("Search / Drawer-picker selection goes through the same transaction")
    func viewModelSelectionUsesTransaction() {
        let s = makeState(dirty: true)
        s.library.libraryActiveSelectionSource = .drawer
        let vm = LibraryViewModel()
        vm.bindActions(from: s)
        vm.selectExistingDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a")
        #expect(s.library.librarySelectedSampleId == "PN1-a")
        #expect(s.library.hasPendingSelectionChange())

        let clean = makeState()
        let vm2 = LibraryViewModel()
        vm2.bindActions(from: clean)
        vm2.selectExistingDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a")
        #expect(clean.library.librarySelectedSampleId == "PN2-a")
        #expect(clean.library.currentRoute == .sampleWorkspace(prefix: "PN", batchId: "PN2"))
    }

    // MARK: - Data-driven route repair

    @Test("a Sample Workspace whose Batch disappears falls back to Management")
    func routeRepairWhenBatchGone() {
        let s = makeState()
        s.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))
        s.library.libraryExistingGroups["PN"]?.removeAll { $0.batchId == "PN2" }
        s.library.reconcileRouteWithLoadedData()
        #expect(s.library.currentRoute == .management)
    }
}
