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
    /// AC3 / R03: Explicit delete rejected because sample has active Workbench artifacts that would be orphaned.
    case attachedWorkbenchArtifact(sampleId: String, path: String, reason: String)
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
        case let .attachedWorkbenchArtifact(sampleId, path, reason):
            return "Cannot delete sample '\(sampleId)': Sample has active Workbench artifacts at '\(path)' (\(reason)). Explicit deletion refused to prevent leaving detached orphaned artifacts in Workbench namespace."
        case let .orphanArtifactCollision(sampleKey, path):
            return "Orphan artifact detected at '\(path)'. Re-creation of locator '\(sampleKey)' is blocked to prevent inheriting unverified legacy artifacts."
        }
    }
}

enum LibraryMutationSafetyGuard {

    // MARK: - Scientific Data Detection (AC2, S1, S2)

    /// Detects whether a Sample has real scientific measurements, sidecars, plots, Workbench artifacts,
    /// parameters, numeric tags, or revision records (F003, F006).
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

        // 2. Scientific parameters (numeric tags, numeric display, or metadata parameters) (R01, F003)
        if !sample.numericTags.isEmpty {
            reasons.append("\(sample.numericTags.count) numeric tag(s)")
        }
        let unmappedNumeric = sample.numericDisplay.keys.filter { sample.numericTags[$0] == nil }
        if !unmappedNumeric.isEmpty {
            reasons.append("\(unmappedNumeric.count) numeric display value(s)")
        }
        if !sample.metadata.isEmpty {
            reasons.append("\(sample.metadata.count) metadata parameter(s)")
        }

