import Foundation

struct InboxRecomputeHintsOutcome {
    var recomputedPendingImports: [SpinLabDomain.PendingImport]
    var workspaceByPendingID: [String: InboxPendingWorkspaceState]
}

@MainActor
struct InboxWorkflowService {
    func importFiles(
        urls: [URL],
        inboxStore: InboxFeatureStore,
        managedStorage: SpinLabManagedStorage,
        importPipeline: SpinLabImportPipeline,
        excludedOriginalPaths: Set<String>
    ) -> [SpinLabDomain.PendingImport] {
        inboxStore.importFiles(
            from: urls,
            managedStorage: managedStorage,
            importPipeline: importPipeline,
            excludedOriginalFilePaths: excludedOriginalPaths
        )
    }

    func clearPendingImports(inboxStore: InboxFeatureStore) {
        inboxStore.clearPendingImports()
    }

    func recomputeAllPendingParsedHints(
        inboxStore: InboxFeatureStore,
        existingWorkspaceByPendingID: [String: InboxPendingWorkspaceState],
        recomputeHints: (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints,
        pendingDisplayDraft: (SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft
    ) -> InboxRecomputeHintsOutcome {
        let recomputedPendingImports = inboxStore.recomputeAllPendingParsedHints(recomputeParsedHints: recomputeHints)
        var updatedWorkspaceByPendingID: [String: InboxPendingWorkspaceState] = [:]
        for pending in recomputedPendingImports {
            let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
            guard let existing = existingWorkspaceByPendingID[key] else {
                continue
            }
            updatedWorkspaceByPendingID[key] = InboxPendingWorkspaceState.snapshotSafe(
                draft: pendingDisplayDraft(pending),
                editableFileContents: existing.editableFileContents,
                hasEditableFileContents: existing.hasEditableFileContents,
                routingDraft: nil
            )
        }
        return InboxRecomputeHintsOutcome(
            recomputedPendingImports: recomputedPendingImports,
            workspaceByPendingID: updatedWorkspaceByPendingID
        )
    }

}
