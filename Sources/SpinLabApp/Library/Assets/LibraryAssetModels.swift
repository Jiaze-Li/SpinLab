import CryptoKit
import Foundation

// MARK: - Adapter / codec contracts (workflow-neutral)

/// One file of a standardized payload, addressed by a plain file name inside its asset directory.
struct StandardizedFile: Equatable, Sendable {
    let name: String
    let data: Data
}

/// Dataset content as produced by a workflow codec: a format id plus its files.
struct StandardizedDatasetContent: Equatable, Sendable {
    let format: String
    let files: [StandardizedFile]
}

/// Everything the shared asset service needs to register one raw instrument file and its
/// independent standard data. Carries no AFM-specific types.
struct StandardizedDatasetPayload: Equatable, Sendable {
    let sourceFormat: String
    let originalFileName: String
    /// Historical provenance only; formal relations use Source IDs.
    let originalSourcePath: String?
    let sourceBytes: Data
    let dataset: StandardizedDatasetContent
    /// Stable in-source signal locators (e.g. channel ids) recorded on the dataset dependency.
    let signalLocators: [String]
}

protocol AssetStandardizationAdapter {
    var sourceFormat: String { get }
    func standardize(sourceFileURL: URL) throws -> StandardizedDatasetPayload
}

protocol DatasetPayloadCodec {
    associatedtype Dataset
    var datasetFormat: String { get }
    func decode(files: [String: Data]) throws -> Dataset
}

// MARK: - Records and results

struct AssetFileEntry: Codable, Equatable, Sendable {
    let name: String
    let sha256: String
    let size: Int
}

struct AssetRecord: Equatable, Sendable {
    let id: String
    let kind: String
    let format: String
    let status: String
    let storageRelPath: String
    let currentRevision: Int
    let sha256: String?
    let byteSize: Int64?
    let originalFilename: String?
    let liveState: String?
    let errorMessage: String?
    let files: [AssetFileEntry]

    init(row: SQLRow) throws {
        id = row.string("asset_id") ?? ""
        kind = row.string("kind") ?? ""
        format = row.string("format") ?? ""
        status = row.string("status") ?? ""
        storageRelPath = row.string("storage_rel_path") ?? ""
        currentRevision = Int(row.int("current_revision") ?? 1)
        sha256 = row.string("sha256")
        byteSize = row.int("byte_size")
        originalFilename = row.string("original_filename")
        liveState = row.string("live_state")
        errorMessage = row.string("error_message")
        files = try AssetFileEntry.decodeList(row.string("files_json"))
    }
}

extension AssetFileEntry {
    static func decodeList(_ json: String?) throws -> [AssetFileEntry] {
        guard let json, let data = json.data(using: .utf8) else {
            throw LibraryAssetError.databaseCorrupt("files_json is missing or invalid UTF-8")
        }
        do {
            return try JSONDecoder().decode([AssetFileEntry].self, from: data)
        } catch {
            throw LibraryAssetError.databaseCorrupt("files_json is corrupt: \(error.localizedDescription)")
        }
    }

    static func encodeList(_ entries: [AssetFileEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    static func make(_ file: StandardizedFile) -> AssetFileEntry {
        AssetFileEntry(name: file.name, sha256: AssetHashing.sha256Hex(file.data), size: file.data.count)
    }
}

enum AssetHashing {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Identity-free digest of a file set: sorted `name=sha` lines.
    static func digest(of entries: [AssetFileEntry]) -> String {
        let text = entries.sorted { $0.name < $1.name }.map { "\($0.name)=\($0.sha256)" }.joined(separator: "\n")
        return sha256Hex(Data(text.utf8))
    }
}

struct AssetIngestResult: Codable, Equatable, Sendable {
    let sourceID: String
    let datasetID: String
    let sampleUIDs: [String]
    let datasetRevision: Int
    let reusedSource: Bool
}

struct AssetReviseResult: Codable, Equatable, Sendable {
    let datasetID: String
    let revision: Int
    let staleLiveAssetIDs: [String]
}

enum SourceAvailability: Equatable, Sendable {
    case available
    case missing
    case corrupt(String)
}

struct LoadedDataset<Dataset> {
    let datasetID: String
    let revision: Int
    let dataset: Dataset
    let sourceAvailability: SourceAvailability
}

struct PermanentDeletionPlan: Codable, Equatable, Sendable {
    let sampleUIDs: [String]
    let assetsToDelete: [String]
    /// Assets that were candidates for this deletion but are kept because something else uses them.
    let retainedAssets: [String]
    let deleteFileCount: Int
    let retainedFileCount: Int
    /// Retained Live assets that lose an input and become stale.
    let staleLiveAssetIDs: [String]
    let fingerprint: String
}

struct PermanentDeletionResult: Codable, Equatable, Sendable {
    let sampleUIDs: [String]
    let deletedAssetIDs: [String]
    let retainedAssetIDs: [String]
}

struct AssetRecoveryReport: Equatable, Sendable {
    var recoveredOperations: [String] = []
    var abortedOperations: [String] = []
    /// Leftovers that could not be attributed to an operation; reported, never deleted.
    var unknownResidue: [String] = []
}

/// Test-only crash simulation points. A thrown error at a point behaves like a process crash:
/// the service never cleans up after it, and the next operation / reopen must recover.
enum AssetFaultPoint: Equatable, Sendable {
    case ingestAfterSourceWritten
    case ingestBeforeCommit
    case reviseAfterStaging
    case reviseAfterPublish
    case reviseAfterCommit
    case deleteAfterPendingCommit
    case deleteAfterSampleRemoved
    case deleteAfterFile(Int)
}
