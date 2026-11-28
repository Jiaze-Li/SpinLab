import Foundation

// MARK: - WP1 step ④ — coordination of ingest → standardize (and the auto-plot follow-up row)
//
// The only place where the independent steps are called one after another. Ingest and
// standardization never call each other; this layer sequences them and owns the
// `coordinator_followup` row that remembers an automatic-plot intent across a crash.

extension LibraryAssetService {
    /// Operation ID of the standardize step that belongs to an ingest operation.
    static func standardizeOperationID(forIngest operationID: String) -> String { operationID + "-std" }

    /// Sequential ingest then standardize. Standardization problems never undo the stored Source:
    /// a refusal is reported through an empty `datasetIDs`; a technical error is thrown after the
    /// Source is already safe, and a retry only repeats the standardize step.
    func ingestAsset(
        sourceFileURL: URL,
        adapter: (any AssetStandardizationAdapter)?,
        targetSampleUID: String,
        operationID: String,
        reuseSourceID: String? = nil,
        context: SourceContextInput? = nil,
        effectiveChannels: [EffectiveChannel]? = nil,
        autoPlotIntent: AutoPlotIntent? = nil,
        rootURL: URL
    ) throws -> AssetIngestResult {
        let receipt = try ingestSource(
            SourceIngestRequest(
                sourceFileURL: sourceFileURL, targetSampleUID: targetSampleUID, operationID: operationID,
                context: context ?? SourceContextInput(legacyPath: sourceFileURL.path),
                effectiveChannels: effectiveChannels, reuseSourceID: reuseSourceID
            ),
            rootURL: rootURL
        )
        let standardizeOp = Self.standardizeOperationID(forIngest: operationID)
        // A replay keeps the intent persisted by the first attempt and ignores a newly supplied one.
        if let autoPlotIntent, try !standardizeOperationExists(standardizeOp, rootURL: rootURL) {
            try recordFollowup(
                standardizeOperationID: standardizeOp, sourceID: receipt.sourceID,
                kind: Self.autoPlotFollowupKind, requestJSON: encodeJSON(autoPlotIntent), rootURL: rootURL
            )
        }
        let storedIntent = try followupIntent(standardizeOperationID: standardizeOp, rootURL: rootURL)
        let result = try standardizeSource(
            sourceID: receipt.sourceID, adapter: adapter, operationID: standardizeOp, rootURL: rootURL
        )
        switch result {
        case let .standardized(datasetIDs, revision):
            return AssetIngestResult(
                sourceID: receipt.sourceID, datasetIDs: datasetIDs, sampleUID: receipt.sampleUID,
                datasetRevision: revision, reusedSource: receipt.reusedSource, autoPlotIntent: storedIntent
            )
        case .notStandardized:
            return AssetIngestResult(
                sourceID: receipt.sourceID, datasetIDs: [], sampleUID: receipt.sampleUID,
                datasetRevision: 1, reusedSource: receipt.reusedSource, autoPlotIntent: nil
            )
        }
    }

    // MARK: Follow-up rows (coordinator-owned)

    func standardizeOperationExists(_ operationID: String, rootURL: URL) throws -> Bool {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return false
        }
        return try operation(db, id: operationID) != nil
    }

    func followupIntent(standardizeOperationID: String, rootURL: URL) throws -> AutoPlotIntent? {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager),
              let json = try db.query(
                "SELECT request_json FROM coordinator_followup WHERE standardize_operation_id = ? AND kind = 'auto_plot';",
                [.text(standardizeOperationID)]
              ).first?.string("request_json") else { return nil }
        return try? decodeJSON(AutoPlotIntent.self, json)
    }

    static let autoPlotFollowupKind = "auto_plot"

    /// Written *before* the standardize call, so a crash between the two never forgets the intent.
    func recordFollowup(
        standardizeOperationID: String, sourceID: String, kind: String, requestJSON: String, rootURL: URL
    ) throws {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(sourceID)
        }
        try db.execute(
            "INSERT OR IGNORE INTO coordinator_followup(standardize_operation_id, source_id, kind, request_json, state) VALUES (?, ?, ?, ?, 'pending');",
            [.text(standardizeOperationID), .text(sourceID), .text(kind), .text(requestJSON)]
        )
    }

    /// Closes follow-ups whose standardize step was refused, or whose every Dataset already has a
    /// committed publish receipt. Never opens a new one; safe to repeat.
    func settleFollowups(rootURL: URL) throws {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager) else {
            return
        }
        try db.execute(
            """
            UPDATE coordinator_followup SET state = 'done'
            WHERE state = 'pending' AND EXISTS (
                SELECT 1 FROM asset_operations o
                WHERE o.operation_id = coordinator_followup.standardize_operation_id AND o.op_type = 'standardize'
                  AND o.state = 'committed' AND json_extract(o.payload_json, '$.result.notStandardized') IS NOT NULL
            );
            """
        )
    }

    func followupStates(sourceID: String, rootURL: URL) throws -> [String: String] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return [:]
        }
        var result: [String: String] = [:]
        for row in try db.query("SELECT standardize_operation_id, state FROM coordinator_followup WHERE source_id = ?;", [.text(sourceID)]) {
            if let id = row.string("standardize_operation_id"), let state = row.string("state") { result[id] = state }
        }
        return result
    }

    // MARK: Status reads

    /// The honest status of every active Source of a Sample (design P3): file, standardization state,
    /// context knowledge. One batched query; no payload is read.
    func sourceStatusSummaries(forSampleUID sampleUID: String, rootURL: URL) throws -> [SourceStatusSummary] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        let rows = try db.query(
            """
            SELECT a.asset_id AS source_id, a.original_filename AS file_name, l.effective_channels_json AS channels,
                   (SELECT COUNT(*) FROM asset_dependencies d JOIN assets x ON x.asset_id = d.consumer_asset_id
                      WHERE d.upstream_asset_id = a.asset_id AND d.dependency_kind = 'dataset_source'
                        AND x.kind = 'dataset' AND x.status = 'ready') AS dataset_count,
                   o.state AS o_state, o.adapter_id AS o_adapter, o.code AS o_code, o.detail AS o_detail,
                   c.source_id AS c_id, c.workflow_id AS workflow_id, c.workflow_origin AS workflow_origin
            FROM assets a
            JOIN sample_asset_links l ON l.asset_id = a.asset_id
            LEFT JOIN standardization_outcome o ON o.source_id = a.asset_id
            LEFT JOIN source_context c ON c.source_id = a.asset_id
            WHERE l.sample_uid = ? AND l.ownership_status = 'active' AND a.kind = 'source' AND a.status = 'ready'
            ORDER BY a.created_at, a.asset_id;
            """,
            [.text(sampleUID)]
        )
        return try rows.compactMap { row in
            guard let id = row.string("source_id") else { return nil }
            let state: StandardizationState
            switch row.string("o_state") {
            case "standardized": state = .standardized(adapterID: row.string("o_adapter"))
            case "not_standardized": state = .notStandardized(code: row.string("o_code") ?? "", detail: row.string("o_detail") ?? "")
            default: state = .pending
            }
            return SourceStatusSummary(
                sourceID: id, originalFileName: row.string("file_name") ?? "", sampleUID: sampleUID,
                datasetCount: Int(row.int("dataset_count") ?? 0), standardization: state,
                workflowID: row.string("workflow_id"),
                workflowOrigin: ContextOrigin(rawValue: row.string("workflow_origin") ?? "") ?? .unknown,
                effectiveChannels: try row.string("channels").map { try decodeJSON([EffectiveChannel].self, $0) },
                hasContextRow: row.string("c_id") != nil
            )
        }
    }
}
