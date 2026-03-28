import Foundation

@MainActor
final class InboxFacade {
    private let inboxWorkflowService: InboxWorkflowService
    private let inboxStore: InboxFeatureStore
    private let managedStorage: SpinLabManagedStorage
    private let importPipeline: SpinLabImportPipeline

    private let existingImportedOriginalPaths: () -> Set<String>
    private let syncInboxWorkspaceToPendingImports: () -> Void
    private let persistInteractionSnapshotIfReady: () -> Void
    private let selectFirstImportedPendingAndFocusInbox: (UUID) -> Void
    private let refreshRoutingRuleMetadata: () -> Void
    private let readInboxWorkspace: () -> [String: InboxPendingWorkspaceState]
    private let writeInboxWorkspace: ([String: InboxPendingWorkspaceState]) -> Void
    private let recomputedParsedHints: (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints
    private let pendingDisplayDraft: (SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft
    private let bumpAppStateRevision: () -> Void

    init(
        inboxWorkflowService: InboxWorkflowService,
        inboxStore: InboxFeatureStore,
        managedStorage: SpinLabManagedStorage,
        importPipeline: SpinLabImportPipeline,
        existingImportedOriginalPaths: @escaping () -> Set<String>,
        syncInboxWorkspaceToPendingImports: @escaping () -> Void,
        persistInteractionSnapshotIfReady: @escaping () -> Void,
        selectFirstImportedPendingAndFocusInbox: @escaping (UUID) -> Void,
        refreshRoutingRuleMetadata: @escaping () -> Void,
        readInboxWorkspace: @escaping () -> [String: InboxPendingWorkspaceState],
        writeInboxWorkspace: @escaping ([String: InboxPendingWorkspaceState]) -> Void,
        recomputedParsedHints: @escaping (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints,
        pendingDisplayDraft: @escaping (SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft,
        bumpAppStateRevision: @escaping () -> Void
    ) {
        self.inboxWorkflowService = inboxWorkflowService
        self.inboxStore = inboxStore
        self.managedStorage = managedStorage
        self.importPipeline = importPipeline
        self.existingImportedOriginalPaths = existingImportedOriginalPaths
        self.syncInboxWorkspaceToPendingImports = syncInboxWorkspaceToPendingImports
        self.persistInteractionSnapshotIfReady = persistInteractionSnapshotIfReady
        self.selectFirstImportedPendingAndFocusInbox = selectFirstImportedPendingAndFocusInbox
        self.refreshRoutingRuleMetadata = refreshRoutingRuleMetadata
        self.readInboxWorkspace = readInboxWorkspace
        self.writeInboxWorkspace = writeInboxWorkspace
        self.recomputedParsedHints = recomputedParsedHints
        self.pendingDisplayDraft = pendingDisplayDraft
        self.bumpAppStateRevision = bumpAppStateRevision
    }

    func importFiles(from urls: [URL]) {
        let imported = inboxWorkflowService.importFiles(
            urls: urls,
            inboxStore: inboxStore,
            managedStorage: managedStorage,
            importPipeline: importPipeline,
            excludedOriginalPaths: existingImportedOriginalPaths()
        )
        guard !imported.isEmpty else {
            return
        }
        syncInboxWorkspaceToPendingImports()
        persistInteractionSnapshotIfReady()
        if let pendingID = imported.first?.id {
            selectFirstImportedPendingAndFocusInbox(pendingID)
        }
    }

    func clearPendingImports() {
        inboxWorkflowService.clearPendingImports(inboxStore: inboxStore)
        writeInboxWorkspace([:])
        persistInteractionSnapshotIfReady()
    }

    func recomputeAllPendingParsedHints() {
        refreshRoutingRuleMetadata()
        let recomputeOutcome = inboxWorkflowService.recomputeAllPendingParsedHints(
            inboxStore: inboxStore,
            existingWorkspaceByPendingID: readInboxWorkspace(),
            recomputeHints: { [recomputedParsedHints] pending in
                recomputedParsedHints(pending)
            },
            pendingDisplayDraft: { [pendingDisplayDraft] pending in
                pendingDisplayDraft(pending)
            }
        )
        writeInboxWorkspace(recomputeOutcome.workspaceByPendingID)
        persistInteractionSnapshotIfReady()
        bumpAppStateRevision()
    }
}
