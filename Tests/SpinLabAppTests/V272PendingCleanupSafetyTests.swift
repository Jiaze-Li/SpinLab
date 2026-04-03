import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.7.2 Pending Cleanup Safety")
struct V272PendingCleanupSafetyTests {
    @Test("clear imports removes pending and snapshots together")
    func clearImportsPurgesPendingRoutingAndInteractionWorkspace() {
        let pending = SpinLabDomain.PendingImport(
            fileName: "PN20_RT.dat",
            sourceFilePath: "/tmp/PN20_RT.dat",
            originalFilePath: "/tmp/PN20_RT.dat",
            parsedHints: .init(defaultSampleKey: "PN20")
        )
        let persistence = LocalPersistenceStub(
            pendingImports: [pending],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let inboxStore = InboxFeatureStore(
            inboxRepository: InboxRepository(persistence: persistence),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability()
        )

        var workspaceByPendingID: [String: InboxPendingWorkspaceState] = [
            InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id): .snapshotSafe(
                draft: PendingImportConfirmationDraft(
                    batchName: "B1",
                    sampleName: "S1",
                    measurementName: "M1",
                    workflowID: "RT",
                    conditionValues: [:],
                    selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
                    newProjectName: ""
                ),
                editableFileContents: "raw",
                hasEditableFileContents: true,
                routingDraft: nil
            )
        ]
        var persisted = false

        PendingCleanupService().clearImports(
            inboxStore: inboxStore,
            writeInboxWorkspace: { workspaceByPendingID = $0 },
            persistInteractionSnapshotIfReady: { persisted = true }
        )

        #expect(inboxStore.pendingImports.isEmpty)
        #expect(inboxStore.selectedPendingImportID == nil)
        #expect(inboxStore.cachedPendingRoutingSnapshot(for: pending.id) == nil)
        #expect(workspaceByPendingID.isEmpty)
        #expect(persisted)
    }
}
