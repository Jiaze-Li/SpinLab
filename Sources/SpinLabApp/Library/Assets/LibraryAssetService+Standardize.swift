import Foundation

// MARK: - WP1 step ② — standardization of an already committed Source
//
// Independent of ingest: it reads the stored bytes only through `readSource`, never writes to a
// Source, its context or its ownership, and never decides on plotting. The caller supplies the
// adapter (or none). Its own two-phase transaction covers Dataset rows, the `dataset_source`
// dependency and the outcome row only (design §3.0, §3.2 ②).

extension LibraryAssetService {
    struct StandardizeOpPayload: Codable {
        var sourceID: String
        var adapterID: String?
        var requestHash: String
        var datasets: [IngestDatasetEntry]
        var result: StandardizationResult?
    }

    @discardableResult
    func standardizeSource(
        sourceID: String, adapter: (any AssetStandardizationAdapter)?, operationID: String, rootURL: URL
    ) throws -> StandardizationResult {
        try requireV2(rootURL)
        try requireWritable(rootURL)

        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }

        guard let db = try LibraryAssetDatabase.open(
            rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager
        ) else { throw LibraryAssetError.assetNotFound(sourceID) }
        _ = try recoverPending(db: db, rootURL: rootURL)

        let adapterID = adapter?.adapterID
        let requestHash = "\(sourceID)|\(adapterID ?? "none")".sha256Hex

        if let existing = try operation(db, id: operationID) {
            guard existing.type == "standardize" else { throw LibraryAssetError.operationKindMismatch(operationID) }
            let stored = try decodeJSON(StandardizeOpPayload.self, existing.payload)
            guard stored.requestHash == requestHash else { throw LibraryAssetError.operationRequestMismatch(operationID) }
            if existing.state == "committed", let result = stored.result { return result }
        }

        // Existence, readiness and an intact Library copy are checked through the read contract.
        let content = try readSource(db, sourceID: sourceID, rootURL: rootURL)

        // Already standardized by the same adapter: return the existing result (idempotent retry).
        if let adapterID,
           let outcome = try db.query("SELECT adapter_id, state FROM standardization_outcome WHERE source_id = ?;", [.text(sourceID)]).first,
           outcome.string("state") == "standardized", outcome.string("adapter_id") == adapterID {
            let existingDatasets = try db.query(
                """
                SELECT a.asset_id, a.current_revision FROM assets a
                JOIN asset_dependencies d ON d.consumer_asset_id = a.asset_id
                WHERE d.upstream_asset_id = ? AND d.dependency_kind = 'dataset_source' AND a.kind = 'dataset' AND a.status = 'ready'
                ORDER BY a.created_at, a.asset_id;
                """,
                [.text(sourceID)]
            )
            if !existingDatasets.isEmpty {
                return .standardized(
                    datasetIDs: existingDatasets.compactMap { $0.string("asset_id") },
                    datasetRevision: Int(existingDatasets.first?.int("current_revision") ?? 1)
                )
            }
        }

        guard let adapter else {
            return try recordNotStandardized(
                db, sourceID: sourceID, adapterID: nil, operationID: operationID, requestHash: requestHash,
                code: "no_adapter", detail: "no adapter is registered for this file"
            )
        }

        let items: [StandardizedDatasetItem]
        do {
            items = try adapter.standardize(sourceBytes: content.bytes, originalFileName: content.originalFileName)
        } catch let rejected as StandardizationRejected {
            return try recordNotStandardized(
                db, sourceID: sourceID, adapterID: adapter.adapterID, operationID: operationID, requestHash: requestHash,
                code: rejected.code, detail: rejected.detail
            )
        }
        guard !items.isEmpty else {
            return try recordNotStandardized(
                db, sourceID: sourceID, adapterID: adapter.adapterID, operationID: operationID, requestHash: requestHash,
                code: "no_datasets", detail: "the adapter produced no dataset"
            )
        }
        for item in items { try validateFileNames(item.content.files) }

        var datasetItems: [(entry: IngestDatasetEntry, files: [StandardizedFile], byteSize: Int64)] = []
        for item in items {
            let datasetID = "dst_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            let datasetRel = "storage/\(datasetID)/rev_1"
            let entries = item.content.files.map(AssetFileEntry.make)
            datasetItems.append((
                entry: IngestDatasetEntry(
                    datasetID: datasetID, format: item.content.format, datasetRelPath: datasetRel,
                    files: entries, signalLocatorJSON: try encodeJSON(item.signalLocators)
                ),
                files: item.content.files,
                byteSize: entries.reduce(Int64(0)) { $0 + Int64($1.size) }
            ))
        }
        var payload = StandardizeOpPayload(
            sourceID: sourceID, adapterID: adapter.adapterID, requestHash: requestHash,
            datasets: datasetItems.map(\.entry), result: nil
        )

