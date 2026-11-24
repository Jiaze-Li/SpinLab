import Darwin
import Foundation

/// Workflow-neutral owner of Source / Dataset assets in a Storage v2 library: identity, sample
/// links, payload registration, revisions, reference-safe deletion and crash recovery.
///
/// Authority: SQLite (`_spinlab/library.sqlite`) owns relations and registration; the file system
/// owns bulk content. Every cross-system change persists an operation record first, so a crash
/// at any boundary is recovered (completed or rolled back) the next time the library is used.
///
/// All mutating entry points run inside one process-wide critical section. Single-writer
/// (task 3) makes this sufficient; it is not cross-process coordination.
final class LibraryAssetService: @unchecked Sendable {
    static let commitLock = NSRecursiveLock()

    let libraryStore: LibraryStore
    let fileManager: FileManager
    /// Test hook: a thrown error behaves like a crash at that point.
    var faultHook: ((AssetFaultPoint) throws -> Void)?
    var lastRecoveryReport = AssetRecoveryReport()

    init(libraryStore: LibraryStore = LibraryStore(), fileManager: FileManager = .default) {
        self.libraryStore = libraryStore
        self.fileManager = fileManager
    }

    // MARK: - Shared helpers

    func fault(_ point: AssetFaultPoint) throws {
        try faultHook?(point)
    }

    func requireV2(_ rootURL: URL) throws {
        switch LibraryLayoutRouter.resolve(rootURL: rootURL, fileManager: fileManager) {
        case .v2: return
        case let .invalid(error): throw error
        case .v1, .uninitialized: throw LibraryAssetError.v2Required
        }
    }

    func requireWritable(_ rootURL: URL) throws {
        try LibraryWriteLease.shared.ensureWritable(LibraryAssetDatabase.databaseURL(rootURL: rootURL))
    }

