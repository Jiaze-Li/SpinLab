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

    func syncIndexFromFilesystem(rootURL: URL) -> LibraryIndex {
        buildIndexFromFilesystem(rootURL: rootURL, persist: true)
    }

    func snapshotIndexFromFilesystem(rootURL: URL) -> LibraryIndex {
        buildIndexFromFilesystem(rootURL: rootURL, persist: false)
    }

    func buildIndexFromFilesystem(rootURL: URL, persist: Bool) -> LibraryIndex {
        ensureRoot(at: rootURL)
        let existingIndex = loadIndex(from: rootURL)
        let now = Date()
        let batchDirectories = discoverBatchDirectories(rootURL: rootURL)

        var batchesByID: [String: LibraryBatch] = [:]
        var samplesByID: [String: LibrarySample] = [:]

        for batchDirectory in batchDirectories {
            let batchJSONURL = batchDirectory.appending(path: "batch.json")
            guard let batch = decodeBatch(from: batchJSONURL) else {
                continue
            }

            var sampleIDs: Set<String> = []
            for sample in decodeSamples(from: batchDirectory) {
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
        if persist {
            saveIndex(index, to: rootURL)
        }
        return index
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
