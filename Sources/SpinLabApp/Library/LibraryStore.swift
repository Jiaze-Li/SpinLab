import Foundation

final class LibraryStore {
    private let fileManager = FileManager.default

    func ensureRoot(at rootURL: URL) {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: indexDirectoryURL(rootURL), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: batchesDirectoryURL(rootURL), withIntermediateDirectories: true)
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
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibraryIndex.self, from: data)
    }

    func syncIndexFromFilesystem(rootURL: URL) -> LibraryIndex {
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
        saveIndex(index, to: rootURL)
        return index
    }

    func saveIndex(_ index: LibraryIndex, to rootURL: URL) {
        let url = indexFileURL(rootURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(index) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    func createDrawer(for sample: LibrarySample, batch: LibraryBatch, rootURL: URL) {
        ensureRoot(at: rootURL)
        let batchURL = preferredBatchDirectoryURL(rootURL, batchID: batch.id)
        let sampleURL = sampleDirectoryURL(rootURL, batchID: batch.id, sampleKey: sample.id)
        try? fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: sampleURL, withIntermediateDirectories: true)

        let testsURL = sampleURL.appending(path: "tests", directoryHint: .isDirectory)
        let plotsURL = sampleURL.appending(path: "plots", directoryHint: .isDirectory)
        let analysisURL = sampleURL.appending(path: "analysis", directoryHint: .isDirectory)
        let measurementsURL = sampleURL.appending(path: "measurements", directoryHint: .isDirectory)
        let testSlots = ["XRD", "M-H", "R-H", "EDS", "AFM"]
        try? fileManager.createDirectory(at: testsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: plotsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: analysisURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: measurementsURL, withIntermediateDirectories: true)
        for slot in testSlots {
            try? fileManager.createDirectory(at: testsURL.appending(path: slot, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }

        writeBatch(batch, to: batchURL)
        writeSample(sample, to: sampleURL)
    }

    func updateSample(_ sample: LibrarySample, rootURL: URL) {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        try? fileManager.createDirectory(at: sampleURL, withIntermediateDirectories: true)
        writeSample(sample, to: sampleURL)
    }

    func updateBatch(_ batch: LibraryBatch, rootURL: URL) {
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: batch.id)
        try? fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        writeBatch(batch, to: batchURL)
    }

    func deleteSampleDrawer(for sample: LibrarySample, rootURL: URL) {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        if fileManager.fileExists(atPath: sampleURL.path) {
            try? fileManager.removeItem(at: sampleURL)
        }
        let samplesDirectory = resolvedBatchDirectoryURL(rootURL, batchID: sample.batchId)
            .appending(path: "samples", directoryHint: .isDirectory)
        removeDirectoryIfEmpty(samplesDirectory)
    }

    func deleteBatchDrawer(batchID: String, rootURL: URL) {
        let preferred = preferredBatchDirectoryURL(rootURL, batchID: batchID)
        let legacy = legacyBatchDirectoryURL(rootURL, batchID: batchID)
        if fileManager.fileExists(atPath: preferred.path) {
            try? fileManager.removeItem(at: preferred)
        }
        if preferred.path != legacy.path, fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.removeItem(at: legacy)
        }
        removeDirectoryIfEmpty(preferred.deletingLastPathComponent())
    }

    func copyMeasurementFile(from sourcePath: String, to sample: LibrarySample, rootURL: URL) -> URL? {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let measurementsURL = sampleURL.appending(path: "measurements", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: measurementsURL, withIntermediateDirectories: true)
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let sanitized = sourceURL.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destination = measurementsURL.appending(path: "\(UUID().uuidString)-\(sanitized)")
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    func syncBackup(from rootURL: URL, to backupURL: URL) -> Bool {
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: rootURL, to: backupURL)
            return true
        } catch {
            return false
        }
    }

    private func writeSample(_ sample: LibrarySample, to sampleURL: URL) {
        let url = sampleURL.appending(path: "sample.json")
        writeJSON(sample, to: url)
    }

    private func writeBatch(_ batch: LibraryBatch, to batchURL: URL) {
        let url = batchURL.appending(path: "batch.json")
        writeJSON(batch, to: url)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func indexDirectoryURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "index", directoryHint: .isDirectory)
    }

    private func batchesDirectoryURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "batches", directoryHint: .isDirectory)
    }

    private func preferredBatchDirectoryURL(_ rootURL: URL, batchID: String) -> URL {
        let prefix = batchPrefix(for: batchID)
        return prefixDirectoryURL(rootURL, prefix: prefix)
            .appending(path: sanitizedPathComponent(batchID), directoryHint: .isDirectory)
    }

    private func legacyBatchDirectoryURL(_ rootURL: URL, batchID: String) -> URL {
        batchesDirectoryURL(rootURL).appending(path: sanitizedPathComponent(batchID), directoryHint: .isDirectory)
    }

    private func resolvedBatchDirectoryURL(_ rootURL: URL, batchID: String) -> URL {
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

    private func sampleDirectoryURL(_ rootURL: URL, batchID: String, sampleKey: String) -> URL {
        resolvedBatchDirectoryURL(rootURL, batchID: batchID)
            .appending(path: "samples", directoryHint: .isDirectory)
            .appending(path: sanitizedPathComponent(sampleKey), directoryHint: .isDirectory)
    }

    private func indexFileURL(_ rootURL: URL) -> URL {
        indexDirectoryURL(rootURL).appending(path: "library_index.json")
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    private func prefixDirectoryURL(_ rootURL: URL, prefix: String) -> URL {
        batchesDirectoryURL(rootURL).appending(path: sanitizedPathComponent(prefix), directoryHint: .isDirectory)
    }

    private func batchPrefix(for batchID: String) -> String {
        let prefix = LibrarySort.batchSortKey(batchID).prefix
        return prefix.isEmpty ? "UNKNOWN" : prefix
    }

    private func migrateLegacyBatchLayoutIfNeeded(at rootURL: URL) {
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

            try? fileManager.createDirectory(at: targetPrefixURL, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: entry, to: targetBatchURL)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
            return false
        }
        return values.isDirectory == true
    }

    private func decodeBatchID(from batchJSONURL: URL) -> String? {
        guard let data = try? Data(contentsOf: batchJSONURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LibraryBatch.self, from: data))?.id
    }

    private func decodeBatch(from batchJSONURL: URL) -> LibraryBatch? {
        guard let data = try? Data(contentsOf: batchJSONURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibraryBatch.self, from: data)
    }

    private func decodeSamples(from batchDirectory: URL) -> [LibrarySample] {
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

    private func decodeSample(from sampleJSONURL: URL) -> LibrarySample? {
        guard let data = try? Data(contentsOf: sampleJSONURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibrarySample.self, from: data)
    }

    private func discoverBatchDirectories(rootURL: URL) -> [URL] {
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

    private func directoryEntries(at url: URL) -> [URL]? {
        try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard isDirectory(url) else {
            return
        }
        guard let entries = directoryEntries(at: url), entries.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: url)
    }
}
