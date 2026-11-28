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
        var sampleUIDs: [String]
        var assets: [DeleteAssetEntry]
        var retained: [String]
        var stale: [String]
        var result: PermanentDeletionResult?
    }

    // MARK: Plan

    func planPermanentSampleDeletion(sampleUIDs: [String], rootURL: URL) throws -> PermanentDeletionPlan {
        try requireV2(rootURL)
        let uids = Array(Set(sampleUIDs)).sorted()
        guard !uids.isEmpty else { throw LibraryAssetError.invalidSample("no target sample selected") }
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        for uid in uids {
            try requireTrashed(uid, rootURL: rootURL)
        }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return Self.emptyPlan(sampleUIDs: uids)
        }
        let pending = try db.query("SELECT COUNT(*) AS n FROM asset_operations WHERE state = 'pending';").first?.int("n") ?? 0
        if pending > 0 { throw LibraryAssetError.pendingOperations(Int(pending)) }
        return try computePlan(db: db, sampleUIDs: uids)
    }

    private static func emptyPlan(sampleUIDs: [String]) -> PermanentDeletionPlan {
        PermanentDeletionPlan(
            sampleUIDs: sampleUIDs, assetsToDelete: [], deleteMeasurementCount: 0,
            retainedAssets: [], deleteFileCount: 0, retainedFileCount: 0,
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

    /// Reference closure across one or more samples being deleted together: starts from
    /// their active owned Sources, derives downstream Datasets and Plots/Snapshots, and retains
    /// anything another non-deleting sample or retained consumer still uses. Retained Sources
    /// of deleted samples keep their unique Sample UID marked as `historical`.
    func computePlan(db: LibraryAssetDatabase, sampleUIDs: [String]) throws -> PermanentDeletionPlan {
        let uids = Array(Set(sampleUIDs)).sorted()
        let deletingUIDs = Set(uids)

        let links = try db.query("SELECT sample_uid, asset_id, ownership_status FROM sample_asset_links;")
            .compactMap { row -> (sampleUID: String, assetID: String, status: String)? in
                guard let sample = row.string("sample_uid"), let asset = row.string("asset_id") else { return nil }
                return (sample, asset, row.string("ownership_status") ?? "active")
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

        let activeOutsideSources = Set(
            links.filter { $0.status == "active" && !deletingUIDs.contains($0.sampleUID) }.map(\.assetID)
        )
        let activeOutsideDatasets = Set(
            deps.filter { $0.kind == "dataset_source" && activeOutsideSources.contains($0.upstream) }.map(\.consumer)
        )
        let activeOutsideAssets = activeOutsideSources.union(activeOutsideDatasets)
        let activeOwnedSources = Set(
            links.filter { $0.status == "active" && deletingUIDs.contains($0.sampleUID) }.map(\.assetID)
        )

        var candidates = activeOwnedSources
        var frontier = Array(activeOwnedSources)
        while let current = frontier.popLast() {
            for dep in deps where dep.upstream == current && !candidates.contains(dep.consumer) {
                if assets[dep.consumer] != nil {
                    candidates.insert(dep.consumer)
                    frontier.append(dep.consumer)
                }
            }
        }
        // Also pull in any non-outside-active upstreams of candidate derived assets (e.g. historical Sources/Datasets
        // whose only remaining consumer was a cross-sample Plot now being deleted with the last active Sample).
        var upstreamFrontier = Array(candidates)
        while let current = upstreamFrontier.popLast() {
            for dep in deps where dep.consumer == current && !candidates.contains(dep.upstream) {
                if !activeOutsideAssets.contains(dep.upstream), assets[dep.upstream] != nil {
                    candidates.insert(dep.upstream)
                    upstreamFrontier.append(dep.upstream)
                }
            }
        }

        var deleting = candidates
        var retained = Set<String>()
        var changed = true
        while changed {
            changed = false
            for asset in deleting.sorted() {
                let kind = assets[asset]?.kind
                let usedByOutsideSample = (kind == "source") && activeOutsideSources.contains(asset)
                let datasetMissingSource = (kind == "dataset") && deps.contains {
                    $0.consumer == asset && $0.kind == "dataset_source" && !deleting.contains($0.upstream)
                }
                let derivedHasOutsideInput = (kind == "plot" || kind == "snapshot") && deps.contains {
                    $0.consumer == asset && !deleting.contains($0.upstream)
                }
                let usedByRetainedConsumer = deps.contains { $0.upstream == asset && !deleting.contains($0.consumer) }
                if usedByOutsideSample || datasetMissingSource || derivedHasOutsideInput || usedByRetainedConsumer {
                    deleting.remove(asset)
                    retained.insert(asset)
                    changed = true
                }
            }
        }

        let stale = retained.intersection(candidates).filter { assets[$0]?.liveState != nil }.sorted()
        let deleteCount = deleting.reduce(0) { $0 + (assets[$1]?.files.count ?? 0) }
        let retainedCount = retained.reduce(0) { $0 + (assets[$1]?.files.count ?? 0) }

        let involved = candidates
        var lines: [String] = uids.map { "sample|\($0)" }
        for link in links where involved.contains(link.assetID) || deletingUIDs.contains(link.sampleUID) {
            lines.append("L|\(link.sampleUID)|\(link.assetID)|\(link.status)")
        }
        for dep in deps where involved.contains(dep.consumer) || involved.contains(dep.upstream) {
            lines.append("D|\(dep.consumer)|\(dep.upstream)|\(dep.kind)")
        }
        for id in involved {
            if let record = assets[id] { lines.append("A|\(id)|\(record.status)|\(record.currentRevision)|\(record.liveState ?? "-")") }
        }
        let fingerprint = AssetHashing.sha256Hex(Data(lines.sorted().joined(separator: "\n").utf8))

        let deleteMeasurementCount = deleting.filter { assets[$0]?.kind == "source" }.count

        return PermanentDeletionPlan(
            sampleUIDs: uids, assetsToDelete: deleting.sorted(), deleteMeasurementCount: deleteMeasurementCount,
            retainedAssets: retained.sorted(), deleteFileCount: deleteCount, retainedFileCount: retainedCount,
            staleLiveAssetIDs: stale, fingerprint: fingerprint
        )
    }

    // MARK: Commit

    func commitPermanentSampleDeletion(
        plan: PermanentDeletionPlan, operationID: String, rootURL: URL
    ) throws -> PermanentDeletionResult {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        try validateOperationID(operationID)
        let uids = Array(Set(plan.sampleUIDs)).sorted()
        guard !uids.isEmpty else { throw LibraryAssetError.invalidSample("no target sample selected") }
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }

        let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager)
        if let db {
            _ = try recoverPending(db: db, rootURL: rootURL)
            if let existing = try operation(db, id: operationID) {
                guard existing.type == "delete_sample" else { throw LibraryAssetError.operationKindMismatch(operationID) }
                if existing.state == "committed", let result = try decodeJSON(DeleteOpPayload.self, existing.payload).result {
                    return result
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
            return PermanentDeletionResult(sampleUIDs: uids, deletedAssetIDs: [], retainedAssetIDs: [])
        }

        var payload = DeleteOpPayload(sampleUIDs: uids, assets: [], retained: [], stale: [], result: nil)

        // Transaction 1: re-verify the confirmed plan, then persist the intent and the new state.
        try db.transaction {
            let fresh = try computePlan(db: db, sampleUIDs: uids)
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
            payload.retained = fresh.retainedAssets
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try insertOperation(db, id: operationID, type: "delete_sample", state: "pending", payload: try encodeJSON(payload))
            let now = Self.timestamp()
            for id in fresh.staleLiveAssetIDs {
                try db.execute("UPDATE assets SET live_state = 'stale', updated_at = ? WHERE asset_id = ?;", [.text(now), .text(id)])
            }
            for id in fresh.assetsToDelete {
                try db.execute("UPDATE assets SET status = 'deleting', updated_at = ? WHERE asset_id = ?;", [.text(now), .text(id)])
            }
        }
        try fault(.deleteAfterPendingCommit)
        payload.result = PermanentDeletionResult(
            sampleUIDs: uids, deletedAssetIDs: payload.assets.map(\.id), retainedAssetIDs: payload.retained
        )
        return try finishDeletion(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
    }

    // MARK: - Independent Source / Dataset deletion

    enum AssetDeletionTarget: Equatable, Sendable {
        case source(String)
        case dataset(String)
        /// A formal Plot: only the Plot is removed; its input Datasets stay.
        case plot(String)

        var assetID: String {
            switch self {
            case let .source(id), let .dataset(id), let .plot(id):
                return id
            }
        }
    }

    func planAssetDeletion(target: AssetDeletionTarget, rootURL: URL) throws -> PermanentDeletionPlan {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(target.assetID)
        }
        let pending = try db.query("SELECT COUNT(*) AS n FROM asset_operations WHERE state = 'pending';").first?.int("n") ?? 0
        if pending > 0 { throw LibraryAssetError.pendingOperations(Int(pending)) }
        return try computeAssetDeletionPlan(db: db, target: target)
    }

    func computeAssetDeletionPlan(db: LibraryAssetDatabase, target: AssetDeletionTarget) throws -> PermanentDeletionPlan {
        var assets: [String: AssetRecord] = [:]
        for row in try db.query("SELECT * FROM assets;") {
            let record = try AssetRecord(row: row)
            assets[record.id] = record
        }
        let deps = try db.query("SELECT consumer_asset_id, upstream_asset_id, dependency_kind FROM asset_dependencies;")
            .compactMap { row -> (consumer: String, upstream: String, kind: String)? in
                guard let c = row.string("consumer_asset_id"), let u = row.string("upstream_asset_id"),
                      let k = row.string("dependency_kind") else { return nil }
                return (c, u, k)
            }

        guard let targetRecord = assets[target.assetID] else {
            throw LibraryAssetError.assetNotFound(target.assetID)
        }

        let candidates: Set<String>
        let retained: Set<String>
        switch target {
        case let .plot(plotID):
            guard targetRecord.kind == "plot", targetRecord.status == "ready" else {
                throw LibraryAssetError.invalidPayload("expected a ready plot '\(plotID)'")
            }
            candidates = Set([plotID])
            retained = Set(deps.filter { $0.consumer == plotID }.map(\.upstream))
        case let .source(sourceID):
            guard targetRecord.kind == "source" else {
                throw LibraryAssetError.invalidPayload("expected source asset '\(sourceID)'")
            }
            let datasets = deps.filter { $0.upstream == sourceID && $0.kind == "dataset_source" }.map(\.consumer)
            candidates = Set([sourceID] + datasets.filter { assets[$0] != nil })
            retained = []
        case let .dataset(datasetID):
            guard targetRecord.kind == "dataset" else {
                throw LibraryAssetError.invalidPayload("expected dataset asset '\(datasetID)'")
            }
            guard let sourceID = deps.first(where: { $0.consumer == datasetID && $0.kind == "dataset_source" })?.upstream else {
                throw LibraryAssetError.databaseCorrupt("dataset '\(datasetID)' is missing its source link")
            }
            let siblingDatasets = deps.filter { $0.upstream == sourceID && $0.kind == "dataset_source" && assets[$0.consumer] != nil }
            if siblingDatasets.count <= 1 {
                throw LibraryAssetError.lastDatasetDeletionRejected(datasetID: datasetID, sourceID: sourceID)
            }
            candidates = Set([datasetID])
            let survivingSiblings = siblingDatasets.map(\.consumer).filter { $0 != datasetID }
            retained = Set([sourceID] + survivingSiblings)
        }

        let externalConsumers = Set(
            deps.filter { candidates.contains($0.upstream) && !candidates.contains($0.consumer) && assets[$0.consumer] != nil }
                .map(\.consumer)
        )
        if !externalConsumers.isEmpty {
            let kinds = externalConsumers.compactMap { assets[$0]?.kind }
            throw LibraryAssetError.assetInUse(
                assetID: target.assetID,
                dependentCount: externalConsumers.count,
                dependentKinds: Array(Set(kinds))
            )
        }

        let deleting = candidates.sorted()
        let retainedList = retained.sorted()
        let deleteMeasurementCount = deleting.filter { assets[$0]?.kind == "source" }.count
        let deleteCount = deleting.reduce(0) { $0 + (assets[$1]?.files.count ?? 0) }
        let retainedCount = retainedList.reduce(0) { $0 + (assets[$1]?.files.count ?? 0) }

        var lines: [String] = ["target|\(target.assetID)"]
        for dep in deps where candidates.contains(dep.consumer) || candidates.contains(dep.upstream) {
            lines.append("D|\(dep.consumer)|\(dep.upstream)|\(dep.kind)")
        }
        for id in deleting {
            if let record = assets[id] {
                lines.append("A|\(id)|\(record.status)|\(record.currentRevision)|\(record.liveState ?? "-")")
            }
        }
        for id in retainedList {
            if let record = assets[id] {
                lines.append("R|\(id)|\(record.status)|\(record.currentRevision)|\(record.liveState ?? "-")")
            }
        }
        let fingerprint = AssetHashing.sha256Hex(Data(lines.sorted().joined(separator: "\n").utf8))

        return PermanentDeletionPlan(
            sampleUIDs: [],
            assetsToDelete: deleting,
            deleteMeasurementCount: deleteMeasurementCount,
            retainedAssets: retainedList,
            deleteFileCount: deleteCount,
            retainedFileCount: retainedCount,
            staleLiveAssetIDs: [],
            fingerprint: fingerprint
        )
    }

    func commitAssetDeletion(
        target: AssetDeletionTarget,
        plan: PermanentDeletionPlan,
        operationID: String,
        rootURL: URL
    ) throws -> PermanentDeletionResult {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        try validateOperationID(operationID)
        guard plan.sampleUIDs.isEmpty else {
            throw LibraryAssetError.invalidPayload("asset deletion plan must not include sample UIDs")
        }
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }

        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(target.assetID)
        }
        _ = try recoverPending(db: db, rootURL: rootURL)
        if let existing = try operation(db, id: operationID) {
            guard existing.type == "delete_assets" else { throw LibraryAssetError.operationKindMismatch(operationID) }
            if existing.state == "committed", let result = try decodeJSON(DeleteOpPayload.self, existing.payload).result {
                return result
            }
        }

        var payload = DeleteOpPayload(sampleUIDs: [], assets: [], retained: [], stale: [], result: nil)
        try db.transaction {
            let fresh = try computeAssetDeletionPlan(db: db, target: target)
            guard fresh.fingerprint == plan.fingerprint, fresh.assetsToDelete == plan.assetsToDelete else {
                throw LibraryAssetError.planChanged
            }
            for id in fresh.assetsToDelete {
                guard let record = try assetRecord(db, id: id) else { throw LibraryAssetError.planChanged }
                let components = record.storageRelPath.split(separator: "/").map(String.init)
                let assetDir = components.count >= 2 ? components[0] + "/" + components[1] : ""
                payload.assets.append(DeleteAssetEntry(
                    id: id,
                    dirRel: record.files.isEmpty ? "" : record.storageRelPath,
                    assetDirRel: record.files.isEmpty ? "" : assetDir,
                    files: record.files.map(\.name)
                ))
            }
            payload.retained = fresh.retainedAssets
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try insertOperation(db, id: operationID, type: "delete_assets", state: "pending", payload: try encodeJSON(payload))
            let now = Self.timestamp()
            for id in fresh.assetsToDelete {
                try db.execute("UPDATE assets SET status = 'deleting', updated_at = ? WHERE asset_id = ?;", [.text(now), .text(id)])
            }
        }
        try fault(.deleteAfterPendingCommit)
        payload.result = PermanentDeletionResult(
            sampleUIDs: [],
            deletedAssetIDs: payload.assets.map(\.id),
            retainedAssetIDs: payload.retained
        )
        return try finishDeletion(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
    }

    /// Steps after the pending commit; idempotent so recovery can run them again.
    func finishDeletion(
        db: LibraryAssetDatabase, operationID: String, payload: DeleteOpPayload, rootURL: URL
    ) throws -> PermanentDeletionResult {
        if !payload.sampleUIDs.isEmpty {
            try removeSampleRecords(sampleUIDs: payload.sampleUIDs, rootURL: rootURL)
        }
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
            sampleUIDs: payload.sampleUIDs, deletedAssetIDs: payload.assets.map(\.id), retainedAssetIDs: payload.retained
        )
        var done = payload
        done.result = result
        let ids = payload.assets.map(\.id)
        try db.transaction {
            if !payload.sampleUIDs.isEmpty {
                let sampleMarks = Array(repeating: "?", count: payload.sampleUIDs.count).joined(separator: ",")
                try db.execute(
                    "UPDATE sample_asset_links SET ownership_status = 'historical' WHERE sample_uid IN (\(sampleMarks));",
                    payload.sampleUIDs.map { .text($0) }
                )
            }
            if !ids.isEmpty {
                let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
                let params = ids.map { SQLValue.text($0) }
                try db.execute("DELETE FROM asset_dependencies WHERE consumer_asset_id IN (\(marks)) OR upstream_asset_id IN (\(marks));", params + params)
                // Schema 3 rows hang off the Source row; they go first (foreign_keys = ON).
                try db.execute("DELETE FROM source_context WHERE source_id IN (\(marks));", params)
                try db.execute("DELETE FROM standardization_outcome WHERE source_id IN (\(marks));", params)
                try db.execute("DELETE FROM context_amendment WHERE source_id IN (\(marks));", params)
                try db.execute("DELETE FROM coordinator_followup WHERE source_id IN (\(marks));", params)
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
        for sampleUID in sampleUIDs {
            guard SampleIdentityRule.isValidUID(sampleUID) else { throw LibraryAssetError.unsafePath(sampleUID) }
            let sampleURL = libraryStore.v2SampleDirectoryURL(rootURL, sampleUID: sampleUID)
            guard libraryStore.isPathContained(sampleURL, within: samplesRoot) else {
                throw LibraryAssetError.unsafePath(sampleURL.path)
            }
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
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager) else {
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
            case "ingest_source":
                try abortSourceIngest(db: db, operationID: id, payload: decodeJSON(SourceIngestOpPayload.self, payloadText), rootURL: rootURL)
                report.abortedOperations.append(id)
            case "standardize":
                try abortStandardize(db: db, operationID: id, payload: decodeJSON(StandardizeOpPayload.self, payloadText), rootURL: rootURL)
                report.abortedOperations.append(id)
            case "revise":
                try abortRevise(db: db, operationID: id, payload: decodeJSON(ReviseOpPayload.self, payloadText), rootURL: rootURL)
                report.abortedOperations.append(id)
            case "plot_publish":
                try abortPlotPublish(db: db, operationID: id, payload: decodeJSON(PlotOpPayload.self, payloadText), rootURL: rootURL)
                report.abortedOperations.append(id)
            case "plot_update":
                try abortPlotUpdate(db: db, operationID: id, payload: decodeJSON(PlotOpPayload.self, payloadText), rootURL: rootURL)
                report.abortedOperations.append(id)
            case "delete_sample", "delete_assets":
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

        let uncleanedPlots = try db.query(
            "SELECT operation_id, payload_json FROM asset_operations WHERE op_type = 'plot_update' AND state = 'committed' AND payload_json LIKE '%\"cleanupPending\":true%';"
        )
        for row in uncleanedPlots {
            guard let id = row.string("operation_id"), let payloadText = row.string("payload_json") else { continue }
            try finishPlotCleanup(db: db, operationID: id, payload: decodeJSON(PlotOpPayload.self, payloadText), rootURL: rootURL)
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
        for entry in payload.datasets {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: entry.datasetRelPath, names: entry.files.map(\.name),
                removeWriterTemps: true,
                emptyDirectoryCandidates: [entry.datasetRelPath, "storage/\(entry.datasetID)"], report: &report
            )
        }
        try db.transaction {
            var ids = payload.datasets.map(\.datasetID)
            if !payload.reusedSource { ids.append(payload.sourceID) }
            for id in ids {
                try db.execute("DELETE FROM assets WHERE asset_id = ? AND status = 'staging';", [.text(id)])
            }
            try updateOperation(db, id: operationID, state: "aborted", payload: try encodeJSON(payload))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }
}
