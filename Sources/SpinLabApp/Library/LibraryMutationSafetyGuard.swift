import Foundation

enum LibraryMutationSafetyError: LocalizedError, Equatable {
    /// AC2: Registry diff dropped row or rekeyed a sample that has real scientific data.
    case unauthorizedDeletionOfSampleWithScientificData(sampleId: String, batchId: String, reason: String)
    /// AC2: Registry diff dropped a batch that has scientific data.
    case unauthorizedDeletionOfBatchWithScientificData(batchId: String, reason: String)
    /// AC3: Explicit delete rejected due to shared plot reference.
    case sharedPlotReferenceConflict(sampleId: String, chartPath: String, sharedWith: [String])
    /// AC3: Explicit delete rejected due to corrupted dependencies.
    case corruptDependency(sampleId: String, path: String, reason: String)
    /// AC3: Explicit delete rejected due to dependency ambiguity or invalid relationship.
    case dependencyAmbiguity(sampleId: String, reason: String)
    /// AC3: Explicit delete rejected due to unrecognized cross-namespace asset.
    case unrecognizedCrossNamespaceAsset(sampleId: String, path: String)
    /// AC4: Orphan artifact at samples/<sampleKey>/_spinlab or charts prevents re-creating same legacy locator.
    case orphanArtifactCollision(sampleKey: String, path: String)

    var errorDescription: String? {
        switch self {
        case let .unauthorizedDeletionOfSampleWithScientificData(sampleId, batchId, reason):
            return "Cannot delete sample '\(sampleId)' in batch '\(batchId)': Sample contains scientific data (\(reason)), but registry row is missing or rekeyed. Registry cannot delete samples with scientific data."
        case let .unauthorizedDeletionOfBatchWithScientificData(batchId, reason):
            return "Cannot delete batch '\(batchId)': Batch contains scientific data (\(reason)), but registry sheet is missing or unmapped. Registry cannot delete batches with scientific data."
        case let .sharedPlotReferenceConflict(sampleId, chartPath, sharedWith):
            let others = sharedWith.joined(separator: ", ")
            return "Cannot delete sample '\(sampleId)': Plot '\(chartPath)' is shared with other samples (\(others)). Shared plots cannot be deleted."
        case let .corruptDependency(sampleId, path, reason):
            return "Cannot delete sample '\(sampleId)': Corrupted dependency detected at '\(path)': \(reason). Deletion refused to prevent unverified data loss."
        case let .dependencyAmbiguity(sampleId, reason):
            return "Cannot delete sample '\(sampleId)': Dependency ambiguity: \(reason)."
        case let .unrecognizedCrossNamespaceAsset(sampleId, path):
            return "Cannot delete sample '\(sampleId)': Unrecognized cross-namespace asset detected at '\(path)'."
        case let .orphanArtifactCollision(sampleKey, path):
            return "Orphan artifact detected at '\(path)'. Re-creation of locator '\(sampleKey)' is blocked to prevent inheriting unverified legacy artifacts."
        }
    }
}

enum LibraryMutationSafetyGuard {

    // MARK: - Scientific Data Detection (AC2, S1, S2)

