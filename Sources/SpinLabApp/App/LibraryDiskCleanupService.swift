import Foundation

enum LibraryDiskCleanupService {
    private struct DeletedChartArchiveRecord: Codable, Hashable, Sendable {
        var schemaVersion: Int = 1
        var chartIdentityKey: String
        var deletedAt: Date
        var originalChartImagePath: String
        var originalManifestPath: String
        var archivedChartImagePath: String
        var archivedManifestPath: String
        var workflowID: String
    }

    private static let archiveRecordEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let archiveFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    // MARK: - Metric record deletion (V4.1.11)

    /// Removes a single metric record from measurement_data.json by identity key.
    /// Removes the record from `records` and `latestIndex`, then writes back atomically.
    @discardableResult
    nonisolated static func deleteMetricRecordOnDisk(
        identityKey: String,
        sampleKey: String,
        rootURL: URL
    ) -> Bool {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let dataStore = LibraryMeasurementDataStore(layout: layout)

        guard let absURL = try? layout.measurementDataURL(sampleKey: sampleKey) else {
            return false
        }

        var store: WorkbenchMeasurementDataStore
        do {
            guard let loaded = try dataStore.loadStrict(sampleKey: sampleKey) else {
                return false
            }
            store = loaded
        } catch {
            fputs("[SpinLab] deleteMetricRecord: measurement_data.json unreadable for \(sampleKey), aborting: \(error)\n", stderr)
            return false
        }

        // Find the recordID referenced by this identity key
        guard let pointer = store.latestIndex[identityKey] else {
            fputs("[SpinLab] deleteMetricRecord: identity key not found in latestIndex\n", stderr)
            return false
        }

        // Remove from records and latestIndex
        store.records.removeAll { $0.recordID == pointer.recordID }
        store.latestIndex.removeValue(forKey: identityKey)

        // Write back atomically
        let encoded: Data
        do {
            encoded = try dataStore.encode(store)
        } catch {
            fputs("[SpinLab] deleteMetricRecord: encode failed for \(sampleKey): \(error)\n", stderr)
            return false
        }

        let writer = AtomicFileWriter()
        do {
            try writer.commit([AtomicWriteEntry(destinationURL: absURL, data: encoded)])
        } catch {
            fputs("[SpinLab] deleteMetricRecord: write failed: \(error)\n", stderr)
            return false
        }

        return true
    }

    // MARK: - Workbench Results deletion (V3.4.3)

    /// Removes `ref` from every sample's `results_index.json`, then deletes the chart files.
    ///
    /// Algorithm (fail-closed, index-first):
    /// 1. Enumerate ALL `results_index.json` files directly from the filesystem under `samples/*/`
    ///    — does not depend on LibraryIndex being loadable, so a corrupt or missing library index
    ///    cannot cause partial cleanup.
    /// 2. For each index that contains this identity key, prepare an atomic write entry.
    ///    If ANY write entry cannot be prepared (path resolution or encode failure), abort entirely.
    /// 3. Atomically commit all index rewrites. Abort if the commit throws.
    /// 4. Archive the PNG and manifest under deleted-charts/, then delete the active originals.
    /// 5. If the archive or final delete fails, restore the active indexes and leave a visible log.
    @discardableResult
    nonisolated static func deleteWorkbenchResultOnDisk(
        _ ref: WorkbenchResultReference,
        rootURL: URL
    ) -> Bool {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let writer = AtomicFileWriter()
        let fileManager = FileManager.default
        let now = Date()

        let imageURL: URL
        let manifestURL: URL
        do {
            imageURL = try resolver.absoluteURL(for: ref.chartImagePath)
            manifestURL = try resolver.absoluteURL(for: ref.manifestPath)
        } catch {
            fputs("[SpinLab] deleteWorkbenchResult: path resolve failed for \(ref.chartIdentityKey): \(error)\n", stderr)
            return false
        }

        guard fileManager.fileExists(atPath: imageURL.path) else {
            fputs("[SpinLab] deleteWorkbenchResult: active PNG missing for \(ref.chartIdentityKey)\n", stderr)
            return false
        }
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            fputs("[SpinLab] deleteWorkbenchResult: active manifest missing for \(ref.chartIdentityKey)\n", stderr)
            return false
        }

