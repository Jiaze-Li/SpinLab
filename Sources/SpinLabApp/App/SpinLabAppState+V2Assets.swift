import Foundation

extension SpinLabAppState {
    var isV2LibraryLayout: Bool {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath, !rootPath.isEmpty else {
            return false
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        if case .v2 = LibraryLayoutRouter.resolve(rootURL: rootURL) {
            return true
        }
        return false
    }

    var v2LibraryRootURL: URL? {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath, !rootPath.isEmpty else {
            return nil
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        if case .v2 = LibraryLayoutRouter.resolve(rootURL: rootURL) {
            return rootURL
        }
        return nil
    }

    var v2ActiveSamplesByBatch: [(batchId: String, samples: [LibrarySample])] {
        let allSamples: [LibrarySample] = libraryFeatureStore.libraryExistingGroups.values
            .flatMap { $0 }
            .flatMap(\.samples)
        let active = allSamples.filter { sample in
            !sample.isTrashed && SampleIdentityRule.isValidUID(sample.sampleUID ?? sample.id)
        }
        let grouped = Dictionary(grouping: active, by: \.batchId)
        return grouped.keys.sorted().map { batchId in
            let sortedSamples = (grouped[batchId] ?? []).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return (batchId: batchId, samples: sortedSamples)
        }
    }

    func findExistingV2Sources(forFilePath path: String, ownedBySampleUID sampleUID: String) -> [AssetRecord] {
        guard let rootURL = v2LibraryRootURL else { return [] }
        let fileURL = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let sha = AssetHashing.sha256Hex(data)
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return (try? service.findSources(sha256: sha, ownedBySampleUID: sampleUID, rootURL: rootURL)) ?? []
    }

    func loadV2SourceGroups(for sample: LibrarySample) -> Result<[SampleSourceGroup], Error> {
        guard let rootURL = v2LibraryRootURL else { return .success([]) }
        let uid = sample.sampleUID ?? sample.id
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.listSampleSourceGroups(forSampleUID: uid, rootURL: rootURL)
        }
    }

    /// Honest per-Source status (stored / standardized / refused and why) for the Sample asset list.
    func loadV2SourceStatuses(for sample: LibrarySample) -> [String: SourceStatusSummary] {
        guard let rootURL = v2LibraryRootURL else { return [:] }
        let uid = sample.sampleUID ?? sample.id
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        let summaries = (try? service.sourceStatusSummaries(forSampleUID: uid, rootURL: rootURL)) ?? []
        return Dictionary(summaries.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// "Standardize again" for a stored Source: runs only the standardize step from the Library copy.
    func restandardizeV2Source(sourceID: String, sample: LibrarySample) -> Result<StandardizationResult, Error> {
        guard let rootURL = v2LibraryRootURL else { return .failure(LibraryAssetError.v2Required) }
        let uid = sample.sampleUID ?? sample.id
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            guard let record = try service.listAssets(forSampleUID: uid, rootURL: rootURL).first(where: { $0.id == sourceID }) else {
                throw LibraryAssetError.assetNotFound(sourceID)
            }
            let context = try service.sourceContext(sourceID: sourceID, rootURL: rootURL)
            let confirmed = (context?.workflowOrigin.isConfirmed == true) ? context?.workflowID : nil
            let coordinator = V2SourceStandardizationCoordinator(service: service, rootURL: rootURL)
            let outcome = try coordinator.standardize(
                sourceID: sourceID, sampleUID: uid, operationID: "restd-\(UUID().uuidString)",
                fileName: record.originalFilename ?? "", confirmedWorkflowID: confirmed,
                autoPlotIntent: coordinator.currentAutoPlotIntent(workflowID: confirmed)
            )
            if let trigger = outcome.autoPlotTrigger {
                afmAutoPlotRunner.enqueue(triggers: [trigger], libraryStore: libraryFeatureStore.libraryStore)
            }
            return outcome.result
        }
    }

    /// Audited supplement of unknown workflow / channels (user decision P4).
    func amendV2SourceContext(sourceID: String, changes: SourceContextAmendment) -> Result<SourceAmendmentReceipt, Error> {
        guard let rootURL = v2LibraryRootURL else { return .failure(LibraryAssetError.v2Required) }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.amendSourceContext(
                sourceID: sourceID, operationID: "amend-\(UUID().uuidString)", changes: changes, rootURL: rootURL
            )
        }
    }

    func loadV2SourceContext(sourceID: String) -> (context: SourceContextRecord?, channels: [EffectiveChannel]?) {
        guard let rootURL = v2LibraryRootURL else { return (nil, nil) }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return ((try? service.sourceContext(sourceID: sourceID, rootURL: rootURL)) ?? nil,
                (try? service.effectiveChannels(sourceID: sourceID, rootURL: rootURL)) ?? nil)
    }

    func loadV2Assets(for sample: LibrarySample) -> Result<[AssetRecord], Error> {
        guard let rootURL = v2LibraryRootURL else { return .success([]) }
        let uid = sample.sampleUID ?? sample.id
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.listAssets(forSampleUID: uid, rootURL: rootURL)
        }
    }

