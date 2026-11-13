import Foundation

enum LibraryDrawerError: LocalizedError, Equatable {
    case nativeSampleConflict(sampleId: String, path: String)
    case batchUpdateFailedAfterSampleDeletion(sampleId: String, batchId: String, underlyingError: String)

    var errorDescription: String? {
        switch self {
        case let .nativeSampleConflict(sampleId, path):
            return "Cannot overwrite existing native sample '\(sampleId)' at '\(path)'. Registry cannot silently overwrite native sample scientific data."
        case let .batchUpdateFailedAfterSampleDeletion(sampleId, batchId, underlyingError):
            return "Sample '\(sampleId)' directory was deleted, but updating batch.json for batch '\(batchId)' failed: \(underlyingError)"
        }
    }
}

extension LibraryStore {
    func createDrawer(for sample: LibrarySample, batch: LibraryBatch, rootURL: URL) throws {
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: batch.id)
        let sampleURL = sampleDirectoryURL(rootURL, batchID: batch.id, sampleKey: sample.id)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")

        // Fail-closed against orphan artifact collision (AC4 & S3):
        if !fileManager.fileExists(atPath: sampleURL.path) {
            let (isOrphan, orphanPath) = LibraryMutationSafetyGuard.detectOrphanArtifact(
                sampleKey: sample.id,
                rootURL: rootURL,
                fileManager: fileManager
            )
            if isOrphan {
                throw LibraryMutationSafetyError.orphanArtifactCollision(
                    sampleKey: sample.id,
                    path: orphanPath ?? "samples/\(sample.id)/_spinlab"
                )
            }
        }

        var sampleToWrite = sample
        // Fail-closed against overwriting existing Native Sample scientific data:
        if fileManager.fileExists(atPath: sampleJSONURL.path),
           let existingDiskSample = decodeSample(from: sampleJSONURL) {
            if existingDiskSample.conflictsWithIncomingRegistrySample(sampleToWrite) {
                throw LibraryDrawerError.nativeSampleConflict(sampleId: sample.id, path: sampleURL.path)
            }
            // Preserve immutable machine identity & mappings for existing Registry sample
            if sampleToWrite.sampleUID == nil || sampleToWrite.sampleUID?.isEmpty == true {
                sampleToWrite.sampleUID = existingDiskSample.sampleUID
            }
            if sampleToWrite.legacySampleKey == nil || sampleToWrite.legacySampleKey?.isEmpty == true {
                sampleToWrite.legacySampleKey = existingDiskSample.legacySampleKey
            }
            if sampleToWrite.origin == nil || sampleToWrite.origin?.isEmpty == true {
                sampleToWrite.origin = existingDiskSample.origin
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
        let samplesDir = batchURL.appending(path: "samples", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: batchJSONURL.path),
           let existingDiskBatch = decodeBatch(from: batchJSONURL) {
            if batchToWrite.origin == nil || batchToWrite.origin?.isEmpty == true {
                batchToWrite.origin = existingDiskBatch.origin
            }
            var preservedKeys = Set([sample.id])
            let candidateKeys = Set(batchToWrite.sampleKeys).union(existingDiskBatch.sampleKeys)
            for candidateKey in candidateKeys {
                let candidateSampleDir = samplesDir
                    .appending(path: sanitizedPathComponent(candidateKey), directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: candidateSampleDir.path) {
                    preservedKeys.insert(candidateKey)
                }
            }
            batchToWrite.sampleKeys = preservedKeys.sorted()
        } else {
            var preservedKeys = Set([sample.id])
            for candidateKey in batchToWrite.sampleKeys {
                let candidateSampleDir = samplesDir
                    .appending(path: sanitizedPathComponent(candidateKey), directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: candidateSampleDir.path) {
                    preservedKeys.insert(candidateKey)
                }
            }
            batchToWrite.sampleKeys = preservedKeys.sorted()
        }

        try writeBatchChecked(batchToWrite, to: batchURL)
        try writeSampleChecked(sampleToWrite, to: sampleURL)
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

        var sampleToWrite = sample
        if let previous {
            if sampleToWrite.sampleUID == nil || sampleToWrite.sampleUID?.isEmpty == true {
                sampleToWrite.sampleUID = previous.sampleUID
            }
            if sampleToWrite.legacySampleKey == nil || sampleToWrite.legacySampleKey?.isEmpty == true {
                sampleToWrite.legacySampleKey = previous.legacySampleKey
            }
            if sampleToWrite.origin == nil || sampleToWrite.origin?.isEmpty == true {
                sampleToWrite.origin = previous.origin
            }
        }

        // A failed write must surface: callers (sample edit Save, Registry Apply) report success otherwise.
        try writeJSONChecked(sampleToWrite, to: sampleURL.appending(path: "sample.json"))
        let changes = appendSampleChangeLogIfNeeded(
            previous: previous,
            updated: sampleToWrite,
            source: changeSource,
            sampleURL: sampleURL
        )
        appendBatchEditLogIfNeeded(
            changes: changes,
            updated: sampleToWrite,
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
                   diskSample.isNativeOrManual {
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
        // Preflight safety check: verify dependencies, shared plots, and cross-namespace assets (AC3 & S3)
        // Must fail-closed if library index cannot be read completely: never fallback to [sample] (F002)
        let completeIndex = try readOnlyCompleteIndex(rootURL: rootURL)
        let allSamples = completeIndex.samples
        try LibraryMutationSafetyGuard.validateExplicitDeletionSafety(
            sample: sample,
            rootURL: rootURL,
            allSamples: allSamples,
            fileManager: fileManager
        )

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
                do {
                    try writeBatchChecked(batch, to: batchURL)
                } catch {
                    throw LibraryDrawerError.batchUpdateFailedAfterSampleDeletion(
                        sampleId: sample.id,
                        batchId: sample.batchId,
                        underlyingError: error.localizedDescription
                    )
                }
            }
        }
        let samplesDirectory = batchURL.appending(path: "samples", directoryHint: .isDirectory)
        removeDirectoryIfEmpty(samplesDirectory)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: samplesDirectory)
        invalidateNodeCache(at: batchURL)
    }

