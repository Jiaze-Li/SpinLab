import Foundation

/// A Library sync/mutation baseline could not be established completely, or an
/// index could not be written.
enum LibraryIndexSyncError: Error, LocalizedError {
    case incomplete([String])
    case rootMissing(String)
    case backupFailed(String)
    case writeFailed

    var issues: [String] {
        switch self {
        case let .incomplete(issues): return issues
        case let .rootMissing(path): return ["Library Root not found: \(path)"]
        case let .backupFailed(reason): return [reason]
        case .writeFailed: return ["Could not write the index file."]
        }
    }

    var errorDescription: String? {
        switch self {
        case let .rootMissing(path):
            return "Library Root not found: \(path). Nothing was created or changed."
        case let .backupFailed(reason):
            return "\(reason) The damaged index was not replaced."
        case .writeFailed:
            return "The index file could not be written. The previous index was not replaced."
        case let .incomplete(issues):
            let shown = issues.prefix(3).joined(separator: "; ")
            return "\(issues.count) item(s) could not be read (\(shown)). Nothing was changed."
        }
    }
}

/// Outcome of an explicit, confirmed recovery of a damaged index.
struct LibraryIndexRecovery {
    var backupURL: URL
    var index: LibraryIndex
}

extension LibraryStore {
    func ensureRoot(at rootURL: URL) {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: indexDirectoryURL(rootURL), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: batchesDirectoryURL(rootURL), withIntermediateDirectories: true)
        } catch {
            logger.error(.library, "Failed to create library root directories", metadata: [
                "path": rootURL.path,
                "reason": error.localizedDescription
            ])
        }
        migrateLegacyBatchLayoutIfNeeded(at: rootURL)
    }

    func verifyRoot(at rootURL: URL) -> URL? {
        let verifyURL = rootURL.appending(path: "__spinlab_library_root_check", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: verifyURL, withIntermediateDirectories: true)
            return verifyURL
        } catch {
            return nil
        }
    }

    func loadIndex(from rootURL: URL) -> LibraryIndex? {
        let url = indexFileURL(rootURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error(.library, "Failed to read library index", metadata: [
                "path": url.path,
                "reason": error.localizedDescription
            ])
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(LibraryIndex.self, from: data)
        } catch {
            logger.error(.library, "Failed to decode library index", metadata: [
                "path": url.path,
                "reason": error.localizedDescription
            ])
            return nil
        }
    }

    /// Explicit, user-authorized sync: rebuilds the index from the files AND
    /// persists it. Never call this from startup, browse or selection paths.
    /// Fail-closed: returns the index only when the Library was read completely and the
    /// rebuilt index was written. Otherwise throws and leaves the saved index untouched, so
    /// no caller can mutate files or save an index derived from a partial read.
    func syncIndexFromFilesystem(rootURL: URL) throws -> LibraryIndex {
        let checked = syncIndexFromFilesystemChecked(rootURL: rootURL)
        guard checked.persisted else {
            throw checked.issues == ["Could not write the index file."]
                ? LibraryIndexSyncError.writeFailed
                : LibraryIndexSyncError.incomplete(checked.issues)
        }
        return checked.index
    }

    /// Reads the Library completely without writing anything; throws if any part was unreadable.
    /// Used to validate before a mutation that does its own saving.
    func completeIndexForMutation(rootURL: URL) throws -> LibraryIndex {
        try syncIndexFromFilesystem(rootURL: rootURL)
    }

    /// Fail-closed sync. If any source file, folder or the existing index could
    /// not be read, the scan is incomplete: the index on disk is left exactly as
    /// it was (`persisted == false`) and the issues are returned to be shown.
    @discardableResult
    func syncIndexFromFilesystemChecked(rootURL: URL) -> LibraryIndexSyncResult {
        ensureRoot(at: rootURL)
        let scan = scanIndexFromFilesystem(rootURL: rootURL)
        guard scan.issues.isEmpty else {
            logger.error(.library, "Index sync refused: Library could not be read completely", metadata: [
                "path": rootURL.path,
                "issues": scan.issues.joined(separator: "; ")
            ])
            // Only the index itself is damaged and every source file is fine: the user may
            // choose a confirmed recovery. Anything else stays a hard stop.
            let onlyIndexDamaged = scan.indexUnreadable
                && scan.issues.allSatisfy { $0 == Self.indexUnreadableIssue }
            return LibraryIndexSyncResult(index: scan.index, issues: scan.issues, persisted: false, recoverable: onlyIndexDamaged)
        }
        guard saveIndex(scan.index, to: rootURL) else {
            return LibraryIndexSyncResult(index: scan.index, issues: ["Could not write the index file."], persisted: false, recoverable: false)
        }
        return LibraryIndexSyncResult(index: scan.index, issues: [], persisted: true, recoverable: false)
    }

    static let indexUnreadableIssue = "library_index.json could not be read; showing files as found."

    /// Truly read-only and complete-or-nothing. Never creates, migrates or writes. A missing
    /// root or any unreadable part throws, so a partial scan is never shown as a full diff.
    func readOnlyCompleteIndex(rootURL: URL) throws -> LibraryIndex {
        let scan = scanIndexFromFilesystem(rootURL: rootURL)
        guard scan.rootExists else { throw LibraryIndexSyncError.rootMissing(rootURL.path) }
        guard scan.issues.isEmpty else { throw LibraryIndexSyncError.incomplete(scan.issues) }
        return scan.index
    }

    /// Explicit, confirmed recovery of a damaged `library_index.json`:
    /// verify every source file is readable -> back up the raw damaged bytes under a unique
    /// name (never overwriting) -> verify the backup -> atomically write the rebuilt index.
    /// Any failure leaves the damaged index exactly as it was.
    func recoverIndexFromFilesystem(rootURL: URL) throws -> LibraryIndexRecovery {
        let scan = scanIndexFromFilesystem(rootURL: rootURL)
        guard scan.rootExists else { throw LibraryIndexSyncError.rootMissing(rootURL.path) }
        let sourceIssues = scan.issues.filter { $0 != Self.indexUnreadableIssue }
        guard sourceIssues.isEmpty else { throw LibraryIndexSyncError.incomplete(sourceIssues) }
        guard scan.indexUnreadable else {
            throw LibraryIndexSyncError.incomplete(["There is no damaged index to recover."])
        }
        let indexURL = indexFileURL(rootURL)
        let raw: Data
        do { raw = try Data(contentsOf: indexURL) } catch {
            throw LibraryIndexSyncError.backupFailed("The damaged index could not be read to make a backup.")
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let backupURL = indexURL.deletingLastPathComponent()
            .appending(path: "library_index.json.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).bak")
        do {
            try raw.write(to: backupURL, options: [.withoutOverwriting])
            guard try Data(contentsOf: backupURL) == raw else {
                throw LibraryIndexSyncError.backupFailed("The backup did not verify.")
            }
        } catch let error as LibraryIndexSyncError {
            throw error
        } catch {
            throw LibraryIndexSyncError.backupFailed("The damaged index could not be backed up.")
        }
        guard saveIndex(scan.index, to: rootURL) else { throw LibraryIndexSyncError.writeFailed }
        guard loadIndex(from: rootURL) != nil else { throw LibraryIndexSyncError.writeFailed }
        return LibraryIndexRecovery(backupURL: backupURL, index: scan.index)
    }

    /// Truly read-only: no directory creation, no legacy migration, no index write.
    func snapshotIndexFromFilesystem(rootURL: URL) -> LibraryIndex {
        scanIndexFromFilesystem(rootURL: rootURL).index
    }

    /// Result of a non-persisting scan. `issues` lists unreadable source files
    /// that were left out of `index`; they are reported, never "repaired".
    struct LibraryIndexScan {
        var index: LibraryIndex
        var issues: [String]
        var rootExists: Bool
        var indexUnreadable: Bool = false
    }

    struct LibraryIndexSyncResult {
        var index: LibraryIndex
        var issues: [String]
        var persisted: Bool
        /// True when only the index file is damaged and a confirmed recovery is possible.
        var recoverable: Bool
    }

    /// Pure read of the Library files. Touches nothing on disk.
    func scanIndexFromFilesystem(rootURL: URL) -> LibraryIndexScan {
        var isDir: ObjCBool = false
        let rootExists = fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDir) && isDir.boolValue
        let existingIndex = loadIndex(from: rootURL)
        let now = Date()
        var issues: [String] = []
        let indexUnreadable = existingIndex == nil && fileManager.fileExists(atPath: indexFileURL(rootURL).path)
        if indexUnreadable {
            issues.append(Self.indexUnreadableIssue)
        }
        let batchDirectories = rootExists ? discoverBatchDirectories(rootURL: rootURL, issues: &issues) : []

        var batchesByID: [String: LibraryBatch] = [:]
        var samplesByID: [String: LibrarySample] = [:]

        for batchDirectory in batchDirectories {
            let batchJSONURL = batchDirectory.appending(path: "batch.json")
            guard let batch = decodeBatch(from: batchJSONURL) else {
                issues.append("Unreadable batch.json: \(batchDirectory.lastPathComponent)")
                continue
            }

            var sampleIDs: Set<String> = []
            let samplesRoot = batchDirectory.appending(path: "samples", directoryHint: .isDirectory)
            var sampleEntries: [URL] = []
            if let listed = directoryEntries(at: samplesRoot) {
                sampleEntries = listed
            } else if fileManager.fileExists(atPath: samplesRoot.path) {
                issues.append("Unreadable folder: \(batchDirectory.lastPathComponent)/samples")
            }
            for sampleDirectory in sampleEntries where isDirectory(sampleDirectory) {
                guard let sample = decodeSample(from: sampleDirectory.appending(path: "sample.json")) else {
                    issues.append("Unreadable sample.json: \(batchDirectory.lastPathComponent)/\(sampleDirectory.lastPathComponent)")
                    continue
                }
                sampleIDs.insert(sample.id)
                samplesByID[sample.id] = sample
            }

            var normalizedBatch = batch
            normalizedBatch.sampleKeys = sampleIDs.sorted()
            batchesByID[normalizedBatch.id] = normalizedBatch
        }

        let index = LibraryIndex(
            version: existingIndex?.version ?? 1,
            createdAt: existingIndex?.createdAt ?? now,
            updatedAt: now,
            registryInternalPath: existingIndex?.registryInternalPath,
            registrySourcePath: existingIndex?.registrySourcePath,
            metadataColumnOrder: existingIndex?.metadataColumnOrder ?? [],
            batches: Array(batchesByID.values).sorted { LibrarySort.compareBatch($0.id, $1.id) },
            samples: Array(samplesByID.values).sorted { $0.displayName < $1.displayName }
        )
        return LibraryIndexScan(index: index, issues: issues, rootExists: rootExists, indexUnreadable: indexUnreadable)
    }

    /// Returns true only if the index file was actually written.
    @discardableResult
    func saveIndex(_ index: LibraryIndex, to rootURL: URL) -> Bool {
        let url = indexFileURL(rootURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(index)
        } catch {
            logger.error(.library, "Failed to encode library index", metadata: [
                "path": url.path,
                "reason": error.localizedDescription
            ])
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error(.library, "Failed to persist library index", metadata: [
                "path": url.path,
                "reason": error.localizedDescription
            ])
            return false
        }
        invalidateNodeCache(at: url)
        invalidateNodeCache(at: url.deletingLastPathComponent())
        return true
    }

    func needsIndexRefresh(rootURL: URL) -> Bool {
        guard let index = loadIndex(from: rootURL) else {
            return true
        }
        let batchesRoot = batchesDirectoryURL(rootURL)
        guard let modifiedAt = modificationDate(of: batchesRoot) else {
            return false
        }
        return modifiedAt > index.updatedAt
    }
}
