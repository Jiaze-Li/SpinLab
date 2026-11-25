import Foundation
import SQLite3

/// Failures of the shared asset store. Every case is fail-closed (K13): none of them is ever
/// treated as "empty library".
enum LibraryAssetError: LocalizedError, Equatable {
    case v2Required
    case databaseRelationsLost
    case databaseCorrupt(String)
    case databaseUnknownVersion(String)
    case sqlite(String)
    case invalidSample(String)
    case assetNotFound(String)
    case assetNotReady(String)
    case invalidPayload(String)
    case unsafePath(String)
    case staleRevision(datasetID: String, expected: Int, current: Int)
    case operationKindMismatch(String)
    case datasetCorrupt(String)
    case sourceMismatch(String)
    case crossSampleReuseRejected(String)
    case ownershipViolation(String)
    case planChanged
    case sampleNotTrashed(String)
    case pendingOperations(Int)
    case deletionPlanRequired(String)
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .v2Required:
            return "Shared asset storage requires a Storage v2 library."
        case .databaseRelationsLost:
            return "'_spinlab/library.sqlite' is missing but 'storage/' is not empty. Refusing to rebuild an empty asset database (fail-closed)."
        case let .databaseCorrupt(reason):
            return "Asset database is corrupt or incomplete: \(reason). Refusing write (fail-closed)."
        case let .databaseUnknownVersion(version):
            return "Asset database schema version '\(version)' is not supported. Refusing write (fail-closed)."
        case let .sqlite(message):
            return "Asset database error: \(message)"
        case let .invalidSample(reason):
            return "Invalid target sample: \(reason)"
        case let .assetNotFound(id):
            return "Asset '\(id)' was not found."
        case let .assetNotReady(id):
            return "Asset '\(id)' is not ready."
        case let .invalidPayload(reason):
            return "Invalid standardized payload: \(reason)"
        case let .unsafePath(path):
            return "Refused unsafe asset path '\(path)'."
        case let .staleRevision(datasetID, expected, current):
            return "Dataset '\(datasetID)' revision is \(current), not the expected \(expected). The stale correction was rejected."
        case let .operationKindMismatch(id):
            return "Operation '\(id)' was already used for a different kind of operation."
        case let .datasetCorrupt(reason):
            return "Dataset content is corrupt or incomplete: \(reason)"
        case let .sourceMismatch(reason):
            return "Reused source does not match the new file: \(reason)"
        case let .crossSampleReuseRejected(reason):
            return "Cross-sample source reuse is forbidden: \(reason)"
        case let .ownershipViolation(reason):
            return "Research ownership constraint violated: \(reason)"
        case .planChanged:
            return "Asset links or dependencies changed since the deletion plan was made. Re-confirm the plan."
        case let .sampleNotTrashed(uid):
            return "Sample '\(uid)' must be in the Trash before permanent deletion."
        case let .pendingOperations(count):
            return "\(count) unfinished asset operation(s) must be recovered before this action."
        case let .deletionPlanRequired(uid):
            return "Sample '\(uid)' still has registered assets. Permanent deletion must go through the asset deletion plan."
        case let .cleanupFailed(reason):
            return "Asset cleanup stopped and can be retried: \(reason)"
        }
    }
}

enum SQLValue: Equatable, Sendable {
    case text(String)
    case int(Int64)
    case null

    static func optionalText(_ value: String?) -> SQLValue {
        value.map { .text($0) } ?? .null
    }

    static func optionalInt(_ value: Int64?) -> SQLValue {
        value.map { .int($0) } ?? .null
    }
}

struct SQLRow: Sendable {
    let values: [String: SQLValue]

    func string(_ column: String) -> String? {
        if case let .text(value)? = values[column] { return value }
        return nil
    }

    func int(_ column: String) -> Int64? {
        if case let .int(value)? = values[column] { return value }
        return nil
    }
}

/// Thin wrapper over the system SQLite3 library. One connection per instance; callers never
/// share an instance across threads.
final class LibraryAssetDatabase {
    static let schemaVersion = "2"
    static let requiredTables = ["schema_meta", "assets", "sample_asset_links", "asset_dependencies", "asset_operations"]

    let url: URL
    private var handle: OpaquePointer?

    static func databaseURL(rootURL: URL) -> URL {
        rootURL.appending(path: "_spinlab/library.sqlite", directoryHint: .notDirectory)
    }

