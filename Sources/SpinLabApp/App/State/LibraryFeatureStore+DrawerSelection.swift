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

    /// Selection-level continuation: applies only the pending *selection* (if
    /// any) and clears the pending record. Full navigations use
    /// `takePendingNavigation()` and are committed by `SpinLabAppState`.
    func applyPendingSelectionChangeIfNeeded() -> SelectionChangeOutcome? {
        guard let pending = takePendingNavigation(), let selection = pending.selection else {
            return nil
        }
        return applySelectionChange(selection)
    }

    func takePendingNavigation() -> LibraryPendingNavigation? {
        guard let pending = libraryState.pendingNavigation else {
            return nil
        }
        libraryState.pendingNavigation = nil
        libraryPendingSelectionChangePrompt = nil
        return pending
    }

    func cancelPendingSelectionChange() {
        libraryState.pendingNavigation = nil
        libraryPendingSelectionChangePrompt = nil
    }

    func hasPendingSelectionChange() -> Bool {
        libraryState.pendingNavigation != nil
    }

    /// Records a deferred navigation behind the dirty-draft prompt. Returns
    /// `true` when `candidate` is now (or already was) the waiting request;
    /// `false` when a *different* request is already waiting — the existing
    /// request is never silently overwritten.
    func deferNavigation(_ candidate: LibraryPendingNavigation, prompt: String) -> Bool {
        if let waiting = libraryState.pendingNavigation {
            return waiting.selection == candidate.selection && waiting.target == candidate.target
        }
        libraryState.pendingNavigation = candidate
        libraryPendingSelectionChangePrompt = prompt
        return true
    }

    var currentDraftBinding: LibraryPendingNavigation.DraftBinding {
        .init(prefix: librarySelectedPrefix, batchId: librarySelectedBatchId, sampleId: librarySelectedSampleId)
    }

    /// True when the waiting request was deferred for a draft that is no longer
    /// the one being edited (selection moved underneath it).
    func pendingNavigationIsStale() -> Bool {
        guard let bound = libraryState.pendingNavigation?.boundDraft else {
            return false
        }
        return bound != currentDraftBinding
    }

    /// Whether `identity` is the Drawer sample currently being edited.
    func isCurrentDrawerIdentity(prefix: String, batchId: String, sampleId: String?) -> Bool {
        isCurrentDrawerSelection(prefix: prefix, batchId: batchId, sampleId: sampleId)
    }

    /// Data-driven (not user) route repair: a Sample Workspace whose Batch no
    /// longer exists falls back to Management.
    func reconcileRouteWithLoadedData() {
        guard case let .sampleWorkspace(prefix, batchId) = currentRoute else {
            return
        }
        let exists = libraryExistingGroups[prefix]?.contains(where: { $0.batchId == batchId }) == true
        if !exists {
            selectManagement()
        }
    }

    func normalizeLibrarySelection() {
        let output = LibrarySelectionSync.syncDrawerSelection(
            input: .init(
                selectedPrefix: librarySelectedPrefix,
                selectedBatchId: librarySelectedBatchId,
                selectedSampleId: librarySelectedSampleId
            ),
            existingGroupsByPrefix: libraryExistingGroups
        )

        librarySelectedPrefix = output.selectedPrefix
        librarySelectedBatchId = output.selectedBatchId
        librarySelectedSampleId = output.selectedSampleId

        guard output.selectedPrefix != nil, output.selectedBatchId != nil else {
            return
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

        _ = deferNavigation(
            LibraryPendingNavigation(selection: requested, boundDraft: currentDraftBinding),
            prompt: "You have unsaved sample edits. Save before switching selection?"
        )
        return true
    }

    private func isCurrentDrawerSelection(prefix: String, batchId: String, sampleId: String?) -> Bool {
        librarySelectedPrefix == prefix
            && librarySelectedBatchId == batchId
            && librarySelectedSampleId == sampleId
    }

    func applySelectionChange(_ requested: LibraryPendingSelectionChange) -> SelectionChangeOutcome {
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
