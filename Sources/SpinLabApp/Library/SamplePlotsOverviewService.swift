import Foundation

/// Read-only service that queries all saved plots for a specific sample directly from its
/// `results_index.json` (per P2 requirement), checking disk presence, manifest integrity,
/// and measurement associations without modifying any data.
///
/// Invariants:
/// - Zero mutations to disk, indexes, manifests, or raw measurements.
/// - Directly loads `samples/<sampleKey>/_spinlab/results_index.json`; does NOT rely on
///   reverse measurement index for plot discovery, ensuring unlinked historical charts are surfaced.
/// - Fail-soft on missing or corrupt sample indexes (returns empty array instead of crashing).
/// - Preserves missing PNG entries with `.missingFile` status and intact manifest provenance.
/// - Accurately identifies multi-sample comparison charts (e.g. in `_spinlab/multi-sample/charts/`).
/// - Seamlessly handles nested sample keys containing `/` (e.g. `PN107/SRO2|o|STO|110`).
/// - Canonicalizes workflow IDs via active `WorkflowDefinition`s (Single Source of Truth).
/// - Sorts plots stably according to canonical tab rank and generation timestamp.
struct SamplePlotsOverviewService: Sendable {
    let libraryRootURL: URL
    let workflowDefinitions: [WorkflowDefinition]

    init(libraryRootURL: URL, workflowDefinitions: [WorkflowDefinition]? = nil) {
        self.libraryRootURL = libraryRootURL
        self.workflowDefinitions = workflowDefinitions ?? WorkflowDefinitionStore().load()
    }

    /// Loads all plot items for the specified sample.
    ///
    /// - Parameters:
    ///   - sampleKey: The sample key (e.g. "PN104" or nested "PN107/SRO2|o|STO|110").
    ///   - preloadedResults: Optional in-memory `WorkbenchResultsIndex` matching `sampleKey` to skip re-reading.
    ///   - preloadedPlotIndex: Optional in-memory `MeasurementPlotIndex` matching `sampleKey` to skip re-reading.
    /// - Returns: Ordered list of `WorkflowGalleryItem`s for the sample.
    func loadPlots(
        for sampleKey: String,
        preloadedResults: WorkbenchResultsIndex? = nil,
        preloadedPlotIndex: MeasurementPlotIndex? = nil
    ) -> [WorkflowGalleryItem] {
        let trimmedKey = sampleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }

