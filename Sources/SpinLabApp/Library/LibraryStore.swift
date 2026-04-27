import Foundation

final class LibraryStore {
    struct SidecarSnapshot: Equatable {
        var fileCount: Int
        var fingerprint: String

        static let empty = SidecarSnapshot(fileCount: 0, fingerprint: "")
    }

    struct BackfillSidecarsResult: Equatable {
        var scannedSampleCount: Int
        var scannedMeasurementFileCount: Int
        var createdSidecarCount: Int
        var updatedSidecarCount: Int
        var skippedExistingSidecarCount: Int
        var failedSidecarCount: Int
    }

    private struct DirectoryEntriesCacheEntry {
        let modificationDate: Date?
        let entries: [URL]
    }

    private struct DecodedBatchCacheEntry {
        let modificationDate: Date?
        let batch: LibraryBatch?
    }

    private struct DecodedSampleCacheEntry {
        let modificationDate: Date?
        let sample: LibrarySample?
    }

    private struct FileListCacheEntry {
        let modificationDate: Date?
        let files: [URL]
    }

    private let fileManager = FileManager.default
    private let logger = AppLogger.shared
    private let xlsxSyncService = LibraryXLSXSyncService()
    private var directoryEntriesCache: [String: DirectoryEntriesCacheEntry] = [:]
    private var decodedBatchCache: [String: DecodedBatchCacheEntry] = [:]
    private var decodedSampleCache: [String: DecodedSampleCacheEntry] = [:]
    private var fileListCache: [String: FileListCacheEntry] = [:]

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