    /// Detects whether a Sample has real scientific measurements, sidecars, plots, or Workbench artifacts.
    static func detectScientificData(
        sample: LibrarySample,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> (hasData: Bool, reason: String) {
        var reasons: [String] = []

        // 1. In-memory applied measurements and sets
        if !sample.appliedMeasurements.isEmpty {
            reasons.append("\(sample.appliedMeasurements.count) applied measurement(s)")
        }
        if !sample.measurementSets.isEmpty {
            reasons.append("\(sample.measurementSets.count) measurement set(s)")
        }

        // 2. Physical sample drawer inspect
        let store = LibraryStore(fileManager: fileManager)
        let sampleURL = store.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)

        if fileManager.fileExists(atPath: sampleURL.path) {
            let measurementsDir = sampleURL.appending(path: "measurements", directoryHint: .isDirectory)
            if let files = try? fileManager.contentsOfDirectory(at: measurementsDir, includingPropertiesForKeys: nil) {
                let nonHidden = files.filter { !$0.lastPathComponent.hasPrefix(".") }
                if !nonHidden.isEmpty {
                    reasons.append("\(nonHidden.count) measurement file(s) in drawer")
                }
            }

            let plotsDir = sampleURL.appending(path: "plots", directoryHint: .isDirectory)
            if let files = try? fileManager.contentsOfDirectory(at: plotsDir, includingPropertiesForKeys: nil) {
                let nonHidden = files.filter { !$0.lastPathComponent.hasPrefix(".") }
                if !nonHidden.isEmpty {
                    reasons.append("\(nonHidden.count) plot file(s) in drawer")
                }
            }

            let analysisDir = sampleURL.appending(path: "analysis", directoryHint: .isDirectory)
            if let files = try? fileManager.contentsOfDirectory(at: analysisDir, includingPropertiesForKeys: nil) {
                let nonHidden = files.filter { !$0.lastPathComponent.hasPrefix(".") }
                if !nonHidden.isEmpty {
                    reasons.append("\(nonHidden.count) analysis file(s) in drawer")
                }
            }

            let testsDir = sampleURL.appending(path: "tests", directoryHint: .isDirectory)
            if let testSlots = try? fileManager.contentsOfDirectory(at: testsDir, includingPropertiesForKeys: nil) {
                var testFileCount = 0
                for slot in testSlots {
                    if let files = try? fileManager.contentsOfDirectory(at: slot, includingPropertiesForKeys: nil) {
                        testFileCount += files.filter { !$0.lastPathComponent.hasPrefix(".") }.count
                    }
                }
                if testFileCount > 0 {
                    reasons.append("\(testFileCount) test file(s) in drawer")
                }
            }
        }

        // 3. Workbench artifacts layout
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        if let resultsURL = try? layout.resultsIndexURL(sampleKey: sample.id), fileManager.fileExists(atPath: resultsURL.path) {
            if let data = try? Data(contentsOf: resultsURL),
               let index = try? JSONDecoder().decode(WorkbenchResultsIndex.self, from: data) {
                if !index.references.isEmpty {
                    reasons.append("\(index.references.count) Workbench chart reference(s)")
                }
            } else {
                reasons.append("results_index.json exists")
            }
        }

        if let plotIndexURL = try? layout.measurementPlotIndexURL(sampleKey: sample.id), fileManager.fileExists(atPath: plotIndexURL.path) {
            reasons.append("measurement_plot_index.json exists")
        }

        if let dataURL = try? layout.measurementDataURL(sampleKey: sample.id), fileManager.fileExists(atPath: dataURL.path) {
            reasons.append("measurement_data.json exists")
        }

        let chartsDir = rootURL.appending(path: layout.singleSampleChartDirectoryRelativePath(sampleKey: sample.id), directoryHint: .isDirectory)
        if let chartFiles = try? fileManager.contentsOfDirectory(at: chartsDir, includingPropertiesForKeys: nil) {
            let nonHidden = chartFiles.filter { !$0.lastPathComponent.hasPrefix(".") }
            if !nonHidden.isEmpty {
                reasons.append("\(nonHidden.count) chart file(s)")
            }
        }

        if !reasons.isEmpty {
            return (true, reasons.joined(separator: ", "))
        }
        return (false, "")
    }

    // MARK: - Orphan Artifact Detection (AC4, S3)

    /// Detects whether an orphan artifact exists under samples/<sampleKey>/_spinlab or charts
    /// when NO active sample drawer exists on disk for this key.
    static func detectOrphanArtifact(
        sampleKey: String,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> (isOrphan: Bool, path: String?) {
        let trimmedKey = sampleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return (false, nil) }

        let store = LibraryStore(fileManager: fileManager)
        if let index = store.loadIndex(from: rootURL) {
            if index.samples.contains(where: { $0.id.caseInsensitiveCompare(trimmedKey) == .orderedSame }) {
                // Active sample exists in index; this is not an orphan locator collision
                return (false, nil)
            }
        }

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

        // Check for orphan artifact on disk:
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let spinlabDir = rootURL.appending(path: "samples/\(trimmedKey)/_spinlab", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: spinlabDir.path) {
            if let entries = try? fileManager.contentsOfDirectory(at: spinlabDir, includingPropertiesForKeys: nil) {
                let nonHidden = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
                if !nonHidden.isEmpty {
                    return (true, "samples/\(trimmedKey)/_spinlab")
                }
            }
        }

        let chartsDir = rootURL.appending(path: layout.singleSampleChartDirectoryRelativePath(sampleKey: trimmedKey), directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: chartsDir.path) {
            if let entries = try? fileManager.contentsOfDirectory(at: chartsDir, includingPropertiesForKeys: nil) {
                let nonHidden = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
                if !nonHidden.isEmpty {
                    return (true, layout.singleSampleChartDirectoryRelativePath(sampleKey: trimmedKey))
                }
            }
        }

        return (false, nil)
    }

