import Foundation

// MARK: - Dataset correction (same dataset ID, monotonically increasing revision)

extension LibraryAssetService {
    struct ReviseOpPayload: Codable {
        var datasetID: String
        var expectedRevision: Int
        var nextRevision: Int
        var stagingRelPath: String
        var targetRelPath: String
        var oldRelPath: String
        var files: [AssetFileEntry]
        var oldFiles: [AssetFileEntry]
        var cleanupPending: Bool
        var result: AssetReviseResult?
    }

    /// Replaces the content of an existing Dataset with a corrected one, keeping its ID.
    ///
    /// `expectedRevision` is the revision the caller read when the correction started. The commit
    /// is rejected when the Dataset moved on in the meantime (late writer, A→B→A included).
    /// Dependent Live assets become stale; Snapshots and confirmed Sample Results are untouched.
    func reviseDataset(
        datasetID: String,
        expectedRevision: Int,
        content: StandardizedDatasetContent,
        operationID: String,
        rootURL: URL
    ) throws -> AssetReviseResult {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        try validateFileNames(content.files)
        try validateOperationID(operationID)

        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }

        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(datasetID)
        }
        _ = try recoverPending(db: db, rootURL: rootURL)

        if let existing = try operation(db, id: operationID) {
            guard existing.type == "revise" else { throw LibraryAssetError.operationKindMismatch(operationID) }
            if existing.state == "committed", let result = try decodeJSON(ReviseOpPayload.self, existing.payload).result {
                return result
            }
        }

        let entries = content.files.map(AssetFileEntry.make)
        var payload: ReviseOpPayload!

        // Transaction 1: validate the starting revision and persist the recovery intent before any file work.
        try db.transaction {
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            guard let record = try assetRecord(db, id: datasetID), record.kind == "dataset" else {
                throw LibraryAssetError.assetNotFound(datasetID)
            }
            guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(datasetID) }
            guard record.format == content.format else {
                throw LibraryAssetError.invalidPayload("format '\(content.format)' does not match dataset format '\(record.format)'")
            }
            guard record.currentRevision == expectedRevision else {
                throw LibraryAssetError.staleRevision(datasetID: datasetID, expected: expectedRevision, current: record.currentRevision)
            }
            let next = expectedRevision + 1
            payload = ReviseOpPayload(
                datasetID: datasetID, expectedRevision: expectedRevision, nextRevision: next,
                stagingRelPath: "storage/\(datasetID)/.staging_\(operationID)",
                targetRelPath: "storage/\(datasetID)/rev_\(next)",
                oldRelPath: record.storageRelPath, files: entries, oldFiles: record.files,
                cleanupPending: false, result: nil
            )
            try insertOperation(db, id: operationID, type: "revise", state: "pending", payload: try encodeJSON(payload))
        }

        // Independent staging directory; the formal revision directories are untouched here.
        try writeFiles(content.files, toRelativeDirectory: payload.stagingRelPath, rootURL: rootURL)
        try verifyFiles(entries, relativeDirectory: payload.stagingRelPath, rootURL: rootURL)
        try fault(.reviseAfterStaging)

        // Publish inside the serial critical section: re-check, then atomic rename.
        let current = try currentRevision(db, datasetID: datasetID)
        guard current == expectedRevision else {
            try abortRevise(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
            throw LibraryAssetError.staleRevision(datasetID: datasetID, expected: expectedRevision, current: current ?? -1)
        }
        let stagingURL = try storageURL(rootURL: rootURL, relativePath: payload.stagingRelPath)
        let targetURL = try storageURL(rootURL: rootURL, relativePath: payload.targetRelPath)
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            throw LibraryAssetError.cleanupFailed("revision directory '\(payload.targetRelPath)' already exists")
        }
        try fileManager.moveItem(at: stagingURL, to: targetURL)
        try syncDirectory(targetURL.deletingLastPathComponent())
        try fault(.reviseAfterPublish)

        // Transaction 2: final commit.
        var stale: [String] = []
        let byteSize = entries.reduce(Int64(0)) { $0 + Int64($1.size) }
        try db.transaction {
            guard try currentRevision(db, datasetID: datasetID) == expectedRevision else {
                throw LibraryAssetError.staleRevision(datasetID: datasetID, expected: expectedRevision, current: -1)
            }
            let now = Self.timestamp()
            try db.execute(
                """
                UPDATE assets SET current_revision = ?, storage_rel_path = ?, sha256 = ?, byte_size = ?, files_json = ?, updated_at = ?
                WHERE asset_id = ?;
                """,
                [
                    .int(Int64(payload.nextRevision)), .text(payload.targetRelPath), .text(AssetHashing.digest(of: entries)),
                    .int(byteSize), .text(AssetFileEntry.encodeList(entries)), .text(now), .text(datasetID)
                ]
            )
            stale = try db.query(
                """
                SELECT d.consumer_asset_id AS id FROM asset_dependencies d JOIN assets a ON a.asset_id = d.consumer_asset_id
                WHERE d.upstream_asset_id = ? AND d.dependency_kind = 'live_input' AND a.live_state IS NOT NULL;
                """,
                [.text(datasetID)]
            ).compactMap { $0.string("id") }
            for id in stale {
                try db.execute("UPDATE assets SET live_state = 'stale', updated_at = ? WHERE asset_id = ?;", [.text(now), .text(id)])
            }
            payload.result = AssetReviseResult(datasetID: datasetID, revision: payload.nextRevision, staleLiveAssetIDs: stale.sorted())
            payload.cleanupPending = true
            try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(payload))
        }
        try fault(.reviseAfterCommit)
        try finishRevisionCleanup(db: db, operationID: operationID, payload: payload, rootURL: rootURL)
        return payload.result!
    }

    func validateOperationID(_ id: String) throws {
        guard !id.isEmpty, !id.contains("/"), !id.contains(".."), id.utf8.count < 100 else {
            throw LibraryAssetError.invalidPayload("illegal operation id '\(id)'")
        }
    }

    func currentRevision(_ db: LibraryAssetDatabase, datasetID: String) throws -> Int? {
        try db.query("SELECT current_revision FROM assets WHERE asset_id = ?;", [.text(datasetID)])
            .first?.int("current_revision").map(Int.init)
    }

    /// Removes the superseded revision's registered files after the commit point.
    func finishRevisionCleanup(
        db: LibraryAssetDatabase, operationID: String, payload: ReviseOpPayload, rootURL: URL
    ) throws {
        var report = AssetRecoveryReport()
        if payload.oldRelPath != payload.targetRelPath {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: payload.oldRelPath, names: payload.oldFiles.map(\.name),
                removeWriterTemps: false, emptyDirectoryCandidates: [payload.oldRelPath], report: &report
            )
        }
        var done = payload
        done.cleanupPending = false
        try db.transaction {
            try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(done))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }

    /// Rolls back an unfinished correction. Only files this operation registered are removed; the
    /// target revision directory is touched only while the Dataset still sits at the expected revision
    /// (otherwise that directory may belong to another, committed correction).
    func abortRevise(db: LibraryAssetDatabase, operationID: String, payload: ReviseOpPayload, rootURL: URL) throws {
        var report = AssetRecoveryReport()
        let names = payload.files.map(\.name)
        try removeRegisteredFiles(
            rootURL: rootURL, relativeDirectory: payload.stagingRelPath, names: names,
            removeWriterTemps: true, emptyDirectoryCandidates: [payload.stagingRelPath], report: &report
        )
        if try currentRevision(db, datasetID: payload.datasetID) == payload.expectedRevision {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: payload.targetRelPath, names: names,
                removeWriterTemps: true, emptyDirectoryCandidates: [payload.targetRelPath], report: &report
            )
        }
        try db.transaction {
            try updateOperation(db, id: operationID, state: "aborted", payload: try encodeJSON(payload))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }
}
