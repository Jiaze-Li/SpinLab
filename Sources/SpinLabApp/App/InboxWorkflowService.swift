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
        excludedOriginalPaths: Set<String>,
        excludedContentFingerprints: Set<String>
    ) -> [SpinLabDomain.PendingImport] {
        inboxStore.importFiles(
            from: urls,
            managedStorage: managedStorage,
            importPipeline: importPipeline,
            excludedOriginalFilePaths: excludedOriginalPaths,
            excludedContentFingerprints: excludedContentFingerprints
        )
    }

    func dryRunConditionRecompute(
        pendingImports: [SpinLabDomain.PendingImport],
        recomputeHints: (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints,
        conditionDefinitions: [ConditionDefinitionOption]
    ) -> [ConditionChangeProposal] {
        let labelByID = Dictionary(uniqueKeysWithValues: conditionDefinitions.map { ($0.id, $0.label) })
        return pendingImports.compactMap { pending in
            let newHints = recomputeHints(pending)
            let oldValues = ConditionFieldCatalog.conditionValues(from: pending.parsedHints)
            let newValues = ConditionFieldCatalog.conditionValues(from: newHints)
            let candidateIDs = Set(oldValues.keys).union(newValues.keys).union(labelByID.keys).sorted()

            var changes: [ConditionChangeProposal.FieldChange] = []
            for id in candidateIDs {
                let oldValue = oldValues[id]
                let newValue = newValues[id]
                guard oldValue != newValue else { continue }
                let label = labelByID[id] ?? ConditionFieldCatalog.defaultLabel(for: id)
                changes.append(.init(label: label, before: oldValue, after: newValue))
            }

            guard !changes.isEmpty else { return nil }
            return ConditionChangeProposal(pendingID: pending.id, fileName: pending.fileName, changes: changes)
        }
    }

    func recomputeSpecificPending(
        pendingIDs: Set<UUID>,
        inboxStore: InboxFeatureStore,
        existingWorkspaceByPendingID: [String: InboxPendingWorkspaceState],
        recomputeHints: (SpinLabDomain.PendingImport) -> SpinLabDomain.ParsedFilenameHints,
        pendingDisplayDraft: (SpinLabDomain.PendingImport) -> PendingImportConfirmationDraft
    ) -> InboxRecomputeHintsOutcome {
        let recomputedPendingImports = inboxStore.recomputeSpecificPendingHints(
            pendingIDs: pendingIDs,
            recomputeParsedHints: recomputeHints
        )
        var updatedWorkspaceByPendingID = existingWorkspaceByPendingID
        for pending in recomputedPendingImports where pendingIDs.contains(pending.id) {
            let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
            guard let existing = existingWorkspaceByPendingID[key] else { continue }
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
