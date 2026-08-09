import Foundation
import CryptoKit

extension SpinLabAppState {

    func existingImportedOriginalPaths() -> Set<String> {
        var paths: Set<String> = []

        for pending in inboxFeatureStore.pendingImports {
            if let original = pending.originalFilePath {
                paths.insert(normalizedPath(original))
            }
        }

        for record in workbenchFeatureStore.archivedRecords {
            if let original = record.measurement.originalFilePath {
                paths.insert(normalizedPath(original))
            }
        }

        paths.formUnion(existingLibraryImportedOriginalPaths())

        return paths
    }

    func existingImportedContentFingerprints() -> Set<String> {
        var fingerprints: Set<String> = []
        var seenPaths: Set<String> = []

        func collectFingerprint(from path: String?) {
            guard let path, !path.isEmpty else {
                return
            }
            let normalized = normalizedPath(path)
            guard seenPaths.insert(normalized).inserted else {
                return
            }
            guard let fingerprint = contentFingerprint(atPath: normalized) else {
                return
            }
            fingerprints.insert(fingerprint)
        }

        for pending in inboxFeatureStore.pendingImports {
            collectFingerprint(from: pending.sourceFilePath)
            collectFingerprint(from: pending.originalFilePath)
        }

        for record in workbenchFeatureStore.archivedRecords {
            collectFingerprint(from: record.dataset.sourceFilePath)
            collectFingerprint(from: record.dataset.originalFilePath)
            collectFingerprint(from: record.measurement.sourceFilePath)
            collectFingerprint(from: record.measurement.originalFilePath)
        }

        for fingerprint in existingLibraryImportedContentFingerprints() {
            fingerprints.insert(fingerprint)
        }

        return fingerprints
    }

    func existingImportedFileNames() -> Set<String> {
        var names: Set<String> = []

        for pending in inboxFeatureStore.pendingImports {
            names.insert(pending.fileName.lowercased())
        }

        for record in workbenchFeatureStore.archivedRecords {
            let path = record.measurement.sourceFilePath
            let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if !fileName.isEmpty {
                names.insert(fileName)
            }
        }

        names.formUnion(existingLibraryMeasurementFileNames())

        return names
    }

    private func existingLibraryMeasurementFileNames() -> Set<String> {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return []
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let batchesURL = rootURL.appending(path: "batches", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: batchesURL.path),
              let enumerator = FileManager.default.enumerator(
                at: batchesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var collected: Set<String> = []
        for case let url as URL in enumerator {
            guard url.path.contains("/measurements/") else {
                continue
            }
            guard !url.lastPathComponent.hasSuffix(".spinlab.json") else {
                continue
            }
            collected.insert(url.lastPathComponent.lowercased())
        }
        return collected
    }

    private func existingLibraryImportedOriginalPaths() -> Set<String> {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            libraryImportedOriginalPathsCache = nil
            return []
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let batchesURL = rootURL.appending(path: "batches", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: batchesURL.path) else {
            libraryImportedOriginalPathsCache = nil
            return []
        }

        let cacheFingerprint = batchesDirectoryFingerprint(at: batchesURL)
        if let cached = libraryImportedOriginalPathsCache,
           cached.rootPath == rootPath,
           cached.batchesFingerprint == cacheFingerprint {
            return cached.paths
        }

        let bulkResult = LibrarySidecarBulkReader().enumerateSidecars(rootURL: batchesURL, fileManager: FileManager.default)
        var collected: Set<String> = []
        for record in bulkResult.records {
            let normalized = record.sidecar.sourceFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                continue
            }
            collected.insert(normalizedPath(normalized))
        }
        libraryImportedOriginalPathsCache = (rootPath: rootPath, batchesFingerprint: cacheFingerprint, paths: collected)
        return collected
    }

    private func existingLibraryImportedContentFingerprints() -> Set<String> {
        guard let rootPath = libraryFeatureStore.librarySettings.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return []
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let batchesURL = rootURL.appending(path: "batches", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: batchesURL.path),
              let enumerator = FileManager.default.enumerator(
                at: batchesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var collected: Set<String> = []
        for case let url as URL in enumerator {
            guard url.path.contains("/measurements/") else {
                continue
            }
            guard !url.lastPathComponent.hasSuffix(".spinlab.json") else {
                continue
            }
            if let fingerprint = contentFingerprint(atPath: url.path) {
                collected.insert(fingerprint)
            }
        }
        return collected
    }

    private func batchesDirectoryFingerprint(at batchesURL: URL) -> String {
        let values = try? batchesURL.resourceValues(forKeys: [.contentModificationDateKey])
        let timestamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(Int(timestamp))"
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func contentFingerprint(atPath path: String) -> String? {
        if let cached = contentFingerprintCache[path] {
            return cached
        }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        contentFingerprintCache[path] = fingerprint
        return fingerprint
    }
}
