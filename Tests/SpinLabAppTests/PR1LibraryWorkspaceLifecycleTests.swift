import Foundation
import Testing
@testable import SpinLabApp

/// PR 1 / Phase 1 — Library lifecycle and global dialogs are owned by the
/// stable `LibraryWorkspaceState` + `LibraryWorkspaceHost` pair at
/// `RootSplitView` level, not by whichever Primary view is mounted.
@MainActor
@Suite("PR1 Library Workspace Lifecycle Ownership", .serialized, .rulesGlobalState)
struct PR1LibraryWorkspaceLifecycleTests {

    // MARK: - Helpers

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func sample(_ id: String, batch: String) -> LibrarySample {
        LibrarySample(
            id: id, displayName: id, batchId: batch, substrateRaw: "", substrateDisplay: "",
            substrateTokens: [], substrateTags: [], metadata: [:], numericTags: [:],
            numericDisplay: [:], updatedAt: Date()
        )
    }

    private func makeAppState() -> SpinLabAppState {
        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = nil
        appState.library.libraryExistingGroups = [
            "PN": [
                LibraryPreviewBatchGroup(batchId: "PN1", samples: [sample("PN1-a", batch: "PN1"), sample("PN1-b", batch: "PN1")]),
                LibraryPreviewBatchGroup(batchId: "PN2", samples: [sample("PN2-a", batch: "PN2")])
            ]
        ]
        return appState
    }

    private func restoredPersistedState() -> LibraryInteractionState {
        var persisted = LibraryInteractionState()
        persisted.selectedPrefix = "PN"
        persisted.selectedBatchId = "PN2"
        persisted.selectedSampleId = "PN2-a"
        persisted.searchBatchIdText = "PN"
        persisted.searchKeywordText = "kw"
        persisted.searchHasExecuted = true
        persisted.isSearchWorkspaceExpanded = false
        persisted.expandedWorkflowIDs = ["3w"]
        return persisted
    }

    // MARK: - AC1: lifecycle runs once, without any Primary view

    @Test("start restores interaction state and reconciles selection with no Primary view mounted")
    func startRestoresWithoutPrimaryView() {
        let appState = makeAppState()
        appState.updateInteractionValue(\.libraryView, to: restoredPersistedState(), source: "test")
        let state = LibraryWorkspaceState()

        state.start(appState: appState)

        #expect(appState.library.librarySelectedBatchId == "PN2")
        #expect(appState.library.librarySelectedSampleId == "PN2-a")
        #expect(state.searchBatchIdText == "PN")
        #expect(state.searchKeywordText == "kw")
        #expect(state.searchHasExecuted)
        #expect(!state.isSearchWorkspaceExpanded)
        #expect(state.expandedWorkflows == ["3w"])
        #expect(state.previewDerivedData.previewGroupsForSelectedPrefix.isEmpty || !state.previewDerivedData.previewPrefixes.isEmpty)
    }

    @Test("start reconciles a stale restored Drawer selection against loaded data")
    func startReconcilesInvalidSelection() {
        let appState = makeAppState()
        var persisted = restoredPersistedState()
        persisted.selectedBatchId = "GONE"
        persisted.selectedSampleId = "GONE-1"
        appState.updateInteractionValue(\.libraryView, to: persisted, source: "test")
        let state = LibraryWorkspaceState()

        state.start(appState: appState)

        #expect(appState.library.librarySelectedBatchId != "GONE")
        #expect(appState.library.librarySelectedSampleId != "GONE-1")
    }

    @Test("start is idempotent: repeated calls (route switches) never re-initialise")
    func startIsIdempotentAcrossRouteSwitches() {
        let appState = makeAppState()
        appState.updateInteractionValue(\.libraryView, to: restoredPersistedState(), source: "test")
        let state = LibraryWorkspaceState()
        state.start(appState: appState)
        #expect(state.startCount == 1)

        // User edits page-local persisted fields, then routes around.
        state.searchSubstrateText = "STO"
        appState.navigate(to: .libraryWorkflowGallery(id: "3w"))
        state.start(appState: appState)
        appState.navigate(to: .library)
        state.start(appState: appState)
        appState.navigate(to: .librarySearch)
        state.start(appState: appState)

        #expect(state.startCount == 1)
        #expect(state.searchSubstrateText == "STO", "a later start must not re-apply the restored snapshot over live edits")
        #expect(appState.library.librarySelectedBatchId == "PN2")
    }

