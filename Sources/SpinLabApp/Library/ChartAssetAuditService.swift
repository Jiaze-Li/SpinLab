import Foundation

// MARK: - Chart Asset Audit Report

struct ChartAssetAuditReport: Sendable {
    struct OrphanFile: Sendable, Hashable, Identifiable {
        var id: String { relativePath }
        var relativePath: String
        var sampleKey: String?
        var filename: String
    }

    struct MissingActiveFile: Sendable, Hashable {
        var chartIdentityKey: String
        var relativePath: String
        var sampleKey: String
    }

    var activeChartCount: Int
    var orphanImages: [OrphanFile]
    var orphanManifests: [OrphanFile]
    var missingActiveImages: [MissingActiveFile]
    var missingActiveManifests: [MissingActiveFile]
    /// Sample keys whose `results_index.json` exists but could not be decoded.
    /// Files owned by these samples are excluded from orphan classification —
    /// a corrupt index must never cause a still-referenced chart to be treated
    /// as orphan and become a destructive-delete candidate. Callers must surface
    /// this state to the user rather than silently proceeding as if it were empty.
    var unreadableIndexSampleKeys: [String] = []
}

// MARK: - Operation result types

struct DeleteOrphanResult: Sendable {
    var deletedCount: Int
    var failedPaths: [String]
}

struct CleanMissingRefsResult: Sendable {
    var cleanedRefCount: Int
    var failedSampleKeys: [String]
}

// MARK: - Chart Asset Audit Service

enum ChartAssetAuditService {

    // MARK: - Audit

