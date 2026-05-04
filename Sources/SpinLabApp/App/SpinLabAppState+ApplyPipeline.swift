import Foundation

extension SpinLabAppState {

    func applySelectedPendingImport() {
        inboxFacade.applySelectedPending()
    }

    func applyAllPendingImports() {
        inboxFacade.applyAllPending()
    }

    func performApplySelectedPendingImport() {
        runApply(scope: .selected(selectedPendingImportID))
    }

    func performApplyAllPendingImports() {
        guard !applyProgressState.isRunning else {
            return
        }
        runApply(scope: .all)
    }

    private func runApply(scope: ApplyCoordinator.ApplyScope) {
        guard let libraryRootURL = resolvedLibraryRootURLForApply() else {
            return
        }
        let workspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        let pendingImportsForScope: [SpinLabDomain.PendingImport]
        switch scope {
        case .all:
            pendingImportsForScope = inboxFeatureStore.pendingImports.filter { pending in
                let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
                let draftOverride = workspaceByPendingID[key]?.draft
                if case .allGood = pendingTagReadiness(for: pending, draftOverride: draftOverride) {
                    return true
                }
                return false
            }
        case .selected:
            pendingImportsForScope = inboxFeatureStore.pendingImports
        }

        let context = applyCoordinator.resolveContext(
            libraryRootURL: libraryRootURL,
            pendingImports: pendingImportsForScope,
            routingSnapshotFor: { pending in
                self.routingSnapshotForApply(for: pending)
            },
            libraryStore: libraryFeatureStore.libraryStore
        )
        applyProgressState = .init(
            isRunning: true,
            totalCount: 0,
            processedCount: 0,
            appliedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            currentFileName: ""
        )

        Task { @MainActor in
            let outcome = await applyCoordinator.apply(
                scope: scope,
                context: context,
                libraryStore: libraryFeatureStore.libraryStore,
                applyService: inboxArchiveApplyService,
                draftFor: { pendingID in
                    workspaceByPendingID[InteractionSnapshotKeyCodec.dictionaryKey(for: pendingID)]?.draft
                },
                workflowDefinitions: workflowDefinitions,
                onProgress: { [weak self] update in
                    self?.applyProgressState = .init(
                        isRunning: true,
                        totalCount: update.totalCount,
                        processedCount: update.processedCount,
                        appliedCount: update.appliedCount,
                        skippedCount: update.skippedCount,
                        failedCount: update.failedCount,
                        currentFileName: update.currentFileName
                    )
                }
            )
            finalizeApplyOutcome(outcome)
            applyProgressState = .init()
        }
    }

    private func finalizeApplyOutcome(_ outcome: InboxApplyOutcome) {
        let processedIDs = outcome.processedIDs

        inboxFeatureStore.applyPending(processedIDs: processedIDs)
        for pendingID in processedIDs {
            updateInteractionEntryValue(for: pendingID, in: \.inboxWorkspaceByPendingID, value: nil)
        }

        switch outcome {
        case .nothingToApply:
            appLogger.info(.import, "Apply skipped: no matched pending imports")
        case let .success(appliedIDs, skippedIDs):
            appLogger.info(.import, "Apply completed", metadata: [
                "appliedCount": "\(appliedIDs.count)",
                "skippedCount": "\(skippedIDs.count)"
            ])
            if !appliedIDs.isEmpty { libraryFeatureStore.syncLibraryFromFiles() }
        case let .partialSuccess(appliedIDs, skippedIDs, failedIDs):
            appLogger.warning(.import, "Apply partially completed", metadata: [
                "appliedCount": "\(appliedIDs.count)",
                "skippedCount": "\(skippedIDs.count)",
                "failedCount": "\(failedIDs.count)"
            ])
            if !appliedIDs.isEmpty { libraryFeatureStore.syncLibraryFromFiles() }
            present(
                error: .state("Applied \(appliedIDs.count), skipped \(skippedIDs.count) existing, failed \(failedIDs.count)."),
                title: "Apply Partially Completed"
            )
        case let .failure(message):
            appLogger.error(.import, "Apply failed", metadata: ["reason": message])
            present(error: .io(message), title: "Apply Failed")
        }

        bumpAppStateRevision()
    }

    private func routingSnapshotForApply(
        for pending: SpinLabDomain.PendingImport
    ) -> SpinLabDomain.PendingRoutingSnapshot {
        if let cached = inboxFeatureStore.cachedPendingRoutingSnapshot(for: pending.id) {
            return cached
        }
        return inboxFeatureStore.pendingRoutingSnapshot(for: pending)
    }

    private func resolvedLibraryRootURLForApply() -> URL? {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            present(error: .validation("Library Root is not configured."), title: "Apply Failed")
            return nil
        }
        return URL(fileURLWithPath: rootPath)
    }
}