    private func buildIndexFromFilesystem(rootURL: URL, persist: Bool) -> LibraryIndex {
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
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: batchURL)
        invalidateNodeCache(at: batchURL.deletingLastPathComponent())
        invalidateNodeCache(at: batchesDirectoryURL(rootURL))
    }

    func updateSample(_ sample: LibrarySample, rootURL: URL, changeSource: String = "system_update") {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let previousSampleURL = sampleURL.appending(path: "sample.json")
        let previous = decodeSample(from: previousSampleURL)
        try? fileManager.createDirectory(at: sampleURL, withIntermediateDirectories: true)
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

    func sampleChangeLog(for sample: LibrarySample, rootURL: URL) -> [LibrarySampleChangeLogEntry] {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let logURL = sampleChangeLogURL(sampleURL: sampleURL)
        guard fileManager.fileExists(atPath: logURL.path),
              let data = try? Data(contentsOf: logURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([LibrarySampleChangeLogEntry].self, from: data)) ?? []
        return entries.sorted { $0.changedAt > $1.changedAt }
    }

    func syncRegistrySourceForEditedSample(
        oldSample: LibrarySample,
        updatedSample: LibrarySample,
        registrySourceURL: URL
    ) throws -> LibraryRegistrySourceSyncResult {
        let changes = sampleChangeItems(old: oldSample, new: updatedSample)
        let metadataWrites: [LibraryXLSXSyncService.MetadataWrite] = changes.compactMap { change in
            guard change.key.hasPrefix("metadata.") else {
                return nil
            }
            let key = String(change.key.dropFirst("metadata.".count))
            return LibraryXLSXSyncService.MetadataWrite(
                key: key,
                oldValue: change.oldValue,
                newValue: change.newValue
            )
        }

        let numericLogs: [LibraryXLSXSyncService.NumericLogWrite] = changes.compactMap { change in
            if change.key.hasPrefix("numeric.") {
                return LibraryXLSXSyncService.NumericLogWrite(
                    key: String(change.key.dropFirst("numeric.".count)),
                    oldValue: change.oldValue,
                    newValue: change.newValue
                )
            }
            return nil
        }

        return try xlsxSyncService.syncEditedSample(
            oldSample: oldSample,
            updatedSample: updatedSample,
            registrySourceURL: registrySourceURL,
            metadataWrites: metadataWrites,
            numericWrites: numericLogs
        )
    }

    func updateBatch(_ batch: LibraryBatch, rootURL: URL) {
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: batch.id)
        try? fileManager.createDirectory(at: batchURL, withIntermediateDirectories: true)
        writeBatch(batch, to: batchURL)
        invalidateNodeCache(at: batchURL)
        invalidateNodeCache(at: batchURL.deletingLastPathComponent())
        invalidateNodeCache(at: batchesDirectoryURL(rootURL))
    }

    func deleteSampleDrawer(for sample: LibrarySample, rootURL: URL) {
        let sampleURL = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        if fileManager.fileExists(atPath: sampleURL.path) {
            try? fileManager.removeItem(at: sampleURL)
        }
        let samplesDirectory = resolvedBatchDirectoryURL(rootURL, batchID: sample.batchId)
            .appending(path: "samples", directoryHint: .isDirectory)
        removeDirectoryIfEmpty(samplesDirectory)
        invalidateNodeCache(at: sampleURL)
        invalidateNodeCache(at: samplesDirectory)
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
        invalidateNodeCache(at: preferred)
        invalidateNodeCache(at: legacy)
        invalidateNodeCache(at: preferred.deletingLastPathComponent())
        invalidateNodeCache(at: batchesDirectoryURL(rootURL))
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

    func drawerRootURL(for sample: LibrarySample, rootURL: URL) -> URL {
        sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
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

    // MARK: - Measurement Sets

    private static let measurementSetsFileName = "measurement_sets.json"

    func loadMeasurementSets(for sample: LibrarySample, rootURL: URL) -> [MeasurementSet] {
        let sampleDir = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let fileURL = sampleDir.appending(path: Self.measurementSetsFileName)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MeasurementSet].self, from: data)) ?? []
    }

    func saveMeasurementSets(_ sets: [MeasurementSet], for sample: LibrarySample, rootURL: URL) throws {
        let sampleDir = sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let fileURL = sampleDir.appending(path: Self.measurementSetsFileName)
        if sets.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sets)
        try data.write(to: fileURL, options: .atomic)
    }

    func recomputeAllMeasurementSidecars(rootURL: URL) -> BackfillSidecarsResult {
        ensureRoot(at: rootURL)
        let batchDirectories = discoverBatchDirectories(rootURL: rootURL)
        var scannedSampleCount = 0
        var scannedMeasurementFileCount = 0
        var createdSidecarCount = 0
        var updatedSidecarCount = 0
        var skippedExistingSidecarCount = 0
        var failedSidecarCount = 0

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let loadResult = SpinLabRuleProvider.shared.loadResult()

        for batchDirectory in batchDirectories {
            let batchJSONURL = batchDirectory.appending(path: "batch.json")
            guard let batch = decodeBatch(from: batchJSONURL) else {
                continue
            }

            for sample in decodeSamples(from: batchDirectory) {
                scannedSampleCount += 1
                let sampleDirectory = sampleDirectoryURL(rootURL, batchID: batch.id, sampleKey: sample.id)
                let result = recomputeSidecars(
                    in: sampleDirectory,
                    encoder: encoder,
                    loadResult: loadResult
                )
                scannedMeasurementFileCount += result.scannedMeasurementFileCount
                createdSidecarCount += result.createdSidecarCount
                updatedSidecarCount += result.updatedSidecarCount
                skippedExistingSidecarCount += result.skippedExistingSidecarCount
                failedSidecarCount += result.failedSidecarCount
            }
        }

        return BackfillSidecarsResult(
            scannedSampleCount: scannedSampleCount,
            scannedMeasurementFileCount: scannedMeasurementFileCount,
            createdSidecarCount: createdSidecarCount,
            updatedSidecarCount: updatedSidecarCount,
            skippedExistingSidecarCount: skippedExistingSidecarCount,
            failedSidecarCount: failedSidecarCount
        )
    }

    @available(*, deprecated, renamed: "recomputeAllMeasurementSidecars")
    func backfillMissingMeasurementSidecars(rootURL: URL) -> BackfillSidecarsResult {
        recomputeAllMeasurementSidecars(rootURL: rootURL)
    }

    func syncBackup(from rootURL: URL, to backupURL: URL) -> Bool {
        do {
            var isRootDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isRootDirectory), isRootDirectory.boolValue else {
                return false
            }

            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
            try mergeBackupContents(from: rootURL, to: backupURL)
            return true
        } catch {
            return false
        }
    }

    private func mergeBackupContents(from sourceRootURL: URL, to destinationRootURL: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: sourceRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let sourceURL as URL in enumerator {
            let relativePath = sourceURL.path.replacingOccurrences(of: sourceRootURL.path + "/", with: "")
            guard !relativePath.isEmpty else {
                continue
            }

            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            let destinationURL = destinationRootURL.appending(path: relativePath, directoryHint: values.isDirectory == true ? .isDirectory : .notDirectory)

            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }

            try copyOrReplaceFileIfNeeded(from: sourceURL, to: destinationURL)
        }
    }

    private func copyOrReplaceFileIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        if isSameFile(sourceURL, destinationURL) {
            return
        }

        try fileManager.removeItem(at: destinationURL)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func isSameFile(_ lhsURL: URL, _ rhsURL: URL) -> Bool {
        guard
            let lhs = try? fileManager.attributesOfItem(atPath: lhsURL.path),
            let rhs = try? fileManager.attributesOfItem(atPath: rhsURL.path),
            let lhsSize = lhs[.size] as? NSNumber,
            let rhsSize = rhs[.size] as? NSNumber
        else {
            return false
        }

        guard lhsSize.int64Value == rhsSize.int64Value else {
            return false
        }

        let lhsModified = lhs[.modificationDate] as? Date
        let rhsModified = rhs[.modificationDate] as? Date
        if lhsModified == rhsModified {
            return true
        }

        return fileContentsEqual(lhsURL, rhsURL)
    }

    private func fileContentsEqual(_ lhsURL: URL, _ rhsURL: URL) -> Bool {
        let chunkSize = 64 * 1024

        guard
            let lhsHandle = try? FileHandle(forReadingFrom: lhsURL),
            let rhsHandle = try? FileHandle(forReadingFrom: rhsURL)
        else {
            return false
        }
        defer {
            try? lhsHandle.close()
            try? rhsHandle.close()
        }

        while true {
            guard
                let lhsData = try? lhsHandle.read(upToCount: chunkSize),
                let rhsData = try? rhsHandle.read(upToCount: chunkSize)
            else {
                return false
            }

            guard lhsData == rhsData else {
                return false
            }

            if lhsData.isEmpty {
                return true
            }
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

    @discardableResult
    private func appendSampleChangeLogIfNeeded(
        previous: LibrarySample?,
        updated: LibrarySample,
        source: String,
        sampleURL: URL
    ) -> [LibrarySampleChangeLogItem] {
        guard let previous, previous != updated else {
            return []
        }
        let changes = sampleChangeItems(old: previous, new: updated)
        guard !changes.isEmpty else {
            return []
        }

        let logURL = sampleChangeLogURL(sampleURL: sampleURL)
        var entries = loadSampleChangeLogEntries(from: logURL)
        entries.append(
            LibrarySampleChangeLogEntry(
                id: UUID(),
                sampleId: updated.id,
                batchId: updated.batchId,
                changedAt: .now,
                source: source,
                changes: changes
            )
        )
        writeJSON(entries, to: logURL)
        return changes
    }

    private func appendBatchEditLogIfNeeded(
        changes: [LibrarySampleChangeLogItem],
        updated: LibrarySample,
        source: String,
        rootURL: URL
    ) {
        guard !changes.isEmpty else {
            return
        }
        let batchURL = resolvedBatchDirectoryURL(rootURL, batchID: updated.batchId)
        let logURL = batchEditLogURL(batchURL: batchURL)
        var entries = loadSampleChangeLogEntries(from: logURL)
        entries.append(
            LibrarySampleChangeLogEntry(
                id: UUID(),
                sampleId: updated.id,
                batchId: updated.batchId,
                changedAt: .now,
                source: source,
                changes: changes
            )
        )
        writeJSON(entries, to: logURL)
    }

    private func loadSampleChangeLogEntries(from url: URL) -> [LibrarySampleChangeLogEntry] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LibrarySampleChangeLogEntry].self, from: data)) ?? []
    }

    private func sampleChangeLogURL(sampleURL: URL) -> URL {
        sampleURL.appending(path: "sample_change_log.json")
    }

    private func batchEditLogURL(batchURL: URL) -> URL {
        batchURL.appending(path: "edit_log.json")
    }

    private func sampleChangeItems(old: LibrarySample, new: LibrarySample) -> [LibrarySampleChangeLogItem] {
        var items: [LibrarySampleChangeLogItem] = []

        addChange("displayName", old: old.displayName, new: new.displayName, into: &items)
        addChange("substrateRaw", old: old.substrateRaw, new: new.substrateRaw, into: &items)
        addChange("substrateDisplay", old: old.substrateDisplay, new: new.substrateDisplay, into: &items)
        addChange("substrateTags", old: old.substrateTags.joined(separator: ", "), new: new.substrateTags.joined(separator: ", "), into: &items)
        addChange("substrateTokens", old: old.substrateTokens.joined(separator: ", "), new: new.substrateTokens.joined(separator: ", "), into: &items)

        let metadataKeys = Set(old.metadata.keys).union(new.metadata.keys).sorted()
        for key in metadataKeys {
            addChange("metadata.\(key)", old: old.metadata[key], new: new.metadata[key], into: &items)
        }

        let numericKeys = Set(old.numericDisplay.keys).union(new.numericDisplay.keys).sorted()
        for key in numericKeys {
            addChange("numeric.\(key)", old: old.numericDisplay[key], new: new.numericDisplay[key], into: &items)
        }

        return items
    }

    private func addChange(
        _ key: String,
        old oldValue: String?,
        new newValue: String?,
        into items: inout [LibrarySampleChangeLogItem]
    ) {
        let normalizedOld = normalizedLogValue(oldValue)
        let normalizedNew = normalizedLogValue(newValue)
        guard normalizedOld != normalizedNew else {
            return
        }
        items.append(
            LibrarySampleChangeLogItem(
                key: key,
                oldValue: normalizedOld,
                newValue: normalizedNew
            )
        )
    }

    private func normalizedLogValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func loadRegistryManualUpdateLogEntries(registrySourceURL: URL) throws -> [LibraryManualUpdateLogEntry] {
        try xlsxSyncService.loadNumericLogEntries(registrySourceURL: registrySourceURL)
    }

    func updateRegistryManualUpdateLogStatus(
        registrySourceURL: URL,
        rowIndex: Int,
        status: LibraryManualLogStatus,
        statusChangedBy: String
    ) throws {
        try xlsxSyncService.updateNumericLogStatus(
            registrySourceURL: registrySourceURL,
            rowIndex: rowIndex,
            status: status,
            statusChangedBy: statusChangedBy
        )
    }

    func loadRegistryMetadataSyncLogEntries(registrySourceURL: URL) throws -> [LibraryMetadataSyncLogEntry] {
        try xlsxSyncService.loadMetadataLogEntries(registrySourceURL: registrySourceURL)
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
        let key = batchJSONURL.path
        let modificationDate = modificationDate(of: batchJSONURL)
        if let cached = decodedBatchCache[key], cached.modificationDate == modificationDate {
            return cached.batch
        }
        guard let data = try? Data(contentsOf: batchJSONURL) else {
            decodedBatchCache[key] = DecodedBatchCacheEntry(modificationDate: modificationDate, batch: nil)
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(LibraryBatch.self, from: data)
        decodedBatchCache[key] = DecodedBatchCacheEntry(modificationDate: modificationDate, batch: decoded)
        return decoded
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
        let key = sampleJSONURL.path
        let modificationDate = modificationDate(of: sampleJSONURL)
        if let cached = decodedSampleCache[key], cached.modificationDate == modificationDate {
            return cached.sample
        }
        guard let data = try? Data(contentsOf: sampleJSONURL) else {
            decodedSampleCache[key] = DecodedSampleCacheEntry(modificationDate: modificationDate, sample: nil)
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(LibrarySample.self, from: data)
        decodedSampleCache[key] = DecodedSampleCacheEntry(modificationDate: modificationDate, sample: decoded)
        return decoded
    }

    private func scanAppliedMeasurements(in sampleDirectory: URL) -> [AppliedMeasurement] {
        let measurementsURL = sampleDirectory.appending(path: "measurements", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: measurementsURL.path),
              let enumerator = fileManager.enumerator(
                at: measurementsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var results: [AppliedMeasurement] = []
        results.reserveCapacity(16)

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
            guard let data = try? Data(contentsOf: url),
                  let sidecar = try? decoder.decode(SpinLabFileSidecar.self, from: data) else {
                continue
            }

            let normalizedSourceFileName = URL(fileURLWithPath: sidecar.sourceFilePath).lastPathComponent
            let sourceFileName: String
            if normalizedSourceFileName.isEmpty {
                sourceFileName = url.lastPathComponent.replacingOccurrences(of: ".spinlab.json", with: "")
            } else {
                sourceFileName = normalizedSourceFileName
            }
            // For sidecars written before workflowDisplayName was added, fall back to id.
            let displayName = sidecar.workflowDisplayName.isEmpty
                ? sidecar.workflow
                : sidecar.workflowDisplayName
            results.append(
                AppliedMeasurement(
                    id: url.path,
                    workflow: sidecar.workflow,
                    workflowDisplayName: displayName,
                    conditions: sidecar.effectiveConditions,
                    appliedAt: sidecar.appliedAt,
                    sourceFileName: sourceFileName
                )
            )
        }

        return results.sorted { $0.appliedAt > $1.appliedAt }
    }

    private struct SidecarBackfillStats {
        var scannedMeasurementFileCount: Int = 0
        var createdSidecarCount: Int = 0
        var updatedSidecarCount: Int = 0
        var skippedExistingSidecarCount: Int = 0
        var failedSidecarCount: Int = 0
    }

    private func recomputeSidecars(
        in sampleDirectory: URL,
        encoder: JSONEncoder,
        loadResult: RuleLoader.LoadResult
    ) -> SidecarBackfillStats {
        let measurementsURL = sampleDirectory.appending(path: "measurements", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: measurementsURL.path),
              let enumerator = fileManager.enumerator(
                at: measurementsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return SidecarBackfillStats()
        }

        let parser = FilenameRuleParser(ruleSet: loadResult.ruleSet)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var stats = SidecarBackfillStats()
        var mutated = false
        for case let url as URL in enumerator {
            guard !url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }

            stats.scannedMeasurementFileCount += 1

            let hints = parser.parse(from: url)
            let snapshot = SidecarCompositionUseCase.buildRuleSnapshot(
                hints: hints,
                ruleSetFingerprint: loadResult.ruleSetFingerprint,
                ruleSetVersion: loadResult.ruleSetVersion,
                evaluatedAt: .now
            )

            let sidecarURL = url.deletingPathExtension().appendingPathExtension(url.pathExtension + ".spinlab.json")

            if fileManager.fileExists(atPath: sidecarURL.path) {
                guard let existingData = try? Data(contentsOf: sidecarURL),
                      let existing = try? decoder.decode(SpinLabFileSidecar.self, from: existingData) else {
                    stats.skippedExistingSidecarCount += 1
                    continue
                }

                let updated = SidecarCompositionUseCase.composeSidecarV2(
                    base: SidecarCompositionBase(
                        workflow: existing.workflow,
                        workflowDisplayName: existing.workflowDisplayName,
                        channels: existing.channels,
                        sourceFilePath: existing.sourceFilePath,
                        existingSidecar: existing
                    ),
                    snapshot: snapshot,
                    preserveUserOverrides: true,
                    now: .now
                )
                do {
                    let data = try encoder.encode(updated)
                    try data.write(to: sidecarURL, options: .atomic)
                    stats.updatedSidecarCount += 1
                    mutated = true
                } catch {
                    stats.failedSidecarCount += 1
                    logger.warning(.library, "Failed to recompute sidecar", metadata: [
                        "sidecarPath": sidecarURL.path,
                        "reason": error.localizedDescription
                    ])
                }
            } else {
                let workflow = inferredWorkflow(forMeasurementFile: url, measurementsRoot: measurementsURL)
                let sidecar = SidecarCompositionUseCase.composeSidecarV2(
                    base: SidecarCompositionBase(
                        workflow: workflow,
                        workflowDisplayName: workflow,
                        channels: [],
                        sourceFilePath: url.path,
                        existingSidecar: nil
                    ),
                    snapshot: snapshot,
                    preserveUserOverrides: false,
                    now: .now
                )
                do {
                    let data = try encoder.encode(sidecar)
                    try data.write(to: sidecarURL, options: .atomic)
                    stats.createdSidecarCount += 1
                    mutated = true
                } catch {
                    stats.failedSidecarCount += 1
                    logger.warning(.library, "Failed to create sidecar", metadata: [
                        "measurementPath": url.path,
                        "sidecarPath": sidecarURL.path,
                        "reason": error.localizedDescription
                    ])
                }
            }
        }

        if mutated {
            invalidateNodeCache(at: sampleDirectory)
        }
        return stats
    }

    private func inferredWorkflow(forMeasurementFile fileURL: URL, measurementsRoot: URL) -> String {
        let components = fileURL.pathComponents
        guard let measurementsIndex = components.lastIndex(of: "measurements") else {
            return "General"
        }
        let workflowIndex = measurementsIndex + 1
        guard workflowIndex < components.count - 1 else {
            return "General"
        }
        return components[workflowIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "General"
    }

    private func sidecarSignatures(in sampleDirectory: URL) -> [String] {
        let measurementsURL = sampleDirectory.appending(path: "measurements", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: measurementsURL.path),
              let enumerator = fileManager.enumerator(
                at: measurementsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var signatures: [String] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".spinlab.json") else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let fileSize = values?.fileSize ?? 0
            signatures.append("\(url.path)|\(modifiedAt)|\(fileSize)")
        }

        return signatures.sorted()
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
        let key = url.path
        let modificationDate = modificationDate(of: url)
        if let cached = directoryEntriesCache[key], cached.modificationDate == modificationDate {
            return cached.entries
        }

        let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        if let entries {
            directoryEntriesCache[key] = DirectoryEntriesCacheEntry(modificationDate: modificationDate, entries: entries)
        } else {
            directoryEntriesCache.removeValue(forKey: key)
        }
        return entries
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard isDirectory(url) else {
            return
        }
        guard let entries = directoryEntries(at: url), entries.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: url)
        invalidateNodeCache(at: url)
    }

    private func modificationDate(of url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    private func cachedFileEntries(in directoryURL: URL) -> [URL] {
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

    private func invalidateNodeCache(at url: URL) {
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