    /// Scans the library root and classifies chart assets as active, orphan, or missing.
    /// - Active: referenced by results_index.json.
    /// - Orphan: PNG/manifest exists on disk but is not referenced by any active index.
    /// - Missing: active reference exists in index but the file is absent on disk.
    nonisolated static func audit(rootURL: URL) -> ChartAssetAuditReport {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let fm = FileManager.default

        let samplesURL = layout.samplesRootURL()
        let sampleDirs = sampleDirectories(at: samplesURL, using: fm)

        // 1. Collect all active refs from every sample's results_index.json.
        // A corrupt index is recorded as unreadable and excluded from this sample's
        // orphan classification below — never silently treated as "no active refs".
        var activeImagePaths = Set<String>()
        var activeManifestPaths = Set<String>()
        var identityByImagePath: [String: String] = [:]
        var identityByManifestPath: [String: String] = [:]
        var sampleKeyByImagePath: [String: String] = [:]
        var sampleKeyByManifestPath: [String: String] = [:]
        var unreadableSampleKeys: [String] = []

        for sampleDir in sampleDirs {
            let sk = sampleDir.lastPathComponent
            switch indexStore.loadResultsIndexForAudit(sampleKey: sk) {
            case .missing:
                continue
            case .corrupt:
                unreadableSampleKeys.append(sk)
                continue
            case .ok(let index):
                for ref in index.references {
                    activeImagePaths.insert(ref.chartImagePath)
                    activeManifestPaths.insert(ref.manifestPath)
                    identityByImagePath[ref.chartImagePath] = ref.chartIdentityKey
                    identityByManifestPath[ref.manifestPath] = ref.chartIdentityKey
                    if sampleKeyByImagePath[ref.chartImagePath] == nil {
                        sampleKeyByImagePath[ref.chartImagePath] = sk
                    }
                    if sampleKeyByManifestPath[ref.manifestPath] == nil {
                        sampleKeyByManifestPath[ref.manifestPath] = sk
                    }
                }
            }
        }

        let unreadableSet = Set(unreadableSampleKeys)

        // 2. Scan charts directories for actual files on disk. Samples with an
        // unreadable index are skipped entirely — their real chart files must
        // never enter the orphan candidate pool while we cannot confirm what
        // the (corrupt) index actually references.
        var foundImagePaths = Set<String>()
        var foundManifestPaths = Set<String>()

        for sampleDir in sampleDirs {
            guard !unreadableSet.contains(sampleDir.lastPathComponent) else { continue }
            scanChartsDirectory(sampleDir.appending(path: "charts"), resolver: resolver, fm: fm,
                                images: &foundImagePaths, manifests: &foundManifestPaths)
        }
        // A shared multi-sample chart may be referenced only by an index we could not
        // read, so its path would never reach activeImagePaths/activeManifestPaths.
        // Skip the shared directory entirely whenever any index is unreadable — the
        // alternative (scanning it unconditionally) can misclassify a still-referenced
        // shared chart as orphan and expose it to permanent deletion.
        if unreadableSet.isEmpty {
            scanChartsDirectory(rootURL.appending(path: "_spinlab/multi-sample/charts"), resolver: resolver, fm: fm,
                                images: &foundImagePaths, manifests: &foundManifestPaths)
        }

        // 3. Classify orphans (found on disk but not in any active index).
        let orphanImages = foundImagePaths.subtracting(activeImagePaths).sorted().map { rp in
            ChartAssetAuditReport.OrphanFile(relativePath: rp, sampleKey: sampleKeyFromPath(rp),
                                             filename: URL(fileURLWithPath: rp).lastPathComponent)
        }
        let orphanManifests = foundManifestPaths.subtracting(activeManifestPaths).sorted().map { rp in
            ChartAssetAuditReport.OrphanFile(relativePath: rp, sampleKey: sampleKeyFromPath(rp),
                                             filename: URL(fileURLWithPath: rp).lastPathComponent)
        }

        // 4. Classify missing active files (in active index but absent on disk).
        let missingActiveImages: [ChartAssetAuditReport.MissingActiveFile] = activeImagePaths.sorted().compactMap { rp in
            guard let absURL = try? resolver.absoluteURL(for: rp), !fm.fileExists(atPath: absURL.path) else { return nil }
            return ChartAssetAuditReport.MissingActiveFile(
                chartIdentityKey: identityByImagePath[rp] ?? "",
                relativePath: rp,
                sampleKey: sampleKeyByImagePath[rp] ?? "")
        }
        let missingActiveManifests: [ChartAssetAuditReport.MissingActiveFile] = activeManifestPaths.sorted().compactMap { rp in
            guard let absURL = try? resolver.absoluteURL(for: rp), !fm.fileExists(atPath: absURL.path) else { return nil }
            return ChartAssetAuditReport.MissingActiveFile(
                chartIdentityKey: identityByManifestPath[rp] ?? "",
                relativePath: rp,
                sampleKey: sampleKeyByManifestPath[rp] ?? "")
        }

        return ChartAssetAuditReport(
            activeChartCount: activeImagePaths.count,
            orphanImages: orphanImages,
            orphanManifests: orphanManifests,
            missingActiveImages: missingActiveImages,
            missingActiveManifests: missingActiveManifests,
            unreadableIndexSampleKeys: unreadableSampleKeys.sorted()
        )
    }

    // MARK: - Delete orphan files

    /// Permanently deletes orphan files from disk.
    /// Orphan files are not referenced by any active index, so no index rewrite is needed.
    /// Returns counts and any paths that could not be deleted.
    @discardableResult
    nonisolated static func deleteOrphanFiles(_ relativePaths: [String], rootURL: URL) -> DeleteOrphanResult {
        guard !relativePaths.isEmpty else { return DeleteOrphanResult(deletedCount: 0, failedPaths: []) }
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let fm = FileManager.default

        var deletedCount = 0
        var failedPaths: [String] = []

        for relPath in relativePaths {
            guard let sourceURL = try? resolver.absoluteURL(for: relPath) else {
                fputs("[SpinLab] ChartAssetAudit: cannot resolve path — \(relPath)\n", stderr)
                failedPaths.append(relPath)
                continue
            }
            guard fm.fileExists(atPath: sourceURL.path) else {
                deletedCount += 1  // already absent — treat as success
                continue
            }
            do {
                try fm.removeItem(at: sourceURL)
                deletedCount += 1
            } catch {
                fputs("[SpinLab] ChartAssetAudit: delete failed \(sourceURL.path): \(error)\n", stderr)
                failedPaths.append(relPath)
            }
        }

        return DeleteOrphanResult(deletedCount: deletedCount, failedPaths: failedPaths)
    }

    // MARK: - Clean missing references

