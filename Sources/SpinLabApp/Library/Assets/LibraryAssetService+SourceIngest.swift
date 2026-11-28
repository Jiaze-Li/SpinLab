import Foundation

// MARK: - WP1 step ① — Source ingest and audited context amendment
//
// This file is the *ingest module*. It owns original bytes, identity, Sample ownership,
// integrity and the confirmed-or-unknown context. It must not mention adapters, Datasets,
// Workbench or automatic plotting (design §3.0, checked by `SourceIngestStructureTests`).
// Whether a file can later be standardized or analysed is none of its business.

extension LibraryAssetService {
    /// Generic `assets.format` of every newly ingested Source. The instrument/container is shown
    /// from context, file suffix and the standardization outcome, not from this value.
    static let genericSourceFormat = "source_file_v1"

    struct SourceIngestOpPayload: Codable {
        var sourceID: String
        var sourceRelPath: String
        var sourceFiles: [AssetFileEntry]
        var sampleUID: String
        /// Binds the request (Sample, ingest-time context, channels); excludes bytes.
        var requestHash: String
        var sha256: String
        var reusedSource: Bool
        var result: SourceReceipt?
    }

    private struct SourceManifestV1: Codable {
        let format: String
        let originalFileName: String
        let originalSourcePath: String?
        let byteSize: Int
        let sha256: String
        let ingestedAt: String
    }

    private struct IngestRequestBinding: Codable {
        let sampleUID: String
        let context: SourceContextInput
        let effectiveChannels: [EffectiveChannel]?
        let reuseSourceID: String?
    }

    // MARK: Ingest

    @discardableResult
    func ingestSource(_ request: SourceIngestRequest, rootURL: URL) throws -> SourceReceipt {
        try requireV2(rootURL)
        let uid = request.targetSampleUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { throw LibraryAssetError.invalidSample("no target sample selected") }
        try requireWritable(rootURL)

        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }

        guard let db = try LibraryAssetDatabase.open(
            rootURL: rootURL, createIfMissing: true, upgrade: true, fileManager: fileManager
        ) else {
            throw LibraryAssetError.databaseCorrupt("asset database could not be created")
        }
        _ = try recoverPending(db: db, rootURL: rootURL)

        let channels = try normalizedChannels(request.effectiveChannels)
        let reuseID = request.reuseSourceID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyValue
        // The old path, free-form interpretation and the file-derived time are provenance, not the request.
        var boundContext = request.context
        boundContext.legacyPath = nil
        boundContext.interpretation = [:]
        // Taken from the file at read time (like the modification time), so a retry must not need it.
        boundContext.measuredAt = nil
        boundContext.measuredAtOrigin = .unknown
        let requestHash = try encodeJSON(IngestRequestBinding(
            sampleUID: uid, context: boundContext, effectiveChannels: channels, reuseSourceID: reuseID
        )).sha256Hex

        // A committed operation answers from its stored receipt before any external file is read.
        if let existing = try operation(db, id: request.operationID) {
            guard existing.type == "ingest_source" else { throw LibraryAssetError.operationKindMismatch(request.operationID) }
            if existing.state == "committed" {
                let stored = try decodeJSON(SourceIngestOpPayload.self, existing.payload)
                if let receipt = stored.result {
                    guard receipt.sampleUID == uid else {
                        throw LibraryAssetError.ownershipViolation(
                            "operation '\(request.operationID)' was already committed for sample '\(receipt.sampleUID)', cannot replay for '\(uid)'"
                        )
                    }
                    guard stored.requestHash == requestHash else {
                        throw LibraryAssetError.operationRequestMismatch(request.operationID)
                    }
                    return receipt
                }
            }
        }

        try validateSample(uid, rootURL: rootURL)

        let bytes: Data
        let mtime: String?
        do {
            bytes = try Data(contentsOf: request.sourceFileURL)
            mtime = (try? fileManager.attributesOfItem(atPath: request.sourceFileURL.path)[.modificationDate] as? Date)
                .map { ISO8601DateFormatter().string(from: $0) }
        } catch {
            throw LibraryAssetError.invalidPayload("the original file cannot be read: \(error.localizedDescription)")
        }
        guard !bytes.isEmpty else { throw LibraryAssetError.invalidPayload("source file is empty") }
        let sha = AssetHashing.sha256Hex(bytes)
        let fileName = request.sourceFileURL.lastPathComponent

        if let reuseID {
            return try reuseSource(
                db: db, reuseID: reuseID, uid: uid, sha: sha, request: request, channels: channels,
                requestHash: requestHash
            )
        }

