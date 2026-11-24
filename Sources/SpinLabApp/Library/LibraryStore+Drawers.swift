import Foundation

enum LibraryDrawerError: LocalizedError, Equatable {
    case nativeSampleConflict(sampleId: String, path: String)
    case batchUpdateFailedAfterSampleDeletion(sampleId: String, batchId: String, underlyingError: String)
    case sampleNotFound(sampleId: String, path: String)
    case sampleUnreadable(sampleId: String, path: String)
    case permanentDeleteRequiresTrash(sampleId: String)
    case unsafePath(path: String)
    case deletionDisabled

    /// Shown whenever a batch delete is refused. Batch deletion remains closed.
    static let deletionDisabledMessage = "删除功能暂未开放"

    var errorDescription: String? {
        switch self {
        case .deletionDisabled:
            return Self.deletionDisabledMessage
        case let .nativeSampleConflict(sampleId, path):
            return "Cannot overwrite existing native sample '\(sampleId)' at '\(path)'. Registry cannot silently overwrite native sample scientific data."
        case let .batchUpdateFailedAfterSampleDeletion(sampleId, batchId, underlyingError):
            return "Sample '\(sampleId)' directory was deleted, but updating batch.json for batch '\(batchId)' failed: \(underlyingError)"
        case let .sampleNotFound(sampleId, path):
            return "Sample '\(sampleId)' was not found on disk at '\(path)'."
        case let .sampleUnreadable(sampleId, path):
            return "Sample '\(sampleId)' could not be read at '\(path)'."
        case let .permanentDeleteRequiresTrash(sampleId):
            return "Sample '\(sampleId)' must be moved to Trash before permanent deletion."
        case let .unsafePath(path):
            return "Refused operation on unsafe path outside Library root: '\(path)'."
        }
    }
}

extension LibraryStore {
    func createDrawer(for sample: LibrarySample, batch: LibraryBatch, rootURL: URL) throws {
        let layout = resolveLayout(at: rootURL)
        if case let .invalid(layoutError) = layout {
            throw layoutError
        }
        let isV2 = layout.isV2
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: batch.id)
        let sampleURL = isV2
            ? drawerRootURL(for: sample, rootURL: rootURL)
            : sampleDirectoryURL(rootURL, batchID: batch.id, sampleKey: sample.id)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")

        // Fail-closed against orphan artifact collision (AC4 & S3) on V1:
        if !isV2 && !fileManager.fileExists(atPath: sampleURL.path) {
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
            if sampleToWrite.deletedAt == nil {
                sampleToWrite.deletedAt = existingDiskSample.deletedAt
            }
            // Result values are never changed by Registry sync; disk is the only authority.
            sampleToWrite.results = existingDiskSample.results
        }

