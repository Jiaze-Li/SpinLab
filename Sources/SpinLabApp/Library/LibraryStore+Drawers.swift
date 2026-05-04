import Foundation

extension LibraryStore {
    func createDrawer(for sample: LibrarySample, batch: LibraryBatch, rootURL: URL) throws {
        ensureRoot(at: rootURL)
        let batchURL = preferredBatchDirectoryURL(rootURL, batchID: batch.id)
        let sampleURL = sampleDirectoryURL(rootURL, batchID: batch.id, sampleKey: sample.id)
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

        writeBatch(batch, to: batchURL)
        writeSample(sample, to: sampleURL)
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
        writeSample(sample, to: sampleURL)
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
        writeBatch(batch, to: batchURL)
        invalidateNodeCache(at: batchURL)
        invalidateNodeCache(at: batchURL.deletingLastPathComponent())
        invalidateNodeCache(at: batchesDirectoryURL(rootURL))
    }

    func deleteSampleDrawer(for sample: LibrarySample, rootURL: URL) throws {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        if fileManager.fileExists(atPath: sampleURL.path) {
            try fileManager.removeItem(at: sampleURL)
        }
        let samplesDirectory = resolvedBatchDirectoryURL(rootURL, batchID: sample.batchId)
            .appending(path: "samples", directoryHint: .isDirectory)
        removeDirectoryIfEmpty(samplesDirectory)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: samplesDirectory)
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

    func writeBatch(_ batch: LibraryBatch, to batchURL: URL) {
        let url = batchURL.appending(path: "batch.json")
        writeJSON(batch, to: url)
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
