import Foundation

/// In-memory cache for multi-sample chart references across the library.
/// Ensures cross-sample comparison charts resolve their participating samples in O(1) time
/// without repeating full-library disk scans on the main thread.
final class MultiSampleChartDirectoryCache: @unchecked Sendable {
    static let shared = MultiSampleChartDirectoryCache()
    private let lock = NSLock()
    private var cachedIndices: [String: [String: Set<String>]] = [:]

    func hasIndex(for rootURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let path = rootURL.standardizedFileURL.path
        return cachedIndices[path] != nil
    }

    func lookupSamples(for ref: WorkbenchResultReference, in rootURL: URL) -> Set<String>? {
        lock.lock()
        defer { lock.unlock() }
        let path = rootURL.standardizedFileURL.path
        guard let map = cachedIndices[path] else { return nil }
        let key = ref.chartIdentityKey.isEmpty ? ref.chartImagePath : ref.chartIdentityKey
        return map[key]
    }

    func set(map: [String: Set<String>], for rootURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        let path = rootURL.standardizedFileURL.path
        cachedIndices[path] = map
    }

    func invalidate(for rootURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        let path = rootURL.standardizedFileURL.path
        cachedIndices.removeValue(forKey: path)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cachedIndices.removeAll()
    }
}

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
/// - Accurately identifies multi-sample comparison charts strictly by confirmed participating samples (> 1).
///   Never classifies single-sample charts (e.g. PN90 historical IV charts in shared directories) as multi-sample.
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

    static func clearMultiSampleCache() {
        MultiSampleChartDirectoryCache.shared.clear()
    }

    static func invalidateMultiSampleCache(for rootURL: URL) {
        MultiSampleChartDirectoryCache.shared.invalidate(for: rootURL)
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

        // 3. Sort references by canonical tab rank (1ω → 3ω → RAHE → Hc → RT → Scaling)
        let sortedRefs = WorkbenchResultReference.sortedByTabRank(results.references)

        // 4. Pre-check if any chart references a non-sample-local path (e.g. multi-sample/charts)
        // If so, lazily build the library multi-sample reference index once and cache it.
        let hasSharedCharts = sortedRefs.contains { ref in
            !ref.chartImagePath.hasPrefix("samples/\(trimmedKey)/")
        }
        if hasSharedCharts && !MultiSampleChartDirectoryCache.shared.hasIndex(for: libraryRootURL) {
            let sharedMap = buildSharedChartIndex(layout: layout, indexStore: indexStore, resolver: resolver, fm: fm)
            MultiSampleChartDirectoryCache.shared.set(map: sharedMap, for: libraryRootURL)
        }

        // 5. Transform into WorkflowGalleryItem
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
            let title = WorkflowGalleryItem.cleanDisplayTitle(chartImagePath: ref.chartImagePath, tabKey: ref.tabKey)

            // Resolve participating samples strictly from confirmed results_index.json references.
            // Charts local to this sample belong only to this sample.
            let associatedSamples: [String]
            if ref.chartImagePath.hasPrefix("samples/\(trimmedKey)/") {
                associatedSamples = [trimmedKey]
            } else if let cached = MultiSampleChartDirectoryCache.shared.lookupSamples(for: ref, in: libraryRootURL) {
                var set = cached
                set.insert(trimmedKey)
                associatedSamples = set.sorted()
            } else {
                associatedSamples = [trimmedKey]
            }

            // P0 Semantic: A chart is multi-sample IF AND ONLY IF it has more than one confirmed participating sample.
            // Single-sample charts residing in shared directories (e.g. PN90 historical IV charts) remain isMultiSample == false.
            let isMulti = associatedSamples.count > 1

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

    /// Scans sample directories across the library once to index which samples reference shared charts.
    /// Strictly discovers confirmed references in `results_index.json`; never infers sample ownership from manifests.
    private func buildSharedChartIndex(
        layout: LibraryArtifactLayout,
        indexStore: LibraryChartIndexStore,
        resolver: LibraryPathResolver,
        fm: FileManager
    ) -> [String: Set<String>] {
        let samplesURL = layout.samplesRootURL()
        let allSampleKeys = WorkflowGalleryQueryService.findSampleKeys(at: samplesURL, resolver: resolver, using: fm)
        var map: [String: Set<String>] = [:]

        for sampleKey in allSampleKeys {
            guard let sampleResults = indexStore.loadResultsIndexFailSoft(sampleKey: sampleKey) else {
                continue
            }
            for ref in sampleResults.references {
                // Index by both identity key and image path for robust lookup
                if !ref.chartIdentityKey.isEmpty {
                    map[ref.chartIdentityKey, default: []].insert(sampleKey)
                }
                map[ref.chartImagePath, default: []].insert(sampleKey)
            }
        }

        return map
    }
}
