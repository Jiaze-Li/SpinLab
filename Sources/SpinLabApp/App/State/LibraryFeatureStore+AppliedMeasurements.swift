import Foundation

@MainActor extension LibraryFeatureStore {

    func selectedExistingDrawerSample() -> LibrarySample? {
        guard let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId,
              let sampleId = librarySelectedSampleId else {
            return nil
        }
        let groups = libraryExistingGroups[prefix] ?? []
        guard let group = groups.first(where: { $0.batchId == batchId }) else {
            return nil
        }
        return group.samples.first(where: { $0.id == sampleId })
    }

    func refreshSelectedDrawerAppliedMeasurementsIfNeeded() {
        guard libraryActiveSelectionSource == .drawer,
              let rootPath = librarySettings.rootPath,
              let prefix = librarySelectedPrefix,
              let batchId = librarySelectedBatchId,
              let sample = selectedExistingDrawerSample() else {
            return
        }

        let rootURL = URL(fileURLWithPath: rootPath)
        let snapshot = libraryStore.sidecarSnapshot(for: sample, rootURL: rootURL)
        let measurements: [AppliedMeasurement]
        if let cached = appliedMeasurementsCacheBySampleID[sample.id], cached.snapshot == snapshot {
            measurements = cached.measurements
        } else {
            measurements = libraryStore.loadAppliedMeasurements(for: sample, rootURL: rootURL)
            appliedMeasurementsCacheBySampleID[sample.id] = AppliedMeasurementsCacheEntry(
                snapshot: snapshot,
                measurements: measurements
            )
        }

        let sets = libraryStore.loadMeasurementSets(for: sample, rootURL: rootURL)

        guard sample.appliedMeasurements != measurements || sample.measurementSets != sets else {
            return
        }
        updateSampleAppliedMeasurements(
            prefix: prefix,
            batchId: batchId,
            sampleId: sample.id,
            measurements: measurements
        )
        if sample.measurementSets != sets {
            updateSampleMeasurementSets(
                prefix: prefix,
                batchId: batchId,
                sampleId: sample.id,
                sets: sets
            )
        }
    }

    func sampleChangeLog(for sample: LibrarySample) -> [LibrarySampleChangeLogEntry] {
        guard let rootPath = librarySettings.rootPath else {
            return []
        }
        return libraryStore.sampleChangeLog(for: sample, rootURL: URL(fileURLWithPath: rootPath))
    }

    func loadSidecar(for measurement: AppliedMeasurement) -> SpinLabFileSidecar? {
        librarySidecarService.loadSidecar(atPath: measurement.id)
    }

    func saveConditionOverride(measurement: AppliedMeasurement, conditionId: String, value: String) {
        guard canMutateLibraryDetailSelection else { return }
        let updated = librarySidecarService.saveConditionOverride(
            sidecarPath: measurement.id,
            conditionId: conditionId,
            value: value
        )
        if updated {
            appliedMeasurementsCacheBySampleID.removeAll()
            refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        }
    }

    func removeConditionOverride(measurement: AppliedMeasurement, conditionId: String) {
        guard canMutateLibraryDetailSelection else { return }
        let updated = librarySidecarService.removeConditionOverride(
            sidecarPath: measurement.id,
            conditionId: conditionId
        )
        if updated {
            appliedMeasurementsCacheBySampleID.removeAll()
            refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        }
    }

    func saveWorkflowOverride(measurement: AppliedMeasurement, workflowOverride: String) {
        guard canMutateLibraryDetailSelection else { return }
        let updated = librarySidecarService.saveWorkflowOverride(
            sidecarPath: measurement.id,
            workflowOverride: workflowOverride
        )
        if updated {
            appliedMeasurementsCacheBySampleID.removeAll()
            refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        }
    }

    func clearWorkflowOverride(measurement: AppliedMeasurement) {
        guard canMutateLibraryDetailSelection else { return }
        let updated = librarySidecarService.clearWorkflowOverride(sidecarPath: measurement.id)
        if updated {
            appliedMeasurementsCacheBySampleID.removeAll()
            refreshSelectedDrawerAppliedMeasurementsIfNeeded()
        }
    }

    private func updateSampleAppliedMeasurements(
        prefix: String,
        batchId: String,
        sampleId: String,
        measurements: [AppliedMeasurement]
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
        sample.appliedMeasurements = measurements
        group.samples[sampleIndex] = sample
        groups[groupIndex] = group
        libraryExistingGroups[prefix] = groups
    }
}
