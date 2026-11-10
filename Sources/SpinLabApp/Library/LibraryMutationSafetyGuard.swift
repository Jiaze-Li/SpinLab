import Foundation

enum LibraryMutationSafetyError: LocalizedError, Equatable {
    /// AC2 / S2: Registry diff dropped or rekeyed a sample. A missing or changed Registry row is not deletion authorization.
    case registrySampleRemovalNotAuthorized(sampleId: String, batchId: String)
    /// AC2 / S2: Registry diff dropped or rekeyed a batch. A missing or changed Registry sheet is not deletion authorization.
    case registryBatchRemovalNotAuthorized(batchId: String)
    /// S5: The Library changed after the first safety check (another writer). The apply stopped before applying
    /// the plan, but the preparation step had already refreshed batch bookkeeping and the index.
    case registryPlanChangedDuringApply(subject: String)
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
        case let .registrySampleRemovalNotAuthorized(sampleId, batchId):
            return "Registry apply refused before any change: sample '\(sampleId)' in batch '\(batchId)' is missing from the Registry (or its key was changed). A missing or re-keyed Registry row is not authorization to delete a Library sample, and no automatic Registry deletion is approved. Nothing was modified. Restore the row or the original key in the Registry and apply again, or delete the sample explicitly from the Library."
        case let .registryBatchRemovalNotAuthorized(batchId):
            return "Registry apply refused before any change: batch '\(batchId)' is missing from the Registry (or its key was changed). A missing or re-keyed Registry sheet is not authorization to delete a Library batch, and no automatic Registry deletion is approved. Nothing was modified. Restore the sheet or the original key in the Registry and apply again, or delete the batch explicitly from the Library."
        case let .registryPlanChangedDuringApply(subject):
            return "Registry apply stopped: the Library changed while the apply was being prepared, and \(subject) is no longer matched by the Registry preview. A missing Registry row is not authorization to delete, so no sample or measurement was deleted and the Registry changes were not applied. Preparation had already refreshed the Library index and batch bookkeeping to match the folders on disk. Review the Library, rebuild the Registry preview and apply again."
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
    /// Explicit user deletion is a separate path guarded by `validateExplicitDeletionSafety` (AC3).
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
