import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("Interaction Memory")
struct InteractionMemoryStoreTests {
    @Test("restore + capture roundtrip persists latest state")
    func restoreAndCaptureRoundTrip() async throws {
        let persistence = MockSpinLabPersistence()
        persistence.interactionSnapshot.selectedArea = .library
        let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.01)

        var restoredArea: AppArea = .inbox
        store.restore { snapshot in
            restoredArea = snapshot.selectedArea
        }
        #expect(restoredArea == .library)

        store.markReady()
        store.captureIfReady(source: "test") { snapshot in
            snapshot.selectedArea = .workbench
        }

        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(persistence.saveInteractionSnapshotCallCount == 1)
        #expect(persistence.interactionSnapshot.selectedArea == .workbench)
    }

    @Test("debounce coalesces burst writes into one save")
    func debounceCoalescesWrites() async throws {
        let persistence = MockSpinLabPersistence()
        let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.05)

        store.restore { _ in }
        store.markReady()
        store.captureIfReady(source: "test") { snapshot in
            snapshot.selectedArea = .inbox
        }
        store.captureIfReady(source: "test") { snapshot in
            snapshot.selectedArea = .library
        }

        try await Task.sleep(nanoseconds: 140_000_000)
        #expect(persistence.saveInteractionSnapshotCallCount == 1)
        #expect(persistence.interactionSnapshot.selectedArea == .library)
    }

    @Test("updating sidebar does not mutate library or inbox snapshots")
    func isolationAcrossSections() async throws {
        let persistence = MockSpinLabPersistence()
        persistence.interactionSnapshot.libraryView.isSearchWorkspaceExpanded = false
        persistence.interactionSnapshot.inboxWorkspaceByPendingID["p1"] = InboxPendingWorkspaceState.snapshotSafe(
            draft: PendingImportConfirmationDraft(
                batchName: "B",
                sampleName: "S",
                measurementName: "M",
                workflowID: "",
                conditionValues: ["device": "D", "temperature": "300"],
                selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
                newProjectName: ""
            ),
            editableFileContents: "content",
            hasEditableFileContents: true
        )
        let baselineLibrary = persistence.interactionSnapshot.libraryView
        let baselineInbox = persistence.interactionSnapshot.inboxWorkspaceByPendingID

        let store = InteractionMemoryStore(persistence: persistence, saveDebounceInterval: 0.01)
        store.restore { _ in }
        store.markReady()

        store.updateValue(\.sidebar, to: SidebarInteractionState(isLibraryTreeExpanded: false, expandedPrefixes: []), source: "test")
        try await Task.sleep(nanoseconds: 60_000_000)

        #expect(persistence.interactionSnapshot.sidebar.isLibraryTreeExpanded == false)
        #expect(persistence.interactionSnapshot.libraryView == baselineLibrary)
        #expect(persistence.interactionSnapshot.inboxWorkspaceByPendingID == baselineInbox)
    }
}

@MainActor
@Suite("Inbox Snapshot")
struct InboxWorkspaceSnapshotTests {
    @Test("large editable contents are truncated for snapshot safety")
    func truncatesLargeEditableContents() {
        let oversized = String(repeating: "x", count: InboxPendingWorkspaceState.maxStoredEditableContentsLength + 500)
        let draft = PendingImportConfirmationDraft(
            batchName: "B1",
            sampleName: "S1",
            measurementName: "M1",
            workflowID: "",
            conditionValues: ["device": "D1", "temperature": "25"],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        let state = InboxPendingWorkspaceState.snapshotSafe(
            draft: draft,
            editableFileContents: oversized,
            hasEditableFileContents: true
        )

        #expect(state.editableFileContents.count == InboxPendingWorkspaceState.maxStoredEditableContentsLength)
        #expect(state.editableFileContents.hasSuffix(InboxPendingWorkspaceState.truncatedSuffix))
    }
}

private final class MockSpinLabPersistence: SpinLabPersistence {
    var interactionSnapshot: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()
    var saveInteractionSnapshotCallCount = 0

    func loadPendingImports() -> [SpinLabDomain.PendingImport] { [] }
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) {}
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] { [] }
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) {}
    func loadProjects() -> [SpinLabDomain.Project] { [] }
    func saveProjects(_ projects: [SpinLabDomain.Project]) {}

    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot {
        interactionSnapshot
    }

    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) {
        saveInteractionSnapshotCallCount += 1
        interactionSnapshot = snapshot
    }
}