        try ensureRootDirectories(at: rootURL)
        try fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sampleURL, withIntermediateDirectories: true)

        if !isV2 {
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
        }

        var batchToWrite = batch
        let batchJSONURL = batchURL.appending(path: "batch.json")
        if isV2 {
            if fileManager.fileExists(atPath: batchJSONURL.path),
               let existingDiskBatch = decodeBatch(from: batchJSONURL) {
                if batchToWrite.origin == nil || batchToWrite.origin?.isEmpty == true {
                    batchToWrite.origin = existingDiskBatch.origin
                }
            }
            batchToWrite.sampleKeys = []
        } else {
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
        }

        try writeBatchChecked(batchToWrite, to: batchURL)
        try writeSampleChecked(sampleToWrite, to: sampleURL)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: batchURL)
        invalidateNodeCache(at: batchURL.deletingLastPathComponent())
        invalidateNodeCache(at: isV2 ? recordsDirectoryURL(rootURL) : batchesDirectoryURL(rootURL))
    }

    func updateSample(_ sample: LibrarySample, rootURL: URL, changeSource: String = "system_update") throws {
        if case let .invalid(layoutError) = resolveLayout(at: rootURL) {
            throw layoutError
        }
        let sampleURL = drawerRootURL(for: sample, rootURL: rootURL)
        try LibraryWriteLease.shared.ensureWritable(sampleURL)
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
            if sampleToWrite.deletedAt == nil {
                sampleToWrite.deletedAt = previous.deletedAt
            }
            // Result values are never changed here (Registry Apply, Sample edit, system updates):
            // only `LibraryResultService` writes them, so an in-memory/incoming copy can never erase or revert them.
            sampleToWrite.results = previous.results
            if sampleToWrite.notes == nil {
                sampleToWrite.notes = previous.notes
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
        let layout = resolveLayout(at: rootURL)
        if case let .invalid(layoutError) = layout {
            throw layoutError
        }
        let isV2 = layout.isV2
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: batch.id)
        try LibraryWriteLease.shared.ensureWritable(batchURL)
        try fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        var batchToWrite = batch
        let batchJSONURL = batchURL.appending(path: "batch.json")
        if isV2 {
            if fileManager.fileExists(atPath: batchJSONURL.path),
               let existingDiskBatch = decodeBatch(from: batchJSONURL) {
                if batchToWrite.origin == nil || batchToWrite.origin?.isEmpty == true {
                    batchToWrite.origin = existingDiskBatch.origin
                }
            }
            batchToWrite.sampleKeys = []
        } else if fileManager.fileExists(atPath: batchJSONURL.path),
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
        invalidateNodeCache(at: isV2 ? recordsDirectoryURL(rootURL) : batchesDirectoryURL(rootURL))
        if var existingIndex = loadIndex(from: rootURL),
           let idx = existingIndex.batches.firstIndex(where: { $0.id == batchToWrite.id }) {
            var indexedBatch = batchToWrite
            if isV2 {
                indexedBatch.sampleKeys = existingIndex.samples
                    .filter { $0.batchId == batchToWrite.id }
                    .map(\.id)
                    .sorted()
            }
            existingIndex.batches[idx] = indexedBatch
            existingIndex.updatedAt = batchToWrite.updatedAt
            _ = saveIndex(existingIndex, to: rootURL)
        }
    }

    func deleteSampleDrawer(for sample: LibrarySample, rootURL: URL) throws {
        // Legacy direct drawer deletion remains closed; callers must use moveSampleToTrash / permanentlyDeleteTrashedSample.
        throw LibraryDrawerError.deletionDisabled
    }

    @discardableResult
    func moveSampleToTrash(sample: LibrarySample, rootURL: URL, now: Date = Date()) throws -> LibrarySample {
        if case let .invalid(layoutError) = resolveLayout(at: rootURL) {
            throw layoutError
        }
        let sampleURL = drawerRootURL(for: sample, rootURL: rootURL)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")
        guard fileManager.fileExists(atPath: sampleJSONURL.path) else {
            throw LibraryDrawerError.sampleNotFound(sampleId: sample.id, path: sampleJSONURL.path)
        }
        guard var diskSample = decodeSample(from: sampleJSONURL) else {
            throw LibraryDrawerError.sampleUnreadable(sampleId: sample.id, path: sampleJSONURL.path)
        }
        if diskSample.deletedAt == nil {
            diskSample.deletedAt = now
        }
        diskSample.updatedAt = now
        try writeJSONChecked(diskSample, to: sampleJSONURL)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: sampleURL.deletingLastPathComponent())
        _ = try syncIndexFromFilesystem(rootURL: rootURL)
        return diskSample
    }

    @discardableResult
    func restoreSampleFromTrash(sample: LibrarySample, rootURL: URL, now: Date = Date()) throws -> LibrarySample {
        if case let .invalid(layoutError) = resolveLayout(at: rootURL) {
            throw layoutError
        }
        let sampleURL = drawerRootURL(for: sample, rootURL: rootURL)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")
        guard fileManager.fileExists(atPath: sampleJSONURL.path) else {
            throw LibraryDrawerError.sampleNotFound(sampleId: sample.id, path: sampleJSONURL.path)
        }
        guard var diskSample = decodeSample(from: sampleJSONURL) else {
            throw LibraryDrawerError.sampleUnreadable(sampleId: sample.id, path: sampleJSONURL.path)
        }
        diskSample.deletedAt = nil
        diskSample.updatedAt = now
        try writeJSONChecked(diskSample, to: sampleJSONURL)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: sampleURL.deletingLastPathComponent())
        _ = try syncIndexFromFilesystem(rootURL: rootURL)
        return diskSample
    }

    func permanentlyDeleteTrashedSample(sample: LibrarySample, rootURL: URL) throws {
        let layout = resolveLayout(at: rootURL)
        if case let .invalid(layoutError) = layout {
            throw layoutError
        }
        let isV2 = layout.isV2
        guard sample.isTrashed else {
            throw LibraryDrawerError.permanentDeleteRequiresTrash(sampleId: sample.id)
        }

        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: sample.batchId)
        let sampleURL = drawerRootURL(for: sample, rootURL: rootURL)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")
        try LibraryWriteLease.shared.ensureWritable(sampleURL)

        let expectedParent = isV2 ? v2SamplesDirectoryURL(rootURL) : rootURL
        guard isStrictChildPath(sampleURL, of: expectedParent) else {
            throw LibraryDrawerError.unsafePath(path: sampleURL.path)
        }
        guard fileManager.fileExists(atPath: sampleJSONURL.path) else {
            throw LibraryDrawerError.sampleNotFound(sampleId: sample.id, path: sampleJSONURL.path)
        }
        guard let diskSample = decodeSample(from: sampleJSONURL) else {
            throw LibraryDrawerError.sampleUnreadable(sampleId: sample.id, path: sampleJSONURL.path)
        }
        guard diskSample.isTrashed else {
            throw LibraryDrawerError.permanentDeleteRequiresTrash(sampleId: sample.id)
        }

        // 1. Delete physical sample directory
        if fileManager.fileExists(atPath: sampleURL.path) {
            try fileManager.removeItem(at: sampleURL)
        }

        if !isV2 {
            // 2. Update batch.json sampleKeys (V1 only; V2 does not maintain sampleKeys on disk)
            let batchJSONURL = batchURL.appending(path: "batch.json")
            if fileManager.fileExists(atPath: batchJSONURL.path) {
                do {
                    guard var batch = decodeBatch(from: batchJSONURL) else {
                        throw LibraryDrawerError.sampleUnreadable(sampleId: sample.id, path: batchJSONURL.path)
                    }
                    batch.sampleKeys.removeAll { $0 == sample.id }
                    batch.updatedAt = Date()
                    try writeBatchChecked(batch, to: batchURL)
                } catch {
                    throw LibraryDrawerError.batchUpdateFailedAfterSampleDeletion(
                        sampleId: sample.id,
                        batchId: sample.batchId,
                        underlyingError: error.localizedDescription
                    )
                }
            }

            // 3. Delete sample's own artifact directory: samples/<sampleKey>/
            // Never touches _spinlab/multi-sample/charts/.
            let samplesRoot = rootURL.appending(path: "samples", directoryHint: .isDirectory)
            let candidateKeys = Array(Set([sample.id, sanitizedPathComponent(sample.id)]))
            for key in candidateKeys where !key.isEmpty && key != "." && key != ".." {
                let artifactSampleURL = samplesRoot.appending(path: key, directoryHint: .isDirectory)
                if isStrictChildPath(artifactSampleURL, of: samplesRoot),
                   fileManager.fileExists(atPath: artifactSampleURL.path) {
                    try fileManager.removeItem(at: artifactSampleURL)
                }
            }
        }

        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: batchURL)
        invalidateNodeCache(at: batchURL.deletingLastPathComponent())
        invalidateNodeCache(at: isV2 ? recordsDirectoryURL(rootURL) : batchesDirectoryURL(rootURL))

        // 4. Rebuild library_index.json
        _ = try syncIndexFromFilesystem(rootURL: rootURL)
    }

    private func isStrictChildPath(_ childURL: URL, of parentURL: URL) -> Bool {
        let parentPath = parentURL.resolvingSymlinksInPath().standardizedFileURL.path
        let childPath = childURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard childPath != parentPath else { return false }
        let prefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        return childPath.hasPrefix(prefix)
    }

    /// Reconciles batch.json sampleKeys against physical sample directories.
    /// Removes any sample keys from batch.json whose sample directory does not exist on disk.
    @discardableResult
    func reconcileBatchSampleKeys(rootURL: URL, batchID: String? = nil) throws -> [String: [String]] {
        switch resolveLayout(at: rootURL) {
        case let .invalid(layoutError):
            throw layoutError
        case .v2:
            return [:]
        case .v1, .uninitialized:
            break
        }
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
        // Deletion is closed: refuse before reading or touching anything.
        throw LibraryDrawerError.deletionDisabled
    }

    func drawerRootURL(for sample: LibrarySample, rootURL: URL) -> URL {
        if resolveLayout(at: rootURL).isV2 {
            let uid = (sample.sampleUID?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? sample.id
            return v2SampleDirectoryURL(rootURL, sampleUID: uid)
        }
        return sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
    }

    private struct V2BatchDiskPayload: Encodable {
        var id: String
        var displayName: String
        var sheetName: String
        var metadata: [String: String]
        var numericTags: [String: Double]
        var numericDisplay: [String: String]
        var updatedAt: Date
        var origin: String?

        init(_ batch: LibraryBatch) {
            self.id = batch.id
            self.displayName = batch.displayName
            self.sheetName = batch.sheetName
            self.metadata = batch.metadata
            self.numericTags = batch.numericTags
            self.numericDisplay = batch.numericDisplay
            self.updatedAt = batch.updatedAt
            self.origin = batch.origin
        }
    }

    private func isV2BatchDirectory(_ batchURL: URL) -> Bool {
        batchURL.deletingLastPathComponent().lastPathComponent == "batches"
            && batchURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "records"
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
        if isV2BatchDirectory(batchURL) {
            writeJSON(V2BatchDiskPayload(batch), to: url)
        } else {
            writeJSON(batch, to: url)
        }
    }

    func writeBatchChecked(_ batch: LibraryBatch, to batchURL: URL) throws {
        let url = batchURL.appending(path: "batch.json")
        if isV2BatchDirectory(batchURL) {
            try writeJSONChecked(V2BatchDiskPayload(batch), to: url)
        } else {
            try writeJSONChecked(batch, to: url)
        }
        invalidateNodeCache(at: batchURL)
    }

    func writeJSONChecked<T: Encodable>(_ value: T, to url: URL) throws {
        try LibraryWriteLease.shared.ensureWritable(url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        guard LibraryWriteLease.shared.allowsWrite(to: url) else { return }
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
