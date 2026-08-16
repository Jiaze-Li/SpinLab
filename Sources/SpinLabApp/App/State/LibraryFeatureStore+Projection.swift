import Foundation

extension LibraryFeatureStore {
    // MARK: - Workbench Results load (V3.4.2)

    /// Loads the `WorkbenchResultsIndex` for the currently selected sample.
    /// Called automatically from selection changes; idempotent when called manually.
    func loadWorkbenchResultsForCurrentSelection() {
        guard let sampleKey = currentSelectionSampleId,
              let rootPath = librarySettings.rootPath else {
            workbenchResults = nil
            return
        }
        let resolver = LibraryPathResolver(libraryRootURL: URL(fileURLWithPath: rootPath))
        workbenchResults = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
        // Refresh measurement plot index after results are loaded so dirty-key filtering is current.
        loadMeasurementPlotIndexForCurrentSelection()
    }

    // MARK: - Measurement Plot Index load (v4.1.2.17)

    /// Loads `MeasurementPlotIndex` and filters out stale chart identity keys
    /// (those absent from the current `workbenchResults.references`).
    /// Must be called after `loadWorkbenchResultsForCurrentSelection()` to ensure valid filtering.
    func loadMeasurementPlotIndexForCurrentSelection() {
        guard let sampleKey = currentSelectionSampleId,
              let rootPath = librarySettings.rootPath else {
            measurementPlotIndex = nil
            return
        }
        let resolver = LibraryPathResolver(libraryRootURL: URL(fileURLWithPath: rootPath))
        let raw: MeasurementPlotIndex?
        if let loaded = LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sampleKey) {
            raw = loaded
        } else if let results = workbenchResults, !results.references.isEmpty {
            // Index missing but old charts exist — backfill once from manifests.
            raw = BackfillMeasurementPlotIndexUseCase(pathResolver: resolver)
                .execute(sampleKey: sampleKey, results: results)
        } else {
            raw = nil
        }
        guard let raw else {
            measurementPlotIndex = nil
            return
        }
        // Filter out chartIdentityKeys that no longer exist in results_index.json.
        let validKeys = Set(workbenchResults?.references.map(\.chartIdentityKey) ?? [])
        var clean = raw
        clean.entries = raw.entries
            .mapValues { $0.filter { validKeys.contains($0) } }
            .filter { !$0.value.isEmpty }
        measurementPlotIndex = clean
    }

    // MARK: - Measurement Data load (V3.4.3)

    /// Loads the `WorkbenchMeasurementDataStore` and `ConditionAliasBook` for the current selection.
    /// Called automatically from selection changes; idempotent when called manually.
    func loadMeasurementDataForCurrentSelection() {
        guard let sampleKey = currentSelectionSampleId,
              let rootPath = librarySettings.rootPath else {
            measurementData = nil
            conditionAliasBook = nil
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath)
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        measurementData = LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: sampleKey)
        // Alias config is library-level; nil on any failure is non-fatal (Adj-5).
        let aliasConfigURL = rootURL.appending(path: "_spinlab/condition_aliases.json")
        conditionAliasBook = try? ConditionAliasConfigLoader().load(from: aliasConfigURL)
    }

    // MARK: - Metric record deletion (V4.1.11)

    /// Deletes a single metric record from measurement_data.json by identity key.
    func deleteMetricRecord(identityKey: String) {
        guard let sampleKey = librarySelectedSampleId,
              let rootPath = librarySettings.rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        guard LibraryDiskCleanupService.deleteMetricRecordOnDisk(identityKey: identityKey, sampleKey: sampleKey, rootURL: rootURL) else {
            librarySampleEditError = "Failed to delete metric record."
            return
        }

        loadMeasurementDataForCurrentSelection()
    }

    // MARK: - Workbench Results deletion (V3.4.3)

    /// Removes `ref` from every sample's `results_index.json`, then deletes the chart files.
    func deleteWorkbenchResult(_ ref: WorkbenchResultReference) {
        guard let rootPath = librarySettings.rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        guard LibraryDiskCleanupService.deleteWorkbenchResultOnDisk(ref, rootURL: rootURL) else {
            librarySampleEditError = "Failed to archive chart."
            return
        }

        // Refresh the in-memory projection (both indexes).
        loadWorkbenchResultsForCurrentSelection()
        loadMeasurementPlotIndexForCurrentSelection()
    }

    // MARK: - Applied Measurement delete (V4.1.6)

    /// Cascade-deletes an applied measurement: associated charts, sidecar, data file,
    /// and measurement set membership. Refreshes all in-memory projections afterward.
    func deleteAppliedMeasurement(_ measurement: AppliedMeasurement) {
        guard !measurement.id.isEmpty else { return }
        guard let rootPath = librarySettings.rootPath else { return }
        let rootURL = URL(fileURLWithPath: rootPath)

        guard LibraryDiskCleanupService.deleteAppliedMeasurementOnDisk(measurement, rootURL: rootURL) else {
            librarySampleEditError = "Failed to delete measurement (index may be corrupt)."
            return
        }

        // Invalidate the cache so the next refresh re-scans from disk.
        if let sample = selectedExistingDrawerSample() {
            appliedMeasurementsCacheBySampleID.removeValue(forKey: sample.id)
        }
        refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        // Internally also refreshes measurement plot index.
        loadWorkbenchResultsForCurrentSelection()
    }

    // MARK: - Measurement Set CRUD

    func createMeasurementSet(name: String, workflow: String, initialMember: String?) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        var members: [String] = []
        if let member = initialMember { members.append(member) }
        let newSet = MeasurementSet(
            id: UUID().uuidString,
            name: name,
            workflow: workflow,
            memberFileNames: members,
            createdAt: Date()
        )
        sets.append(newSet)
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func addToMeasurementSet(setID: String, fileName: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        if !sets[idx].memberFileNames.contains(fileName) {
            sets[idx].memberFileNames.append(fileName)
        }
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func removeFromMeasurementSet(setID: String, fileName: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[idx].memberFileNames.removeAll { $0 == fileName }
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func renameMeasurementSet(setID: String, newName: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        guard let idx = sets.firstIndex(where: { $0.id == setID }) else { return }
        sets[idx].name = newName
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func deleteMeasurementSet(setID: String) {
        guard let sample = selectedExistingDrawerSample(),
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId else { return }

        var sets = sample.measurementSets
        sets.removeAll { $0.id == setID }
        persistAndUpdateSets(sets, sample: sample, rootPath: rootPath, prefix: prefix, batchId: batchId)
    }

    func persistAndUpdateSets(
        _ sets: [MeasurementSet],
        sample: LibrarySample,
        rootPath: String,
        prefix: String,
        batchId: String
    ) {
        let rootURL = URL(fileURLWithPath: rootPath)
        // Serialize writes: cancel any in-flight persist before starting a new one
        // to prevent an older snapshot from overwriting a newer one.
        measurementSetsPersistTask?.cancel()
        measurementSetsPersistTask = Task.detached { [libraryStore] in
            do {
                try libraryStore.saveMeasurementSets(sets, for: sample, rootURL: rootURL)
            } catch {
                fputs("[SpinLab] persistAndUpdateSets: save failed for \(sample.id): \(error)\n", stderr)
            }
        }
        updateSampleMeasurementSets(
            prefix: prefix,
            batchId: batchId,
            sampleId: sample.id,
            sets: sets
        )
    }

    func updateSampleMeasurementSets(
        prefix: String,
        batchId: String,
        sampleId: String,
        sets: [MeasurementSet]
    ) {
        guard var groups = libraryExistingGroups[prefix],
              let groupIndex = groups.firstIndex(where: { $0.batchId == batchId }) else {
            return
        }
        var group = groups[groupIndex]
        guard let sampleIndex = group.samples.firstIndex(where: { $0.id == sampleId }) else {
            return
        }
        var sample = group.samples[sampleIndex]
        sample.measurementSets = sets
        group.samples[sampleIndex] = sample
        groups[groupIndex] = group
        libraryExistingGroups[prefix] = groups
    }
}