    /// Reconciles batch.json sampleKeys against physical sample directories.
    /// Removes any sample keys from batch.json whose sample directory does not exist on disk.
    @discardableResult
    func reconcileBatchSampleKeys(rootURL: URL, batchID: String? = nil) throws -> [String: [String]] {
        var issues: [String] = []
        let batchDirs = discoverBatchDirectories(rootURL: rootURL, issues: &issues)
        guard issues.isEmpty else {
            throw LibraryIndexSyncError.incomplete(issues)
        }

        // Validate batch IDs across physical directories for collisions before modifying any file
        var batchDirectoriesByID: [String: URL] = [:]
        for batchDir in batchDirs {
            let batchJSONURL = batchDir.appending(path: "batch.json")
            guard fileManager.fileExists(atPath: batchJSONURL.path) else { continue }
            guard let batch = decodeBatch(from: batchJSONURL) else {
                throw LibraryIndexSyncError.incomplete(["Unreadable batch.json: \(batchDir.lastPathComponent)"])
            }
            let normalizedKey = batch.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let existingDir = batchDirectoriesByID[normalizedKey] {
                throw LibraryIndexSyncError.incomplete(["Batch ID collision: duplicate batch ID '\(batch.id)' found in multiple physical directories: '\(existingDir.path)' and '\(batchDir.path)'"])
            }
            batchDirectoriesByID[normalizedKey] = batchDir
        }

        var reconciled: [String: [String]] = [:]

        for batchDir in batchDirs {
            let batchJSONURL = batchDir.appending(path: "batch.json")
            guard fileManager.fileExists(atPath: batchJSONURL.path) else {
                continue
            }
            guard var batch = decodeBatch(from: batchJSONURL) else {
                throw LibraryIndexSyncError.incomplete(["Unreadable batch.json: \(batchDir.lastPathComponent)"])
            }
            if let batchID, batch.id != batchID {
                continue
            }
            let samplesDir = batchDir.appending(path: "samples", directoryHint: .isDirectory)
            var validKeys: [String] = []
            var staleKeys: [String] = []
            for key in batch.sampleKeys {
                let sampleDir = samplesDir.appending(path: sanitizedPathComponent(key), directoryHint: .isDirectory)
                if fileManager.fileExists(atPath: sampleDir.path) {
                    validKeys.append(key)
                } else {
                    staleKeys.append(key)
                }
            }
            if !staleKeys.isEmpty {
                batch.sampleKeys = validKeys.sorted()
                try writeBatchChecked(batch, to: batchDir)
                invalidateNodeCache(at: batchDir)
                invalidateNodeCache(at: batchDir.deletingLastPathComponent())
                reconciled[batch.id] = staleKeys
            }
        }
        if !reconciled.isEmpty {
            invalidateNodeCache(at: batchesDirectoryURL(rootURL))
        }
        return reconciled
    }

    func deleteBatchDrawer(batchID: String, rootURL: URL) throws {
        // Must fail-closed if library index cannot be read completely: never fallback to nil (F001)
        let baseline = try readOnlyCompleteIndex(rootURL: rootURL)
        try LibraryMutationSafetyGuard.validateBatchDeletionSafety(
            batchID: batchID,
            rootURL: rootURL,
            baselineIndex: baseline,
            fileManager: fileManager
        )

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
        invalidateNodeCache(at: batchURL)
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
