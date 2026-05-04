import Foundation

extension LibraryStore {
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
            invalidateNodeCache(at: measurementsURL)
            return destination
        } catch {
            return nil
        }
    }

    func listMeasurementFiles(batchID: String, sampleKey: String, rootURL: URL) -> [URL] {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: batchID, sampleKey: sampleKey)
        let measurementsURL = sampleURL.appending(path: "measurements", directoryHint: .isDirectory)
        return cachedFileEntries(in: measurementsURL)
    }

    func sidecarSnapshot(for sample: LibrarySample, rootURL: URL) -> SidecarSnapshot {
        let sampleDirectory = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let signatures = sidecarSignatures(in: sampleDirectory)
        guard !signatures.isEmpty else {
            return .empty
        }
        return SidecarSnapshot(fileCount: signatures.count, fingerprint: signatures.joined(separator: "\n"))
    }

    func loadAppliedMeasurements(for sample: LibrarySample, rootURL: URL) -> [AppliedMeasurement] {
        let sampleDirectory = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        return scanAppliedMeasurements(in: sampleDirectory)
    }
}