    /// Removes active index entries whose PNG or manifest files are absent on disk.
    /// Cleans both results_index.json and measurement_plot_index.json for every affected sample.
    /// Does not delete any files — only rewrites index JSON.
    nonisolated static func cleanMissingReferences(rootURL: URL) -> CleanMissingRefsResult {
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let fm = FileManager.default
        let sampleDirs = sampleDirectories(at: layout.samplesRootURL(), using: fm)
        let writer = AtomicFileWriter()

        var totalCleaned = 0
        var failedSampleKeys: [String] = []

        for sampleDir in sampleDirs {
            let sk = sampleDir.lastPathComponent

            // Load results_index — absent file is fine (nothing to clean).
            guard let resultsIndex = LoadWorkbenchResultsUseCase(pathResolver: resolver).execute(sampleKey: sk) else {
                continue
            }

            // Identify refs where either the PNG or the manifest is missing on disk.
            var brokenKeys = Set<String>()
            for ref in resultsIndex.references {
                let imageMissing: Bool
                if let url = try? resolver.absoluteURL(for: ref.chartImagePath) {
                    imageMissing = !fm.fileExists(atPath: url.path)
                } else {
                    imageMissing = true
                }
                let manifestMissing: Bool
                if let url = try? resolver.absoluteURL(for: ref.manifestPath) {
                    manifestMissing = !fm.fileExists(atPath: url.path)
                } else {
                    manifestMissing = true
                }
                if imageMissing || manifestMissing {
                    brokenKeys.insert(ref.chartIdentityKey)
                }
            }

            guard !brokenKeys.isEmpty else { continue }

            // Build cleaned results_index.
            var updatedResults = resultsIndex
            updatedResults.references.removeAll { brokenKeys.contains($0.chartIdentityKey) }
            updatedResults.updatedAt = Date()

            guard let resultsAbsURL = try? layout.resultsIndexURL(sampleKey: sk),
                  let resultsData = try? indexStore.encodeResultsIndex(updatedResults) else {
                failedSampleKeys.append(sk)
                continue
            }

            // Build cleaned measurement_plot_index if present.
            var plotWrites: [AtomicWriteEntry] = []
            if let plotAbsURL = try? layout.measurementPlotIndexURL(sampleKey: sk),
               fm.fileExists(atPath: plotAbsURL.path),
               let plotIndex = LoadMeasurementPlotIndexUseCase(pathResolver: resolver).execute(sampleKey: sk) {
                let updatedPlot = indexStore.removingChartKeys(brokenKeys, from: plotIndex, updatedAt: Date())
                if let plotData = try? indexStore.encodePlotIndex(updatedPlot) {
                    plotWrites.append(AtomicWriteEntry(destinationURL: plotAbsURL, data: plotData))
                }
            }

            var writes: [AtomicWriteEntry] = [AtomicWriteEntry(destinationURL: resultsAbsURL, data: resultsData)]
            writes.append(contentsOf: plotWrites)

            do {
                try writer.commit(writes)
                totalCleaned += brokenKeys.count
            } catch {
                fputs("[SpinLab] ChartAssetAudit: cleanMissingRefs write failed for \(sk): \(error)\n", stderr)
                failedSampleKeys.append(sk)
            }
        }

        return CleanMissingRefsResult(cleanedRefCount: totalCleaned, failedSampleKeys: failedSampleKeys)
    }

    // MARK: - Helpers

    private static func sampleDirectories(at samplesURL: URL, using fm: FileManager) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: samplesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private static func scanChartsDirectory(
        _ chartsDir: URL,
        resolver: LibraryPathResolver,
        fm: FileManager,
        images: inout Set<String>,
        manifests: inout Set<String>
    ) {
        guard let files = try? fm.contentsOfDirectory(
            at: chartsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }
        for file in files {
            guard let relPath = try? resolver.relativePath(for: file) else { continue }
            let name = file.lastPathComponent
            if name.hasSuffix(".png") {
                images.insert(relPath)
            } else if name.hasSuffix(".manifest.json") {
                manifests.insert(relPath)
            }
        }
    }

    private static func sampleKeyFromPath(_ relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/", maxSplits: 3)
        guard parts.count >= 2, parts[0] == "samples" else { return nil }
        return String(parts[1])
    }
}
