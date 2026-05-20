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
            libraryFeatureStore.libraryExistingMessage = "No Library Root selected."
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
        libraryFeatureStore.syncLibraryFromFiles()
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) {
        let outcome = libraryFeatureStore.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
        handleLibrarySelectionChangeOutcome(outcome)
    }

    func selectBrowserSample() {
        let outcome = libraryFeatureStore.selectBrowserSample()
        handleLibrarySelectionChangeOutcome(outcome)
    }

    func saveAndContinuePendingLibrarySelectionChange() {
        guard libraryFeatureStore.hasPendingSelectionChange() else {
            return
        }
        libraryFeatureStore.saveLibrarySampleEdits()
        guard libraryFeatureStore.librarySampleEditError == nil else {
            return
        }
        if let outcome = libraryFeatureStore.applyPendingSelectionChangeIfNeeded() {
            handleLibrarySelectionChangeOutcome(outcome)
        }
    }

    func discardAndContinuePendingLibrarySelectionChange() {
        guard libraryFeatureStore.hasPendingSelectionChange() else {
            return
        }
        libraryFeatureStore.discardEditingSelectedLibrarySample()
        if let outcome = libraryFeatureStore.applyPendingSelectionChangeIfNeeded() {
            handleLibrarySelectionChangeOutcome(outcome)
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

    func commitLibraryMutation(
        rootURL: URL,
        previewIndex: LibraryIndex?,
        precomputedDiff: LibraryDiff? = nil,
        precomputedReview: LibraryRefreshReview? = nil
    ) {
        let outcome = libraryMutationService.commitMutation(
            rootURL: rootURL,
            previewIndex: previewIndex,
            precomputedDiff: precomputedDiff,
            precomputedReview: precomputedReview,
            librarySyncService: libraryFeatureStore.librarySyncService
        )
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

    private func handleLibrarySelectionChangeOutcome(_ outcome: LibraryFeatureStore.SelectionChangeOutcome) {
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
