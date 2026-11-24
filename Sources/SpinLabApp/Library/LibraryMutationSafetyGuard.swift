import Foundation

enum LibraryMutationSafetyError: LocalizedError, Equatable {
    /// AC2 / S2: Registry diff dropped or rekeyed a sample. A missing or changed Registry row is not deletion authorization.
    case registrySampleRemovalNotAuthorized(sampleId: String, batchId: String)
    /// AC2 / S2: Registry diff dropped or rekeyed a batch. A missing or changed Registry sheet is not deletion authorization.
    case registryBatchRemovalNotAuthorized(batchId: String)
    /// S5: The Library changed after the first safety check (another writer). The apply stopped before applying
    /// the plan, but the preparation step had already refreshed batch bookkeeping and the index.
    case registryPlanChangedDuringApply(subject: String)
    /// AC4: Orphan artifact at samples/<sampleKey>/_spinlab or charts prevents re-creating same legacy locator.
    case orphanArtifactCollision(sampleKey: String, path: String)

    var errorDescription: String? {
        switch self {
        case let .registrySampleRemovalNotAuthorized(sampleId, batchId):
            return "Registry apply refused before any change: sample '\(sampleId)' in batch '\(batchId)' is missing from the Registry (or its key was changed). A missing or re-keyed Registry row is not authorization to delete a Library sample, and no automatic Registry deletion is approved. Nothing was modified. Restore the row or the original key in the Registry and apply again. Deleting samples is not available yet (删除功能暂未开放)."
        case let .registryBatchRemovalNotAuthorized(batchId):
            return "Registry apply refused before any change: batch '\(batchId)' is missing from the Registry (or its key was changed). A missing or re-keyed Registry sheet is not authorization to delete a Library batch, and no automatic Registry deletion is approved. Nothing was modified. Restore the sheet or the original key in the Registry and apply again. Deleting batches is not available yet (删除功能暂未开放)."
        case let .registryPlanChangedDuringApply(subject):
            return "Registry apply stopped: the Library changed while the apply was being prepared, and \(subject) is no longer matched by the Registry preview. A missing Registry row is not authorization to delete, so no sample or measurement was deleted and the Registry changes were not applied. Preparation had already refreshed the Library index and batch bookkeeping to match the folders on disk. Review the Library, rebuild the Registry preview and apply again."
        case let .orphanArtifactCollision(sampleKey, path):
            return "Orphan artifact detected at '\(path)'. Re-creation of locator '\(sampleKey)' is blocked to prevent inheriting unverified legacy artifacts."
        }
    }
}

enum LibraryMutationSafetyGuard {

    // MARK: - Orphan Artifact Detection (AC4, S3)