    // MARK: - Shared Plot Reference Detection (AC3, S3)

    static func detectSharedPlotReferences(
        sample: LibrarySample,
        rootURL: URL,
        allSamples: [LibrarySample],
        fileManager: FileManager = .default
    ) -> (isShared: Bool, chartPath: String?, sharedWith: [String]) {
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let indexStore = LibraryChartIndexStore(layout: layout)

        guard let myResults = indexStore.loadResultsIndexFailSoft(sampleKey: sample.id) else {
            return (false, nil, [])
        }

        let otherSamples = allSamples.filter { $0.id != sample.id }

        for ref in myResults.references {
            var referencingSamples: [String] = []
            for other in otherSamples {
                if let otherResults = indexStore.loadResultsIndexFailSoft(sampleKey: other.id) {
                    let matches = otherResults.references.contains { otherRef in
                        (!ref.chartIdentityKey.isEmpty && otherRef.chartIdentityKey == ref.chartIdentityKey) ||
                        otherRef.chartImagePath == ref.chartImagePath
                    }
                    if matches {
                        referencingSamples.append(other.id)
                    }
                }
            }
            if !referencingSamples.isEmpty {
                return (true, ref.chartImagePath, referencingSamples.sorted())
            }
            if ref.chartImagePath.contains("multi-sample/charts") {
                if let manifestURL = try? layout.pathResolver.absoluteURL(for: ref.manifestPath),
                   fileManager.fileExists(atPath: manifestURL.path) {
                    return (true, ref.chartImagePath, referencingSamples.sorted())
                }
            }
        }

        return (false, nil, [])
    }

    // MARK: - Corrupt Dependencies Detection (AC3)

