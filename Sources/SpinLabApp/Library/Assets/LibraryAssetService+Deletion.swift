import CryptoKit
import Foundation

// MARK: - Permanent sample deletion with reference closure, and crash recovery

extension LibraryAssetService {
    struct DeleteAssetEntry: Codable {
        var id: String
        /// Directory that holds the registered files (empty for relation-only assets).
        var dirRel: String
        /// The asset's own top-level directory, removed only when empty.
        var assetDirRel: String
        var files: [String]
    }

    struct DeleteOpPayload: Codable {
        var sampleUID: String
        var sampleUIDs: [String]?
        var assets: [DeleteAssetEntry]
        var retained: [String]
        var stale: [String]
        var result: PermanentDeletionResult?

        var resolvedSampleUIDs: [String] {
            if let sampleUIDs, !sampleUIDs.isEmpty { return sampleUIDs }
            return sampleUID.isEmpty ? [] : [sampleUID]
        }
    }

    // MARK: Plan

    func planPermanentSampleDeletion(sampleUID: String, rootURL: URL) throws -> PermanentDeletionPlan {
        let batch = try planPermanentSamplesDeletion(sampleUIDs: [sampleUID], rootURL: rootURL)
        return PermanentDeletionPlan(
            sampleUID: sampleUID,
            assetsToDelete: batch.assetsToDelete,
            retainedAssets: batch.retainedAssets,
            deleteFileCount: batch.deleteFileCount,
            retainedFileCount: batch.retainedFileCount,
            staleLiveAssetIDs: batch.staleLiveAssetIDs,
            fingerprint: batch.fingerprint
        )
    }