    static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LibraryAssetError.invalidPayload("JSON is not valid UTF-8")
        }
        return text
    }

    func decodeJSON<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(text.utf8))
        } catch {
            throw LibraryAssetError.databaseCorrupt("operation payload is unreadable: \(error.localizedDescription)")
        }
    }

    /// Resolves a registered relative path, which must live strictly inside `storage/`.
    func storageURL(rootURL: URL, relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2, components[0] == "storage",
              !relativePath.hasPrefix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw LibraryAssetError.unsafePath(relativePath)
        }
        let url = rootURL.appending(path: relativePath, directoryHint: .notDirectory)
        let storageRoot = rootURL.appending(path: "storage", directoryHint: .isDirectory)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(storageRoot + "/") else {
            throw LibraryAssetError.unsafePath(relativePath)
        }
        return url
    }

    func validateFileName(_ name: String) throws {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."), name != "..", name.utf8.count < 200 else {
            throw LibraryAssetError.invalidPayload("illegal file name '\(name)'")
        }
    }

    func validateFileNames(_ files: [StandardizedFile]) throws {
        guard !files.isEmpty else { throw LibraryAssetError.invalidPayload("dataset has no files") }
        var seen = Set<String>()
        for file in files {
            try validateFileName(file.name)
            guard seen.insert(file.name).inserted else {
                throw LibraryAssetError.invalidPayload("duplicate file name '\(file.name)'")
            }
        }
    }

    func writeFiles(_ files: [StandardizedFile], toRelativeDirectory relDir: String, rootURL: URL) throws {
        let writer = AtomicFileWriter(fileManager: fileManager)
        var entries: [AtomicWriteEntry] = []
        for file in files {
            let url = try storageURL(rootURL: rootURL, relativePath: relDir + "/" + file.name)
            entries.append(AtomicWriteEntry(destinationURL: url, data: file.data))
        }
        try writer.commit(entries)
    }

    /// Reads back every registered file; size and hash must match.
    func verifyFiles(_ entries: [AssetFileEntry], relativeDirectory relDir: String, rootURL: URL) throws {
        for entry in entries {
            let url = try storageURL(rootURL: rootURL, relativePath: relDir + "/" + entry.name)
            guard let data = try? Data(contentsOf: url) else {
                throw LibraryAssetError.datasetCorrupt("file '\(entry.name)' is missing or unreadable")
            }
            guard data.count == entry.size, AssetHashing.sha256Hex(data) == entry.sha256 else {
                throw LibraryAssetError.datasetCorrupt("file '\(entry.name)' failed size/hash verification")
            }
        }
    }

    /// Removes exactly the registered files in a directory (plus, for operation-owned fresh
    /// directories, the writer's own temp files), then removes the listed directories only when
    /// they are empty. Unknown leftovers are reported, never deleted.
    func removeRegisteredFiles(
        rootURL: URL,
        relativeDirectory relDir: String,
        names: [String],
        removeWriterTemps: Bool,
        emptyDirectoryCandidates: [String],
        report: inout AssetRecoveryReport
    ) throws {
        guard !relDir.isEmpty else { return }
        let dirURL = try storageURL(rootURL: rootURL, relativePath: relDir)
        for name in names {
            try validateFileName(name)
            let fileURL = dirURL.appending(path: name, directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: fileURL.path) {
                do { try fileManager.removeItem(at: fileURL) } catch {
                    throw LibraryAssetError.cleanupFailed("\(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        if removeWriterTemps, let entries = try? fileManager.contentsOfDirectory(atPath: dirURL.path) {
            for entry in entries where entry.hasPrefix(".spinlab-tmp-") {
                try? fileManager.removeItem(at: dirURL.appending(path: entry, directoryHint: .notDirectory))
            }
        }
        for candidate in emptyDirectoryCandidates {
            let url = try storageURL(rootURL: rootURL, relativePath: candidate)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let remaining = ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? ["?"]).filter { $0 != ".DS_Store" }
            if remaining.isEmpty {
                try? fileManager.removeItem(at: url)
            } else {
                report.unknownResidue.append(candidate)
            }
        }
    }

    func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw LibraryAssetError.cleanupFailed("cannot open \(url.lastPathComponent)") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw LibraryAssetError.cleanupFailed("fsync failed for \(url.lastPathComponent)") }
    }

    // MARK: - Operation records

    struct OperationRow {
        let id: String
        let type: String
        let state: String
        let payload: String
    }

    func operation(_ db: LibraryAssetDatabase, id: String) throws -> OperationRow? {
        guard let row = try db.query(
            "SELECT operation_id, op_type, state, payload_json FROM asset_operations WHERE operation_id = ?;", [.text(id)]
        ).first else { return nil }
        return OperationRow(
            id: id, type: row.string("op_type") ?? "", state: row.string("state") ?? "", payload: row.string("payload_json") ?? "{}"
        )
    }

    func insertOperation(_ db: LibraryAssetDatabase, id: String, type: String, state: String, payload: String) throws {
        let now = Self.timestamp()
        try db.execute(
            "INSERT INTO asset_operations(operation_id, op_type, state, payload_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);",
            [.text(id), .text(type), .text(state), .text(payload), .text(now), .text(now)]
        )
    }

    func updateOperation(_ db: LibraryAssetDatabase, id: String, state: String, payload: String) throws {
        try db.execute(
            "UPDATE asset_operations SET state = ?, payload_json = ?, updated_at = ? WHERE operation_id = ?;",
            [.text(state), .text(payload), .text(Self.timestamp()), .text(id)]
        )
    }

    // MARK: - Sample validation

    func validateTargets(_ uids: [String], rootURL: URL) throws {
        for uid in uids {
            try validateSample(uid, rootURL: rootURL)
        }
    }

    func validateSample(_ uid: String, rootURL: URL) throws {
        guard SampleIdentityRule.isValidUID(uid) else {
            throw LibraryAssetError.invalidSample("'\(uid)' is not a valid sample UID")
        }
        let sampleJSON = libraryStore.v2SampleDirectoryURL(rootURL, sampleUID: uid).appending(path: "sample.json")
        guard fileManager.fileExists(atPath: sampleJSON.path), let sample = libraryStore.decodeSample(from: sampleJSON) else {
            throw LibraryAssetError.invalidSample("sample '\(uid)' record is missing or unreadable")
        }
        guard (sample.sampleUID ?? sample.id) == uid else {
            throw LibraryAssetError.invalidSample("sample '\(uid)' record carries a different UID")
        }
        guard !sample.isTrashed else {
            throw LibraryAssetError.invalidSample("sample '\(uid)' is in the Trash")
        }
    }

    // MARK: - Ingest

    private struct SourceManifest: Codable {
        let format: String
        let originalFileName: String
        let originalSourcePath: String?
        let byteSize: Int
        let sha256: String
        let ingestedAt: String
    }

    struct IngestOpPayload: Codable {
        var sourceID: String
        var datasetID: String
        var sourceRelPath: String
        var datasetRelPath: String
        var sourceFiles: [AssetFileEntry]
        var datasetFiles: [AssetFileEntry]
        var reusedSource: Bool
        var sampleUIDs: [String]
        var result: AssetIngestResult?
    }

    func ingestAsset(
        sourceFileURL: URL,
        adapter: any AssetStandardizationAdapter,
        targetSampleUIDs: [String],
        operationID: String,
        reuseSourceID: String? = nil,
        rootURL: URL
    ) throws -> AssetIngestResult {
        try requireV2(rootURL)
        var uids: [String] = []
        for uid in targetSampleUIDs where !uids.contains(uid) { uids.append(uid) }
        guard !uids.isEmpty else { throw LibraryAssetError.invalidSample("no target sample selected") }
        try requireWritable(rootURL)

        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }

        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: true, fileManager: fileManager) else {
            throw LibraryAssetError.databaseCorrupt("asset database could not be created")
        }
        _ = try recoverPending(db: db, rootURL: rootURL)

        if let existing = try operation(db, id: operationID) {
            guard existing.type == "ingest" else { throw LibraryAssetError.operationKindMismatch(operationID) }
            if existing.state == "committed", let result = try decodeJSON(IngestOpPayload.self, existing.payload).result {
                return result
            }
        }

        try validateTargets(uids, rootURL: rootURL)
        let payload = try adapter.standardize(sourceFileURL: sourceFileURL)
        try validateFileNames(payload.dataset.files)
        guard !payload.sourceBytes.isEmpty else { throw LibraryAssetError.invalidPayload("source file is empty") }

        let sourceSHA = AssetHashing.sha256Hex(payload.sourceBytes)
        var reusedSource: AssetRecord?
        if let reuseSourceID {
            guard let record = try assetRecord(db, id: reuseSourceID), record.kind == "source" else {
                throw LibraryAssetError.assetNotFound(reuseSourceID)
            }
            guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(reuseSourceID) }
            guard record.sha256 == sourceSHA else {
                throw LibraryAssetError.sourceMismatch("content hash differs from '\(reuseSourceID)'")
            }
            reusedSource = record
        }

        let sourceID = reusedSource?.id ?? "src_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let datasetID = "dst_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let sourceRel = "storage/\(sourceID)"
        let datasetRel = "storage/\(datasetID)/rev_1"

        let sourceManifest = SourceManifest(
            format: payload.sourceFormat, originalFileName: payload.originalFileName,
            originalSourcePath: payload.originalSourcePath, byteSize: payload.sourceBytes.count,
            sha256: sourceSHA, ingestedAt: Self.timestamp()
        )
        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sourceFiles = [
            StandardizedFile(name: "payload.bin", data: payload.sourceBytes),
            StandardizedFile(name: "manifest.json", data: try manifestEncoder.encode(sourceManifest))
        ]
        let sourceEntries = sourceFiles.map(AssetFileEntry.make)
        let datasetEntries = payload.dataset.files.map(AssetFileEntry.make)
        let datasetByteSize = datasetEntries.reduce(Int64(0)) { $0 + Int64($1.size) }
        let locatorJSON = try encodeJSON(payload.signalLocators)

        var opPayload = IngestOpPayload(
            sourceID: sourceID, datasetID: datasetID, sourceRelPath: sourceRel, datasetRelPath: datasetRel,
            sourceFiles: sourceEntries, datasetFiles: datasetEntries, reusedSource: reusedSource != nil,
            sampleUIDs: uids, result: nil
        )

        // Transaction 1: persist the recovery intent and staging rows before touching files.
        try db.transaction {
            try db.execute("DELETE FROM asset_operations WHERE operation_id = ? AND state = 'aborted';", [.text(operationID)])
            try insertOperation(db, id: operationID, type: "ingest", state: "pending", payload: try encodeJSON(opPayload))
            let now = Self.timestamp()
            if reusedSource == nil {
                try insertAsset(
                    db, id: sourceID, kind: "source", format: payload.sourceFormat, status: "staging",
                    relPath: sourceRel, revision: 1, sha256: sourceSHA, byteSize: Int64(payload.sourceBytes.count),
                    originalFilename: payload.originalFileName, files: sourceEntries, now: now
                )
            }
            try insertAsset(
                db, id: datasetID, kind: "dataset", format: payload.dataset.format, status: "staging",
                relPath: datasetRel, revision: 1, sha256: AssetHashing.digest(of: datasetEntries),
                byteSize: datasetByteSize, originalFilename: nil, files: datasetEntries, now: now
            )
        }

        if reusedSource == nil {
            try writeFiles(sourceFiles, toRelativeDirectory: sourceRel, rootURL: rootURL)
            try verifyFiles(sourceEntries, relativeDirectory: sourceRel, rootURL: rootURL)
        }
        try fault(.ingestAfterSourceWritten)
        try writeFiles(payload.dataset.files, toRelativeDirectory: datasetRel, rootURL: rootURL)
        try verifyFiles(datasetEntries, relativeDirectory: datasetRel, rootURL: rootURL)
        try fault(.ingestBeforeCommit)

        let result = AssetIngestResult(
            sourceID: sourceID, datasetID: datasetID, sampleUIDs: uids, datasetRevision: 1,
            reusedSource: reusedSource != nil
        )
        opPayload.result = result

        // Transaction 2: the formal commit point.
        try db.transaction {
            let now = Self.timestamp()
            try db.execute(
                "UPDATE assets SET status = 'ready', updated_at = ? WHERE asset_id IN (?, ?) AND status = 'staging';",
                [.text(now), .text(sourceID), .text(datasetID)]
            )
            try db.execute(
                "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, 'dataset_source', ?);",
                [.text(datasetID), .text(sourceID), .text(locatorJSON)]
            )
            for uid in uids {
                for assetID in [sourceID, datasetID] {
                    try db.execute(
                        "INSERT OR IGNORE INTO sample_asset_links(sample_uid, asset_id, role, linked_at) VALUES (?, ?, 'primary', ?);",
                        [.text(uid), .text(assetID), .text(now)]
                    )
                }
            }
            try updateOperation(db, id: operationID, state: "committed", payload: try encodeJSON(opPayload))
        }
        return result
    }

    func insertAsset(
        _ db: LibraryAssetDatabase, id: String, kind: String, format: String, status: String,
        relPath: String, revision: Int, sha256: String?, byteSize: Int64?, originalFilename: String?,
        liveState: String? = nil, files: [AssetFileEntry], now: String
    ) throws {
        try db.execute(
            """
            INSERT INTO assets(asset_id, kind, format, status, storage_rel_path, current_revision, sha256, byte_size,
                               original_filename, live_state, error_message, files_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?);
            """,
            [
                .text(id), .text(kind), .text(format), .text(status), .text(relPath), .int(Int64(revision)),
                .optionalText(sha256), .optionalInt(byteSize), .optionalText(originalFilename),
                .optionalText(liveState), .text(AssetFileEntry.encodeList(files)), .text(now), .text(now)
            ]
        )
    }

    func assetRecord(_ db: LibraryAssetDatabase, id: String) throws -> AssetRecord? {
        try db.query("SELECT * FROM assets WHERE asset_id = ?;", [.text(id)]).first.map(AssetRecord.init(row:))
    }

    // MARK: - Reading

    func loadDataset<Codec: DatasetPayloadCodec>(
        datasetID: String, codec: Codec, rootURL: URL
    ) throws -> LoadedDataset<Codec.Dataset> {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager),
              let record = try assetRecord(db, id: datasetID), record.kind == "dataset" else {
            throw LibraryAssetError.assetNotFound(datasetID)
        }
        guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(datasetID) }
        guard record.format == codec.datasetFormat else {
            throw LibraryAssetError.invalidPayload("dataset format '\(record.format)' is not '\(codec.datasetFormat)'")
        }
        try verifyFiles(record.files, relativeDirectory: record.storageRelPath, rootURL: rootURL)
        var files: [String: Data] = [:]
        for entry in record.files {
            let url = try storageURL(rootURL: rootURL, relativePath: record.storageRelPath + "/" + entry.name)
            files[entry.name] = try Data(contentsOf: url)
        }
        let dataset: Codec.Dataset
        do {
            dataset = try codec.decode(files: files)
        } catch {
            throw LibraryAssetError.datasetCorrupt("\(error)")
        }
        return LoadedDataset(
            datasetID: datasetID, revision: record.currentRevision, dataset: dataset,
            sourceAvailability: try sourceAvailability(db, datasetID: datasetID, rootURL: rootURL)
        )
    }

    private func sourceAvailability(_ db: LibraryAssetDatabase, datasetID: String, rootURL: URL) throws -> SourceAvailability {
        guard let upstreamID = try db.query(
            "SELECT upstream_asset_id FROM asset_dependencies WHERE consumer_asset_id = ? AND dependency_kind = 'dataset_source';",
            [.text(datasetID)]
        ).first?.string("upstream_asset_id"), let source = try assetRecord(db, id: upstreamID) else {
            return .missing
        }
        guard source.status == "ready" else { return .missing }
        guard let payloadEntry = source.files.first(where: { $0.name == "payload.bin" }),
              let url = try? storageURL(rootURL: rootURL, relativePath: source.storageRelPath + "/payload.bin"),
              fileManager.fileExists(atPath: url.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: url) else { return .corrupt("source payload is unreadable") }
        guard data.count == payloadEntry.size, AssetHashing.sha256Hex(data) == payloadEntry.sha256 else {
            return .corrupt("source payload failed size/hash verification")
        }
        return .available
    }

    func listAssets(forSampleUID sampleUID: String, rootURL: URL) throws -> [AssetRecord] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        return try db.query(
            """
            SELECT a.* FROM assets a JOIN sample_asset_links l ON l.asset_id = a.asset_id
            WHERE l.sample_uid = ? AND a.status = 'ready' ORDER BY a.created_at, a.asset_id;
            """,
            [.text(sampleUID)]
        ).map(AssetRecord.init(row:))
    }

    /// Ready sources whose bytes hash to `sha256`; used to prompt "reuse existing asset?" before an import.
    func findSources(sha256: String, rootURL: URL) throws -> [AssetRecord] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        return try db.query(
            "SELECT * FROM assets WHERE kind = 'source' AND status = 'ready' AND sha256 = ? ORDER BY created_at;", [.text(sha256)]
        ).map(AssetRecord.init(row:))
    }

    func linkedSampleUIDs(assetID: String, rootURL: URL) throws -> [String] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        return try db.query(
            "SELECT sample_uid FROM sample_asset_links WHERE asset_id = ? ORDER BY sample_uid;", [.text(assetID)]
        ).compactMap { $0.string("sample_uid") }
    }

    // MARK: - Link / unlink

    func linkAsset(assetID: String, toSampleUID sampleUID: String, rootURL: URL) throws {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(assetID)
        }
        _ = try recoverPending(db: db, rootURL: rootURL)
        try validateSample(sampleUID, rootURL: rootURL)
        try db.transaction {
            guard let record = try assetRecord(db, id: assetID) else { throw LibraryAssetError.assetNotFound(assetID) }
            guard record.status == "ready" else { throw LibraryAssetError.assetNotReady(assetID) }
            try db.execute(
                "INSERT OR IGNORE INTO sample_asset_links(sample_uid, asset_id, role, linked_at) VALUES (?, ?, 'primary', ?);",
                [.text(sampleUID), .text(assetID), .text(Self.timestamp())]
            )
        }
    }

    /// Removes only the relation (K6); the asset and its files stay.
    func unlinkAsset(assetID: String, fromSampleUID sampleUID: String, rootURL: URL) throws {
        try requireV2(rootURL)
        try requireWritable(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return
        }
        _ = try recoverPending(db: db, rootURL: rootURL)
        try db.transaction {
            try db.execute(
                "DELETE FROM sample_asset_links WHERE sample_uid = ? AND asset_id = ?;", [.text(sampleUID), .text(assetID)]
            )
        }
    }

    // MARK: - Minimal Live Plot / Snapshot relation fixture (consumers arrive with task 6)

    /// Registers a file-less derived asset (`plot` / `snapshot`) with its inputs and sample links.
    /// This is only the relation model the deletion/revision contracts need; it writes no plot content.
    @discardableResult
    func registerDerivedAsset(
        kind: String, inputAssetIDs: [String], sampleUIDs: [String], rootURL: URL
    ) throws -> String {
        guard kind == "plot" || kind == "snapshot" else { throw LibraryAssetError.invalidPayload("unsupported derived kind '\(kind)'") }
        try requireV2(rootURL)
        try requireWritable(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(inputAssetIDs.first ?? "")
        }
        _ = try recoverPending(db: db, rootURL: rootURL)
        try validateTargets(sampleUIDs, rootURL: rootURL)
        let prefix = kind == "plot" ? "plt_" : "snp_"
        let id = prefix + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let dependencyKind = kind == "plot" ? "live_input" : "snapshot_input"
        try db.transaction {
            let now = Self.timestamp()
            try insertAsset(
                db, id: id, kind: kind, format: "relation_only_v1", status: "ready", relPath: "storage/\(id)",
                revision: 1, sha256: nil, byteSize: nil, originalFilename: nil,
                liveState: kind == "plot" ? "current" : nil, files: [], now: now
            )
            for input in inputAssetIDs {
                guard let record = try assetRecord(db, id: input), record.status == "ready" else {
                    throw LibraryAssetError.assetNotFound(input)
                }
                try db.execute(
                    "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, ?, NULL);",
                    [.text(id), .text(input), .text(dependencyKind)]
                )
            }
            for uid in sampleUIDs {
                try db.execute(
                    "INSERT OR IGNORE INTO sample_asset_links(sample_uid, asset_id, role, linked_at) VALUES (?, ?, 'primary', ?);",
                    [.text(uid), .text(id), .text(now)]
                )
            }
        }
        return id
    }

    // MARK: - Reference gate for legacy entry points

    /// Number of asset links of a sample. Throws (fail-closed) when the asset database cannot be
    /// trusted or an unfinished operation exists.
    static func linkedAssetCount(sampleUID: String, rootURL: URL) throws -> Int {
        commitLock.lock()
        defer { commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false) else { return 0 }
        let pending = try db.query("SELECT COUNT(*) AS n FROM asset_operations WHERE state = 'pending';").first?.int("n") ?? 0
        if pending > 0 { throw LibraryAssetError.pendingOperations(Int(pending)) }
        return Int(try db.query(
            "SELECT COUNT(*) AS n FROM sample_asset_links WHERE sample_uid = ?;", [.text(sampleUID)]
        ).first?.int("n") ?? 0)
    }

    /// Guard for the pre-asset permanent-delete entry point: refuses whenever deleting the sample
    /// record could bypass the reference-closure plan.
    static func requireNoAssetReferences(sampleUID: String, rootURL: URL) throws {
        if try linkedAssetCount(sampleUID: sampleUID, rootURL: rootURL) > 0 {
            throw LibraryAssetError.deletionPlanRequired(sampleUID)
        }
    }
}