    @Test("selection and Browser/Drawer triples survive Library route round trips")
    func selectionSurvivesRouteRoundTrip() {
        let appState = makeAppState()
        let state = LibraryWorkspaceState()
        state.start(appState: appState)
        appState.library.libraryBrowserSelectedPrefix = "PN"
        appState.library.libraryBrowserSelectedBatchId = "PN1"
        appState.library.libraryBrowserSelectedSampleId = "PN1-a"
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))

        appState.navigate(to: .libraryWorkflowGallery(id: "3w"))
        appState.navigate(to: .library)

        #expect(appState.library.librarySelectedBatchId == "PN2")
        #expect(appState.library.librarySelectedSampleId == "PN2-a")
        #expect(appState.library.libraryBrowserSelectedBatchId == "PN1")
        #expect(appState.library.libraryBrowserSelectedSampleId == "PN1-a")
    }

    // MARK: - Interaction state persistence (schema unchanged)

    @Test("flushInteractionState persists page-local edits with no Primary view mounted")
    func flushPersistsWithoutPrimaryView() {
        let appState = makeAppState()
        let state = LibraryWorkspaceState()
        state.start(appState: appState)
        state.searchBatchIdText = "PN9"
        state.isRegistryWorkspaceExpanded = false

        state.flushInteractionState(appState: appState)

        let persisted = appState.interactionValue(\.libraryView)
        #expect(persisted.searchBatchIdText == "PN9")
        #expect(!persisted.isRegistryWorkspaceExpanded)
    }

    @Test("interaction snapshot round-trips through restore without changing the schema")
    func snapshotRoundTrip() throws {
        let appState = makeAppState()
        appState.updateInteractionValue(\.libraryView, to: restoredPersistedState(), source: "test")
        let state = LibraryWorkspaceState()
        state.start(appState: appState)

        let captured = state.interactionSnapshot(appState: appState)
        let data = try JSONEncoder().encode(captured)
        let decoded = try JSONDecoder().decode(LibraryInteractionState.self, from: data)

        #expect(decoded == captured)
        #expect(decoded.selectedSampleId == "PN2-a")
        #expect(decoded.searchKeywordText == "kw")
    }

    // MARK: - AC2: dialogs are presented by the stable owner, never by a route's view

    @Test("pending-navigation prompt state exists while the Gallery route (not the legacy page) is active")
    func pendingPromptIndependentOfMountedPage() {
        let appState = makeAppState()
        let state = LibraryWorkspaceState()
        state.start(appState: appState)
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN1", sampleId: "PN1-a"))
        appState.navigate(to: .libraryWorkflowGallery(id: "3w"))
        appState.library.librarySampleEditDraft = LibrarySampleEditDraft(
            sampleId: "PN1-a", batchId: "PN1", baseUpdatedAt: Date(), substrateTagsText: "dirty",
            numericValues: [], metadataValues: []
        )
        appState.library.libraryState.sampleEditOriginalDraft = LibrarySampleEditDraft(
            sampleId: "PN1-a", batchId: "PN1", baseUpdatedAt: Date(), substrateTagsText: "clean",
            numericValues: [], metadataValues: []
        )

        let outcome = appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN2", sampleId: "PN2-a"))

        #expect(outcome == .deferred)
        #expect(appState.library.hasPendingSelectionChange())
        #expect(appState.library.currentRoute == .workflowGallery(workflowID: "3w"))
    }

    @Test("exactly one Unsaved Edits dialog and one of each global sheet exist, all in the host")
    func singleDialogAndSheetPresenters() throws {
        let host = try source("Sources/SpinLabApp/Features/Library/LibraryWorkspaceLifecycle.swift")
        let sheets = try source("Sources/SpinLabApp/Features/Library/LibrarySheets.swift")
        #expect(occurrences(of: "LibraryDialogsModifier(", in: host) == 1)
        #expect(occurrences(of: "confirmationDialog(\"Unsaved Edits\"", in: sheets) == 1)
        #expect(occurrences(of: ".sheet(item: $state.conditionDetailMeasurement)", in: host) == 1)
        #expect(occurrences(of: "isShowingChartAudit", in: host) >= 1)
        #expect(occurrences(of: "isShowingRegistryGrowthImportSheet", in: host) >= 1)

        // No other file in the app presents the Unsaved Edits dialog.
        let sourcesRoot = repoRoot().appendingPathComponent("Sources/SpinLabApp")
        let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        var presenters: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("\"Unsaved Edits\"") {
                presenters.append(url.lastPathComponent)
            }
        }
        #expect(presenters == ["LibrarySheets.swift"], "found: \(presenters)")
    }

    @Test("Library Primary/Detail views no longer own lifecycle, persistence or global presentations")
    func primaryViewOwnsNoGlobalDuties() throws {
        for path in [
            "Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift",
            "Sources/SpinLabApp/Features/Library/WorkflowGallery/WorkflowGalleryDetailView.swift",
            "Sources/SpinLabApp/Features/Library/WorkflowGallery/WorkflowGalleryPrimaryView.swift"
        ] {
            guard let text = try? source(path) else { continue }
            #expect(!text.contains("LibraryDialogsModifier"), "\(path)")
            #expect(!text.contains("bindActions"), "\(path)")
            #expect(!text.contains("validateLibraryCacheOnAppear"), "\(path)")
            #expect(!text.contains("persistInteractionState"), "\(path)")
            #expect(!text.contains("confirmationDialog("), "\(path)")
            #expect(!text.contains(".sheet(isPresented: Binding("), "\(path)")
        }
    }

    @Test("RootSplitView hosts the Library workspace and starts it exactly once at root appear")
    func rootHostsLibraryWorkspace() throws {
        let root = try source("Sources/SpinLabApp/App/RootSplitView.swift")
        #expect(occurrences(of: ".modifier(LibraryWorkspaceHost(state: libraryState))", in: root) == 1)
        #expect(occurrences(of: "libraryState.start(appState: appState)", in: root) == 1)
        // The host is applied above (outside) the pane content, not inside Primary/Detail.
        let hostIndex = try #require(root.range(of: "LibraryWorkspaceHost(state: libraryState)"))
        let primaryIndex = try #require(root.range(of: "AppPrimaryContent("))
        #expect(primaryIndex.lowerBound < hostIndex.lowerBound)
    }
}
