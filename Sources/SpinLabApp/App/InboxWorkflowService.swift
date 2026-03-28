import Foundation

struct InboxRecomputeHintsOutcome {
    var recomputedPendingImports: [SpinLabDomain.PendingImport]
    var workspaceByPendingID: [String: InboxPendingWorkspaceState]
}

enum InboxConfirmPendingImportOutcome {
    struct Success {
        var output: ConfirmPendingImportUseCase.Output
        var route: PendingConfirmationRouteResolution
        var confirmedPending: SpinLabDomain.PendingImport
        var clearWorkspaceEntryPendingID: UUID
        var selectArchivedRecordID: UUID
    }

    case skipped
    case failure(pending: SpinLabDomain.PendingImport, error: AppError, phase: Phase)
    case success(Success)

    enum Phase {
        case saveEditedFile
        case confirm
    }
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

    func confirmPendingImport(
        selectedPending: SpinLabDomain.PendingImport?,
        draft: PendingImportConfirmationDraft,
        editedFileContents: String?,
        savePendingImportContents: (String, SpinLabDomain.PendingImport) throws -> Void,
        inboxStore: InboxFeatureStore,
        confirmUseCase: ConfirmPendingImportUseCase,
        libraryRepository: LibraryRepository,
        makeArchivedRecord: (SpinLabDomain.PendingImport, PendingImportConfirmationDraft) -> SpinLabDomain.ArchivedRecord,
        coordinator: AppCoordinator
    ) -> InboxConfirmPendingImportOutcome {
        guard let pending = selectedPending else {
            return .skipped
        }

        if let editedFileContents {
            do {
                try savePendingImportContents(editedFileContents, pending)
            } catch {
                return .failure(
                    pending: pending,
                    error: AppError.from(error, fallback: "Failed to save edited import contents."),
                    phase: .saveEditedFile
                )
            }
        }

        let result = inboxStore.confirmPendingImport(
            pending: pending,
            draft: draft,
            useCase: confirmUseCase,
            libraryRepository: libraryRepository,
            makeArchivedRecord: makeArchivedRecord
        )
        guard case let .success(output) = result else {
            if case let .failure(error) = result {
                return .failure(pending: pending, error: error, phase: .confirm)
            }
            return .skipped
        }

        let route = coordinator.routeAfterPendingConfirmation(
            archivedRecordID: output.archivedRecord.id,
            nextPendingID: inboxStore.pendingImports.first?.id
        )
        return .success(.init(
            output: output,
            route: route,
            confirmedPending: pending,
            clearWorkspaceEntryPendingID: pending.id,
            selectArchivedRecordID: route.archivedRecordID
        ))
    }
}
