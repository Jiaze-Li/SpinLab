import Foundation

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
    func syncIndexFromFilesystem(rootURL: URL) -> LibraryIndex {
        ensureRoot(at: rootURL)
        let scan = scanIndexFromFilesystem(rootURL: rootURL)
        saveIndex(scan.index, to: rootURL)
        return scan.index
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
    }

    /// Pure read of the Library files. Touches nothing on disk.
    func scanIndexFromFilesystem(rootURL: URL) -> LibraryIndexScan {
        var isDir: ObjCBool = false
        let rootExists = fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDir) && isDir.boolValue
        let existingIndex = loadIndex(from: rootURL)
        let now = Date()
        var issues: [String] = []
        if existingIndex == nil, fileManager.fileExists(atPath: indexFileURL(rootURL).path) {
            issues.append("library_index.json could not be read; showing files as found.")
        }
        let batchDirectories = rootExists ? discoverBatchDirectories(rootURL: rootURL) : []

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
            for sampleDirectory in directoryEntries(at: samplesRoot) ?? [] where isDirectory(sampleDirectory) {
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
        return LibraryIndexScan(index: index, issues: issues, rootExists: rootExists)
    }

    func saveIndex(_ index: LibraryIndex, to rootURL: URL) {
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
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error(.library, "Failed to persist library index", metadata: [
                "path": url.path,
                "reason": error.localizedDescription
            ])
            return
        }
        invalidateNodeCache(at: url)
        invalidateNodeCache(at: url.deletingLastPathComponent())
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