    func planPermanentSamplesDeletion(sampleUIDs: [String], rootURL: URL) throws -> BatchPermanentDeletionPlan {
        try requireV2(rootURL)
        let uids = Array(Set(sampleUIDs)).sorted()
        guard !uids.isEmpty else { throw LibraryAssetError.invalidSample("no target sample selected") }
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        for uid in uids {
            try requireTrashed(uid, rootURL: rootURL)
        }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return Self.emptyBatchPlan(sampleUIDs: uids)
        }
        let pending = try db.query("SELECT COUNT(*) AS n FROM asset_operations WHERE state = 'pending';").first?.int("n") ?? 0
        if pending > 0 { throw LibraryAssetError.pendingOperations(Int(pending)) }
        return try computeBatchPlan(db: db, sampleUIDs: uids)
    }

    private static func emptyBatchPlan(sampleUIDs: [String]) -> BatchPermanentDeletionPlan {
        BatchPermanentDeletionPlan(
            sampleUIDs: sampleUIDs, assetsToDelete: [], retainedAssets: [], deleteFileCount: 0, retainedFileCount: 0,
            staleLiveAssetIDs: [], fingerprint: AssetHashing.sha256Hex(Data("empty|\(sampleUIDs.joined(separator: ","))".utf8))
        )
    }

    func requireTrashed(_ uid: String, rootURL: URL) throws {
        let sampleJSON = libraryStore.v2SampleDirectoryURL(rootURL, sampleUID: uid).appending(path: "sample.json")
        guard fileManager.fileExists(atPath: sampleJSON.path), let sample = libraryStore.decodeSample(from: sampleJSON) else {
            throw LibraryAssetError.invalidSample("sample '\(uid)' record is missing or unreadable")
        }
        guard sample.isTrashed else { throw LibraryAssetError.sampleNotTrashed(uid) }
    }

    func computePlan(db: LibraryAssetDatabase, sampleUID: String) throws -> PermanentDeletionPlan {
        let batch = try computeBatchPlan(db: db, sampleUIDs: [sampleUID])
        return PermanentDeletionPlan(
            sampleUID: sampleUID,
            assetsToDelete: batch.assetsToDelete,
            retainedAssets: batch.retainedAssets,
            deleteFileCount: batch.deleteFileCount,
            retainedFileCount: batch.retainedFileCount,
            staleLiveAssetIDs: batch.staleLiveAssetIDs,
            fingerprint: batch.fingerprint
        )
    }

    /// Reference closure across a whole batch of samples being deleted together: starts from
    /// their assets (plus unlinked upstreams) and iterates to a fixed point, keeping anything
    /// another non-deleting sample or another live object still uses.
    func computeBatchPlan(db: LibraryAssetDatabase, sampleUIDs: [String]) throws -> BatchPermanentDeletionPlan {
        let uids = Array(Set(sampleUIDs)).sorted()
        let deletingUIDs = Set(uids)

        let links = try db.query("SELECT sample_uid, asset_id FROM sample_asset_links;")
            .compactMap { row -> (String, String)? in
                guard let sample = row.string("sample_uid"), let asset = row.string("asset_id") else { return nil }
                return (sample, asset)
            }
        let deps = try db.query("SELECT consumer_asset_id, upstream_asset_id, dependency_kind FROM asset_dependencies;")
            .compactMap { row -> (consumer: String, upstream: String, kind: String)? in
                guard let c = row.string("consumer_asset_id"), let u = row.string("upstream_asset_id"),
                      let k = row.string("dependency_kind") else { return nil }
                return (c, u, k)
            }
        var assets: [String: AssetRecord] = [:]
        for row in try db.query("SELECT * FROM assets;") {
            let record = try AssetRecord(row: row)
            assets[record.id] = record
        }

        let owned = Set(links.filter { deletingUIDs.contains($0.0) }.map { $0.1 })
        var candidates = owned
        var frontier = Array(owned)
        while let current = frontier.popLast() {
            for dep in deps where dep.consumer == current && !candidates.contains(dep.upstream) {
                let usedOutsideBatch = links.contains { $0.1 == dep.upstream && !deletingUIDs.contains($0.0) }
                if !usedOutsideBatch, assets[dep.upstream] != nil {
                    candidates.insert(dep.upstream)
                    frontier.append(dep.upstream)
                }
            }
        }

        var deleting = candidates
        var retained = Set<String>()
        var changed = true
        while changed {
            changed = false
            for asset in deleting.sorted() {
                let usedByOutsideSample = links.contains { $0.1 == asset && !deletingUIDs.contains($0.0) }
                let usedByLiveConsumer = deps.contains { $0.upstream == asset && !deleting.contains($0.consumer) }
                if usedByOutsideSample || usedByLiveConsumer {
                    deleting.remove(asset)
                    retained.insert(asset)
                    changed = true
                }
            }
        }

        let stale = retained.intersection(owned).filter { assets[$0]?.liveState != nil }.sorted()
        let deleteCount = deleting.reduce(0) { $0 + (assets[$1]?.files.count ?? 0) }
        let retainedCount = retained.reduce(0) { $0 + (assets[$1]?.files.count ?? 0) }

        let involved = candidates
        var lines: [String] = uids.map { "sample|\($0)" }
        for link in links where involved.contains(link.1) || deletingUIDs.contains(link.0) { lines.append("L|\(link.0)|\(link.1)") }
        for dep in deps where involved.contains(dep.consumer) || involved.contains(dep.upstream) {
            lines.append("D|\(dep.consumer)|\(dep.upstream)|\(dep.kind)")
        }
        for id in involved {
            if let record = assets[id] { lines.append("A|\(id)|\(record.status)|\(record.currentRevision)|\(record.liveState ?? "-")") }
        }
        let fingerprint = AssetHashing.sha256Hex(Data(lines.sorted().joined(separator: "\n").utf8))

        return BatchPermanentDeletionPlan(
            sampleUIDs: uids, assetsToDelete: deleting.sorted(), retainedAssets: retained.sorted(),
            deleteFileCount: deleteCount, retainedFileCount: retainedCount, staleLiveAssetIDs: stale,
            fingerprint: fingerprint
        )
    }

    // MARK: Commit

    func commitPermanentSampleDeletion(
        plan: PermanentDeletionPlan, operationID: String, rootURL: URL
    ) throws -> PermanentDeletionResult {
        let batchPlan = BatchPermanentDeletionPlan(
            sampleUIDs: [plan.sampleUID],
            assetsToDelete: plan.assetsToDelete,
            retainedAssets: plan.retainedAssets,
            deleteFileCount: plan.deleteFileCount,
            retainedFileCount: plan.retainedFileCount,
            staleLiveAssetIDs: plan.staleLiveAssetIDs,
            fingerprint: plan.fingerprint
        )
        let batchResult = try commitPermanentSamplesDeletion(plan: batchPlan, operationID: operationID, rootURL: rootURL)
        return PermanentDeletionResult(
            sampleUID: plan.sampleUID,
            deletedAssetIDs: batchResult.deletedAssetIDs,
            retainedAssetIDs: batchResult.retainedAssetIDs
        )
    }

    func commitPermanentSamplesDeletion(
        plan: BatchPermanentDeletionPlan, operationID: String, rootURL: URL
    ) throws -> BatchPermanentDeletionResult {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        try validateOperationID(operationID)
        let uids = Array(Set(plan.sampleUIDs)).sorted()
        guard !uids.isEmpty else { throw LibraryAssetError.invalidSample("no target sample selected") }
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }

        let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager)
        if let db {
            _ = try recoverPending(db: db, rootURL: rootURL)
            if let existing = try operation(db, id: operationID) {
                guard existing.type == "delete_sample" else { throw LibraryAssetError.operationKindMismatch(operationID) }
                if existing.state == "committed", let result = try decodeJSON(DeleteOpPayload.self, existing.payload).result {
                    return BatchPermanentDeletionResult(
                        sampleUIDs: uids,
                        deletedAssetIDs: result.deletedAssetIDs,
                        retainedAssetIDs: result.retainedAssetIDs
                    )
                }
            }
        }
        for uid in uids {
            try requireTrashed(uid, rootURL: rootURL)
        }

        guard let db else {
            // The asset library was never enabled: there is nothing registered, only the records to remove.
            guard plan.assetsToDelete.isEmpty, plan.retainedAssets.isEmpty else { throw LibraryAssetError.planChanged }
            try removeSampleRecords(sampleUIDs: uids, rootURL: rootURL)
            return BatchPermanentDeletionResult(sampleUIDs: uids, deletedAssetIDs: [], retainedAssetIDs: [])
        }

        var payload = DeleteOpPayload(
            sampleUID: uids.first ?? "", sampleUIDs: uids, assets: [], retained: [], stale: [], result: nil
        )

        // Transaction 1: re-verify the confirmed plan, then persist the intent and the new state.
        try db.transaction {
            let fresh = try computeBatchPlan(db: db, sampleUIDs: uids)
            guard fresh.fingerprint == plan.fingerprint, fresh.assetsToDelete == plan.assetsToDelete else {
                throw LibraryAssetError.planChanged
            }
            for id in fresh.assetsToDelete {
                guard let record = try assetRecord(db, id: id) else { throw LibraryAssetError.planChanged }
                let components = record.storageRelPath.split(separator: "/").map(String.init)
                let assetDir = components.count >= 2 ? components[0] + "/" + components[1] : ""
                payload.assets.append(DeleteAssetEntry(
                    id: id, dirRel: record.files.isEmpty ? "" : record.storageRelPath,
                    assetDirRel: record.files.isEmpty ? "" : assetDir, files: record.files.map(\.name)
                ))
            }
            payload.retained = fresh.retainedAssets
            payload.stale = fresh.staleLiveAssetIDs
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try insertOperation(db, id: operationID, type: "delete_sample", state: "pending", payload: try encodeJSON(payload))
            let now = Self.timestamp()
            let marks = Array(repeating: "?", count: uids.count).joined(separator: ",")
            try db.execute("DELETE FROM sample_asset_links WHERE sample_uid IN (\(marks));", uids.map { .text($0) })
            for id in fresh.staleLiveAssetIDs {
                try db.execute("UPDATE assets SET live_state = 'stale', updated_at = ? WHERE asset_id = ?;", [.text(now), .text(id)])
            }
            for id in fresh.assetsToDelete {
                try db.execute("UPDATE assets SET status = 'deleting', updated_at = ? WHERE asset_id = ?;", [.text(now), .text(id)])
            }
        }
        try fault(.deleteAfterPendingCommit)
        payload.result = PermanentDeletionResult(
            sampleUID: payload.sampleUID, deletedAssetIDs: payload.assets.map(\.id), retainedAssetIDs: payload.retained
        )
        let singleResult = try finishDeletion(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
        return BatchPermanentDeletionResult(
            sampleUIDs: uids,
            deletedAssetIDs: singleResult.deletedAssetIDs,
            retainedAssetIDs: singleResult.retainedAssetIDs
        )
    }

    /// Steps after the pending commit; idempotent so recovery can run them again.
    func finishDeletion(
        db: LibraryAssetDatabase, operationID: String, payload: DeleteOpPayload, rootURL: URL
    ) throws -> PermanentDeletionResult {
        try removeSampleRecords(sampleUIDs: payload.resolvedSampleUIDs, rootURL: rootURL)
        try fault(.deleteAfterSampleRemoved)

        var report = AssetRecoveryReport()
        var fileIndex = 0
        for entry in payload.assets where !entry.dirRel.isEmpty {
            for name in entry.files {
                try removeRegisteredFiles(
                    rootURL: rootURL, relativeDirectory: entry.dirRel, names: [name], removeWriterTemps: false,
                    emptyDirectoryCandidates: [], report: &report
                )
                fileIndex += 1
                try fault(.deleteAfterFile(fileIndex))
            }
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: entry.dirRel, names: [], removeWriterTemps: false,
                emptyDirectoryCandidates: [entry.dirRel, entry.assetDirRel].filter { !$0.isEmpty }, report: &report
            )
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)

        let result = payload.result ?? PermanentDeletionResult(
            sampleUID: payload.sampleUID, deletedAssetIDs: payload.assets.map(\.id), retainedAssetIDs: payload.retained
        )
        var done = payload
        done.result = result
        let ids = payload.assets.map(\.id)
        try db.transaction {
            if !ids.isEmpty {
                let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
                let params = ids.map { SQLValue.text($0) }
                try db.execute("DELETE FROM asset_dependencies WHERE consumer_asset_id IN (\(marks)) OR upstream_asset_id IN (\(marks));", params + params)
                try db.execute("DELETE FROM sample_asset_links WHERE asset_id IN (\(marks));", params)
                try db.execute("DELETE FROM assets WHERE asset_id IN (\(marks)) AND status = 'deleting';", params)
            }
            try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(done))
        }
        return result
    }

    /// Removes `records/samples/<uid>/` (strictly contained) and rebuilds the index.
    func removeSampleRecord(sampleUID: String, rootURL: URL) throws {
        try removeSampleRecords(sampleUIDs: [sampleUID], rootURL: rootURL)
    }

    func removeSampleRecords(sampleUIDs: [String], rootURL: URL) throws {
        let samplesRoot = libraryStore.v2SamplesDirectoryURL(rootURL)
        let rootPath = samplesRoot.resolvingSymlinksInPath().standardizedFileURL.path
        for sampleUID in sampleUIDs {
            guard SampleIdentityRule.isValidUID(sampleUID) else { throw LibraryAssetError.unsafePath(sampleUID) }
            let sampleURL = libraryStore.v2SampleDirectoryURL(rootURL, sampleUID: sampleUID)
            let samplePath = sampleURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard samplePath.hasPrefix(rootPath + "/") else { throw LibraryAssetError.unsafePath(sampleURL.path) }
            if fileManager.fileExists(atPath: sampleURL.path) {
                do { try fileManager.removeItem(at: sampleURL) } catch {
                    throw LibraryAssetError.cleanupFailed("sample record: \(error.localizedDescription)")
                }
            }
            libraryStore.invalidateNodeCache(at: sampleURL)
        }
        libraryStore.invalidateNodeCache(at: samplesRoot)
        libraryStore.invalidateNodeCache(at: libraryStore.recordsDirectoryURL(rootURL))
        do {
            _ = try libraryStore.syncIndexFromFilesystem(rootURL: rootURL)
        } catch {
            throw LibraryAssetError.cleanupFailed("index rebuild: \(error.localizedDescription)")
        }
    }

    // MARK: Recovery

    /// Completes or rolls back every unfinished operation. Call when a writable V2 library is opened.
    @discardableResult
    func recoverPendingOperations(rootURL: URL) throws -> AssetRecoveryReport {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return AssetRecoveryReport()
        }
        return try recoverPending(db: db, rootURL: rootURL)
    }

    @discardableResult
    func recoverPending(db: LibraryAssetDatabase, rootURL: URL) throws -> AssetRecoveryReport {
        var report = AssetRecoveryReport()
        lastRecoveryReport = AssetRecoveryReport()

        let pending = try db.query(
            "SELECT operation_id, op_type, state, payload_json FROM asset_operations WHERE state = 'pending' ORDER BY created_at, operation_id;"
        )
        for row in pending {
            guard let id = row.string("operation_id"), let type = row.string("op_type"),
                  let payloadText = row.string("payload_json") else { continue }
            switch type {
            case "ingest":
                try abortIngest(db: db, operationID: id, payload: decodeJSON(IngestOpPayload.self, payloadText), rootURL: rootURL)
                report.abortedOperations.append(id)
            case "revise":
                try abortRevise(db: db, operationID: id, payload: decodeJSON(ReviseOpPayload.self, payloadText), rootURL: rootURL)
                report.abortedOperations.append(id)
            case "delete_sample":
                _ = try finishDeletion(db: db, operationID: id, payload: decodeJSON(DeleteOpPayload.self, payloadText), rootURL: rootURL)
                report.recoveredOperations.append(id)
            default:
                throw LibraryAssetError.databaseCorrupt("unknown operation type '\(type)'")
            }
        }

        let uncleaned = try db.query(
            "SELECT operation_id, payload_json FROM asset_operations WHERE op_type = 'revise' AND state = 'committed' AND payload_json LIKE '%\"cleanupPending\":true%';"
        )
        for row in uncleaned {
            guard let id = row.string("operation_id"), let payloadText = row.string("payload_json") else { continue }
            try finishRevisionCleanup(db: db, operationID: id, payload: decodeJSON(ReviseOpPayload.self, payloadText), rootURL: rootURL)
            report.recoveredOperations.append(id)
        }

        report.unknownResidue.append(contentsOf: lastRecoveryReport.unknownResidue)
        lastRecoveryReport = report
        return report
    }

    func abortIngest(db: LibraryAssetDatabase, operationID: String, payload: IngestOpPayload, rootURL: URL) throws {
        var report = AssetRecoveryReport()
        if !payload.reusedSource {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: payload.sourceRelPath, names: payload.sourceFiles.map(\.name),
                removeWriterTemps: true, emptyDirectoryCandidates: [payload.sourceRelPath], report: &report
            )
        }
        try removeRegisteredFiles(
            rootURL: rootURL, relativeDirectory: payload.datasetRelPath, names: payload.datasetFiles.map(\.name),
            removeWriterTemps: true,
            emptyDirectoryCandidates: [payload.datasetRelPath, "storage/\(payload.datasetID)"], report: &report
        )
        try db.transaction {
            var ids = [payload.datasetID]
            if !payload.reusedSource { ids.append(payload.sourceID) }
            for id in ids {
                try db.execute("DELETE FROM assets WHERE asset_id = ? AND status = 'staging';", [.text(id)])
            }
            try updateOperation(db, id: operationID, state: "aborted", payload: try encodeJSON(payload))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }
}
