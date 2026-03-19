import Foundation

final class LibraryStore {
    private let fileManager = FileManager.default

    func ensureRoot(at rootURL: URL) {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: indexDirectoryURL(rootURL), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: batchesDirectoryURL(rootURL), withIntermediateDirectories: true)
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
        let batchURL = batchDirectoryURL(rootURL, batchID: batch.id)
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
        writeSample(sample, to: sampleURL)
    }

    func updateBatch(_ batch: LibraryBatch, rootURL: URL) {
        let batchURL = batchDirectoryURL(rootURL, batchID: batch.id)
        writeBatch(batch, to: batchURL)
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

    private func batchDirectoryURL(_ rootURL: URL, batchID: String) -> URL {
        batchesDirectoryURL(rootURL).appending(path: sanitizedPathComponent(batchID), directoryHint: .isDirectory)
    }

    private func sampleDirectoryURL(_ rootURL: URL, batchID: String, sampleKey: String) -> URL {
        batchDirectoryURL(rootURL, batchID: batchID)
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
}
