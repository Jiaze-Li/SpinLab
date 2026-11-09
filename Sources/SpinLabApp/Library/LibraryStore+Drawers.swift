import Foundation

enum LibraryDrawerError: LocalizedError, Equatable {
    case nativeSampleConflict(sampleId: String, path: String)

    var errorDescription: String? {
        switch self {
        case let .nativeSampleConflict(sampleId, path):
            return "Cannot overwrite existing native sample '\(sampleId)' at '\(path)'. Registry cannot silently overwrite native sample scientific data."
        }
    }
}

extension LibraryStore {
    func createDrawer(for sample: LibrarySample, batch: LibraryBatch, rootURL: URL) throws {
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: batch.id)
        let sampleURL = sampleDirectoryURL(rootURL, batchID: batch.id, sampleKey: sample.id)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")

        // Fail-closed against overwriting existing Native Sample scientific data:
        if fileManager.fileExists(atPath: sampleJSONURL.path),
           let existingDiskSample = decodeSample(from: sampleJSONURL) {
            if existingDiskSample.origin == "native" || existingDiskSample.sourceSheetName == nil {
                throw LibraryDrawerError.nativeSampleConflict(sampleId: sample.id, path: sampleURL.path)
            }
        }

        try ensureRootDirectories(at: rootURL)
        try fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sampleURL, withIntermediateDirectories: true)

        let testsURL = sampleURL.appending(path: "tests", directoryHint: .isDirectory)
        let plotsURL = sampleURL.appending(path: "plots", directoryHint: .isDirectory)
        let analysisURL = sampleURL.appending(path: "analysis", directoryHint: .isDirectory)
        let measurementsURL = sampleURL.appending(path: "measurements", directoryHint: .isDirectory)
        let testSlots = ["XRD", "M-H", "R-H", "EDS", "AFM"]
        try fileManager.createDirectory(at: testsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: plotsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: analysisURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: measurementsURL, withIntermediateDirectories: true)
        for slot in testSlots {
            try fileManager.createDirectory(at: testsURL.appending(path: slot, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }

        var batchToWrite = batch
        let batchJSONURL = batchURL.appending(path: "batch.json")
        if fileManager.fileExists(atPath: batchJSONURL.path),
           let existingDiskBatch = decodeBatch(from: batchJSONURL) {
            if batchToWrite.origin == nil || batchToWrite.origin?.isEmpty == true {
                batchToWrite.origin = existingDiskBatch.origin
            }
            let samplesDir = batchURL.appending(path: "samples", directoryHint: .isDirectory)
            var preservedKeys = Set(batchToWrite.sampleKeys).union([sample.id])
            for existingKey in existingDiskBatch.sampleKeys {
                let existingSampleJSON = samplesDir
                    .appending(path: sanitizedPathComponent(existingKey), directoryHint: .isDirectory)
                    .appending(path: "sample.json")
                if fileManager.fileExists(atPath: existingSampleJSON.path) {
                    preservedKeys.insert(existingKey)
                }
            }
            batchToWrite.sampleKeys = preservedKeys.sorted()
        }

        try writeBatchChecked(batchToWrite, to: batchURL)
        try writeSampleChecked(sample, to: sampleURL)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: batchURL)
        invalidateNodeCache(at: batchURL.deletingLastPathComponent())
        invalidateNodeCache(at: batchesDirectoryURL(rootURL))
    }

    func updateSample(_ sample: LibrarySample, rootURL: URL, changeSource: String = "system_update") throws {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let previousSampleURL = sampleURL.appending(path: "sample.json")
        let previous = decodeSample(from: previousSampleURL)
        try fileManager.createDirectory(at: sampleURL, withIntermediateDirectories: true)
        // A failed write must surface: callers (sample edit Save, Registry Apply) report success otherwise.
        try writeJSONChecked(sample, to: sampleURL.appending(path: "sample.json"))
        let changes = appendSampleChangeLogIfNeeded(
            previous: previous,
            updated: sample,
            source: changeSource,
            sampleURL: sampleURL
        )
        appendBatchEditLogIfNeeded(
            changes: changes,
            updated: sample,
            source: changeSource,
            rootURL: rootURL
        )
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: sampleURL.deletingLastPathComponent())
    }

    func updateBatch(_ batch: LibraryBatch, rootURL: URL) throws {
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: batch.id)
        try fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        var batchToWrite = batch
        let batchJSONURL = batchURL.appending(path: "batch.json")
        if fileManager.fileExists(atPath: batchJSONURL.path),
           let existingDiskBatch = decodeBatch(from: batchJSONURL) {
            if batchToWrite.origin == nil || batchToWrite.origin?.isEmpty == true {
                batchToWrite.origin = existingDiskBatch.origin
            }
            // Preserve still-existing native sample keys on disk that might not be in batch.sampleKeys
            let samplesDir = batchURL.appending(path: "samples", directoryHint: .isDirectory)
            var preservedKeys = Set(batchToWrite.sampleKeys)
            for existingKey in existingDiskBatch.sampleKeys {
                let sampleJSON = samplesDir
                    .appending(path: sanitizedPathComponent(existingKey), directoryHint: .isDirectory)
                    .appending(path: "sample.json")
                if fileManager.fileExists(atPath: sampleJSON.path),
                   let diskSample = decodeSample(from: sampleJSON),
                   diskSample.origin == "native" || diskSample.sourceSheetName == nil {
                    preservedKeys.insert(existingKey)
                }
            }
            // Filter out any sampleKey whose sample directory does not exist on disk
            batchToWrite.sampleKeys = preservedKeys.filter { key in
                let sampleDir = samplesDir.appending(path: sanitizedPathComponent(key), directoryHint: .isDirectory)
                return fileManager.fileExists(atPath: sampleDir.path)
            }.sorted()
        }
        try writeBatchChecked(batchToWrite, to: batchURL)
        invalidateNodeCache(at: batchURL)
        invalidateNodeCache(at: batchURL.deletingLastPathComponent())
        invalidateNodeCache(at: batchesDirectoryURL(rootURL))
    }

    func deleteSampleDrawer(for sample: LibrarySample, rootURL: URL) throws {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        if fileManager.fileExists(atPath: sampleURL.path) {
            try fileManager.removeItem(at: sampleURL)
        }
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: sample.batchId)
        let batchJSONURL = batchURL.appending(path: "batch.json")
        if fileManager.fileExists(atPath: batchJSONURL.path),
           var batch = decodeBatch(from: batchJSONURL) {
            if batch.sampleKeys.contains(sample.id) {
                batch.sampleKeys.removeAll { $0 == sample.id }
                try writeBatchChecked(batch, to: batchURL)
            }
        }
        let samplesDirectory = batchURL.appending(path: "samples", directoryHint: .isDirectory)
        removeDirectoryIfEmpty(samplesDirectory)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: samplesDirectory)
        invalidateNodeCache(at: batchURL)
    }

    func deleteBatchDrawer(batchID: String, rootURL: URL) throws {
        let preferred = preferredBatchDirectoryURL(rootURL, batchID: batchID)
        let legacy = legacyBatchDirectoryURL(rootURL, batchID: batchID)
        if fileManager.fileExists(atPath: preferred.path) {
            try fileManager.removeItem(at: preferred)
        }
        if preferred.path != legacy.path, fileManager.fileExists(atPath: legacy.path) {
            try fileManager.removeItem(at: legacy)
        }
        removeDirectoryIfEmpty(preferred.deletingLastPathComponent())
        invalidateNodeCache(at: preferred)
        invalidateNodeCache(at: legacy)
        invalidateNodeCache(at: preferred.deletingLastPathComponent())
        invalidateNodeCache(at: batchesDirectoryURL(rootURL))
    }

    func drawerRootURL(for sample: LibrarySample, rootURL: URL) -> URL {
        sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
    }

    func writeSample(_ sample: LibrarySample, to sampleURL: URL) {
        let url = sampleURL.appending(path: "sample.json")
        writeJSON(sample, to: url)
    }

    func writeSampleChecked(_ sample: LibrarySample, to sampleURL: URL) throws {
        let url = sampleURL.appending(path: "sample.json")
        try writeJSONChecked(sample, to: url)
    }

    func writeBatch(_ batch: LibraryBatch, to batchURL: URL) {
        let url = batchURL.appending(path: "batch.json")
        writeJSON(batch, to: url)
    }

    func writeBatchChecked(_ batch: LibraryBatch, to batchURL: URL) throws {
        let url = batchURL.appending(path: "batch.json")
        try writeJSONChecked(batch, to: url)
    }

    func writeJSONChecked<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            fputs("[SpinLab] LibraryStore: JSON encode failed for \(url.lastPathComponent): \(error)\n", stderr)
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            fputs("[SpinLab] LibraryStore: write failed for \(url.lastPathComponent): \(error)\n", stderr)
        }
    }
}
