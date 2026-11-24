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

    func findExistingV2Sources(forFilePath path: String) -> [AssetRecord] {
        guard let rootURL = v2LibraryRootURL else { return [] }
        let fileURL = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let sha = AssetHashing.sha256Hex(data)
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return (try? service.findSources(sha256: sha, rootURL: rootURL)) ?? []
    }

    func loadV2Assets(for sample: LibrarySample) -> Result<[AssetRecord], Error> {
        guard let rootURL = v2LibraryRootURL else { return .success([]) }
        let uid = sample.sampleUID ?? sample.id
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.listAssets(forSampleUID: uid, rootURL: rootURL)
        }
    }

    func loadV2LinkedSampleUIDs(forAssetID assetID: String) -> Result<[String], Error> {
        guard let rootURL = v2LibraryRootURL else { return .success([]) }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.linkedSampleUIDs(assetID: assetID, rootURL: rootURL)
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

    @discardableResult
    func linkV2Asset(assetID: String, toSampleUID uid: String) -> Result<Void, Error> {
        guard let rootURL = v2LibraryRootURL else {
            return .failure(LibraryAssetError.v2Required)
        }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.linkAsset(assetID: assetID, toSampleUID: uid, rootURL: rootURL)
        }
    }

    @discardableResult
    func unlinkV2Asset(assetID: String, fromSampleUID uid: String) -> Result<Void, Error> {
        guard let rootURL = v2LibraryRootURL else {
            return .failure(LibraryAssetError.v2Required)
        }
        let service = LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
        return Result {
            try service.unlinkAsset(assetID: assetID, fromSampleUID: uid, rootURL: rootURL)
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

    func hasAnyV2ReadyPendingImports() -> Bool {
        let workspaceByPendingID = interactionValue(\.inboxWorkspaceByPendingID)
        return inboxFeatureStore.pendingImports.contains { pending in
            let key = InteractionSnapshotKeyCodec.dictionaryKey(for: pending.id)
            guard let draft = workspaceByPendingID[key]?.draft,
                  !draft.v2TargetSampleUIDs.isEmpty,
                  InboxArchiveApplyService.standardizationAdapter(forWorkflowID: draft.workflowID) != nil else {
                return false
            }
            return true
        }
    }
}
