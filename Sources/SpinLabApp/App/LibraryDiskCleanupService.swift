import Foundation

enum LibraryDiskCleanupService {
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
        let relPath = "samples/\(sampleKey)/_spinlab/measurement_data.json"

        guard let absURL = try? resolver.absoluteURL(for: relPath),
              let data = try? Data(contentsOf: absURL) else {
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var store = try? decoder.decode(WorkbenchMeasurementDataStore.self, from: data) else {
            fputs("[SpinLab] deleteMetricRecord: measurement_data.json unreadable for \(sampleKey), aborting\n", stderr)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded: Data
        do {
            encoded = try encoder.encode(store)
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
    /// 4. Only after all indexes are consistent, delete the PNG and manifest (best-effort).
    @discardableResult
    nonisolated static func deleteWorkbenchResultOnDisk(
        _ ref: WorkbenchResultReference,
        rootURL: URL
    ) -> Bool {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let writer = AtomicFileWriter()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // 1. Enumerate all results_index.json files directly from the filesystem.
        let samplesURL = rootURL.appending(path: "samples")
        let sampleDirs = (try? FileManager.default.contentsOfDirectory(
            at: samplesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        // 2. For every index that references this identity key, build an updated write entry.
        let now = Date()
        var indexWrites: [AtomicWriteEntry] = []
        var preparationFailed = false

        for sampleDir in sampleDirs {
            let indexURL = sampleDir.appending(path: "_spinlab/results_index.json")
            guard FileManager.default.fileExists(atPath: indexURL.path) else { continue }
            let sk = sampleDir.lastPathComponent

            // Fail-closed: if the file exists but cannot be decoded, abort entirely.
            // A corrupt index may still reference this chart; deleting the chart files
            // without cleaning the reference would leave a dangling pointer.
            guard var index = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sk) else {
                fputs("[SpinLab] deleteWorkbenchResult: results_index unreadable for \(sk), aborting\n", stderr)
                preparationFailed = true
                break
            }
            guard index.references.contains(where: { $0.chartIdentityKey == ref.chartIdentityKey }) else {
                continue  // This sample does not reference the chart — nothing to do
            }

            // Reference found: build the write entry. Any failure here must abort the whole operation.
            index.references.removeAll { $0.chartIdentityKey == ref.chartIdentityKey }
            index.updatedAt = now
            let data: Data
            do {
                data = try encoder.encode(index)
            } catch {
                fputs("[SpinLab] deleteWorkbenchResult: encode failed for \(sk): \(error)\n", stderr)
                preparationFailed = true
                break
            }
            indexWrites.append(AtomicWriteEntry(destinationURL: indexURL, data: data))

            // Also clean measurement_plot_index.json for this sample (P1: disk-level cleanup).
            let plotIndexURL = sampleDir.appending(path: "_spinlab/measurement_plot_index.json")
            if var plotIndex = LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sk) {
                let keyToRemove = ref.chartIdentityKey
                var changed = false
                plotIndex.entries = plotIndex.entries
                    .mapValues { keys in
                        let filtered = keys.filter { $0 != keyToRemove }
                        if filtered.count != keys.count { changed = true }
                        return filtered
                    }
                    .filter { !$0.value.isEmpty }
                if changed {
                    plotIndex.updatedAt = now
                    let plotData: Data
                    do {
                        plotData = try encoder.encode(plotIndex)
                    } catch {
                        fputs("[SpinLab] deleteWorkbenchResult: plot index encode failed for \(sk): \(error)\n", stderr)
                        preparationFailed = true
                        break
                    }
                    indexWrites.append(AtomicWriteEntry(destinationURL: plotIndexURL, data: plotData))
                }
            }
            // measurement_plot_index.json missing → nothing to clean (not an error).
        }

        // Abort if any write entry could not be prepared — do not touch files.
        guard !preparationFailed else { return false }

        // 3. Atomically commit all index updates. Abort if the commit fails.
        do {
            try writer.commit(indexWrites)
        } catch {
            fputs("[SpinLab] deleteWorkbenchResult: atomic commit failed: \(error)\n", stderr)
            return false
        }

        // 4. Delete the chart files only after all indexes are consistent.
        for relPath in [ref.chartImagePath, ref.manifestPath] {
            if let url = try? resolver.absoluteURL(for: relPath) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return true
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
        let sourceFileName = measurement.sourceFileName

        // --- Step 1: Cascade-delete associated charts (scoped to this sample) ---

        let plotIndexRelPath = "samples/\(sampleKey)/_spinlab/measurement_plot_index.json"
        if let plotIndexAbsURL = try? resolver.absoluteURL(for: plotIndexRelPath),
           fm.fileExists(atPath: plotIndexAbsURL.path) {
            // File exists — must be decodable or fail-closed.
            guard let plotIndex = LoadMeasurementPlotIndexUseCase(pathResolver: resolver)
                .execute(sampleKey: sampleKey) else {
                fputs("[SpinLab] deleteAppliedMeasurement: measurement_plot_index corrupt for \(sampleKey), aborting\n", stderr)
                return false
            }

            if let chartKeys = plotIndex.entries[sourceFileName], !chartKeys.isEmpty {
                let resultsIndexRelPath = "samples/\(sampleKey)/_spinlab/results_index.json"
                if let resultsIndexAbsURL = try? resolver.absoluteURL(for: resultsIndexRelPath),
                   fm.fileExists(atPath: resultsIndexAbsURL.path) {
                    // File exists — must be decodable or fail-closed.
                    guard let resultsIndex = LoadWorkbenchResultsUseCase(pathResolver: resolver)
                        .execute(sampleKey: sampleKey) else {
                        fputs("[SpinLab] deleteAppliedMeasurement: results_index corrupt for \(sampleKey), aborting\n", stderr)
                        return false
                    }

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
