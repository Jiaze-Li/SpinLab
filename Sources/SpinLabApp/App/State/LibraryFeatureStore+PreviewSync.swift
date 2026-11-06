import Foundation

@MainActor extension LibraryFeatureStore {

    func applySyncChangeIndicators(_ indicators: LibrarySyncChangeIndicators) {
        libraryBatchSyncStatusByID = indicators.batchStatusByID
        librarySampleSyncChangesByID = indicators.sampleChangesByID
        libraryBatchSyncChangesByID = indicators.batchChangesByID
    }

    func refreshSyncChangeIndicators(using mutationService: LibraryMutationService) {
        applySyncChangeIndicators(
            mutationService.makeSyncChangeIndicators(review: libraryRefreshReview)
        )
    }

    func prepareLibrarySyncReview(
        mutationService: LibraryMutationService,
        precomputedDiff: LibraryDiff? = nil
    ) -> (diff: LibraryDiff, baselineIndex: LibraryIndex)? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        let result = mutationService.prepareSyncReview(
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            precomputedDiff: precomputedDiff,
            librarySyncService: librarySyncService
        )

        switch result {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(review, diff, baselineIndex, message, indicators):
            libraryRefreshReview = review
            applySyncChangeIndicators(indicators)
            libraryDrawerMessage = message
            return (diff: diff, baselineIndex: baselineIndex)
        }
    }

    func refreshLibraryIncremental(
        mutationService: LibraryMutationService
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.refreshIncremental(
            librarySyncService: librarySyncService,
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            settings: librarySettings
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        case let .partial(rootURL, previewIndex, message):
            libraryDrawerError = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func confirmLibraryNumericRefreshChanges(
        mutationService: LibraryMutationService
    ) -> Bool {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.confirmNumericRefreshChanges(
            review: libraryRefreshReview,
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            settings: librarySettings,
            libraryStore: libraryStore
        ) {
        case let .failure(message):
            if message == "No numeric changes pending confirmation." {
                libraryDrawerMessage = message
            } else {
                libraryDrawerError = message
            }
            return false
        case let .success(updatedReview, appliedCount, lastRefreshAt):
            librarySettings.lastRefreshAt = lastRefreshAt
            librarySettingsStore.save(librarySettings)
            libraryRefreshReview = updatedReview
            libraryDrawerMessage = "Confirmed and applied \(appliedCount) numeric changes."
            refreshSyncChangeIndicators(using: mutationService)
            return true
        }
    }

    func createDrawersFromPreview(
        mutationService: LibraryMutationService
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.createDrawersFromPreview(
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            libraryStore: libraryStore,
            settings: librarySettings
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, _, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        case let .partial(rootURL, previewIndex, _, message):
            libraryDrawerError = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func createDrawersForSelection(
        mutationService: LibraryMutationService,
        batchId: String?,
        sampleId: String?
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.createDrawersForSelection(
            preview: libraryPreview,
            rootPath: librarySettings.rootPath,
            batchId: batchId,
            sampleId: sampleId,
            libraryStore: libraryStore,
            settings: librarySettings
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, _, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        case let .partial(rootURL, previewIndex, _, message):
            libraryDrawerError = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func deleteExistingDrawer(
        mutationService: LibraryMutationService,
        batchId: String
    ) -> MutationCommitContext? {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        switch mutationService.deleteExistingDrawer(
            batchId: batchId,
            rootPath: librarySettings.rootPath,
            previewIndex: libraryPreview?.index,
            libraryStore: libraryStore
        ) {
        case let .failure(message):
            libraryDrawerError = message
            return nil
        case let .success(rootURL, previewIndex, message):
            libraryDrawerMessage = message
            return MutationCommitContext(rootURL: rootURL, previewIndex: previewIndex)
        }
    }

    func applySelectedRegistryDiff(batchId: String?) -> ApplySelectedRegistryDiffOutcome {
        libraryDrawerError = nil
        libraryDrawerMessage = nil

        guard let batchId else {
            let message = "Select a batch first."
            libraryDrawerError = message
            return .failure(message: message)
        }
        guard let preview = libraryPreview else {
            let message = "Load the registry preview first."
            libraryDrawerError = message
            return .failure(message: message)
        }
        guard let rootPath = librarySettings.rootPath else {
            let message = "Select a Library Root first."
            libraryDrawerError = message
            return .failure(message: message)
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        libraryStore.ensureRoot(at: rootURL)
        let applied: LibraryApplyBatchResult?
        do {
            applied = try librarySyncService.applyBatch(
                batchId: batchId,
                preview: preview,
                rootURL: rootURL,
                settings: librarySettings
            )
        } catch {
            let message = "Apply stopped: \(error.localizedDescription)"
            libraryDrawerError = message
            return .failure(message: message)
        }
        guard let applyResult = applied else {
            let message = "No pending sync changes for \(batchId)."
            libraryDrawerMessage = message
            return .noPendingChanges(batchId: batchId, message: message)
        }

        if applyResult.isPartial {
            var message = "PARTIAL: selected sync for \(batchId): \(applyResult.touchedSamples) change(s) applied, \(applyResult.failedSamples) failed"
            if let first = applyResult.failures.first { message += " (first: \(first))" }
            if let indexError = applyResult.indexError { message += "; the index may not match the files: \(indexError)" }
            message += ". Files were changed and nothing was rolled back; run Sync from files."
            libraryDrawerError = message
            return .success(
                rootURL: rootURL,
                previewIndex: preview.index,
                batchId: batchId,
                batchAction: applyResult.batchAction,
                touchedSamples: applyResult.touchedSamples,
                message: message
            )
        }
        let message = "Applied selected sync for \(batchId): \(applyResult.batchAction), \(applyResult.touchedSamples) sample changes."
        libraryDrawerMessage = message
        return .success(
            rootURL: rootURL,
            previewIndex: preview.index,
            batchId: batchId,
            batchAction: applyResult.batchAction,
            touchedSamples: applyResult.touchedSamples,
            message: message
        )
    }

    /// Read-only: scans the Library files without creating, migrating or
    /// rewriting anything. Returns nil when no usable Library Root exists.
    func loadExistingDrawersIndexForCurrentRoot() -> LibraryIndex? {
        guard let rootPath = librarySettings.rootPath else {
            libraryReadIssues = []
            return nil
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let scan = libraryStore.scanIndexFromFilesystem(rootURL: rootURL)
        guard scan.rootExists else {
            libraryReadIssues = []
            libraryRootVerificationMessage = "Library Root not found: \(rootPath). Nothing was created or changed."
            libraryRootVerificationPath = rootPath
            return nil
        }
        libraryReadIssues = scan.issues
        if !scan.issues.isEmpty {
            libraryRootVerificationMessage = "\(scan.issues.count) unreadable Library file(s) were skipped. Nothing was modified."
            libraryRootVerificationPath = rootPath
        }
        return scan.index
    }

    func syncLibraryFromFilesForCurrentRoot(offerRecovery: Bool = false) -> SyncLibraryFromFilesOutcome? {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return nil
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let previousIndex = libraryStore.loadIndex(from: rootURL)
        let checked = libraryStore.syncIndexFromFilesystemChecked(rootURL: rootURL)
        guard checked.persisted else {
            if offerRecovery, checked.recoverable {
                libraryReadIssues = checked.issues
                libraryIndexRecoveryRootPath = rootPath
                libraryRootVerificationMessage = "The saved index is damaged. Nothing was changed. Confirm recovery to rebuild it from the Library files."
                libraryRootVerificationPath = rootPath
                return nil
            }
            libraryReadIssues = checked.issues
            let shown = checked.issues.prefix(3).joined(separator: "; ")
            libraryRootVerificationMessage = "File sync stopped: \(checked.issues.count) item(s) could not be read (\(shown)). The saved index was not changed."
            libraryRootVerificationPath = rootPath
            return nil
        }
        libraryReadIssues = []
        let syncedIndex = checked.index

        let previousSamplesByID = Dictionary(uniqueKeysWithValues: (previousIndex?.samples ?? []).map { ($0.id, $0) })
        let syncedSamplesByID = Dictionary(uniqueKeysWithValues: syncedIndex.samples.map { ($0.id, $0) })
        let previousIDs = Set(previousSamplesByID.keys)
        let syncedIDs = Set(syncedSamplesByID.keys)
        let addedCount = syncedIDs.subtracting(previousIDs).count
        let removedCount = previousIDs.subtracting(syncedIDs).count
        let updatedCount = previousIDs.intersection(syncedIDs).reduce(into: 0) { partialResult, id in
            if previousSamplesByID[id] != syncedSamplesByID[id] {
                partialResult += 1
            }
        }

        return SyncLibraryFromFilesOutcome(
            rootPath: rootPath,
            syncedIndex: syncedIndex,
            summaryMessage: "File sync complete: \(syncedIndex.samples.count) samples (+\(addedCount) / -\(removedCount) / ~\(updatedCount))."
        )
    }

    /// Confirmed recovery of a damaged index (backup first, verify, then rebuild).
    func recoverLibraryIndexForCurrentRoot() -> SyncLibraryFromFilesOutcome? {
        libraryIndexRecoveryRootPath = nil
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return nil
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        do {
            let recovery = try libraryStore.recoverIndexFromFilesystem(rootURL: rootURL)
            libraryReadIssues = []
            return SyncLibraryFromFilesOutcome(
                rootPath: rootPath,
                syncedIndex: recovery.index,
                summaryMessage: "Index rebuilt from files: \(recovery.index.samples.count) samples. The damaged index was kept as \(recovery.backupURL.lastPathComponent). Index-only metadata could not be recovered."
            )
        } catch {
            libraryReadIssues = (error as? LibraryIndexSyncError)?.issues ?? [error.localizedDescription]
            libraryRootVerificationMessage = "Recovery stopped: \(error.localizedDescription)"
            libraryRootVerificationPath = rootPath
            return nil
        }
    }

    func backfillSidecarsForCurrentRoot() -> BackfillSidecarsOutcome? {
        guard let rootPath = librarySettings.rootPath else {
            libraryRootVerificationMessage = "No Library Root selected."
            return nil
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let result = librarySidecarService.recomputeAllMeasurementSidecars(rootURL: rootURL)
        appliedMeasurementsCacheBySampleID.removeAll()
        refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        let summary = """
        Sidecar recompute complete: scanned \(result.scannedSampleCount) samples, \
        \(result.scannedMeasurementFileCount) measurement files; created \(result.createdSidecarCount), \
        updated \(result.updatedSidecarCount), \
        skipped \(result.skippedExistingSidecarCount), failed \(result.failedSidecarCount).
        """
        return BackfillSidecarsOutcome(
            rootPath: rootPath,
            result: result,
            summaryMessage: summary
        )
    }

    func applyLoadedLibraryPreview(
        _ snapshot: LibraryPreviewParseSnapshot,
        refreshActionablePreviewGroups: () -> Void
    ) {
        let preview = LibraryPreview(index: snapshot.index, warnings: snapshot.warnings)
        libraryPreview = preview
        libraryPreviewWarnings = snapshot.warnings
        refreshActionablePreviewGroups()
        libraryLogger.write(snapshot.warnings)
    }

    func loadLibraryPreview(
        resolvedRegistryPath: String?,
        dataActor: any SpinLabDataActing,
        refreshActionablePreviewGroups: @escaping () -> Void,
        onFailure: @escaping (AppError) -> Void
    ) {
        guard let registryPath = resolvedRegistryPath else {
            libraryPreviewMessage = "No registry available. Load it from Library first."
            return
        }

        let settings = librarySettings
        Task {
            do {
                let snapshot = try await dataActor.parseLibraryPreview(registryPath: registryPath, settings: settings)
                await MainActor.run {
                    self.applyLoadedLibraryPreview(snapshot, refreshActionablePreviewGroups: refreshActionablePreviewGroups)
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to load registry preview.")
                    self.libraryPreview = nil
                    self.libraryPreviewWarnings = []
                    self.libraryPreviewMessage = appError.localizedDescription
                    onFailure(appError)
                }
            }
        }
    }

    func syncLibraryFromRegistry(
        resolvedRegistryPath: String?,
        dataActor: any SpinLabDataActing,
        prepareLibrarySyncReview: @escaping () -> Void,
        refreshActionablePreviewGroups: @escaping () -> Void,
        formatSyncDate: @escaping (Date) -> String,
        onFailure: @escaping (AppError) -> Void,
        onComplete: (() -> Void)?
    ) {
        guard let registryPath = resolvedRegistryPath else {
            libraryPreviewMessage = "No registry available. Load it from Library first."
            librarySyncStatusMessage = nil
            onComplete?()
            return
        }

        let settings = librarySettings
        Task {
            do {
                let snapshot = try await dataActor.parseLibraryPreview(registryPath: registryPath, settings: settings)
                await MainActor.run {
                    self.applyLoadedLibraryPreview(snapshot, refreshActionablePreviewGroups: refreshActionablePreviewGroups)
                    guard self.libraryPreview != nil else {
                        self.librarySyncStatusMessage = nil
                        onComplete?()
                        return
                    }
                    prepareLibrarySyncReview()
                    self.libraryLastSyncedAt = Date()
                    if let syncedAt = self.libraryLastSyncedAt {
                        self.librarySyncStatusMessage = "Registry diff prepared at \(formatSyncDate(syncedAt)); waiting for manual apply."
                    }
                    onComplete?()
                }
            } catch {
                await MainActor.run {
                    let appError = AppError.from(error, fallback: "Failed to prepare library sync preview.")
                    self.librarySyncStatusMessage = nil
                    self.libraryPreview = nil
                    self.libraryPreviewWarnings = []
                    self.libraryPreviewMessage = appError.localizedDescription
                    onFailure(appError)
                    onComplete?()
                }
            }
        }
    }
}