        // 1. Enumerate all sample directories directly from the filesystem.
        let samplesURL = layout.samplesRootURL()
        let sampleDirs = (try? FileManager.default.contentsOfDirectory(
            at: samplesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        // 2. For every index that references this identity key, build an updated write entry.
        // Fail-closed: missing index → nothing to do; corrupt index → abort the whole
        // operation with zero filesystem mutation (a corrupt index may still reference
        // this chart, so deleting files without cleaning the reference would dangle it).
        var indexWrites: [AtomicWriteEntry] = []
        var rollbackIndexWrites: [AtomicWriteEntry] = []
        var preparationFailed = false

        for sampleDir in sampleDirs {
            let sk = sampleDir.lastPathComponent

            let loadedResults: (index: WorkbenchResultsIndex, rawData: Data)?
            do {
                loadedResults = try indexStore.loadResultsIndexStrict(sampleKey: sk)
            } catch {
                fputs("[SpinLab] deleteWorkbenchResult: results_index unreadable for \(sk), aborting: \(error)\n", stderr)
                preparationFailed = true
                break
            }
            guard let (originalIndex, originalIndexData) = loadedResults else {
                continue  // Missing index — nothing to do for this sample.
            }
            guard originalIndex.references.contains(where: { $0.chartIdentityKey == ref.chartIdentityKey }) else {
                continue  // This sample does not reference the chart — nothing to do
            }

            // Reference found: build the write entry. Any failure here must abort the whole operation.
            let updatedIndex = indexStore.removingReference(chartIdentityKey: ref.chartIdentityKey, from: originalIndex, updatedAt: now)
            let indexURL: URL
            let data: Data
            do {
                indexURL = try layout.resultsIndexURL(sampleKey: sk)
                data = try indexStore.encodeResultsIndex(updatedIndex)
            } catch {
                fputs("[SpinLab] deleteWorkbenchResult: encode failed for \(sk): \(error)\n", stderr)
                preparationFailed = true
                break
            }
            indexWrites.append(AtomicWriteEntry(destinationURL: indexURL, data: data))
            rollbackIndexWrites.append(AtomicWriteEntry(destinationURL: indexURL, data: originalIndexData))

            // Also clean measurement_plot_index.json for this sample (P1: disk-level cleanup).
            let loadedPlot: (index: MeasurementPlotIndex, rawData: Data)?
            do {
                loadedPlot = try indexStore.loadPlotIndexStrict(sampleKey: sk)
            } catch {
                fputs("[SpinLab] deleteWorkbenchResult: plot_index unreadable for \(sk), aborting: \(error)\n", stderr)
                preparationFailed = true
                break
            }
            if let (originalPlotIndex, originalPlotIndexData) = loadedPlot {
                let keyToRemove = ref.chartIdentityKey
                let changed = originalPlotIndex.entries.values.contains { $0.contains(keyToRemove) }
                if changed {
                    let updatedPlotIndex = indexStore.removingChartKeys([keyToRemove], from: originalPlotIndex, updatedAt: now)
                    let plotIndexURL: URL
                    let plotData: Data
                    do {
                        plotIndexURL = try layout.measurementPlotIndexURL(sampleKey: sk)
                        plotData = try indexStore.encodePlotIndex(updatedPlotIndex)
                    } catch {
                        fputs("[SpinLab] deleteWorkbenchResult: plot index encode failed for \(sk): \(error)\n", stderr)
                        preparationFailed = true
                        break
                    }
                    indexWrites.append(AtomicWriteEntry(destinationURL: plotIndexURL, data: plotData))
                    rollbackIndexWrites.append(AtomicWriteEntry(destinationURL: plotIndexURL, data: originalPlotIndexData))
                }
            }
            // measurement_plot_index.json missing → nothing to clean (not an error).
        }

        // Abort if any write entry could not be prepared — do not touch files.
        guard !preparationFailed else { return false }

        let archiveFolderName = Self.archiveFolderName(for: ref, generatedAt: ref.generatedAt)
        let archiveDirectoryURL = layout.deletedChartArchiveDirectoryURL(
            forChartImageURL: imageURL,
            folderName: archiveFolderName
        )
        let archivedImageURL = archiveDirectoryURL.appending(path: imageURL.lastPathComponent, directoryHint: .notDirectory)
        let archivedManifestURL = archiveDirectoryURL.appending(path: manifestURL.lastPathComponent, directoryHint: .notDirectory)
        let archiveRecordURL = archiveDirectoryURL.appending(path: "archive.json", directoryHint: .notDirectory)
        let archivedImagePath: String
        let archivedManifestPath: String
        do {
            archivedImagePath = try resolver.relativePath(for: archivedImageURL)
            archivedManifestPath = try resolver.relativePath(for: archivedManifestURL)
        } catch {
            fputs("[SpinLab] deleteWorkbenchResult: archive path resolution failed for \(ref.chartIdentityKey): \(error)\n", stderr)
            return false
        }

        let archiveRecord = DeletedChartArchiveRecord(
            chartIdentityKey: ref.chartIdentityKey,
            deletedAt: now,
            originalChartImagePath: ref.chartImagePath,
            originalManifestPath: ref.manifestPath,
            archivedChartImagePath: archivedImagePath,
            archivedManifestPath: archivedManifestPath,
            workflowID: ref.workflowID
        )
        guard let archiveRecordData = try? Self.archiveRecordEncoder.encode(archiveRecord) else {
            fputs("[SpinLab] deleteWorkbenchResult: archive record encode failed for \(ref.chartIdentityKey)\n", stderr)
            return false
        }

        do {
            try fileManager.createDirectory(at: archiveDirectoryURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: imageURL, to: archivedImageURL)
            try fileManager.copyItem(at: manifestURL, to: archivedManifestURL)
        } catch {
            fputs("[SpinLab] deleteWorkbenchResult: archive staging failed for \(ref.chartIdentityKey): \(error)\n", stderr)
            try? fileManager.removeItem(at: archiveDirectoryURL)
            return false
        }

        // 3. Atomically commit all index updates. Abort if the commit fails.
        do {
            try writer.commit(indexWrites + [AtomicWriteEntry(destinationURL: archiveRecordURL, data: archiveRecordData)])
        } catch {
            fputs("[SpinLab] deleteWorkbenchResult: atomic commit failed: \(error)\n", stderr)
            if !rollbackIndexWrites.isEmpty {
                do {
                    try writer.commit(rollbackIndexWrites)
                    try? fileManager.removeItem(at: archiveDirectoryURL)
                } catch {
                    fputs("[SpinLab] deleteWorkbenchResult: failed to restore active indexes: \(error)\n", stderr)
                }
            } else {
                try? fileManager.removeItem(at: archiveDirectoryURL)
            }
            return false
        }

        // 4. Delete the active originals only after all indexes and archive files are in place.
        var deleteFailed = false
        for url in [imageURL, manifestURL] {
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            } catch {
                fputs("[SpinLab] deleteWorkbenchResult: failed to remove active file \(url.path): \(error)\n", stderr)
                deleteFailed = true
            }
        }

        if deleteFailed {
            fputs("[SpinLab] deleteWorkbenchResult: restoring active indexes after filesystem failure for \(ref.chartIdentityKey)\n", stderr)
            if fileManager.fileExists(atPath: imageURL.path) == false {
                try? fileManager.copyItem(at: archivedImageURL, to: imageURL)
            }
            if fileManager.fileExists(atPath: manifestURL.path) == false {
                try? fileManager.copyItem(at: archivedManifestURL, to: manifestURL)
            }
            if !rollbackIndexWrites.isEmpty {
                do {
                    try writer.commit(rollbackIndexWrites)
                    try? fileManager.removeItem(at: archiveDirectoryURL)
                } catch {
                    fputs("[SpinLab] deleteWorkbenchResult: failed to restore active indexes: \(error)\n", stderr)
                }
            }
            return false
        }

        return true
    }