    static func detectCorruptDependencies(
        sample: LibrarySample,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> (isCorrupt: Bool, path: String?, reason: String?) {
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let indexStore = LibraryChartIndexStore(layout: layout)

        do {
            _ = try indexStore.loadResultsIndexStrict(sampleKey: sample.id)
        } catch {
            let path = (try? layout.resultsIndexURL(sampleKey: sample.id))?.path ?? "results_index.json"
            return (true, path, error.localizedDescription)
        }

        do {
            _ = try indexStore.loadPlotIndexStrict(sampleKey: sample.id)
        } catch {
            let path = (try? layout.measurementPlotIndexURL(sampleKey: sample.id))?.path ?? "measurement_plot_index.json"
            return (true, path, error.localizedDescription)
        }

        let store = LibraryStore(fileManager: fileManager)
        let sampleURL = store.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")
        if fileManager.fileExists(atPath: sampleJSONURL.path) {
            if store.decodeSample(from: sampleJSONURL) == nil {
                return (true, sampleJSONURL.path, "sample.json is corrupt or unreadable")
            }
        }

        return (false, nil, nil)
    }

    // MARK: - Unrecognized Cross-Namespace Assets (AC3)

    static func detectUnrecognizedCrossNamespaceAssets(
        sample: LibrarySample,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> (isUnrecognized: Bool, path: String?, reason: String?) {
        let store = LibraryStore(fileManager: fileManager)
        let sampleURL = store.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
        guard fileManager.fileExists(atPath: sampleURL.path) else {
            return (false, nil, nil)
        }

        if store.containsSymbolicLink(sampleURL, relativeTo: rootURL) {
            return (true, sampleURL.path, "Sample directory contains or is a symbolic link.")
        }

        let standardNames: Set<String> = [
            "sample.json",
            "tests",
            "plots",
            "analysis",
            "measurements",
            "sample_change_log.json",
            "change_log.jsonl",
            "edit_log.json",
            ".DS_Store"
        ]

        if let entries = try? fileManager.contentsOfDirectory(at: sampleURL, includingPropertiesForKeys: nil) {
            for entry in entries {
                let name = entry.lastPathComponent
                if !standardNames.contains(name) && !name.hasPrefix(".") {
                    return (true, entry.path, "Unrecognized directory entry '\(name)' in sample drawer.")
                }
            }
        }

        return (false, nil, nil)
    }

    // MARK: - Explicit Deletion Safety Validation (AC3)

    static func validateExplicitDeletionSafety(
        sample: LibrarySample,
        rootURL: URL,
        allSamples: [LibrarySample],
        fileManager: FileManager = .default
    ) throws {
        let (isCorrupt, corruptPath, corruptReason) = detectCorruptDependencies(
            sample: sample,
            rootURL: rootURL,
            fileManager: fileManager
        )
        if isCorrupt {
            throw LibraryMutationSafetyError.corruptDependency(
                sampleId: sample.id,
                path: corruptPath ?? "",
                reason: corruptReason ?? "Corrupt index"
            )
        }

        let (isShared, chartPath, sharedWith) = detectSharedPlotReferences(
            sample: sample,
            rootURL: rootURL,
            allSamples: allSamples,
            fileManager: fileManager
        )
        if isShared {
            throw LibraryMutationSafetyError.sharedPlotReferenceConflict(
                sampleId: sample.id,
                chartPath: chartPath ?? "",
                sharedWith: sharedWith
            )
        }

        let (isUnrecognized, unrecPath, unrecReason) = detectUnrecognizedCrossNamespaceAssets(
            sample: sample,
            rootURL: rootURL,
            fileManager: fileManager
        )
        if isUnrecognized {
            throw LibraryMutationSafetyError.unrecognizedCrossNamespaceAsset(
                sampleId: sample.id,
                path: unrecPath ?? unrecReason ?? ""
            )
        }
    }

    // MARK: - Batch Deletion Safety Validation (AC3)

    static func validateBatchDeletionSafety(
        batchID: String,
        rootURL: URL,
        baselineIndex: LibraryIndex?,
        fileManager: FileManager = .default
    ) throws {
        let allSamples = baselineIndex?.samples ?? []
        let batchSamples = allSamples.filter { $0.batchId == batchID }
        for sample in batchSamples {
            try validateExplicitDeletionSafety(
                sample: sample,
                rootURL: rootURL,
                allSamples: allSamples,
                fileManager: fileManager
            )
        }
    }

    // MARK: - Pre-Write Registry Diff Safety Validation (AC2, AC4, S1, S2, S3)

    static func validateRegistryDiffSafety(
        removedSamples: [LibrarySample],
        newSamples: [LibrarySample],
        removedBatches: [LibraryBatch],
        baselineIndex: LibraryIndex,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        // 1. Check all removed samples: S1, S2, AC2
        for sample in removedSamples {
            let (hasData, dataReason) = detectScientificData(
                sample: sample,
                rootURL: rootURL,
                fileManager: fileManager
            )
            if hasData {
                throw LibraryMutationSafetyError.unauthorizedDeletionOfSampleWithScientificData(
                    sampleId: sample.id,
                    batchId: sample.batchId,
                    reason: dataReason
                )
            }

            try validateExplicitDeletionSafety(
                sample: sample,
                rootURL: rootURL,
                allSamples: baselineIndex.samples,
                fileManager: fileManager
            )
        }

        // 2. Check all removed batches:
        for batch in removedBatches {
            let batchSamples = baselineIndex.samples.filter { $0.batchId == batch.id }
            for sample in batchSamples {
                let (hasData, dataReason) = detectScientificData(
                    sample: sample,
                    rootURL: rootURL,
                    fileManager: fileManager
                )
                if hasData {
                    throw LibraryMutationSafetyError.unauthorizedDeletionOfBatchWithScientificData(
                        batchId: batch.id,
                        reason: "Contains sample '\(sample.id)' with \(dataReason)"
                    )
                }
            }
            try validateBatchDeletionSafety(
                batchID: batch.id,
                rootURL: rootURL,
                baselineIndex: baselineIndex,
                fileManager: fileManager
            )
        }

        // 3. Check all new samples for orphan artifact collisions: S3, AC4
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