        let sourceID = "src_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let sourceRel = "storage/\(sourceID)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = SourceManifestV1(
            format: Self.genericSourceFormat, originalFileName: fileName, originalSourcePath: request.context.legacyPath,
            byteSize: bytes.count, sha256: sha, ingestedAt: Self.timestamp()
        )
        let files = [
            StandardizedFile(name: "payload.bin", data: bytes),
            StandardizedFile(name: "manifest.json", data: try encoder.encode(manifest))
        ]
        let entries = files.map(AssetFileEntry.make)
        let receipt = SourceReceipt(sourceID: sourceID, sampleUID: uid, sha256: sha, byteSize: bytes.count)
        var payload = SourceIngestOpPayload(
            sourceID: sourceID, sourceRelPath: sourceRel, sourceFiles: entries, sampleUID: uid,
            requestHash: requestHash, sha256: sha, reusedSource: false, result: nil
        )

        // Transaction 1: recovery intent + staging row before any file is touched.
        try db.transaction {
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(request.operationID)])
            try insertOperation(db, id: request.operationID, type: "ingest_source", state: "pending", payload: try encodeJSON(payload))
            try insertAsset(
                db, id: sourceID, kind: "source", format: Self.genericSourceFormat, status: "staging",
                relPath: sourceRel, revision: 1, sha256: sha, byteSize: Int64(bytes.count),
                originalFilename: fileName, files: entries, now: Self.timestamp()
            )
        }
        try writeFiles(files, toRelativeDirectory: sourceRel, rootURL: rootURL)
        try verifyFiles(entries, relativeDirectory: sourceRel, rootURL: rootURL)
        try fault(.ingestAfterSourceWritten)
        try fault(.ingestBeforeCommit)

        payload.result = receipt
        // Transaction 2: the formal commit point of the Source, context and ownership together.
        try db.transaction {
            let now = Self.timestamp()
            try db.execute("UPDATE assets SET status = 'ready', updated_at = ? WHERE asset_id = ? AND status = 'staging';", [.text(now), .text(sourceID)])
            try db.execute(
                "INSERT INTO sample_asset_links(asset_id, sample_uid, ownership_status, linked_at, effective_channels_json) VALUES (?, ?, 'active', ?, ?);",
                [.text(sourceID), .text(uid), .text(now), .optionalText(try channels.map { try encodeJSON($0) })]
            )
            try insertSourceContext(db, sourceID: sourceID, context: request.context, mtime: mtime, now: now)
            try updateOperation(db, id: request.operationID, state: "committed", payload: try encodeJSON(payload))
        }
        try fault(.ingestAfterCommit)
        return receipt
    }

    /// User-chosen reuse of an identical stored file: no new bytes, no new ownership.
    private func reuseSource(
        db: LibraryAssetDatabase, reuseID: String, uid: String, sha: String, request: SourceIngestRequest,
        channels: [EffectiveChannel]?, requestHash: String
    ) throws -> SourceReceipt {
        guard let record = try assetRecord(db, id: reuseID), record.kind == "source" else {
            throw LibraryAssetError.assetNotFound(reuseID)
        }
        guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(reuseID) }
        guard record.sha256 == sha else {
            throw LibraryAssetError.sourceMismatch("content hash differs from '\(reuseID)'")
        }
        guard let owner = try sourceOwnership(db, sourceID: reuseID) else {
            throw LibraryAssetError.ownershipViolation("source '\(reuseID)' has no sample owner")
        }
        guard !owner.isHistorical else {
            throw LibraryAssetError.ownershipViolation("source '\(reuseID)' belongs to a permanently deleted sample")
        }
        guard owner.sampleUID == uid else {
            throw LibraryAssetError.crossSampleReuseRejected("source '\(reuseID)' belongs to sample '\(owner.sampleUID)', not '\(uid)'")
        }
        try checkReuseContext(db, sourceID: reuseID, context: request.context, channels: channels)
        let receipt = SourceReceipt(
            sourceID: reuseID, sampleUID: uid, sha256: sha, byteSize: Int(record.byteSize ?? 0), reusedSource: true
        )
        let payload = SourceIngestOpPayload(
            sourceID: reuseID, sourceRelPath: record.storageRelPath, sourceFiles: [], sampleUID: uid,
            requestHash: requestHash, sha256: sha, reusedSource: true, result: receipt
        )
        try db.transaction {
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(request.operationID)])
            try insertOperation(db, id: request.operationID, type: "ingest_source", state: "committed", payload: try encodeJSON(payload))
        }
        return receipt
    }

    /// Confirmed request values must equal confirmed stored values; unknown values do not constrain.
    private func checkReuseContext(
        _ db: LibraryAssetDatabase, sourceID: String, context: SourceContextInput, channels: [EffectiveChannel]?
    ) throws {
        let stored = try sourceContext(db, sourceID: sourceID)
        if let workflow = context.workflowID, context.workflowOrigin.isConfirmed,
           let known = stored?.workflowID, stored?.workflowOrigin.isConfirmed == true, known != workflow {
            throw LibraryAssetError.contextConflict("workflow '\(workflow)' differs from recorded '\(known)'")
        }
        for (key, value) in context.conditions where value.origin.isConfirmed {
            if let known = stored?.conditions[key], known.origin.isConfirmed, known.value != value.value {
                throw LibraryAssetError.contextConflict("condition '\(key)' = '\(value.value)' differs from recorded '\(known.value)'")
            }
        }
        if let channels, let known = try storedChannels(db, sourceID: sourceID), Set(known) != Set(channels) {
            throw LibraryAssetError.contextConflict("effective channels differ from the recorded ones")
        }
    }

    private func insertSourceContext(
        _ db: LibraryAssetDatabase, sourceID: String, context: SourceContextInput, mtime: String?, now: String
    ) throws {
        try db.execute(
            """
            INSERT INTO source_context(source_id, workflow_id, workflow_origin, conditions_json, measured_at, measured_at_origin,
                                       source_mtime, legacy_path, interpretation_json, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text(sourceID), .optionalText(context.workflowID), .text(context.workflowOrigin.rawValue),
                .text(try encodeJSON(context.conditions)), .optionalText(context.measuredAt),
                .text(context.measuredAtOrigin.rawValue), .optionalText(mtime), .optionalText(context.legacyPath),
                .text(try encodeJSON(context.interpretation)), .text(now)
            ]
        )
    }

    private func normalizedChannels(_ channels: [EffectiveChannel]?) throws -> [EffectiveChannel]? {
        guard let channels else { return nil }
        var seen = Set<String>()
        var result: [EffectiveChannel] = []
        for channel in channels {
            let id = channel.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { throw LibraryAssetError.invalidPayload("an effective channel has no id") }
            if seen.insert(id).inserted { result.append(EffectiveChannel(id: id, role: channel.role)) }
        }
        return result.sorted { $0.id < $1.id }
    }

    // MARK: Context reads

    func sourceContext(_ db: LibraryAssetDatabase, sourceID: String) throws -> SourceContextRecord? {
        guard let row = try db.query("SELECT * FROM source_context WHERE source_id = ?;", [.text(sourceID)]).first else { return nil }
        return SourceContextRecord(
            sourceID: sourceID,
            workflowID: row.string("workflow_id"),
            workflowOrigin: ContextOrigin(rawValue: row.string("workflow_origin") ?? "") ?? .unknown,
            conditions: (try? decodeJSON([String: ContextConditionValue].self, row.string("conditions_json") ?? "{}")) ?? [:],
            measuredAt: row.string("measured_at"),
            measuredAtOrigin: ContextOrigin(rawValue: row.string("measured_at_origin") ?? "") ?? .unknown,
            sourceMTime: row.string("source_mtime"),
            legacyPath: row.string("legacy_path"),
            interpretation: (try? decodeJSON([String: String].self, row.string("interpretation_json") ?? "{}")) ?? [:],
            recordedAt: row.string("recorded_at") ?? ""
        )
    }

    func storedChannels(_ db: LibraryAssetDatabase, sourceID: String) throws -> [EffectiveChannel]? {
        guard let json = try db.query(
            "SELECT effective_channels_json FROM sample_asset_links WHERE asset_id = ?;", [.text(sourceID)]
        ).first?.string("effective_channels_json") else { return nil }
        return try decodeJSON([EffectiveChannel].self, json)
    }

    /// Read-only: the stored context (nil for a legacy Source without a context row).
    func sourceContext(sourceID: String, rootURL: URL) throws -> SourceContextRecord? {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return nil
        }
        return try sourceContext(db, sourceID: sourceID)
    }

    /// Read-only: confirmed effective channels (`nil` = unconfirmed, never "all").
    func effectiveChannels(sourceID: String, rootURL: URL) throws -> [EffectiveChannel]? {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return nil
        }
        return try storedChannels(db, sourceID: sourceID)
    }

    // MARK: Amendment

    private struct AmendOpPayload: Codable {
        var sourceID: String
        var requestHash: String
        var result: SourceAmendmentReceipt?
    }

    /// Turns unknown context into confirmed context (origin `manual`). Never overwrites a confirmed
    /// value, never touches the Source ID, bytes, hash or ownership, and never triggers anything else.
    @discardableResult
    func amendSourceContext(
        sourceID: String, operationID: String, changes: SourceContextAmendment, rootURL: URL
    ) throws -> SourceAmendmentReceipt {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        guard !changes.isEmpty else { throw LibraryAssetError.invalidPayload("the amendment changes nothing") }
        let channels = try normalizedChannels(changes.effectiveChannels)
        var normalized = changes
        normalized.effectiveChannels = channels
        let requestHash = try encodeJSON(AmendBinding(sourceID: sourceID, changes: normalized)).sha256Hex

        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(
            rootURL: rootURL, createIfMissing: false, upgrade: true, fileManager: fileManager
        ) else { throw LibraryAssetError.assetNotFound(sourceID) }
        _ = try recoverPending(db: db, rootURL: rootURL)

        if let existing = try operation(db, id: operationID) {
            guard existing.type == "amend_context" else { throw LibraryAssetError.operationKindMismatch(operationID) }
            let stored = try decodeJSON(AmendOpPayload.self, existing.payload)
            guard stored.requestHash == requestHash else { throw LibraryAssetError.operationRequestMismatch(operationID) }
            if existing.state == "committed", let result = stored.result { return result }
        }

        guard let record = try assetRecord(db, id: sourceID), record.kind == "source" else {
            throw LibraryAssetError.assetNotFound(sourceID)
        }
        guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(sourceID) }
        guard let owner = try sourceOwnership(db, sourceID: sourceID), !owner.isHistorical else {
            throw LibraryAssetError.ownershipViolation("source '\(sourceID)' has no active sample owner")
        }

        let current = try sourceContext(db, sourceID: sourceID)
        var changed: [String] = []
        var before: [String: String] = [:]

        var newWorkflow: String?
        if let workflow = normalized.workflowID {
            if let known = current?.workflowID, current?.workflowOrigin.isConfirmed == true {
                if known != workflow { throw LibraryAssetError.contextConflict("workflow is already confirmed as '\(known)'") }
            } else {
                newWorkflow = workflow
                changed.append("workflow")
                before["workflow"] = "unknown"
            }
        }
        var newConditions: [String: ContextConditionValue] = [:]
        for (key, value) in normalized.conditions.sorted(by: { $0.key < $1.key }) {
            if let known = current?.conditions[key], known.origin.isConfirmed {
                if known.value != value { throw LibraryAssetError.contextConflict("condition '\(key)' is already confirmed as '\(known.value)'") }
            } else {
                newConditions[key] = ContextConditionValue(value: value, origin: .manual)
                changed.append("condition:\(key)")
                before["condition:\(key)"] = "unknown"
            }
        }
        var newChannels: [EffectiveChannel]?
        if let channels {
            if let known = try storedChannels(db, sourceID: sourceID) {
                if Set(known) != Set(channels) { throw LibraryAssetError.contextConflict("effective channels are already confirmed") }
            } else {
                newChannels = channels
                changed.append("effectiveChannels")
                before["effectiveChannels"] = "unknown"
            }
        }
        var newMeasuredAt: String?
        if let measuredAt = normalized.measuredAt {
            if let known = current?.measuredAt, current?.measuredAtOrigin.isConfirmed == true {
                if known != measuredAt { throw LibraryAssetError.contextConflict("measurement time is already confirmed as '\(known)'") }
            } else {
                newMeasuredAt = measuredAt
                changed.append("measuredAt")
                before["measuredAt"] = "unknown"
            }
        }

        let result = SourceAmendmentReceipt(sourceID: sourceID, changedFields: changed)
        let payload = AmendOpPayload(sourceID: sourceID, requestHash: requestHash, result: result)
        let auditJSON = try encodeJSON(AmendAudit(changed: changed, before: before, request: normalized))
        try db.transaction {
            let now = Self.timestamp()
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            if current == nil {
                try insertSourceContext(db, sourceID: sourceID, context: .unknown, mtime: nil, now: now)
            }
            if let newWorkflow {
                try db.execute(
                    "UPDATE source_context SET workflow_id = ?, workflow_origin = 'manual' WHERE source_id = ?;",
                    [.text(newWorkflow), .text(sourceID)]
                )
            }
            if !newConditions.isEmpty {
                var merged = current?.conditions ?? [:]
                for (key, value) in newConditions { merged[key] = value }
                try db.execute(
                    "UPDATE source_context SET conditions_json = ? WHERE source_id = ?;",
                    [.text(try encodeJSON(merged)), .text(sourceID)]
                )
            }
            if let newMeasuredAt {
                try db.execute(
                    "UPDATE source_context SET measured_at = ?, measured_at_origin = 'manual' WHERE source_id = ?;",
                    [.text(newMeasuredAt), .text(sourceID)]
                )
            }
            if let newChannels {
                try db.execute(
                    "UPDATE sample_asset_links SET effective_channels_json = ? WHERE asset_id = ?;",
                    [.text(try encodeJSON(newChannels)), .text(sourceID)]
                )
            }
            try db.execute(
                "INSERT INTO context_amendment(source_id, operation_id, request_hash, changes_json, recorded_at) VALUES (?, ?, ?, ?, ?);",
                [.text(sourceID), .text(operationID), .text(requestHash), .text(auditJSON), .text(now)]
            )
            try insertOperation(db, id: operationID, type: "amend_context", state: "committed", payload: try encodeJSON(payload))
        }
        return result
    }

    private struct AmendBinding: Codable {
        let sourceID: String
        let changes: SourceContextAmendment
    }

    private struct AmendAudit: Codable {
        let changed: [String]
        let before: [String: String]
        let request: SourceContextAmendment
    }

    /// Number of audit rows for a Source (test and UI support).
    func contextAmendmentCount(sourceID: String, rootURL: URL) throws -> Int {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return 0
        }
        return Int(try db.query("SELECT COUNT(*) AS n FROM context_amendment WHERE source_id = ?;", [.text(sourceID)]).first?.int("n") ?? 0)
    }

    // MARK: Read-only data contract

    /// The read-only contract other steps use to get a stored Source: verified bytes or an error.
    func readSource(sourceID: String, rootURL: URL) throws -> SourceContent {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(sourceID)
        }
        return try readSource(db, sourceID: sourceID, rootURL: rootURL)
    }

    func readSource(_ db: LibraryAssetDatabase, sourceID: String, rootURL: URL) throws -> SourceContent {
        guard let source = try assetRecord(db, id: sourceID), source.kind == "source" else {
            throw LibraryAssetError.assetNotFound(sourceID)
        }
        guard source.status == "ready" else { throw LibraryAssetError.assetNotReady(sourceID) }
        guard let entry = source.files.first(where: { $0.name == "payload.bin" }) else {
            throw LibraryAssetError.sourceUnavailable("the stored copy has no payload")
        }
        let url = try storageURL(rootURL: rootURL, relativePath: source.storageRelPath + "/payload.bin")
        guard fileManager.fileExists(atPath: url.path) else { throw LibraryAssetError.sourceUnavailable("the stored copy is missing") }
        guard let data = try? Data(contentsOf: url) else { throw LibraryAssetError.sourceUnavailable("the stored copy is unreadable") }
        guard data.count == entry.size, AssetHashing.sha256Hex(data) == entry.sha256 else {
            throw LibraryAssetError.sourceUnavailable("the stored copy failed size/hash verification")
        }
        return SourceContent(sourceID: sourceID, originalFileName: source.originalFilename ?? "", bytes: data, sha256: entry.sha256)
    }

    // MARK: Recovery

    /// Rolls back an unfinished ingest: removes exactly the registered files and the staging row.
    func abortSourceIngest(db: LibraryAssetDatabase, operationID: String, payload: SourceIngestOpPayload, rootURL: URL) throws {
        var report = AssetRecoveryReport()
        if !payload.reusedSource {
            try removeRegisteredFiles(
                rootURL: rootURL, relativeDirectory: payload.sourceRelPath, names: payload.sourceFiles.map(\.name),
                removeWriterTemps: true, emptyDirectoryCandidates: [payload.sourceRelPath], report: &report
            )
        }
        try db.transaction {
            if !payload.reusedSource {
                try db.execute("DELETE FROM assets WHERE asset_id = ? AND status = 'staging';", [.text(payload.sourceID)])
            }
            try updateOperation(db, id: operationID, state: "aborted", payload: try encodeJSON(payload))
        }
        lastRecoveryReport.unknownResidue.append(contentsOf: report.unknownResidue)
    }
}

extension String {
    var sha256Hex: String { AssetHashing.sha256Hex(Data(utf8)) }

    var nilIfEmptyValue: String? { isEmpty ? nil : self }
}