    /// Detects whether an orphan artifact exists under samples/<sampleKey>/_spinlab or charts
    /// when NO active sample drawer exists on disk for this key (F004).
    static func detectOrphanArtifact(
        sampleKey: String,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> (isOrphan: Bool, path: String?) {
        let trimmedKey = sampleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return (false, nil) }

        let store = LibraryStore(fileManager: fileManager)
        if store.resolveLayout(at: rootURL).isV2 {
            return (false, nil)
        }

        // Do NOT rely on index.samples alone: a stale library_index.json can still contain
        // the old sampleKey while the physical drawer is gone. An orphan artifact at
        // samples/<sampleKey>/_spinlab or charts must still be detected! (F004)
        // We only return false if the physical sample drawer ACTUALLY exists on disk.
        var issues: [String] = []
        let batchDirs = store.discoverBatchDirectories(rootURL: rootURL, issues: &issues)
        for batchDir in batchDirs {
            let sampleDir = batchDir.appending(path: "samples", directoryHint: .isDirectory)
                .appending(path: store.sanitizedPathComponent(trimmedKey), directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: sampleDir.path) {
                // Active sample drawer exists on disk
                return (false, nil)
            }
        }

        // Check for orphan artifact on disk (AC4, S3, R02):
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let spinlabDir: URL
        let chartsDir: URL
        let workbenchSampleDir: URL
        do {
            let resultsIndexURL = try layout.resultsIndexURL(sampleKey: trimmedKey)
            spinlabDir = resultsIndexURL.deletingLastPathComponent()
            let chartRelPath = layout.singleSampleChartDirectoryRelativePath(sampleKey: trimmedKey)
            chartsDir = try layout.pathResolver.absoluteURL(for: chartRelPath)
            workbenchSampleDir = spinlabDir.deletingLastPathComponent()
        } catch {
            return (true, "samples/\(trimmedKey)")
        }

        if fileManager.fileExists(atPath: workbenchSampleDir.path) {
            if store.containsSymbolicLink(workbenchSampleDir, relativeTo: rootURL) {
                return (true, workbenchSampleDir.path)
            }
            do {
                let entries = try fileManager.contentsOfDirectory(at: workbenchSampleDir, includingPropertiesForKeys: nil)
                let nonHidden = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
                let unknownTopLevel = nonHidden.filter { $0.lastPathComponent != "_spinlab" && $0.lastPathComponent != "charts" }
                if !unknownTopLevel.isEmpty {
                    return (true, unknownTopLevel.first?.path ?? workbenchSampleDir.path)
                }
            } catch {
                // R02: Unreadable directory must fail-closed
                return (true, workbenchSampleDir.path)
            }
        }

        if fileManager.fileExists(atPath: spinlabDir.path) {
            if store.containsSymbolicLink(spinlabDir, relativeTo: rootURL) {
                return (true, spinlabDir.path)
            }
            do {
                let entries = try fileManager.contentsOfDirectory(at: spinlabDir, includingPropertiesForKeys: nil)
                let nonHidden = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
                if !nonHidden.isEmpty {
                    return (true, spinlabDir.path)
                }
            } catch {
                // R02: Unreadable directory must fail-closed
                return (true, spinlabDir.path)
            }
        }

        if fileManager.fileExists(atPath: chartsDir.path) {
            if store.containsSymbolicLink(chartsDir, relativeTo: rootURL) {
                return (true, chartsDir.path)
            }
            do {
                let entries = try fileManager.contentsOfDirectory(at: chartsDir, includingPropertiesForKeys: nil)
                let nonHidden = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
                if !nonHidden.isEmpty {
                    return (true, chartsDir.path)
                }
            } catch {
                // R02: Unreadable directory must fail-closed
                return (true, chartsDir.path)
            }
        }

        return (false, nil)
    }

    /// Second check on the authoritative diff, run after preparation (reconcile + index refresh) has already
    /// written bookkeeping. Rejects the same removals, but reports the accurate state (S5).
    static func validateNoRegistryRemovalAfterPreparation(
        removedSamples: [LibrarySample],
        removedBatches: [LibraryBatch]
    ) throws {
        if let sample = removedSamples.sorted(by: { ($0.batchId, $0.id) < ($1.batchId, $1.id) }).first {
            throw LibraryMutationSafetyError.registryPlanChangedDuringApply(subject: "sample '\(sample.id)' in batch '\(sample.batchId)'")
        }
        if let batch = removedBatches.sorted(by: { $0.id < $1.id }).first {
            throw LibraryMutationSafetyError.registryPlanChangedDuringApply(subject: "batch '\(batch.id)'")
        }
    }

    // MARK: - Pre-Write Registry Diff Safety Validation (AC2, AC4, S1, S2, S4)

    /// Rejects a Registry plan before its first write.
    ///
    /// G1 has no approved Registry-driven deletion authorization. A missing row, missing sheet or
    /// re-key (old object gone, new object present) therefore never authorizes removal, whatever the
    /// object's metadata contains (empty metadata is not permission either). The whole plan is refused (S1/S4).
    /// Explicit user deletion is closed (`LibraryDrawerError.deletionDisabled`).
    static func validateRegistryDiffSafety(
        removedSamples: [LibrarySample],
        newSamples: [LibrarySample],
        removedBatches: [LibraryBatch],
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        if let sample = removedSamples.sorted(by: { ($0.batchId, $0.id) < ($1.batchId, $1.id) }).first {
            throw LibraryMutationSafetyError.registrySampleRemovalNotAuthorized(sampleId: sample.id, batchId: sample.batchId)
        }
        if let batch = removedBatches.sorted(by: { $0.id < $1.id }).first {
            throw LibraryMutationSafetyError.registryBatchRemovalNotAuthorized(batchId: batch.id)
        }

        // New samples must not inherit orphan artifacts: S3, AC4
        for newSample in newSamples {
            let (isOrphan, orphanPath) = detectOrphanArtifact(
                sampleKey: newSample.id,
                rootURL: rootURL,
                fileManager: fileManager
            )
            if isOrphan {
                throw LibraryMutationSafetyError.orphanArtifactCollision(
                    sampleKey: newSample.id,
                    path: orphanPath ?? "samples/\(newSample.id)/_spinlab"
                )
            }
        }
    }
}