    func loadV2AFMDataset(datasetID: String) -> Result<LoadedDataset<CanonicalAFMDataset>, Error> {
        guard let rootURL = v2LibraryRootURL else {
            return .failure(LibraryAssetError.v2Required)
        }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.loadDataset(datasetID: datasetID, codec: AFMDatasetCodec(), rootURL: rootURL)
        }
    }

    func planV2AssetDeletion(target: LibraryAssetService.AssetDeletionTarget) -> Result<PermanentDeletionPlan, Error> {
        guard let rootURL = v2LibraryRootURL else {
            return .failure(LibraryAssetError.v2Required)
        }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.planAssetDeletion(target: target, rootURL: rootURL)
        }
    }

    @discardableResult
    func commitV2AssetDeletion(
        target: LibraryAssetService.AssetDeletionTarget,
        plan: PermanentDeletionPlan,
        operationPrefix: String
    ) -> Result<PermanentDeletionResult, Error> {
        guard let rootURL = v2LibraryRootURL else {
            return .failure(LibraryAssetError.v2Required)
        }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.commitAssetDeletion(
                target: target,
                plan: plan,
                operationID: "\(operationPrefix)-\(UUID().uuidString)",
                rootURL: rootURL
            )
        }
    }

    func planV2PermanentSampleDeletion(samples: [LibrarySample]) -> Result<PermanentDeletionPlan, Error> {
        guard let rootURL = v2LibraryRootURL else {
            return .failure(LibraryAssetError.v2Required)
        }
        let uids = samples.map { $0.sampleUID ?? $0.id }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.planPermanentSampleDeletion(sampleUIDs: uids, rootURL: rootURL)
        }
    }

    @discardableResult
    func commitV2PermanentSampleDeletion(
        plan: PermanentDeletionPlan,
        operationPrefix: String,
        successMessage: (PermanentDeletionResult) -> String
    ) -> Bool {
        libraryFeatureStore.libraryDrawerError = nil
        libraryFeatureStore.libraryDrawerMessage = nil
        guard let rootURL = v2LibraryRootURL else {
            libraryFeatureStore.libraryDrawerError = LibraryAssetError.v2Required.localizedDescription
            return false
        }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        do {
            let result = try service.commitPermanentSampleDeletion(
                plan: plan,
                operationID: "\(operationPrefix)-\(UUID().uuidString)",
                rootURL: rootURL
            )
            if let synced = libraryFeatureStore.libraryStore.loadIndex(from: rootURL) {
                applyExistingIndex(synced)
            }
            libraryFeatureStore.libraryDrawerMessage = successMessage(result)
            return true
        } catch {
            libraryFeatureStore.libraryDrawerError = error.localizedDescription
            return false
        }
    }

    func isValidActiveV2TargetSampleUID(_ uid: String?) -> Bool {
        let trimmed = uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        return v2ActiveSamplesByBatch.contains { group in
            group.samples.contains { ($0.sampleUID ?? $0.id) == trimmed }
        }
    }

    func hasAnyV2ReadyPendingImports() -> Bool {
        let workspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        return inboxFeatureStore.pendingImports.contains { pending in
            let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
            return InboxArchiveApplyService.canApplyV2(
                draft: workspaceByPendingID[key]?.draft, isValidActiveSample: { isValidActiveV2TargetSampleUID($0) }
            )
        }
    }

    /// After an apply attempt: remember which targets are stored / finished so the draft locks them
    /// and a retry only repeats what is still open. Nothing here changes the Library.
    func recordV2TargetResults(pendingID: UUID, results: [V2TargetApplyResult]) {
        let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pendingID)
        guard var state = interactionValue(\.inboxWorkspaceByPendingID)[key] else { return }
        for result in results {
            guard let index = state.draft.v2Targets.firstIndex(where: { $0.sampleUID == result.sampleUID }) else { continue }
            if let sourceID = result.sourceID { state.draft.v2Targets[index].ingestedSourceID = sourceID }
            if result.isFinished { state.draft.v2Targets[index].standardizationFinished = true }
        }
        updateInteractionEntryValue(for: pendingID, in: \.inboxWorkspaceByPendingID, value: state, source: "v2TargetProgress")
    }
}