    private init(url: URL, create: Bool, useWAL: Bool) throws {
        self.url = url
        var flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if create { flags |= SQLITE_OPEN_CREATE }
        var opened: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &opened, flags, nil)
        guard code == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed (\(code))"
            if let opened { sqlite3_close(opened) }
            throw LibraryAssetError.databaseCorrupt("cannot open database: \(message)")
        }
        handle = opened
        sqlite3_busy_timeout(opened, 5000)
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA synchronous = FULL;")
        if useWAL {
            _ = try query("PRAGMA journal_mode = WAL;")
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    // MARK: - Opening and the K13 matrix

    /// Opens (and, when `createIfMissing`, initializes) the asset database of a V2 library.
    /// Returns nil only when the asset library has never been enabled and creation was not asked for.
    static func open(rootURL: URL, createIfMissing: Bool, fileManager: FileManager = .default) throws -> LibraryAssetDatabase? {
        let dbURL = databaseURL(rootURL: rootURL)
        if !fileManager.fileExists(atPath: dbURL.path) {
            if try storageHasEntries(rootURL: rootURL, fileManager: fileManager) {
                throw LibraryAssetError.databaseRelationsLost
            }
            guard createIfMissing else { return nil }
            try initialize(at: dbURL, fileManager: fileManager)
        }
        let database = try LibraryAssetDatabase(url: dbURL, create: false, useWAL: true)
        try database.validate()
        return database
    }

    private static func storageHasEntries(rootURL: URL, fileManager: FileManager) throws -> Bool {
        let storageURL = rootURL.appending(path: "storage", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: storageURL.path, isDirectory: &isDirectory) else { return false }
        guard isDirectory.boolValue else {
            throw LibraryAssetError.databaseCorrupt("'storage' is not a directory")
        }
        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: storageURL.path)
        } catch {
            throw LibraryAssetError.databaseCorrupt("'storage/' cannot be read: \(error.localizedDescription)")
        }
        return entries.contains { $0 != ".DS_Store" }
    }

    /// Builds the schema in a side file and renames it into place, so a crash can never leave a
    /// half-initialized `library.sqlite` that later looks like corruption.
    private static func initialize(at dbURL: URL, fileManager: FileManager) throws {
        try LibraryWriteLease.shared.ensureWritable(dbURL)
        try fileManager.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempURL = dbURL.deletingLastPathComponent()
            .appending(path: ".library.sqlite.init-\(UUID().uuidString)", directoryHint: .notDirectory)
        defer { try? fileManager.removeItem(at: tempURL) }
        do {
            let database = try LibraryAssetDatabase(url: tempURL, create: true, useWAL: false)
            try database.transaction {
                for statement in schemaStatements { try database.execute(statement) }
                try database.execute(
                    "INSERT INTO schema_meta(key, value) VALUES ('schema_version', ?), ('layout_version', '2');",
                    [.text(schemaVersion)]
                )
            }
        }
        try fileManager.moveItem(at: tempURL, to: dbURL)
    }

    private func validate() throws {
        let check: [SQLRow]
        do {
            check = try query("PRAGMA quick_check;")
        } catch {
            throw LibraryAssetError.databaseCorrupt("quick_check failed: \(error.localizedDescription)")
        }
        guard check.count == 1, case let .text(result)? = check.first?.values.values.first, result == "ok" else {
            throw LibraryAssetError.databaseCorrupt("quick_check did not return ok")
        }
        let tables = Set(try query("SELECT name FROM sqlite_master WHERE type = 'table';").compactMap { $0.string("name") })
        let missing = Self.requiredTables.filter { !tables.contains($0) }
        guard missing.isEmpty else {
            throw LibraryAssetError.databaseCorrupt("missing tables: \(missing.joined(separator: ", "))")
        }
        let version = try query("SELECT value FROM schema_meta WHERE key = 'schema_version';").first?.string("value")
        guard let version else {
            throw LibraryAssetError.databaseCorrupt("schema_version is missing")
        }
        guard version == Self.schemaVersion else {
            throw LibraryAssetError.databaseUnknownVersion(version)
        }
    }

    static let schemaStatements: [String] = [
        """
        CREATE TABLE schema_meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE assets (
            asset_id          TEXT PRIMARY KEY,
            kind              TEXT NOT NULL,
            format            TEXT NOT NULL,
            status            TEXT NOT NULL,
            storage_rel_path  TEXT NOT NULL,
            current_revision  INTEGER NOT NULL DEFAULT 1,
            sha256            TEXT,
            byte_size         INTEGER,
            original_filename TEXT,
            live_state        TEXT,
            error_message     TEXT,
            files_json        TEXT NOT NULL DEFAULT '[]',
            created_at        TEXT NOT NULL,
            updated_at        TEXT NOT NULL
        );
        """,
        "CREATE INDEX idx_assets_sha256 ON assets(sha256) WHERE sha256 IS NOT NULL;",
        "CREATE INDEX idx_assets_status ON assets(status);",
        """
        CREATE TABLE sample_asset_links (
            asset_id         TEXT PRIMARY KEY REFERENCES assets(asset_id),
            sample_uid       TEXT NOT NULL,
            ownership_status TEXT NOT NULL DEFAULT 'active' CHECK (ownership_status IN ('active', 'historical')),
            linked_at        TEXT NOT NULL
        );
        """,
        "CREATE INDEX idx_links_sample ON sample_asset_links(sample_uid, ownership_status);",
        """
        CREATE TRIGGER trg_sample_asset_links_source_only
        BEFORE INSERT ON sample_asset_links
        BEGIN
            SELECT RAISE(ABORT, 'only source assets can have sample ownership')
            WHERE NOT EXISTS (SELECT 1 FROM assets WHERE asset_id = NEW.asset_id AND kind = 'source');
        END;
        """,
        """
        CREATE TABLE asset_dependencies (
            consumer_asset_id TEXT NOT NULL REFERENCES assets(asset_id),
            upstream_asset_id TEXT NOT NULL REFERENCES assets(asset_id),
            dependency_kind   TEXT NOT NULL CHECK (dependency_kind IN ('dataset_source', 'live_input', 'snapshot_input')),
            signal_locator    TEXT,
            PRIMARY KEY (consumer_asset_id, upstream_asset_id, dependency_kind)
        );
        """,
        "CREATE UNIQUE INDEX idx_deps_dataset_source ON asset_dependencies(consumer_asset_id) WHERE dependency_kind = 'dataset_source';",
        "CREATE INDEX idx_deps_upstream ON asset_dependencies(upstream_asset_id);",
        """
        CREATE TRIGGER trg_asset_dependencies_dataset_source
        BEFORE INSERT ON asset_dependencies
        WHEN NEW.dependency_kind = 'dataset_source'
        BEGIN
            SELECT RAISE(ABORT, 'dataset_source requires dataset consumer and source upstream')
            WHERE NOT EXISTS (SELECT 1 FROM assets WHERE asset_id = NEW.consumer_asset_id AND kind = 'dataset')
               OR NOT EXISTS (SELECT 1 FROM assets WHERE asset_id = NEW.upstream_asset_id AND kind = 'source');
        END;
        """,
        """
        CREATE TABLE asset_operations (
            operation_id TEXT PRIMARY KEY,
            op_type      TEXT NOT NULL,
            state        TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at   TEXT NOT NULL,
            updated_at   TEXT NOT NULL
        );
        """
    ]

    // MARK: - Statements

    var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
    }

    @discardableResult
    func execute(_ sql: String, _ params: [SQLValue] = []) throws -> Int {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW { continue }
            if code == SQLITE_DONE { break }
            throw LibraryAssetError.sqlite("\(lastErrorMessage) [\(sql.prefix(60))]")
        }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var rows: [SQLRow] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else {
                throw LibraryAssetError.sqlite("\(lastErrorMessage) [\(sql.prefix(60))]")
            }
            var values: [String: SQLValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    values[name] = .int(sqlite3_column_int64(statement, index))
                case SQLITE_NULL:
                    values[name] = .null
                default:
                    if let text = sqlite3_column_text(statement, index) {
                        values[name] = .text(String(cString: text))
                    } else {
                        values[name] = .null
                    }
                }
            }
            rows.append(SQLRow(values: values))
        }
        return rows
    }

    /// Runs `body` inside `BEGIN IMMEDIATE ... COMMIT`; any thrown error rolls back.
    @discardableResult
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryAssetError.sqlite("\(lastErrorMessage) [\(sql.prefix(60))]")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch param {
            case let .text(value): code = sqlite3_bind_text(statement, index, value, -1, transient)
            case let .int(value): code = sqlite3_bind_int64(statement, index, value)
            case .null: code = sqlite3_bind_null(statement, index)
            }
            guard code == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw LibraryAssetError.sqlite(lastErrorMessage)
            }
        }
        return statement
    }
}
