import Foundation

@MainActor
final class InboxFacade {
    private let inboxWorkflowService: InboxWorkflowService
    private let inboxStore: InboxFeatureStore
    private let managedStorage: SpinLabManagedStorage
    private let importPipeline: SpinLabImportPipeline

    private let existingImportedOriginalPaths: () -> Set<String>
    private let existingImportedContentFingerprints: () -> Set<String>
    private let syncInboxWorkspaceToPendingImports: () -> Void
    private let persistInteractionSnapshotIfReady: () -> Void
    private let selectFirstImportedPendingAndFocusInbox: (UUID) -> Void
    private let refreshRoutingRuleMetadata: () -> Void
    private let readInboxWorkspace: () -> [String: InboxPendingWorkspaceState]
    private let writeInboxWorkspace: ([String: InboxPendingWorkspaceState]) -> Void
    private let recomputedParsedHints: (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints
    private let conditionDefinitions: () -> [ConditionDefinitionOption]
    private let pendingDisplayDraft: (SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft
    private let bumpAppStateRevision: () -> Void
    private let applySelected: () -> Void
    private let applyAll: () -> Void

    init(
        inboxWorkflowService: InboxWorkflowService,
        inboxStore: InboxFeatureStore,
        managedStorage: SpinLabManagedStorage,
        importPipeline: SpinLabImportPipeline,
        existingImportedOriginalPaths: @escaping () -> Set<String>,
        existingImportedContentFingerprints: @escaping () -> Set<String>,
        syncInboxWorkspaceToPendingImports: @escaping () -> Void,
        persistInteractionSnapshotIfReady: @escaping () -> Void,
        selectFirstImportedPendingAndFocusInbox: @escaping (UUID) -> Void,
        refreshRoutingRuleMetadata: @escaping () -> Void,
        readInboxWorkspace: @escaping () -> [String: InboxPendingWorkspaceState],
        writeInboxWorkspace: @escaping ([String: InboxPendingWorkspaceState]) -> Void,
        recomputedParsedHints: @escaping (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints,
        conditionDefinitions: @escaping () -> [ConditionDefinitionOption],
        pendingDisplayDraft: @escaping (SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft,
        bumpAppStateRevision: @escaping () -> Void,
        applySelected: @escaping () -> Void,
        applyAll: @escaping () -> Void
    ) {
        self.inboxWorkflowService = inboxWorkflowService
        self.inboxStore = inboxStore
        self.managedStorage = managedStorage
        self.importPipeline = importPipeline
        self.existingImportedOriginalPaths = existingImportedOriginalPaths
        self.existingImportedContentFingerprints = existingImportedContentFingerprints
        self.syncInboxWorkspaceToPendingImports = syncInboxWorkspaceToPendingImports
        self.persistInteractionSnapshotIfReady = persistInteractionSnapshotIfReady
        self.selectFirstImportedPendingAndFocusInbox = selectFirstImportedPendingAndFocusInbox
        self.refreshRoutingRuleMetadata = refreshRoutingRuleMetadata
        self.readInboxWorkspace = readInboxWorkspace
        self.writeInboxWorkspace = writeInboxWorkspace
        self.recomputedParsedHints = recomputedParsedHints
        self.conditionDefinitions = conditionDefinitions
        self.pendingDisplayDraft = pendingDisplayDraft
        self.bumpAppStateRevision = bumpAppStateRevision
        self.applySelected = applySelected
        self.applyAll = applyAll
    }

    func importFiles(from urls: [URL]) {
        let sync = syncInboxWorkspaceToPendingImports
        let persist = persistInteractionSnapshotIfReady
        let select = selectFirstImportedPendingAndFocusInbox
        inboxStore.startImportFiles(
            from: urls,
            managedStorage: managedStorage,
            importPipeline: importPipeline,
            excludedOriginalFilePaths: existingImportedOriginalPaths(),
            excludedContentFingerprints: existingImportedContentFingerprints(),
            onCompleted: { imported in
                sync()
                persist()
                if let pendingID = imported.first?.id {
                    select(pendingID)
                }
            }
        )
    }

    func clearPendingImports() {
        inboxWorkflowService.clearPendingImports(inboxStore: inboxStore)
        writeInboxWorkspace([:])
        persistInteractionSnapshotIfReady()
    }

    func clearSelectedPendingImport() {
        guard let removedID = inboxStore.removeSelectedPendingImport() else {
            return
        }
        var workspace = readInboxWorkspace()
        workspace.removeValue(forKey: InteractionSnapshotKeyCodec.dictionaryKey(for: removedID))
        writeInboxWorkspace(workspace)
        persistInteractionSnapshotIfReady()
        bumpAppStateRevision()
    }

    func dryRunConditionRecompute() -> [ConditionChangeProposal] {
        inboxWorkflowService.dryRunConditionRecompute(
            pendingImports: inboxStore.pendingImports,
            recomputeHints: { [recomputedParsedHints] pending in recomputedParsedHints(pending) },
            conditionDefinitions: conditionDefinitions()
        )
    }

    func applyConditionProposals(pendingIDs: Set<UUID>) {
        guard !pendingIDs.isEmpty else { return }
        let outcome = inboxWorkflowService.recomputeSpecificPending(
            pendingIDs: pendingIDs,
            inboxStore: inboxStore,
            existingWorkspaceByPendingID: readInboxWorkspace(),
            recomputeHints: { [recomputedParsedHints] pending in recomputedParsedHints(pending) },
            pendingDisplayDraft: { [pendingDisplayDraft] pending in pendingDisplayDraft(pending) }
        )
        writeInboxWorkspace(outcome.workspaceByPendingID)
        persistInteractionSnapshotIfReady()
        bumpAppStateRevision()
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

    func applySelectedPending() {
        applySelected()
    }

    func applyAllPending() {
        applyAll()
    }
}