        let resolver = LibraryPathResolver(libraryRootURL: libraryRootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let fm = FileManager.default

        // 1. Resolve results_index.json
        // Check disk first to catch live external updates; fall back to preloaded if disk is absent or older
        let diskResults = indexStore.loadResultsIndexFailSoft(sampleKey: trimmedKey)
        let resultsIndex: WorkbenchResultsIndex?
        if let disk = diskResults, let preloaded = preloadedResults, preloaded.sampleKey == trimmedKey {
            resultsIndex = disk.updatedAt >= preloaded.updatedAt ? disk : preloaded
        } else {
            resultsIndex = diskResults ?? ((preloadedResults?.sampleKey == trimmedKey) ? preloadedResults : nil)
        }

        guard let results = resultsIndex, !results.references.isEmpty else {
            return []
        }

        // 2. Resolve measurement_plot_index.json to check measurement associations
        let diskPlotIndex = indexStore.loadPlotIndexFailSoft(sampleKey: trimmedKey)
        let plotIndex: MeasurementPlotIndex?
        if let disk = diskPlotIndex, let preloaded = preloadedPlotIndex, preloaded.sampleKey == trimmedKey {
            plotIndex = disk.updatedAt >= preloaded.updatedAt ? disk : preloaded
        } else {
            plotIndex = diskPlotIndex ?? ((preloadedPlotIndex?.sampleKey == trimmedKey) ? preloadedPlotIndex : nil)
        }

        var linkedChartKeys = Set<String>()
        if let plotIndex {
            for (_, cids) in plotIndex.entries {
                linkedChartKeys.formUnion(cids)
            }
        }

        // 3. Sort references canonical tab rank (1ω → 3ω → RAHE → Hc → RT → Scaling)
        let sortedRefs = WorkbenchResultReference.sortedByTabRank(results.references)

        // 4. Transform into WorkflowGalleryItem
        var items: [WorkflowGalleryItem] = []
        items.reserveCapacity(sortedRefs.count)

        for ref in sortedRefs {
            let canonicalWf = WorkflowClassifier.canonicalID(for: ref.workflowID, definitions: workflowDefinitions)

            // Disk presence check for image
            let imageStatus: WorkflowGalleryAssetStatus
            if let imageURL = try? resolver.absoluteURL(for: ref.chartImagePath) {
                imageStatus = fm.fileExists(atPath: imageURL.path) ? .available : .missingFile
            } else {
                imageStatus = .missingFile
            }

            // Disk presence check for manifest
            let manifestStatus: WorkflowGalleryAssetStatus
            if let manifestURL = try? resolver.absoluteURL(for: ref.manifestPath) {
                manifestStatus = fm.fileExists(atPath: manifestURL.path) ? .available : .missingFile
            } else {
                manifestStatus = .missingFile
            }

            let hasMeasurement = !ref.chartIdentityKey.isEmpty && linkedChartKeys.contains(ref.chartIdentityKey)
            let isMulti = ref.chartImagePath.contains("multi-sample")
            let title = WorkflowGalleryItem.cleanDisplayTitle(chartImagePath: ref.chartImagePath, tabKey: ref.tabKey)

            let associatedSamples: [String]
            if isMulti {
                associatedSamples = resolveMultiSampleKeys(
                    for: ref,
                    currentSampleKey: trimmedKey,
                    layout: layout,
                    indexStore: indexStore,
                    resolver: resolver,
                    fm: fm
                )
            } else {
                associatedSamples = [trimmedKey]
            }

            items.append(WorkflowGalleryItem(
                chartIdentityKey: ref.chartIdentityKey,
                chartImagePath: ref.chartImagePath,
                manifestPath: ref.manifestPath,
                canonicalWorkflowID: canonicalWf,
                rawWorkflowID: ref.workflowID,
                generatedAt: ref.generatedAt,
                tabKey: ref.tabKey,
                associatedSampleKeys: associatedSamples,
                isMultiSample: isMulti,
                imageStatus: imageStatus,
                manifestStatus: manifestStatus,
                hasMeasurementAssociation: hasMeasurement,
                displayTitle: title
            ))
        }

        return items
    }

    /// Resolves all participating samples that reference a multi-sample comparison chart across the library.
    private func resolveMultiSampleKeys(
        for ref: WorkbenchResultReference,
        currentSampleKey: String,
        layout: LibraryArtifactLayout,
        indexStore: LibraryChartIndexStore,
        resolver: LibraryPathResolver,
        fm: FileManager
    ) -> [String] {
        var samples = Set<String>([currentSampleKey])
        let samplesURL = layout.samplesRootURL()
        let allSampleKeys = WorkflowGalleryQueryService.findSampleKeys(at: samplesURL, resolver: resolver, using: fm)

        // 1. Check manifest input files matching known sample keys (including nested keys with slashes)
        if let manifestURL = try? resolver.absoluteURL(for: ref.manifestPath),
           let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(WorkbenchRunManifest.self, from: data) {
            for input in manifest.inputFiles {
                if input.hasPrefix("samples/") {
                    let relPath = String(input.dropFirst("samples/".count))
                    for candidateKey in allSampleKeys {
                        if relPath == candidateKey || relPath.hasPrefix(candidateKey + "/") {
                            samples.insert(candidateKey)
                        }
                    }
                }
            }
        }

        // 2. Scan samples directory in library for results_index.json referencing this chart
        for otherKey in allSampleKeys where otherKey != currentSampleKey {
            if let otherResults = indexStore.loadResultsIndexFailSoft(sampleKey: otherKey) {
                if otherResults.references.contains(where: {
                    (!ref.chartIdentityKey.isEmpty && $0.chartIdentityKey == ref.chartIdentityKey) ||
                    $0.chartImagePath == ref.chartImagePath
                }) {
                    samples.insert(otherKey)
                }
            }
        }

        return samples.sorted()
    }
}
