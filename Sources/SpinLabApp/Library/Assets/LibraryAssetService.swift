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
    /// The process write lease consulted by formal Plot commits; tests inject their own.
    var writeLease: LibraryWriteLease = .shared

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
        let storageRootURL = rootURL.appending(path: "storage", directoryHint: .isDirectory)
        let url = rootURL.appending(path: relativePath, directoryHint: .notDirectory)
        guard libraryStore.isPathContained(url, within: storageRootURL) else {
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

    struct IngestDatasetEntry: Codable {
        var datasetID: String
        var format: String
        var datasetRelPath: String
        var files: [AssetFileEntry]
        var signalLocatorJSON: String
    }

    struct IngestOpPayload: Codable {
        var sourceID: String
        var sourceRelPath: String
        var sourceFiles: [AssetFileEntry]
        var datasets: [IngestDatasetEntry]
        var reusedSource: Bool
        var sampleUID: String
        var result: AssetIngestResult?
    }

    func ingestAsset(
        sourceFileURL: URL,
        adapter: any AssetStandardizationAdapter,
        targetSampleUID: String,
        operationID: String,
        reuseSourceID: String? = nil,
        rootURL: URL
    ) throws -> AssetIngestResult {
        try requireV2(rootURL)
        let uid = targetSampleUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { throw LibraryAssetError.invalidSample("no target sample selected") }
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
                guard result.sampleUID == uid else {
                    throw LibraryAssetError.ownershipViolation(
                        "operation '\(operationID)' was already committed for sample '\(result.sampleUID)', cannot replay for '\(uid)'"
                    )
                }
                return result
            }
        }

        try validateSample(uid, rootURL: rootURL)
        let payload = try adapter.standardize(sourceFileURL: sourceFileURL)
        guard !payload.datasets.isEmpty else { throw LibraryAssetError.invalidPayload("standardized payload has no datasets") }
        for item in payload.datasets {
            try validateFileNames(item.content.files)
        }
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
            guard let owner = try sourceOwnership(db, sourceID: reuseSourceID) else {
                throw LibraryAssetError.ownershipViolation("source '\(reuseSourceID)' has no sample owner")
            }
            guard !owner.isHistorical else {
                throw LibraryAssetError.ownershipViolation("source '\(reuseSourceID)' belongs to a permanently deleted sample")
            }
            guard owner.sampleUID == uid else {
                throw LibraryAssetError.crossSampleReuseRejected(
                    "source '\(reuseSourceID)' belongs to sample '\(owner.sampleUID)', not '\(uid)'"
                )
            }
            reusedSource = record
        }

        let sourceID = reusedSource?.id ?? "src_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let sourceRel = "storage/\(sourceID)"

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

        var datasetItems: [(entry: IngestDatasetEntry, files: [StandardizedFile], byteSize: Int64)] = []
        for item in payload.datasets {
            let datasetID = "dst_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            let datasetRel = "storage/\(datasetID)/rev_1"
            let entries = item.content.files.map(AssetFileEntry.make)
            let byteSize = entries.reduce(Int64(0)) { $0 + Int64($1.size) }
            let locatorJSON = try encodeJSON(item.signalLocators)
            datasetItems.append((
                entry: IngestDatasetEntry(
                    datasetID: datasetID, format: item.content.format, datasetRelPath: datasetRel,
                    files: entries, signalLocatorJSON: locatorJSON
                ),
                files: item.content.files,
                byteSize: byteSize
            ))
        }

        var opPayload = IngestOpPayload(
            sourceID: sourceID, sourceRelPath: sourceRel, sourceFiles: sourceEntries,
            datasets: datasetItems.map(\.entry), reusedSource: reusedSource != nil,
            sampleUID: uid, result: nil
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
            for item in datasetItems {
                try insertAsset(
                    db, id: item.entry.datasetID, kind: "dataset", format: item.entry.format, status: "staging",
                    relPath: item.entry.datasetRelPath, revision: 1, sha256: AssetHashing.digest(of: item.entry.files),
                    byteSize: item.byteSize, originalFilename: nil, files: item.entry.files, now: now
                )
            }
        }

        if reusedSource == nil {
            try writeFiles(sourceFiles, toRelativeDirectory: sourceRel, rootURL: rootURL)
            try verifyFiles(sourceEntries, relativeDirectory: sourceRel, rootURL: rootURL)
        }
        try fault(.ingestAfterSourceWritten)
        for item in datasetItems {
            try writeFiles(item.files, toRelativeDirectory: item.entry.datasetRelPath, rootURL: rootURL)
            try verifyFiles(item.entry.files, relativeDirectory: item.entry.datasetRelPath, rootURL: rootURL)
        }
        try fault(.ingestBeforeCommit)

        let datasetIDs = datasetItems.map(\.entry.datasetID)
        let result = AssetIngestResult(
            sourceID: sourceID, datasetIDs: datasetIDs, sampleUID: uid, datasetRevision: 1,
            reusedSource: reusedSource != nil
        )
        opPayload.result = result

        // Transaction 2: the formal commit point.
        try db.transaction {
            let now = Self.timestamp()
            var idsToReady = datasetIDs
            if reusedSource == nil { idsToReady.append(sourceID) }
            let marks = Array(repeating: "?", count: idsToReady.count).joined(separator: ",")
            var params: [SQLValue] = [.text(now)]
            params.append(contentsOf: idsToReady.map { .text($0) })
            try db.execute(
                "UPDATE assets SET status = 'ready', updated_at = ? WHERE asset_id IN (\(marks)) AND status = 'staging';",
                params
            )
            for item in datasetItems {
                try db.execute(
                    "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, 'dataset_source', ?);",
                    [.text(item.entry.datasetID), .text(sourceID), .text(item.entry.signalLocatorJSON)]
                )
            }
            if reusedSource == nil {
                try db.execute(
                    "INSERT INTO sample_asset_links(asset_id, sample_uid, ownership_status, linked_at) VALUES (?, ?, 'active', ?);",
                    [.text(sourceID), .text(uid), .text(now)]
                )
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

    func sourceOwnership(_ db: LibraryAssetDatabase, sourceID: String) throws -> SourceOwnershipRecord? {
        guard let row = try db.query(
            "SELECT sample_uid, ownership_status FROM sample_asset_links WHERE asset_id = ?;", [.text(sourceID)]
        ).first, let uid = row.string("sample_uid") else { return nil }
        let status = row.string("ownership_status") ?? "active"
        return SourceOwnershipRecord(sampleUID: uid, isHistorical: status == "historical")
    }

    func sourceOwnership(sourceID: String, rootURL: URL) throws -> SourceOwnershipRecord? {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return nil
        }
        return try sourceOwnership(db, sourceID: sourceID)
    }

    func listSampleSourceGroups(forSampleUID sampleUID: String, rootURL: URL) throws -> [SampleSourceGroup] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        let sources = try db.query(
            """
            SELECT a.* FROM assets a
            JOIN sample_asset_links l ON l.asset_id = a.asset_id
            WHERE l.sample_uid = ? AND l.ownership_status = 'active' AND a.kind = 'source' AND a.status = 'ready'
            ORDER BY a.created_at, a.asset_id;
            """,
            [.text(sampleUID)]
        ).map(AssetRecord.init(row:))

        return try sources.map { source in
            let datasets = try db.query(
                """
                SELECT a.* FROM assets a
                JOIN asset_dependencies d ON d.consumer_asset_id = a.asset_id
                WHERE d.upstream_asset_id = ? AND d.dependency_kind = 'dataset_source' AND a.kind = 'dataset' AND a.status = 'ready'
                ORDER BY a.created_at, a.asset_id;
                """,
                [.text(source.id)]
            ).map(AssetRecord.init(row:))
            return SampleSourceGroup(source: source, datasets: datasets)
        }
    }

    func listAssets(forSampleUID sampleUID: String, rootURL: URL) throws -> [AssetRecord] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        let sources = try db.query(
            """
            SELECT a.* FROM assets a
            JOIN sample_asset_links l ON l.asset_id = a.asset_id
            WHERE l.sample_uid = ? AND l.ownership_status = 'active' AND a.kind = 'source' AND a.status = 'ready';
            """,
            [.text(sampleUID)]
        ).map(AssetRecord.init(row:))

        var byID: [String: AssetRecord] = [:]
        for source in sources { byID[source.id] = source }

        let sourceIDs = sources.map(\.id)
        var datasetIDs: [String] = []
        if !sourceIDs.isEmpty {
            let marks = Array(repeating: "?", count: sourceIDs.count).joined(separator: ",")
            let datasets = try db.query(
                """
                SELECT DISTINCT a.* FROM assets a
                JOIN asset_dependencies d ON d.consumer_asset_id = a.asset_id
                WHERE d.upstream_asset_id IN (\(marks)) AND d.dependency_kind = 'dataset_source'
                  AND a.kind = 'dataset' AND a.status = 'ready';
                """,
                sourceIDs.map { .text($0) }
            ).map(AssetRecord.init(row:))
            for dataset in datasets {
                byID[dataset.id] = dataset
                datasetIDs.append(dataset.id)
            }
        }

        let upstreamIDs = sourceIDs + datasetIDs
        if !upstreamIDs.isEmpty {
            let marks = Array(repeating: "?", count: upstreamIDs.count).joined(separator: ",")
            let derived = try db.query(
                """
                SELECT DISTINCT a.* FROM assets a
                JOIN asset_dependencies d ON d.consumer_asset_id = a.asset_id
                WHERE d.upstream_asset_id IN (\(marks)) AND d.dependency_kind IN ('live_input', 'snapshot_input')
                  AND a.status = 'ready';
                """,
                upstreamIDs.map { .text($0) }
            ).map(AssetRecord.init(row:))
            for item in derived { byID[item.id] = item }
        }

        let ordered = (try? db.query("SELECT asset_id FROM assets ORDER BY created_at, asset_id;").compactMap { $0.string("asset_id") }) ?? []
        let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
        return byID.values.sorted {
            let r0 = rank[$0.id] ?? Int.max
            let r1 = rank[$1.id] ?? Int.max
            if r0 != r1 { return r0 < r1 }
            return $0.id < $1.id
        }
    }

    /// Ready sources whose bytes hash to `sha256` and are actively owned by `ownedBySampleUID`
    /// (cross-sample reuse is forbidden).
    func findSources(sha256: String, ownedBySampleUID: String, rootURL: URL) throws -> [AssetRecord] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            return []
        }
        return try db.query(
            """
            SELECT a.* FROM assets a
            JOIN sample_asset_links l ON l.asset_id = a.asset_id
            WHERE a.kind = 'source' AND a.status = 'ready' AND a.sha256 = ?
              AND l.sample_uid = ? AND l.ownership_status = 'active'
            ORDER BY a.created_at;
            """,
            [.text(sha256), .text(ownedBySampleUID)]
        ).map(AssetRecord.init(row:))
    }

    /// Derives the active sample UID(s) associated with an asset through the ownership/dependency chain:
    /// Source → active owner, Dataset → Source → active owner, Plot/Snapshot → input Datasets → active owners.
    func derivedSampleUIDs(forAssetID assetID: String, rootURL: URL) throws -> [String] {
        try requireV2(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager),
              let record = try assetRecord(db, id: assetID) else {
            return []
        }
        switch record.kind {
        case "source":
            if let owner = try sourceOwnership(db, sourceID: assetID), !owner.isHistorical {
                return [owner.sampleUID]
            }
            return []
        case "dataset":
            let rows = try db.query(
                """
                SELECT l.sample_uid FROM asset_dependencies d
                JOIN sample_asset_links l ON l.asset_id = d.upstream_asset_id
                WHERE d.consumer_asset_id = ? AND d.dependency_kind = 'dataset_source' AND l.ownership_status = 'active';
                """,
                [.text(assetID)]
            )
            return rows.compactMap { $0.string("sample_uid") }.sorted()
        default:
            let rows = try db.query(
                """
                SELECT DISTINCT l.sample_uid FROM asset_dependencies d_plot
                JOIN asset_dependencies d_src ON d_src.consumer_asset_id = d_plot.upstream_asset_id AND d_src.dependency_kind = 'dataset_source'
                JOIN sample_asset_links l ON l.asset_id = d_src.upstream_asset_id
                WHERE d_plot.consumer_asset_id = ? AND d_plot.dependency_kind IN ('live_input', 'snapshot_input')
                  AND l.ownership_status = 'active'
                ORDER BY l.sample_uid;
                """,
                [.text(assetID)]
            )
            return rows.compactMap { $0.string("sample_uid") }
        }
    }

    // MARK: - Minimal Live Plot / Snapshot relation fixture (consumers arrive with task 6)

    /// Registers a file-less derived asset (`plot` / `snapshot`) with its dataset inputs.
    /// Sample associations are derived from `Dataset -> Source -> Sample` (K5), never persisted directly.
    @discardableResult
    func registerDerivedAsset(
        kind: String, inputAssetIDs: [String], rootURL: URL
    ) throws -> String {
        guard kind == "plot" || kind == "snapshot" else { throw LibraryAssetError.invalidPayload("unsupported derived kind '\(kind)'") }
        guard !inputAssetIDs.isEmpty else { throw LibraryAssetError.invalidPayload("derived asset requires at least one input") }
        try requireV2(rootURL)
        try requireWritable(rootURL)
        Self.commitLock.lock()
        defer { Self.commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false, fileManager: fileManager) else {
            throw LibraryAssetError.assetNotFound(inputAssetIDs.first ?? "")
        }
        _ = try recoverPending(db: db, rootURL: rootURL)
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
            var hasActiveSample = false
            for input in Set(inputAssetIDs).sorted() {
                guard let record = try assetRecord(db, id: input), record.status == "ready" else {
                    throw LibraryAssetError.assetNotFound(input)
                }
                guard record.kind == "dataset" else {
                    throw LibraryAssetError.ownershipViolation("derived asset '\(kind)' input '\(input)' must be a dataset, not '\(record.kind)'")
                }
                let activeOwners = try db.query(
                    """
                    SELECT 1 FROM asset_dependencies d
                    JOIN sample_asset_links l ON l.asset_id = d.upstream_asset_id
                    WHERE d.consumer_asset_id = ? AND d.dependency_kind = 'dataset_source' AND l.ownership_status = 'active'
                    LIMIT 1;
                    """,
                    [.text(input)]
                )
                if !activeOwners.isEmpty { hasActiveSample = true }
                try db.execute(
                    "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, ?, NULL);",
                    [.text(id), .text(input), .text(dependencyKind)]
                )
            }
            guard hasActiveSample else {
                throw LibraryAssetError.ownershipViolation("derived asset '\(kind)' requires at least one dataset with an active sample owner")
            }
        }
        return id
    }

    // MARK: - Reference gate for legacy entry points

    /// Number of active owned sources of a sample. Throws (fail-closed) when the asset database
    /// cannot be trusted or an unfinished operation exists.
    static func linkedAssetCount(sampleUID: String, rootURL: URL) throws -> Int {
        commitLock.lock()
        defer { commitLock.unlock() }
        guard let db = try LibraryAssetDatabase.open(rootURL: rootURL, createIfMissing: false) else { return 0 }
        let pending = try db.query("SELECT COUNT(*) AS n FROM asset_operations WHERE state = 'pending';").first?.int("n") ?? 0
        if pending > 0 { throw LibraryAssetError.pendingOperations(Int(pending)) }
        return Int(try db.query(
            "SELECT COUNT(*) AS n FROM sample_asset_links WHERE sample_uid = ? AND ownership_status = 'active';", [.text(sampleUID)]
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