        // 3. Physical sample drawer inspect
        let store = LibraryStore(fileManager: fileManager)
        let sampleURL = store.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)

        if fileManager.fileExists(atPath: sampleURL.path) {
            // Check revision logs (F003)
            let changeLogURL = sampleURL.appending(path: "sample_change_log.json")
            if fileManager.fileExists(atPath: changeLogURL.path) {
                do {
                    let data = try Data(contentsOf: changeLogURL)
                    if data.count > 2 {
                        reasons.append("sample change log exists")
                    }
                } catch {
                    reasons.append("sample_change_log.json exists (unreadable)")
                }
            }

            let changeLogLURL = sampleURL.appending(path: "change_log.jsonl")
            if fileManager.fileExists(atPath: changeLogLURL.path) {
                do {
                    let data = try Data(contentsOf: changeLogLURL)
                    if data.count > 0 {
                        reasons.append("change log (.jsonl) exists")
                    }
                } catch {
                    reasons.append("change_log.jsonl exists (unreadable)")
                }
            }

            let editLogURL = sampleURL.appending(path: "edit_log.json")
            if fileManager.fileExists(atPath: editLogURL.path) {
                do {
                    let data = try Data(contentsOf: editLogURL)
                    if data.count > 2 {
                        reasons.append("edit log exists")
                    }
                } catch {
                    reasons.append("edit_log.json exists (unreadable)")
                }
            }

            // Check sample.json on disk if present
            let sampleJSONURL = sampleURL.appending(path: "sample.json")
            if fileManager.fileExists(atPath: sampleJSONURL.path) {
                if let diskSample = store.decodeSample(from: sampleJSONURL) {
                    if !diskSample.numericTags.isEmpty && sample.numericTags.isEmpty {
                        reasons.append("\(diskSample.numericTags.count) numeric tag(s) on disk")
                    }
                    if !diskSample.metadata.isEmpty && sample.metadata.isEmpty {
                        reasons.append("\(diskSample.metadata.count) metadata parameter(s) on disk")
                    }
                } else {
                    reasons.append("sample.json exists (unreadable or corrupted)")
                }
            }

            let measurementsDir = sampleURL.appending(path: "measurements", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: measurementsDir.path) {
                do {
                    let files = try fileManager.contentsOfDirectory(at: measurementsDir, includingPropertiesForKeys: nil)
                    let nonHidden = files.filter { !$0.lastPathComponent.hasPrefix(".") }
                    if !nonHidden.isEmpty {
                        reasons.append("\(nonHidden.count) measurement file(s) in drawer")
                    }
                } catch {
                    reasons.append("measurements directory exists (unreadable)")
                }
            }

            let plotsDir = sampleURL.appending(path: "plots", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: plotsDir.path) {
                do {
                    let files = try fileManager.contentsOfDirectory(at: plotsDir, includingPropertiesForKeys: nil)
                    let nonHidden = files.filter { !$0.lastPathComponent.hasPrefix(".") }
                    if !nonHidden.isEmpty {
                        reasons.append("\(nonHidden.count) plot file(s) in drawer")
                    }
                } catch {
                    reasons.append("plots directory exists (unreadable)")
                }
            }

            let analysisDir = sampleURL.appending(path: "analysis", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: analysisDir.path) {
                do {
                    let files = try fileManager.contentsOfDirectory(at: analysisDir, includingPropertiesForKeys: nil)
                    let nonHidden = files.filter { !$0.lastPathComponent.hasPrefix(".") }
                    if !nonHidden.isEmpty {
                        reasons.append("\(nonHidden.count) analysis file(s) in drawer")
                    }
                } catch {
                    reasons.append("analysis directory exists (unreadable)")
                }
            }

            let testsDir = sampleURL.appending(path: "tests", directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: testsDir.path) {
                do {
                    let entries = try fileManager.contentsOfDirectory(at: testsDir, includingPropertiesForKeys: nil)
                    let nonHidden = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
                    var testFileCount = 0
                    for entry in nonHidden {
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: entry.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                do {
                                    let files = try fileManager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
                                    testFileCount += files.filter { !$0.lastPathComponent.hasPrefix(".") }.count
                                } catch {
                                    reasons.append("test slot directory exists (unreadable): \(entry.lastPathComponent)")
                                }
                            } else {
                                testFileCount += 1
                            }
                        }
                    }
                    if testFileCount > 0 {
                        reasons.append("\(testFileCount) test file(s) in drawer")
                    }
                } catch {
                    reasons.append("tests directory exists (unreadable)")
                }
            }
        }

        // 4. Workbench artifacts layout
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        do {
            let resultsURL = try layout.resultsIndexURL(sampleKey: sample.id)
            if fileManager.fileExists(atPath: resultsURL.path) {
                do {
                    let data = try Data(contentsOf: resultsURL)
                    let index = try JSONDecoder().decode(WorkbenchResultsIndex.self, from: data)
                    if !index.references.isEmpty {
                        reasons.append("\(index.references.count) Workbench chart reference(s)")
                    }
                } catch {
                    reasons.append("results_index.json exists (unreadable or corrupted)")
                }
            }
        } catch {
            reasons.append("Workbench layout resultsIndexURL failed: \(error)")
        }

        do {
            let plotIndexURL = try layout.measurementPlotIndexURL(sampleKey: sample.id)
            if fileManager.fileExists(atPath: plotIndexURL.path) {
                reasons.append("measurement_plot_index.json exists")
            }
        } catch {
            reasons.append("Workbench layout measurementPlotIndexURL failed: \(error)")
        }

        do {
            let dataURL = try layout.measurementDataURL(sampleKey: sample.id)
            if fileManager.fileExists(atPath: dataURL.path) {
                reasons.append("measurement_data.json exists")
            }
        } catch {
            reasons.append("Workbench layout measurementDataURL failed: \(error)")
        }

        do {
            let chartRelPath = layout.singleSampleChartDirectoryRelativePath(sampleKey: sample.id)
            let chartsDir = try layout.pathResolver.absoluteURL(for: chartRelPath)
            if fileManager.fileExists(atPath: chartsDir.path) {
                do {
                    let chartFiles = try fileManager.contentsOfDirectory(at: chartsDir, includingPropertiesForKeys: nil)
                    let nonHidden = chartFiles.filter { !$0.lastPathComponent.hasPrefix(".") }
                    if !nonHidden.isEmpty {
                        reasons.append("\(nonHidden.count) chart file(s)")
                    }
                } catch {
                    reasons.append("charts directory exists (unreadable)")
                }
            }
        } catch {
            reasons.append("Workbench layout chartsDir failed: \(error)")
        }

        if !reasons.isEmpty {
            return (true, reasons.joined(separator: ", "))
        }
        return (false, "")
    }

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

    // MARK: - Shared Plot Reference Detection (AC3, S3, R04)

    static func detectSharedPlotReferences(
        sample: LibrarySample,
        rootURL: URL,
        allSamples: [LibrarySample],
        fileManager: FileManager = .default
    ) throws -> (isShared: Bool, chartPath: String?, sharedWith: [String]) {
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let indexStore = LibraryChartIndexStore(layout: layout)

        let myResultsRecord: (index: WorkbenchResultsIndex, rawData: Data)?
        do {
            myResultsRecord = try indexStore.loadResultsIndexStrict(sampleKey: sample.id)
        } catch {
            throw LibraryMutationSafetyError.corruptDependency(
                sampleId: sample.id,
                path: (try? layout.resultsIndexURL(sampleKey: sample.id))?.path ?? "results_index.json",
                reason: "Cannot read results index for sample '\(sample.id)': \(error.localizedDescription)"
            )
        }

        // Discover all sample keys across both indexed samples and on-disk samples directory (R04)
        var sampleKeysToScan = Set(allSamples.map(\.id))
        let samplesRoot = rootURL.appending(path: "samples", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: samplesRoot.path) {
            let diskEntries: [URL]
            do {
                diskEntries = try fileManager.contentsOfDirectory(at: samplesRoot, includingPropertiesForKeys: nil)
            } catch {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: samplesRoot.path,
                    reason: "Cannot list samples directory: \(error.localizedDescription)"
                )
            }
            for entry in diskEntries where !entry.lastPathComponent.hasPrefix(".") {
                sampleKeysToScan.insert(entry.lastPathComponent)
            }
        }

        let myRefs = myResultsRecord?.index.references ?? []
        var referencingSamples: [String] = []
        var conflictingChartPath: String? = nil

        for otherKey in sampleKeysToScan.sorted() where otherKey != sample.id {
            let otherResultsRecord: (index: WorkbenchResultsIndex, rawData: Data)?
            do {
                otherResultsRecord = try indexStore.loadResultsIndexStrict(sampleKey: otherKey)
            } catch {
                // F006 / R04: Another sample's results_index is corrupt or unreadable.
                // Unknown dependency must fail-closed even if current sample has no results index!
                let otherURL = (try? layout.resultsIndexURL(sampleKey: otherKey))?.path ?? "results_index.json"
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: otherURL,
                    reason: "Failed to read results index for other sample '\(otherKey)': \(error.localizedDescription)"
                )
            }

            if let otherResults = otherResultsRecord?.index {
                for otherRef in otherResults.references {
                    // 1. Reverse reference: otherRef points to this sample's charts or assets (R04)
                    let pointsToSample = otherRef.chartImagePath.contains("samples/\(sample.id)/") ||
                                         otherRef.manifestPath.contains("samples/\(sample.id)/")
                    if pointsToSample {
                        if !referencingSamples.contains(otherKey) {
                            referencingSamples.append(otherKey)
                        }
                        if conflictingChartPath == nil {
                            conflictingChartPath = otherRef.chartImagePath
                        }
                    }

                    // 2. Shared reference: otherRef shares chart identity or image with myRefs
                    for myRef in myRefs {
                        let sharesChart = (!myRef.chartIdentityKey.isEmpty && otherRef.chartIdentityKey == myRef.chartIdentityKey) ||
                                          otherRef.chartImagePath == myRef.chartImagePath
                        if sharesChart {
                            if !referencingSamples.contains(otherKey) {
                                referencingSamples.append(otherKey)
                            }
                            if conflictingChartPath == nil {
                                conflictingChartPath = myRef.chartImagePath
                            }
                        }
                    }
                }
            }
        }

        // 3. Multi-sample charts directory check (R04):
        // If a multi-sample chart or manifest includes the target sample, deletion must be blocked
        // even if target has no matching entry in its own results index.
        // Unreadable or corrupt manifests must fail-closed as corruptDependency (S2, S4).
        let multiSampleChartsDir = rootURL.appending(path: "_spinlab/multi-sample/charts", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: multiSampleChartsDir.path) {
            let entries: [URL]
            do {
                entries = try fileManager.contentsOfDirectory(at: multiSampleChartsDir, includingPropertiesForKeys: nil)
            } catch {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: multiSampleChartsDir.path,
                    reason: "Cannot list multi-sample charts directory: \(error.localizedDescription)"
                )
            }
            let manifestDecoder = JSONDecoder()
            manifestDecoder.dateDecodingStrategy = .iso8601
            for entry in entries where entry.pathExtension == "json" || entry.lastPathComponent.hasSuffix(".manifest.json") {
                let manifestData: Data
                do {
                    manifestData = try Data(contentsOf: entry)
                } catch {
                    throw LibraryMutationSafetyError.corruptDependency(
                        sampleId: sample.id,
                        path: entry.path,
                        reason: "Cannot read multi-sample manifest: \(error.localizedDescription)"
                    )
                }
                guard let manifest = try? manifestDecoder.decode(WorkbenchRunManifest.self, from: manifestData) else {
                    throw LibraryMutationSafetyError.corruptDependency(
                        sampleId: sample.id,
                        path: entry.path,
                        reason: "Corrupted or invalid multi-sample manifest JSON at '\(entry.path)'"
                    )
                }
                let participates = manifest.inputFiles.contains { input in
                    input.contains("samples/\(sample.id)/") ||
                    input == sample.id ||
                    input.contains("/\(sample.id)/") ||
                    input.contains("/\(sample.id).")
                }
                if participates {
                    if !referencingSamples.contains("multi-sample") {
                        referencingSamples.append("multi-sample")
                    }
                    if conflictingChartPath == nil {
                        conflictingChartPath = manifest.outputImagePath
                    }
                }
            }
        }

        // 4. Multi-sample charts in target's myRefs
        for myRef in myRefs where myRef.chartImagePath.contains("multi-sample/charts") {
            if let manifestURL = try? layout.pathResolver.absoluteURL(for: myRef.manifestPath),
               fileManager.fileExists(atPath: manifestURL.path) {
                if !referencingSamples.contains("multi-sample") {
                    referencingSamples.append("multi-sample")
                }
                if conflictingChartPath == nil {
                    conflictingChartPath = myRef.chartImagePath
                }
            }
        }

        if !referencingSamples.isEmpty {
            return (true, conflictingChartPath ?? "shared-plot", referencingSamples.sorted())
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

        let dataStore = LibraryMeasurementDataStore(layout: layout)
        do {
            _ = try dataStore.loadStrict(sampleKey: sample.id)
        } catch {
            let path = (try? layout.measurementDataURL(sampleKey: sample.id))?.path ?? "measurement_data.json"
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

    // MARK: - Unrecognized Cross-Namespace Assets (AC3, F005)

    static func detectUnrecognizedCrossNamespaceAssets(
        sample: LibrarySample,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> (isUnrecognized: Bool, path: String?, reason: String?) {
        let store = LibraryStore(fileManager: fileManager)
        let sampleURL = store.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)

        // 1. Check physical sample drawer under batch
        if fileManager.fileExists(atPath: sampleURL.path) {
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

            do {
                let entries = try fileManager.contentsOfDirectory(at: sampleURL, includingPropertiesForKeys: nil)
                for entry in entries {
                    let name = entry.lastPathComponent
                    if !standardNames.contains(name) && !name.hasPrefix(".") {
                        return (true, entry.path, "Unrecognized directory entry '\(name)' in sample drawer.")
                    }
                }
            } catch {
                return (true, sampleURL.path, "Unreadable sample directory: \(sampleURL.path)")
            }
        }

        // 2. Check independent Workbench storage namespaces: samples/<sampleKey>/_spinlab and charts (F005)
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let spinlabDir: URL
        let chartsDir: URL
        let workbenchSampleDir: URL
        do {
            let resultsIndexURL = try layout.resultsIndexURL(sampleKey: sample.id)
            spinlabDir = resultsIndexURL.deletingLastPathComponent()
            let chartRelPath = layout.singleSampleChartDirectoryRelativePath(sampleKey: sample.id)
            chartsDir = try layout.pathResolver.absoluteURL(for: chartRelPath)
            workbenchSampleDir = spinlabDir.deletingLastPathComponent()
        } catch {
            return (true, rootURL.appending(path: "samples/\(sample.id)").path, "Workbench layout path resolution error: \(error)")
        }

        if fileManager.fileExists(atPath: workbenchSampleDir.path) {
            if store.containsSymbolicLink(workbenchSampleDir, relativeTo: rootURL) {
                return (true, workbenchSampleDir.path, "Workbench sample directory contains or is a symbolic link.")
            }

            let standardTopLevel: Set<String> = [
                "_spinlab",
                "charts",
                ".DS_Store"
            ]

            do {
                let entries = try fileManager.contentsOfDirectory(at: workbenchSampleDir, includingPropertiesForKeys: nil)
                for entry in entries {
                    let name = entry.lastPathComponent
                    if !standardTopLevel.contains(name) && !name.hasPrefix(".") {
                        return (true, entry.path, "Unrecognized directory entry '\(name)' in \(workbenchSampleDir.lastPathComponent).")
                    }
                }
            } catch {
                return (true, workbenchSampleDir.path, "Unreadable Workbench sample directory: \(workbenchSampleDir.path)")
            }
        }

        if fileManager.fileExists(atPath: spinlabDir.path) {
            if store.containsSymbolicLink(spinlabDir, relativeTo: rootURL) {
                return (true, spinlabDir.path, "Workbench _spinlab directory contains or is a symbolic link.")
            }

            let standardSpinlabFiles: Set<String> = [
                "results_index.json",
                "measurement_plot_index.json",
                "measurement_data.json",
                ".DS_Store"
            ]

            do {
                let entries = try fileManager.contentsOfDirectory(at: spinlabDir, includingPropertiesForKeys: nil)
                for entry in entries {
                    let name = entry.lastPathComponent
                    if !standardSpinlabFiles.contains(name) && !name.hasPrefix(".") {
                        return (true, entry.path, "Unrecognized asset '\(name)' in \(spinlabDir.path).")
                    }
                }
            } catch {
                return (true, spinlabDir.path, "Unreadable Workbench _spinlab directory: \(spinlabDir.path)")
            }
        }

        if fileManager.fileExists(atPath: chartsDir.path) {
            if store.containsSymbolicLink(chartsDir, relativeTo: rootURL) {
                return (true, chartsDir.path, "Workbench charts directory contains or is a symbolic link.")
            }

            do {
                let entries = try fileManager.contentsOfDirectory(at: chartsDir, includingPropertiesForKeys: nil)
                for entry in entries {
                    let name = entry.lastPathComponent
                    guard !name.hasPrefix(".") else { continue }
                    let isChartFile = name.hasSuffix(".png") || name.hasSuffix(".manifest.json")
                    if !isChartFile {
                        return (true, entry.path, "Unrecognized asset '\(name)' in \(chartsDir.path).")
                    }
                }
            } catch {
                return (true, chartsDir.path, "Unreadable Workbench charts directory: \(chartsDir.path)")
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

        let (isShared, chartPath, sharedWith) = try detectSharedPlotReferences(
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

        // 4. Check for active Workbench artifacts (R03, Finding 1 & Finding 2):
        // Without an authorized cascading delete / unlink mechanism, deleting a sample drawer
        // must not leave detached orphaned artifacts in the independent Workbench namespace.
        // We strictly align with detectOrphanArtifact: if ANY content exists under samples/<sample.id>
        // (including empty results_index, measurement_data, charts, or other files), explicit deletion
        // is refused fail-closed with attachedWorkbenchArtifact.
        let layout = LibraryArtifactLayout(libraryRootURL: rootURL)
        let spinlabDir: URL
        let chartsDir: URL
        let workbenchSampleDir: URL
        do {
            let resultsIndexURL = try layout.resultsIndexURL(sampleKey: sample.id)
            spinlabDir = resultsIndexURL.deletingLastPathComponent()
            let chartRelPath = layout.singleSampleChartDirectoryRelativePath(sampleKey: sample.id)
            chartsDir = try layout.pathResolver.absoluteURL(for: chartRelPath)
            workbenchSampleDir = spinlabDir.deletingLastPathComponent()
        } catch {
            throw LibraryMutationSafetyError.corruptDependency(
                sampleId: sample.id,
                path: "samples/\(sample.id)",
                reason: "Workbench layout path resolution error: \(error.localizedDescription)"
            )
        }

        let store = LibraryStore(fileManager: fileManager)

        // 4a. Check workbenchSampleDir (samples/<sample.id>)
        if fileManager.fileExists(atPath: workbenchSampleDir.path) {
            if store.containsSymbolicLink(workbenchSampleDir, relativeTo: rootURL) {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: workbenchSampleDir.path,
                    reason: "Workbench sample directory contains or is a symbolic link."
                )
            }
            let topEntries: [URL]
            do {
                topEntries = try fileManager.contentsOfDirectory(at: workbenchSampleDir, includingPropertiesForKeys: nil)
            } catch {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: workbenchSampleDir.path,
                    reason: "Cannot read Workbench sample directory: \(error.localizedDescription)"
                )
            }
            let nonHidden = topEntries.filter { !$0.lastPathComponent.hasPrefix(".") }
            let unknownTopLevel = nonHidden.filter { $0.lastPathComponent != "_spinlab" && $0.lastPathComponent != "charts" }
            if let firstUnknown = unknownTopLevel.first {
                throw LibraryMutationSafetyError.attachedWorkbenchArtifact(
                    sampleId: sample.id,
                    path: firstUnknown.path,
                    reason: "Workbench sample directory contains unrecognized entry '\(firstUnknown.lastPathComponent)'"
                )
            }
        }

        // 4b. Check spinlabDir (samples/<sample.id>/_spinlab)
        if fileManager.fileExists(atPath: spinlabDir.path) {
            if store.containsSymbolicLink(spinlabDir, relativeTo: rootURL) {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: spinlabDir.path,
                    reason: "Workbench _spinlab directory contains or is a symbolic link."
                )
            }
            let spinlabEntries: [URL]
            do {
                spinlabEntries = try fileManager.contentsOfDirectory(at: spinlabDir, includingPropertiesForKeys: nil)
            } catch {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: spinlabDir.path,
                    reason: "Cannot read Workbench _spinlab directory: \(error.localizedDescription)"
                )
            }
            let nonHidden = spinlabEntries.filter { !$0.lastPathComponent.hasPrefix(".") }
            if !nonHidden.isEmpty {
                let path = (try? layout.resultsIndexURL(sampleKey: sample.id))?.path ?? spinlabDir.path
                throw LibraryMutationSafetyError.attachedWorkbenchArtifact(
                    sampleId: sample.id,
                    path: path,
                    reason: "Workbench _spinlab directory contains \(nonHidden.count) file(s)"
                )
            }
        }

        // 4c. Check chartsDir (samples/<sample.id>/charts)
        if fileManager.fileExists(atPath: chartsDir.path) {
            if store.containsSymbolicLink(chartsDir, relativeTo: rootURL) {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: chartsDir.path,
                    reason: "Workbench charts directory contains or is a symbolic link."
                )
            }
            let chartFiles: [URL]
            do {
                chartFiles = try fileManager.contentsOfDirectory(at: chartsDir, includingPropertiesForKeys: nil)
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
            } catch {
                throw LibraryMutationSafetyError.corruptDependency(
                    sampleId: sample.id,
                    path: chartsDir.path,
                    reason: "Cannot read chart directory: \(error.localizedDescription)"
                )
            }
            if !chartFiles.isEmpty {
                throw LibraryMutationSafetyError.attachedWorkbenchArtifact(
                    sampleId: sample.id,
                    path: chartsDir.path,
                    reason: "\(chartFiles.count) chart file(s) in Workbench directory"
                )
            }
        }
    }

    // MARK: - Batch Deletion Safety Validation (AC3)

    static func validateBatchDeletionSafety(
        batchID: String,
        rootURL: URL,
        baselineIndex: LibraryIndex,
        fileManager: FileManager = .default
    ) throws {
        let allSamples = baselineIndex.samples
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