    private static func archiveFolderName(for ref: WorkbenchResultReference, generatedAt: Date) -> String {
        let timestamp = archiveFolderFormatter.string(from: generatedAt)
        return "\(ref.chartIdentityKey)-\(timestamp)"
    }

    private static func archiveDirectoryURL(for sourceURL: URL, folderName: String) -> URL {
        let chartDirectoryURL = sourceURL.deletingLastPathComponent()
        let archiveRootURL = chartDirectoryURL.deletingLastPathComponent().appending(path: "deleted-charts", directoryHint: .isDirectory)
        return archiveRootURL.appending(path: folderName, directoryHint: .isDirectory)
    }

    // MARK: - Applied Measurement deletion (V4.1.6)

    /// Pure filesystem operation: cascade-deletes an applied measurement's charts,
    /// sidecar, data file, and measurement set membership.
    ///
    /// Fail-closed: if any index file exists but cannot be decoded, returns `false`
    /// without deleting any files. Missing sidecar or data file is non-fatal.
    @discardableResult
    nonisolated static func deleteAppliedMeasurementOnDisk(
        _ measurement: AppliedMeasurement,
        rootURL: URL
    ) -> Bool {
        let sidecarURL = URL(fileURLWithPath: measurement.id).standardizedFileURL
        let sidecarPath = sidecarURL.path
        let rootPath = rootURL.standardizedFileURL.path
        let fm = FileManager.default

        // Guard: sidecar must be inside library root.
        guard sidecarPath.hasPrefix(rootPath + "/") else {
            fputs("[SpinLab] deleteAppliedMeasurement: sidecar outside library root\n", stderr)
            return false
        }

        // Dual condition: (1) path is in a /measurements/ subtree,
        //                 (2) derived sample dir contains a measurements/ subdirectory.
        guard let measurementsRange = sidecarPath.range(of: "/measurements/") else {
            fputs("[SpinLab] deleteAppliedMeasurement: sidecar not in measurements/ subtree\n", stderr)
            return false
        }
        let batchSampleDirPath = String(sidecarPath[..<measurementsRange.lowerBound])
        let batchSampleDirURL = URL(fileURLWithPath: batchSampleDirPath)

        guard fm.fileExists(atPath: batchSampleDirURL.appending(path: "measurements").path) else {
            fputs("[SpinLab] deleteAppliedMeasurement: derived sample dir missing measurements/\n", stderr)
            return false
        }

        let sampleKey = batchSampleDirURL.lastPathComponent
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let sourceFileName = measurement.sourceFileName

        // --- Step 1: Cascade-delete associated charts (scoped to this sample) ---
        // Fail-closed: missing index → nothing to cascade; corrupt index → abort.

        let loadedPlotIndex: (index: MeasurementPlotIndex, rawData: Data)?
        do {
            loadedPlotIndex = try indexStore.loadPlotIndexStrict(sampleKey: sampleKey)
        } catch {
            fputs("[SpinLab] deleteAppliedMeasurement: measurement_plot_index corrupt for \(sampleKey), aborting: \(error)\n", stderr)
            return false
        }

        if let (plotIndex, _) = loadedPlotIndex,
           let chartKeys = plotIndex.entries[sourceFileName], !chartKeys.isEmpty {
            let loadedResultsIndex: (index: WorkbenchResultsIndex, rawData: Data)?
            do {
                loadedResultsIndex = try indexStore.loadResultsIndexStrict(sampleKey: sampleKey)
            } catch {
                fputs("[SpinLab] deleteAppliedMeasurement: results_index corrupt for \(sampleKey), aborting: \(error)\n", stderr)
                return false
            }

            if let (resultsIndex, _) = loadedResultsIndex {
                for chartKey in chartKeys {
                    if let ref = resultsIndex.references.first(where: { $0.chartIdentityKey == chartKey }) {
                        guard deleteWorkbenchResultOnDisk(ref, rootURL: rootURL) else {
                            fputs("[SpinLab] deleteAppliedMeasurement: chart cascade failed for \(chartKey), aborting\n", stderr)
                            return false
                        }
                    }
                }
            }
        }
        // measurement_plot_index absent → no charts to cascade (not an error).

        // --- Step 2: Delete sidecar (missing = non-fatal, delete failure = fatal) ---

        if fm.fileExists(atPath: sidecarPath) {
            do {
                try fm.removeItem(atPath: sidecarPath)
            } catch {
                fputs("[SpinLab] deleteAppliedMeasurement: failed to delete sidecar: \(error)\n", stderr)
                return false
            }
        } else {
            fputs("[SpinLab] deleteAppliedMeasurement: sidecar already absent\n", stderr)
        }

        // --- Step 3: Delete data file (missing = non-fatal, delete failure = fatal) ---

        let sidecarFileName = sidecarURL.lastPathComponent
        let sidecarSuffix = ".spinlab.json"
        if sidecarFileName.hasSuffix(sidecarSuffix) {
            let dataFileName = String(sidecarFileName.dropLast(sidecarSuffix.count))
            let dataFileURL = sidecarURL.deletingLastPathComponent().appending(path: dataFileName)
            if fm.fileExists(atPath: dataFileURL.path) {
                do {
                    try fm.removeItem(at: dataFileURL)
                } catch {
                    fputs("[SpinLab] deleteAppliedMeasurement: failed to delete data file: \(error)\n", stderr)
                    return false
                }
            } else {
                fputs("[SpinLab] deleteAppliedMeasurement: data file already absent\n", stderr)
            }
        }

        // --- Step 4: Remove from measurement sets (scoped to matching workflow) ---

        let setsFileURL = batchSampleDirURL.appending(path: "measurement_sets.json")
        if fm.fileExists(atPath: setsFileURL.path),
           let setsData = try? Data(contentsOf: setsFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if var sets = try? decoder.decode([MeasurementSet].self, from: setsData) {
                var changed = false
                for i in sets.indices {
                    guard sets[i].workflow == measurement.workflow else { continue }
                    if sets[i].memberFileNames.contains(sourceFileName) {
                        sets[i].memberFileNames.removeAll { $0 == sourceFileName }
                        changed = true
                    }
                }
                let beforeCount = sets.count
                sets.removeAll { $0.memberFileNames.isEmpty }
                if sets.count != beforeCount { changed = true }

                if changed {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    do {
                        if sets.isEmpty {
                            try fm.removeItem(at: setsFileURL)
                        } else {
                            let data = try encoder.encode(sets)
                            try data.write(to: setsFileURL, options: .atomic)
                        }
                    } catch {
                        fputs("[SpinLab] deleteAppliedMeasurement: failed to update measurement_sets.json: \(error)\n", stderr)
                        return false
                    }
                }
            }
        }

        return true
    }
}