        // Transaction 1: intent and Dataset staging rows. The Source is not touched.
        try db.transaction {
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try insertOperation(db, id: operationID, type: "standardize", state: "pending", payload: try encodeJSON(payload))
            let now = Self.timestamp()
            for item in datasetItems {
                try insertAsset(
                    db, id: item.entry.datasetID, kind: "dataset", format: item.entry.format, status: "staging",
                    relPath: item.entry.datasetRelPath, revision: 1, sha256: AssetHashing.digest(of: item.entry.files),
                    byteSize: item.byteSize, originalFilename: nil, files: item.entry.files, now: now
                )
            }
        }
        for item in datasetItems {
            try writeFiles(item.files, toRelativeDirectory: item.entry.datasetRelPath, rootURL: rootURL)
            try verifyFiles(item.entry.files, relativeDirectory: item.entry.datasetRelPath, rootURL: rootURL)
        }
        try fault(.standardizeAfterWritten)
        try fault(.standardizeBeforeCommit)

        let result = StandardizationResult.standardized(datasetIDs: datasetItems.map(\.entry.datasetID), datasetRevision: 1)
        payload.result = result
        try db.transaction {
            let now = Self.timestamp()
            let ids = datasetItems.map(\.entry.datasetID)
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            try db.execute(
                "UPDATE assets SET status = 'ready', updated_at = ? WHERE asset_id IN (\(marks)) AND status = 'staging';",
                [.text(now)] + ids.map { .text($0) }
            )
            for item in datasetItems {
                try db.execute(
                    "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, 'dataset_source', ?);",
                    [.text(item.entry.datasetID), .text(sourceID), .text(item.entry.signalLocatorJSON)]
                )
            }
            try upsertOutcome(db, sourceID: sourceID, adapterID: adapter.adapterID, state: "standardized", code: nil, detail: nil, now: now)
            try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(payload))
        }
        try fault(.standardizeAfterCommit)
        return result
    }

    private func recordNotStandardized(
        _ db: LibraryAssetDatabase, sourceID: String, adapterID: String?, operationID: String,
        requestHash: String, code: String, detail: String
    ) throws -> StandardizationResult {
        // Existing Datasets are never contradicted: a later refusal does not overwrite a standardized outcome.
        let existing = try db.query(
            """
            SELECT a.asset_id, a.current_revision FROM assets a
            JOIN asset_dependencies d ON d.consumer_asset_id = a.asset_id
            WHERE d.upstream_asset_id = ? AND d.dependency_kind = 'dataset_source' AND a.kind = 'dataset' AND a.status = 'ready'
            ORDER BY a.created_at, a.asset_id;
            """,
            [.text(sourceID)]
        )
        if !existing.isEmpty {
            return .standardized(
                datasetIDs: existing.compactMap { $0.string("asset_id") },
                datasetRevision: Int(existing.first?.int("current_revision") ?? 1)
            )
        }
        let result = StandardizationResult.notStandardized(code: code, detail: detail)
        let payload = StandardizeOpPayload(
            sourceID: sourceID, adapterID: adapterID, requestHash: requestHash, datasets: [], result: result
        )
        try db.transaction {
            let now = Self.timestamp()
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try upsertOutcome(db, sourceID: sourceID, adapterID: adapterID, state: "not_standardized", code: code, detail: detail, now: now)
            try insertOperation(db, id: operationID, type: "standardize", state: "committed", payload: try encodeJSON(payload))
        }
        return result
    }

    private func upsertOutcome(
        _ db: LibraryAssetDatabase, sourceID: String, adapterID: String?, state: String, code: String?, detail: String?, now: String
    ) throws {
        try db.execute(
            """
            INSERT INTO standardization_outcome(source_id, adapter_id, state, code, detail, attempted_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_id) DO UPDATE SET adapter_id = excluded.adapter_id, state = excluded.state,
                code = excluded.code, detail = excluded.detail, attempted_at = excluded.attempted_at;
            """,
            [.text(sourceID), .optionalText(adapterID), .text(state), .optionalText(code), .optionalText(detail), .text(now)]
        )
    }

    /// Rolls back an unfinished standardization: only Dataset staging rows and files. The Source stays.
    func abortStandardize(db: LibraryAssetDatabase, operationID: String, payload: StandardizeOpPayload, rootURL: URL) throws {
        var report = AssetRecoveryReport()
        for entry in payload.datasets {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: entry.datasetRelPath, names: entry.files.map(\.name),
                removeWriterTemps: true,
                emptyDirectoryCandidates: [entry.datasetRelPath, "storage/\(entry.datasetID)"], report: &report
            )
        }
        try db.transaction {
            for entry in payload.datasets {
                try db.execute("DELETE FROM assets WHERE asset_id = ? AND status = 'staging';", [.text(entry.datasetID)])
            }
            try updateOperation(db, id: operationID, state: "aborted", payload: try encodeJSON(payload))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }
}
