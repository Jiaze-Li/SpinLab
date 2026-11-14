import Foundation

extension SpinLabAppState {

    static let syncStatusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    func loadLibraryPreview() {
        libraryFeatureStore.loadLibraryPreview(
            resolvedRegistryPath: resolvedLibraryRegistryPath(),
            dataActor: dataActor,
            refreshActionablePreviewGroups: { [weak self] in
                self?.refreshActionablePreviewGroups()
            },
            onFailure: { [weak self] appError in
                guard let self else { return }
                present(error: appError, title: "Preview Load Failed")
                appLogger.warning(.library, "Library preview load failed", metadata: ["error": appError.localizedDescription])
            }
        )
    }

    func syncLibraryFromRegistry(onComplete: (() -> Void)? = nil) {
        appLogger.info(.function, "Library sync requested", metadata: ["area": "registry"])
        let resolvedPath = resolvedLibraryRegistryPath()
        libraryFeatureStore.syncLibraryFromRegistry(
            resolvedRegistryPath: resolvedPath,
            dataActor: dataActor,
            prepareLibrarySyncReview: { [weak self] in
                self?.libraryFeatureStore.prepareLibrarySyncReview()
            },
            refreshActionablePreviewGroups: { [weak self] in
                self?.refreshActionablePreviewGroups()
            },
            formatSyncDate: { Self.syncStatusTimeFormatter.string(from: $0) },
            onFailure: { [weak self] appError in
                guard let self else { return }
                present(error: appError, title: "Sync Preview Failed")
                appLogger.warning(.library, "Library sync preview failed", metadata: ["error": appError.localizedDescription])
            },
            onComplete: onComplete
        )
        if resolvedPath == nil {
            appLogger.warning(.library, "Library preview unavailable during sync request")
        }
    }

    func applyPreparedLibrarySyncReview() {
        switch libraryFeatureStore.applyPreparedSyncReviewDecision() {
        case let .missingReview(message):
            libraryFeatureStore.libraryDrawerError = message
            appLogger.warning(.library, "Apply all skipped: no sync review")
        case let .noChanges(message):
            libraryFeatureStore.libraryDrawerMessage = message
            appLogger.info(.library, "Apply all skipped: no pending changes")
        case let .apply(totalChanges):
            appLogger.info(.function, "Apply all requested", metadata: [
                "changes": "\(totalChanges)"
            ])
            libraryFeatureStore.refreshLibraryIncremental()
        }
    }

    func applySelectedRegistryDiff(batchId: String?) {
        switch libraryFeatureStore.applySelectedRegistryDiff(batchId: batchId) {
        case let .failure(message):
            appLogger.warning(.library, "Apply selected failed", metadata: [
                "batchId": batchId ?? "-",
                "reason": message
            ])
        case let .noPendingChanges(id, _):
            appLogger.info(.library, "Apply selected skipped: no pending changes", metadata: ["batchId": id])
        case let .success(rootURL, previewIndex, id, action, touched, _):
            commitLibraryMutation(rootURL: rootURL, previewIndex: previewIndex)
            libraryFeatureStore.libraryDrawerMessage = "Applied selected sync for \(id): \(action), \(touched) sample changes."
            appLogger.info(.function, "Apply selected completed", metadata: [
                "batchId": id,
                "action": action,
                "sampleChanges": "\(touched)"
            ])
        }
    }

    func loadExistingDrawers() {
        guard let index = libraryFeatureStore.loadExistingDrawersIndexForCurrentRoot() else {
            libraryFeatureStore.libraryExistingGroups = [:]
            inboxFeatureStore.clearDrawerMatchCandidates()
            libraryFeatureStore.libraryExistingMessage = libraryFeatureStore.librarySettings.rootPath == nil
                ? "No Library Root selected."
                : "Library Root not found."
            libraryFeatureStore.librarySelectedPrefix = nil
            libraryFeatureStore.librarySelectedBatchId = nil
            libraryFeatureStore.librarySelectedSampleId = nil
            libraryFeatureStore.commitSelection()
            refreshPendingDrawerMatches()
            return
        }
        applyExistingIndex(index)
    }

