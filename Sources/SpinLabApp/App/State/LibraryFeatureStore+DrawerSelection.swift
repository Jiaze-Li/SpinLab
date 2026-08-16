import Foundation

@MainActor extension LibraryFeatureStore {

    func incrementLibrarySelectionVersion() {
        librarySelectionVersion &+= 1
    }

    func restoreInteraction(
        libraryActiveSelectionSource: LibrarySelectionSource,
        librarySelectedPrefix: String?,
        librarySelectedBatchId: String?,
        librarySelectedSampleId: String?,
        libraryBrowserSelectedPrefix: String? = nil,
        libraryBrowserSelectedBatchId: String? = nil,
        libraryBrowserSelectedSampleId: String? = nil
    ) {
        self.libraryActiveSelectionSource = libraryActiveSelectionSource
        self.librarySelectedPrefix = librarySelectedPrefix
        self.librarySelectedBatchId = librarySelectedBatchId
        self.librarySelectedSampleId = librarySelectedSampleId
        self.libraryBrowserSelectedPrefix = libraryBrowserSelectedPrefix
        self.libraryBrowserSelectedBatchId = libraryBrowserSelectedBatchId
        self.libraryBrowserSelectedSampleId = libraryBrowserSelectedSampleId
    }

    func captureInteraction(into snapshot: inout SpinLabInteractionSnapshot) {
        snapshot.libraryActiveSelectionSource = libraryActiveSelectionSource
        snapshot.librarySelectedPrefix = librarySelectedPrefix
        snapshot.librarySelectedBatchId = librarySelectedBatchId
        snapshot.librarySelectedSampleId = librarySelectedSampleId
        snapshot.libraryBrowserSelectedPrefix = libraryBrowserSelectedPrefix
        snapshot.libraryBrowserSelectedBatchId = libraryBrowserSelectedBatchId
        snapshot.libraryBrowserSelectedSampleId = libraryBrowserSelectedSampleId
    }

    func commitSelection() {
        onPersistInteractionSnapshot?()
    }

    func applyPreparedSyncReviewDecision() -> ApplyPreparedSyncReviewDecision {
        guard let review = libraryRefreshReview else {
            return .missingReview(message: "No sync review available. Run Sync Registry first.")
        }
        guard review.totalChangesCount > 0 else {
            return .noChanges(message: "No changes to apply.")
        }
        return .apply(totalChanges: review.totalChangesCount)
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) -> SelectionChangeOutcome {
        performSelectionChange(.drawer(prefix: prefix, batchId: batchId, sampleId: sampleId))
    }

    func selectBrowserSample() -> SelectionChangeOutcome {
        performSelectionChange(.browser)
    }

    func applyPendingSelectionChangeIfNeeded() -> SelectionChangeOutcome? {
        guard let pending = libraryState.pendingSelectionChange else {
            return nil
        }
        libraryState.pendingSelectionChange = nil
        libraryPendingSelectionChangePrompt = nil
        return applySelectionChange(pending)
    }

    func cancelPendingSelectionChange() {
        libraryState.pendingSelectionChange = nil
        libraryPendingSelectionChangePrompt = nil
    }

    func hasPendingSelectionChange() -> Bool {
        libraryState.pendingSelectionChange != nil
    }

    func normalizeLibrarySelection() {
        let prefixes = libraryExistingGroups.keys.sorted()
        if librarySelectedPrefix == nil || !prefixes.contains(librarySelectedPrefix ?? "") {
            librarySelectedPrefix = prefixes.first
        }

        guard let prefix = librarySelectedPrefix else {
            librarySelectedBatchId = nil
            librarySelectedSampleId = nil
            return
        }

        let groups = libraryExistingGroups[prefix] ?? []
        let batchIDs = groups.map(\.batchId)
        if librarySelectedBatchId == nil || !batchIDs.contains(librarySelectedBatchId ?? "") {
            librarySelectedBatchId = groups.first?.batchId
        }

        guard let batchId = librarySelectedBatchId,
              let samples = groups.first(where: { $0.batchId == batchId })?.samples else {
            librarySelectedSampleId = nil
            return
        }

        if librarySelectedSampleId == nil || !samples.contains(where: { $0.id == librarySelectedSampleId }) {
            librarySelectedSampleId = samples.first?.id
        }
        commitSelection()
    }

    private func performSelectionChange(_ requested: LibraryPendingSelectionChange) -> SelectionChangeOutcome {
        guard !deferSelectionChangeIfNeeded(requested) else {
            return .deferred
        }
        return applySelectionChange(requested)
    }

    /// Dirty-edit deferral answers exactly one question: will this operation
    /// change the Drawer sample currently being edited? Browser navigation
    /// never changes Drawer identity, so it always bypasses this guard —
    /// Browser focus changes must never trigger (or be blocked by) the
    /// Drawer save/discard prompt.
    private func deferSelectionChangeIfNeeded(_ requested: LibraryPendingSelectionChange) -> Bool {
        guard case let .drawer(prefix, batchId, sampleId) = requested else {
            return false
        }
        guard librarySampleEditIsDirty,
              !isCurrentDrawerSelection(prefix: prefix, batchId: batchId, sampleId: sampleId) else {
            return false
        }

        libraryState.pendingSelectionChange = requested
        libraryPendingSelectionChangePrompt = "You have unsaved sample edits. Save before switching selection?"
        return true
    }

    private func isCurrentDrawerSelection(prefix: String, batchId: String, sampleId: String?) -> Bool {
        librarySelectedPrefix == prefix
            && librarySelectedBatchId == batchId
            && librarySelectedSampleId == sampleId
    }

    private func applySelectionChange(_ requested: LibraryPendingSelectionChange) -> SelectionChangeOutcome {
        switch requested {
        case let .drawer(prefix, batchId, sampleId):
            librarySelectedPrefix = prefix
            librarySelectedBatchId = batchId
            if let sampleId {
                librarySelectedSampleId = sampleId
            } else {
                librarySelectedSampleId = libraryExistingGroups[prefix]?
                    .first(where: { $0.batchId == batchId })?
                    .samples
                    .first?
                    .id
            }
            libraryActiveSelectionSource = .drawer
            commitSelection()
            incrementLibrarySelectionVersion()
            reconcileLibrarySampleEditingSelection()
            loadWorkbenchResultsForCurrentSelection()
            loadMeasurementDataForCurrentSelection()
            return .appliedDrawer(prefix: prefix, batchId: batchId, sampleId: librarySelectedSampleId)

        case .browser:
            // Focus moving to Browser must never touch the Drawer edit
            // session — no reconcile call here. Reconciliation only fires
            // when the Drawer's own selection identity actually changes
            // (the `.drawer` branch above).
            libraryActiveSelectionSource = .browser
            commitSelection()
            incrementLibrarySelectionVersion()
            loadWorkbenchResultsForCurrentSelection()
            loadMeasurementDataForCurrentSelection()
            return .appliedBrowser(
                prefix: libraryBrowserSelectedPrefix,
                batchId: libraryBrowserSelectedBatchId,
                sampleId: libraryBrowserSelectedSampleId
            )
        }
    }
}
