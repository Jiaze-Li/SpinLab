import Foundation

extension LibraryStore {
    func indexDirectoryURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "index", directoryHint: .isDirectory)
    }

    func batchesDirectoryURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "batches", directoryHint: .isDirectory)
    }

    func preferredBatchDirectoryURL(_ rootURL: URL, batchID: String) -> URL {
        let prefix = batchPrefix(for: batchID)
        return prefixDirectoryURL(rootURL, prefix: prefix)
            .appending(path: sanitizedPathComponent(batchID), directoryHint: .isDirectory)
    }

    func legacyBatchDirectoryURL(_ rootURL: URL, batchID: String) -> URL {
        batchesDirectoryURL(rootURL).appending(path: sanitizedPathComponent(batchID), directoryHint: .isDirectory)
    }

    func resolvedBatchDirectoryURL(_ rootURL: URL, batchID: String) -> URL {
        let preferred = preferredBatchDirectoryURL(rootURL, batchID: batchID)
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }
        let legacy = legacyBatchDirectoryURL(rootURL, batchID: batchID)
        if fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }
        return preferred
    }

    func sampleDirectoryURL(_ rootURL: URL, batchID: String, sampleKey: String) -> URL {
        resolvedBatchDirectoryURL(rootURL, batchID: batchID)
            .appending(path: "samples", directoryHint: .isDirectory)
            .appending(path: sanitizedPathComponent(sampleKey), directoryHint: .isDirectory)
    }

    func indexFileURL(_ rootURL: URL) -> URL {
        indexDirectoryURL(rootURL).appending(path: "library_index.json")
    }

    func sanitizedPathComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    func prefixDirectoryURL(_ rootURL: URL, prefix: String) -> URL {
        batchesDirectoryURL(rootURL).appending(path: sanitizedPathComponent(prefix), directoryHint: .isDirectory)
    }

    func batchPrefix(for batchID: String) -> String {
        let prefix = LibrarySort.batchSortKey(batchID).prefix
        return prefix.isEmpty ? "UNKNOWN" : prefix
    }

    func migrateLegacyBatchLayoutIfNeeded(at rootURL: URL) {
        let batchesURL = batchesDirectoryURL(rootURL)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: batchesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for entry in entries {
            guard isDirectory(entry) else {
                continue
            }

            let batchJSON = entry.appending(path: "batch.json")
            guard fileManager.fileExists(atPath: batchJSON.path) else {
                continue
            }

            let legacyBatchFolderName = entry.lastPathComponent
            let sourceBatchID = decodeBatchID(from: batchJSON) ?? legacyBatchFolderName
            let prefix = batchPrefix(for: sourceBatchID)
            let targetPrefixURL = prefixDirectoryURL(rootURL, prefix: prefix)
            let targetBatchURL = targetPrefixURL.appending(path: legacyBatchFolderName, directoryHint: .isDirectory)

            if fileManager.fileExists(atPath: targetBatchURL.path) {
                continue
            }

            do {
                try fileManager.createDirectory(at: targetPrefixURL, withIntermediateDirectories: true)
                try fileManager.moveItem(at: entry, to: targetBatchURL)
            } catch {
                logger.error(.library, "Failed to migrate legacy batch layout", metadata: [
                    "source": entry.path,
                    "target": targetBatchURL.path,
                    "reason": error.localizedDescription
                ])
            }
        }
    }

    func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
            return false
        }
        return values.isDirectory == true
    }

    func decodeBatchID(from batchJSONURL: URL) -> String? {
        guard let data = try? Data(contentsOf: batchJSONURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LibraryBatch.self, from: data))?.id
    }

    func decodeBatch(from batchJSONURL: URL) -> LibraryBatch? {
        let key = batchJSONURL.path
        let modificationDate = modificationDate(of: batchJSONURL)
        if let cached = decodedBatchCache[key], cached.modificationDate == modificationDate {
            return cached.batch
        }
        let data: Data
        do {
            data = try Data(contentsOf: batchJSONURL)
        } catch {
            logger.error(.library, "Failed to read batch JSON", metadata: [
                "path": batchJSONURL.path,
                "reason": error.localizedDescription
            ])
            decodedBatchCache[key] = DecodedBatchCacheEntry(modificationDate: modificationDate, batch: nil)
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded: LibraryBatch?
        do {
            decoded = try decoder.decode(LibraryBatch.self, from: data)
        } catch {
            logger.error(.library, "Failed to decode batch JSON", metadata: [
                "path": batchJSONURL.path,
                "reason": error.localizedDescription
            ])
            decoded = nil
        }
        decodedBatchCache[key] = DecodedBatchCacheEntry(modificationDate: modificationDate, batch: decoded)
        return decoded
    }

    func decodeSamples(from batchDirectory: URL) -> [LibrarySample] {
        let samplesRoot = batchDirectory.appending(path: "samples", directoryHint: .isDirectory)
        guard let sampleDirectories = directoryEntries(at: samplesRoot) else {
            return []
        }

        var samples: [LibrarySample] = []
        for sampleDirectory in sampleDirectories where isDirectory(sampleDirectory) {
            let sampleJSONURL = sampleDirectory.appending(path: "sample.json")
            guard let sample = decodeSample(from: sampleJSONURL) else {
                continue
            }
            samples.append(sample)
        }
        return samples
    }

    func decodeSample(from sampleJSONURL: URL) -> LibrarySample? {
        let key = sampleJSONURL.path
        let modificationDate = modificationDate(of: sampleJSONURL)
        if let cached = decodedSampleCache[key], cached.modificationDate == modificationDate {
            return cached.sample
        }
        let data: Data
        do {
            data = try Data(contentsOf: sampleJSONURL)
        } catch {
            logger.error(.library, "Failed to read sample JSON", metadata: [
                "path": sampleJSONURL.path,
                "reason": error.localizedDescription
            ])
            decodedSampleCache[key] = DecodedSampleCacheEntry(modificationDate: modificationDate, sample: nil)
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded: LibrarySample?
        do {
            decoded = try decoder.decode(LibrarySample.self, from: data)
        } catch {
            logger.error(.library, "Failed to decode sample JSON", metadata: [
                "path": sampleJSONURL.path,
                "reason": error.localizedDescription
            ])
            decoded = nil
        }
        decodedSampleCache[key] = DecodedSampleCacheEntry(modificationDate: modificationDate, sample: decoded)
        return decoded
    }

    func discoverBatchDirectories(rootURL: URL) -> [URL] {
        let batchesRoot = batchesDirectoryURL(rootURL)
        guard let entries = directoryEntries(at: batchesRoot) else {
            return []
        }

        var batchDirectories: [URL] = []
        for entry in entries where isDirectory(entry) {
            let directBatchJSON = entry.appending(path: "batch.json")
            if fileManager.fileExists(atPath: directBatchJSON.path) {
                batchDirectories.append(entry)
                continue
            }

            guard let nested = directoryEntries(at: entry) else {
                continue
            }
            for nestedEntry in nested where isDirectory(nestedEntry) {
                let nestedBatchJSON = nestedEntry.appending(path: "batch.json")
                if fileManager.fileExists(atPath: nestedBatchJSON.path) {
                    batchDirectories.append(nestedEntry)
                }
            }
        }

        return batchDirectories.sorted { $0.path < $1.path }
    }

    func directoryEntries(at url: URL) -> [URL]? {
        let key = url.path
        let modificationDate = modificationDate(of: url)
        if let cached = directoryEntriesCache[key], cached.modificationDate == modificationDate {
            return cached.entries
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            if fileManager.fileExists(atPath: url.path) {
                logger.error(.library, "Failed to read directory contents", metadata: [
                    "path": url.path,
                    "reason": error.localizedDescription
                ])
            }
            directoryEntriesCache.removeValue(forKey: key)
            return nil
        }
        directoryEntriesCache[key] = DirectoryEntriesCacheEntry(modificationDate: modificationDate, entries: entries)
        return entries
    }

    func removeDirectoryIfEmpty(_ url: URL) {
        guard isDirectory(url) else {
            return
        }
        guard let entries = directoryEntries(at: url), entries.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: url)
        invalidateNodeCache(at: url)
    }

    func modificationDate(of url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    func cachedFileEntries(in directoryURL: URL) -> [URL] {
        let key = directoryURL.path
        let modificationDate = modificationDate(of: directoryURL)
        if let cached = fileListCache[key], cached.modificationDate == modificationDate {
            return cached.files
        }
        guard let entries = directoryEntries(at: directoryURL) else {
            fileListCache.removeValue(forKey: key)
            return []
        }
        let files = entries.filter { !isDirectory($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        fileListCache[key] = FileListCacheEntry(modificationDate: modificationDate, files: files)
        return files
    }

    func invalidateNodeCache(at url: URL) {
        let nodePath = url.path
        directoryEntriesCache = directoryEntriesCache.filter { key, _ in
            key != nodePath && !key.hasPrefix(nodePath + "/")
        }
        decodedBatchCache = decodedBatchCache.filter { key, _ in
            key != nodePath && !key.hasPrefix(nodePath + "/")
        }
        decodedSampleCache = decodedSampleCache.filter { key, _ in
            key != nodePath && !key.hasPrefix(nodePath + "/")
        }
        fileListCache = fileListCache.filter { key, _ in
            key != nodePath && !key.hasPrefix(nodePath + "/")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension LibraryStore {
}