    func validateLibraryCacheOnAppear() {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath else {
            return
        }
        let now = Date()
        if lastLibraryCacheValidationRootPath == rootPath,
           let lastLibraryCacheValidationAt,
           now.timeIntervalSince(lastLibraryCacheValidationAt) < 12 {
            return
        }
        lastLibraryCacheValidationRootPath = rootPath
        lastLibraryCacheValidationAt = now

        let rootURL = URL(fileURLWithPath: rootPath)
        guard libraryFeatureStore.libraryStore.needsIndexRefresh(rootURL: rootURL) else {
            return
        }
        // Source files are newer than the persisted index: show their current
        // state without rewriting the index. Persisting is an explicit user action.
        loadExistingDrawers()
        refreshActionablePreviewGroups()
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) {
        let outcome = libraryFeatureStore.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
        handleLibrarySelectionChangeOutcome(outcome)
    }

    func selectBrowserSample() {
        let outcome = libraryFeatureStore.selectBrowserSample()
        handleLibrarySelectionChangeOutcome(outcome)
    }

    /// Applies the Drawer selection with no dirty-draft guard. Only the
    /// navigation transaction calls this, after the guard cleared or the user
    /// resolved the prompt.
    func selectExistingDrawerUnguarded(prefix: String, batchId: String, sampleId: String?) {
        let outcome = libraryFeatureStore.applySelectionChange(.drawer(prefix: prefix, batchId: batchId, sampleId: sampleId))
        handleLibrarySelectionChangeOutcome(outcome)
    }

    /// Save → then run the waiting request. A failed save runs nothing and keeps
    /// Route, Selection, Focus and Draft exactly as they were.
    func saveAndContinuePendingLibrarySelectionChange() {
        guard libraryFeatureStore.hasPendingSelectionChange() else {
            return
        }
        guard !libraryFeatureStore.pendingNavigationIsStale() else {
            libraryFeatureStore.cancelPendingSelectionChange()
            return
        }
        // Decide on the real save outcome, never on librarySampleEditError: a sample that was saved with
        // a Registry/XLSX sync warning also sets that string, but the file IS saved and the draft cleared.
        switch libraryFeatureStore.saveLibrarySampleEdits() {
        case .success:
            // Saved (possibly with a sync warning). The warning stays visible: the "Sync Warning" alert was
            // raised by the save itself and librarySampleEditMessage/Error keep the explicit text.
            break
        case let .failure(error):
            // The legacy Detail editor already presents the save error itself;
            // raise the host alert only where no editor is on screen (Gallery),
            // so a single failure never produces two popups.
            if libraryFeatureStore.currentRoute.isWorkflowGallery {
                libraryFeatureStore.libraryNavigationFailureMessage = error.localizedDescription
            }
            return
        case nil:
            if libraryFeatureStore.currentRoute.isWorkflowGallery {
                libraryFeatureStore.libraryNavigationFailureMessage = "Save could not start."
            }
            return
        }
        continuePendingNavigation()
    }

    /// Discard the explicitly bound Drawer draft → then run the waiting request.
    func discardAndContinuePendingLibrarySelectionChange() {
        guard libraryFeatureStore.hasPendingSelectionChange() else {
            return
        }
        guard !libraryFeatureStore.pendingNavigationIsStale() else {
            libraryFeatureStore.cancelPendingSelectionChange()
            return
        }
        libraryFeatureStore.discardEditingSelectedLibrarySample()
        continuePendingNavigation()
    }

    func continuePendingNavigation() {
        guard let pending = libraryFeatureStore.takePendingNavigation() else {
            return
        }
        if let target = pending.target {
            commitNavigation(target)
        } else if let selection = pending.selection {
            handleLibrarySelectionChangeOutcome(libraryFeatureStore.applySelectionChange(selection))
        }
    }

    func updateLibraryRoot(to url: URL) {
        libraryFeatureStore.updateLibraryRoot(to: url)
        lastLibraryCacheValidationRootPath = nil
        lastLibraryCacheValidationAt = nil
        loadExistingDrawers()
    }

