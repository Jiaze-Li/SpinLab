import Testing
import Foundation
@testable import SpinLabApp

@MainActor
@Suite("V5.1.4 InboxFeatureStore")
struct V514InboxFeatureStoreTests {

    // MARK: - Helpers

    private static func makeStore(
        pendingImports: [SpinLabDomain.PendingImport] = []
    ) -> InboxFeatureStore {
        let persistence = LocalPersistenceStub(
            pendingImports: pendingImports,
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = InboxRepository(persistence: persistence)
        return InboxFeatureStore(
            inboxRepository: repository,
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability()
        )
    }

    private static func makePending(
        id: UUID = UUID(),
        fileName: String = "test_file.dat"
    ) -> SpinLabDomain.PendingImport {
        SpinLabDomain.PendingImport(
            id: id,
            fileName: fileName,
            sourceFilePath: "/tmp/\(fileName)",
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
    }

    // MARK: - Initialization

    @Test("init loads pending imports from repository and selects first")
    func initSelectsFirst() {
        let p1 = Self.makePending(fileName: "file1.dat")
        let p2 = Self.makePending(fileName: "file2.dat")
        let store = Self.makeStore(pendingImports: [p1, p2])
        #expect(store.pendingImports.count == 2)
        #expect(store.selectedPendingImportID == p1.id)
    }

    @Test("init with empty imports sets selection to nil")
    func initEmpty() {
        let store = Self.makeStore()
        #expect(store.pendingImports.isEmpty)
        #expect(store.selectedPendingImportID == nil)
    }

    // MARK: - restoreInteraction

    @Test("restoreInteraction sets selection when ID exists in imports")
    func restoreInteraction_valid() {
        let p1 = Self.makePending(fileName: "a.dat")
        let p2 = Self.makePending(fileName: "b.dat")
        let store = Self.makeStore(pendingImports: [p1, p2])
        store.restoreInteraction(selectedPendingImportID: p2.id)
        #expect(store.selectedPendingImportID == p2.id)
    }

    @Test("restoreInteraction ignores ID that does not exist in imports")
    func restoreInteraction_invalid() {
        let p1 = Self.makePending(fileName: "a.dat")
        let store = Self.makeStore(pendingImports: [p1])
        let bogusID = UUID()
        store.restoreInteraction(selectedPendingImportID: bogusID)
        #expect(store.selectedPendingImportID == p1.id)
    }

    @Test("restoreInteraction with nil keeps current selection")
    func restoreInteraction_nil() {
        let p1 = Self.makePending(fileName: "a.dat")
        let store = Self.makeStore(pendingImports: [p1])
        store.restoreInteraction(selectedPendingImportID: nil)
        #expect(store.selectedPendingImportID == p1.id)
    }

    // MARK: - captureInteraction

    @Test("captureInteraction writes selected ID into snapshot")
    func captureInteraction() {
        let p1 = Self.makePending(fileName: "a.dat")
        let store = Self.makeStore(pendingImports: [p1])
        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)
        #expect(snapshot.selectedPendingImportID == p1.id)
    }

    // MARK: - removeSelectedPendingImport

    @Test("removeSelectedPendingImport removes the selected item and selects next")
    func removeSelected() {
        let p1 = Self.makePending(fileName: "a.dat")
        let p2 = Self.makePending(fileName: "b.dat")
        let store = Self.makeStore(pendingImports: [p1, p2])
        #expect(store.selectedPendingImportID == p1.id)

        let removedID = store.removeSelectedPendingImport()
        #expect(removedID == p1.id)
        #expect(store.pendingImports.count == 1)
        #expect(store.pendingImports[0].id == p2.id)
        #expect(store.selectedPendingImportID == p2.id)
    }

    @Test("removeSelectedPendingImport returns nil when nothing selected")
    func removeSelected_empty() {
        let store = Self.makeStore()
        let removedID = store.removeSelectedPendingImport()
        #expect(removedID == nil)
    }

    // MARK: - clearPendingImports

    @Test("clearPendingImports empties queue and clears selection")
    func clearPendingImports() {
        let p1 = Self.makePending(fileName: "a.dat")
        let store = Self.makeStore(pendingImports: [p1])
        store.clearPendingImports()
        #expect(store.pendingImports.isEmpty)
        #expect(store.selectedPendingImportID == nil)
    }

    // MARK: - replacePendingImports

    @Test("replacePendingImports updates list and adjusts selection")
    func replacePendingImports() {
        let p1 = Self.makePending(fileName: "a.dat")
        let store = Self.makeStore(pendingImports: [p1])
        #expect(store.selectedPendingImportID == p1.id)

        let p2 = Self.makePending(fileName: "b.dat")
        _ = store.replacePendingImports([p2])
        #expect(store.pendingImports.count == 1)
        #expect(store.pendingImports[0].id == p2.id)
        // p1 no longer exists, selection should move to first available
        #expect(store.selectedPendingImportID == p2.id)
    }

    // MARK: - applyPending

    @Test("applyPending removes processed IDs from queue")
    func applyPending() {
        let p1 = Self.makePending(fileName: "a.dat")
        let p2 = Self.makePending(fileName: "b.dat")
        let p3 = Self.makePending(fileName: "c.dat")
        let store = Self.makeStore(pendingImports: [p1, p2, p3])

        store.applyPending(processedIDs: [p1.id, p3.id])
        #expect(store.pendingImports.count == 1)
        #expect(store.pendingImports[0].id == p2.id)
        #expect(store.selectedPendingImportID == p2.id)
    }

    @Test("applyPending with empty IDs is a no-op")
    func applyPending_empty() {
        let p1 = Self.makePending(fileName: "a.dat")
        let store = Self.makeStore(pendingImports: [p1])
        store.applyPending(processedIDs: [])
        #expect(store.pendingImports.count == 1)
    }

    @Test("applyPending removing all items clears selection")
    func applyPending_all() {
        let p1 = Self.makePending(fileName: "a.dat")
        let store = Self.makeStore(pendingImports: [p1])
        store.applyPending(processedIDs: [p1.id])
        #expect(store.pendingImports.isEmpty)
        #expect(store.selectedPendingImportID == nil)
    }

    // MARK: - pruneWorkspaceByValidPendingIDs

    @Test("pruneWorkspaceByValidPendingIDs keeps only valid IDs")
    func pruneWorkspace() {
        let p1 = Self.makePending(fileName: "a.dat")
        let p2 = Self.makePending(fileName: "b.dat")
        let store = Self.makeStore(pendingImports: [p1])

        let key1 = InteractionSnapshotKeyCodec.dictionaryKey(for: p1.id)
        let key2 = InteractionSnapshotKeyCodec.dictionaryKey(for: p2.id)
        let dummyDraft = PendingImportConfirmationDraft(
            batchName: "", sampleName: "", measurementName: "",
            workflowID: "", conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )
        let dummyWorkspace = InboxPendingWorkspaceState(
            draft: dummyDraft, editableFileContents: "", hasEditableFileContents: false
        )
        let workspace: [String: InboxPendingWorkspaceState] = [
            key1: dummyWorkspace,
            key2: dummyWorkspace,
        ]
        let pruned = store.pruneWorkspaceByValidPendingIDs(workspace)
        #expect(pruned.count == 1)
        #expect(pruned[key1] != nil)
        #expect(pruned[key2] == nil)
    }

    // MARK: - Selection auto-adjustment

    @Test("selection moves to first when current selection is removed externally")
    func selectionAutoAdjust() {
        let p1 = Self.makePending(fileName: "a.dat")
        let p2 = Self.makePending(fileName: "b.dat")
        let store = Self.makeStore(pendingImports: [p1, p2])
        store.selectedPendingImportID = p2.id
        #expect(store.selectedPendingImportID == p2.id)

        // Replace imports without p2
        _ = store.replacePendingImports([p1])
        #expect(store.selectedPendingImportID == p1.id)
    }
}