    func syncLibraryBackup() {
        libraryFeatureStore.syncLibraryBackup(formatSyncDate: { Self.syncStatusTimeFormatter.string(from: $0) })
    }

    func applyExistingIndex(_ index: LibraryIndex) {
        guard !index.samples.isEmpty else {
            libraryFeatureStore.libraryExistingGroups = [:]
            inboxFeatureStore.clearDrawerMatchCandidates()
            libraryFeatureStore.libraryExistingMessage = "No existing drawers found."
            libraryFeatureStore.librarySelectedPrefix = nil
            libraryFeatureStore.librarySelectedBatchId = nil
            libraryFeatureStore.librarySelectedSampleId = nil
            libraryFeatureStore.commitSelection()
            libraryFeatureStore.librarySampleEditDraft = nil
            libraryFeatureStore.libraryState.sampleEditBaseSample = nil
            libraryFeatureStore.libraryState.sampleEditOriginalDraft = nil
            refreshPendingDrawerMatches()
            return
        }

        libraryFeatureStore.libraryExistingGroups = buildPreviewGroups(from: index)
        inboxFeatureStore.rebuildDrawerMatchCandidates(from: index.samples)
        libraryFeatureStore.libraryExistingMessage = "Loaded existing drawers: \(index.samples.count) samples"
        libraryFeatureStore.normalizeLibrarySelection()
        libraryFeatureStore.refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        libraryFeatureStore.reconcileLibrarySampleEditingSelection()
        refreshPendingDrawerMatches()
    }

    @discardableResult
    func createNativeSample(draft: CreateNativeSampleDraft) -> CreateNativeSampleOutcome {
        libraryFeatureStore.libraryDrawerError = nil
        libraryFeatureStore.libraryDrawerMessage = nil
        let outcome = libraryMutationService.createNativeSample(
            draft: draft,
            rootPath: libraryFeatureStore.librarySettings.rootPath,
            libraryStore: libraryFeatureStore.libraryStore,
            settings: libraryFeatureStore.librarySettings
        )
        switch outcome {
        case let .success(sample, batch, syncedIndex):
            applyExistingIndex(syncedIndex)
            let prefix = LibrarySort.batchSortKey(batch.id).prefix
            navigate(to: .libraryDrawer(prefix: prefix, batchId: batch.id, sampleId: sample.id))
            libraryFeatureStore.libraryDrawerMessage = "Created sample \(sample.displayName)."
            return .success(sample: sample, batch: batch, syncedIndex: syncedIndex)
        case let .failure(error):
            libraryFeatureStore.libraryDrawerError = error.localizedDescription
            return .failure(error: error)
        }
    }

    /// Collects samples submitted from the phone page. Runs at launch (silent when the pickup token
    /// is not set up) and on the manual refresh (then says so). Never navigates away from the user's view.
    func pickUpPhoneSamples(
        manual: Bool,
        tokenProvider: any PhoneAccessTokenProviding = KeychainPhoneAccessTokenStore(),
        makeTransport: (PhoneAccessToken) -> any PendingSampleTransport = { URLSessionPendingSampleTransport(token: $0) }
    ) {
        guard !phonePickupInFlight else { return }
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath, !rootPath.isEmpty else { return }
        guard let token = tokenProvider.token() else {
            if manual {
                libraryFeatureStore.libraryDrawerMessage =
                    "Phone samples: the pickup token is not set up in the Keychain, so nothing was collected."
            }
            return
        }
        phonePickupInFlight = true
        let transport = makeTransport(token)
        let choices = NativeSampleSubstrateChoices.current()
        Task { @MainActor in
            defer { phonePickupInFlight = false }
            do {
                let summary = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices) { draft in
                    libraryMutationService.createNativeSample(
                        draft: draft,
                        rootPath: libraryFeatureStore.librarySettings.rootPath,
                        libraryStore: libraryFeatureStore.libraryStore,
                        settings: libraryFeatureStore.librarySettings
                    )
                }
                if let index = summary.lastIndex { applyExistingIndex(index) }
                if summary.created > 0 || summary.hasProblems || manual {
                    if summary.hasProblems {
                        libraryFeatureStore.libraryDrawerError = summary.message
                    } else {
                        libraryFeatureStore.libraryDrawerMessage = summary.message
                    }
                }
            } catch {
                if manual { libraryFeatureStore.libraryDrawerError = "Phone samples: \(error.localizedDescription)" }
                appLogger.warning(.library, "Phone sample pickup failed", metadata: ["error": error.localizedDescription])
            }
        }
    }

    func commitLibraryMutation(
        rootURL: URL,
        previewIndex: LibraryIndex?,
        precomputedDiff: LibraryDiff? = nil,
        precomputedReview: LibraryRefreshReview? = nil
    ) {
        let outcome: LibraryCommitMutationOutcome
        do {
            outcome = try libraryMutationService.commitMutation(
                rootURL: rootURL,
                previewIndex: previewIndex,
                precomputedDiff: precomputedDiff,
                precomputedReview: precomputedReview,
                librarySyncService: libraryFeatureStore.librarySyncService
            )
        } catch {
            libraryFeatureStore.libraryDrawerMessage = nil
            libraryFeatureStore.libraryDrawerError = "Index refresh stopped: \(error.localizedDescription)"
            return
        }
        applyExistingIndex(outcome.syncedIndex)

        libraryFeatureStore.libraryRefreshReview = outcome.plan.review
        libraryFeatureStore.refreshSyncChangeIndicators(using: libraryMutationService)
        if let diff = outcome.plan.diff, let baseline = outcome.plan.baselineIndexForPreview {
            refreshActionablePreviewGroups(precomputedDiff: diff, baselineIndex: baseline)
        } else {
            refreshActionablePreviewGroups()
        }

        libraryFeatureStore.librarySettings.lastRefreshAt = outcome.plan.lastRefreshAt
        libraryFeatureStore.librarySettingsStore.save(libraryFeatureStore.librarySettings)
    }

    func handleLibrarySelectionChangeOutcome(_ outcome: LibraryFeatureStore.SelectionChangeOutcome) {
        switch outcome {
        case .deferred:
            break
        case let .appliedDrawer(prefix, batchId, sampleId):
            libraryFeatureStore.refreshSelectedDrawerAppliedMeasurementsIfNeeded()
            appLogger.info(.ui, "Existing drawer selected", metadata: [
                "prefix": prefix,
                "batchId": batchId,
                "sampleId": sampleId ?? "-"
            ])
        case let .appliedBrowser(prefix, batchId, sampleId):
            appLogger.info(.usage, "Pending browser selection updated", metadata: [
                "prefix": prefix ?? "-",
                "batchId": batchId ?? "-",
                "sampleId": sampleId ?? "-"
            ])
        }
    }

    private func buildPreviewGroups(from preview: LibraryPreview) -> [String: [LibraryPreviewBatchGroup]] {
        buildPreviewGroups(from: preview.index)
    }

    private func buildPreviewGroups(from index: LibraryIndex) -> [String: [LibraryPreviewBatchGroup]] {
        libraryPreviewComputationService.buildPreviewGroups(from: index)
    }

    func refreshActionablePreviewGroups(precomputedDiff: LibraryDiff? = nil, baselineIndex: LibraryIndex? = nil) {
        guard let preview = libraryFeatureStore.libraryPreview else {
            libraryFeatureStore.libraryPreviewGroups = [:]
            libraryFeatureStore.libraryPreviewMessage = "No preview loaded."
            return
        }
        let state = libraryFeatureStore.librarySyncService.buildActionablePreviewState(
            preview: preview,
            precomputedDiff: precomputedDiff,
            baselineIndex: baselineIndex,
            rootPath: libraryFeatureStore.librarySettings.rootPath,
            previewComputationService: libraryPreviewComputationService
        )
        libraryFeatureStore.libraryPreviewGroups = state.groups
        libraryFeatureStore.libraryPreviewMessage = state.message
    }
}
