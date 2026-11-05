import Foundation

/// Read-only service that scans existing Library indexes and aggregates charts into a
/// unified, deduplicated Workflow Gallery view.
///
/// Follows all Library safety invariants:
/// - Zero mutations to disks, indexes, manifests, or raw data.
/// - Fail-soft on corrupted sample indexes (records them in unreadable list, doesn't abort scan).
/// - Correctly merges multi-sample references into a single gallery card preserving all sample keys.
/// - Identifies missing PNGs and unlinked measurement charts without discarding or hiding them.
/// - Uses the application's active `WorkflowDefinition`s as the sole authority for workflow metadata.
struct WorkflowGalleryQueryService: Sendable {
    let libraryRootURL: URL
    let workflowDefinitions: [WorkflowDefinition]

    init(libraryRootURL: URL, workflowDefinitions: [WorkflowDefinition]? = nil) {
        self.libraryRootURL = libraryRootURL
        self.workflowDefinitions = workflowDefinitions ?? WorkflowDefinitionStore().load()
    }

    /// Executes the read-only gallery scan, optionally filtering by canonical workflow ID.
    func execute(workflowID: String? = nil) -> WorkflowGalleryQueryResult {
        let resolver = LibraryPathResolver(libraryRootURL: libraryRootURL)
        let layout = LibraryArtifactLayout(pathResolver: resolver)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let fm = FileManager.default

        let samplesURL = layout.samplesRootURL()
        let sampleKeys = Self.findSampleKeys(at: samplesURL, resolver: resolver, using: fm)

        var totalRefs = 0
        var unreadableSampleKeys: [String] = []

        // Temporary storage for aggregating items: chartIdentityKey -> mutable entry
        struct AggregateEntry {
            var chartIdentityKey: String
            var chartImagePath: String
            var manifestPath: String
            var canonicalWorkflowID: String
            var rawWorkflowID: String
            var generatedAt: Date
            var tabKey: String?
            var sampleKeys: Set<String>
        }

        var aggregated: [String: AggregateEntry] = [:]
        var allIndexedMeasurementChartKeys = Set<String>()

        // 1. Scan each sample directory
        for sk in sampleKeys {
            // Collect measurement_plot_index keys if present
            if let plotIndex = indexStore.loadPlotIndexFailSoft(sampleKey: sk) {
                for (_, cids) in plotIndex.entries {
                    allIndexedMeasurementChartKeys.formUnion(cids)
                }
            }

            // Load results_index
            switch indexStore.loadResultsIndexForAudit(sampleKey: sk) {
            case .missing:
                continue
            case .corrupt:
                unreadableSampleKeys.append(sk)
                continue
            case .ok(let index):
                for ref in index.references {
                    totalRefs += 1
                    let key = ref.chartIdentityKey.isEmpty ? "path:\(ref.chartImagePath)" : "chart:\(ref.chartIdentityKey)"
                    let canonicalWf = WorkflowClassifier.canonicalID(for: ref.workflowID, definitions: workflowDefinitions)

                    if var existing = aggregated[key] {
                        existing.sampleKeys.insert(sk)
                        if existing.tabKey == nil { existing.tabKey = ref.tabKey }
                        if ref.generatedAt > existing.generatedAt {
                            existing.generatedAt = ref.generatedAt
                        }
                        aggregated[key] = existing
                    } else {
                        aggregated[key] = AggregateEntry(
                            chartIdentityKey: ref.chartIdentityKey,
                            chartImagePath: ref.chartImagePath,
                            manifestPath: ref.manifestPath,
                            canonicalWorkflowID: canonicalWf,
                            rawWorkflowID: ref.workflowID,
                            generatedAt: ref.generatedAt,
                            tabKey: ref.tabKey,
                            sampleKeys: [sk]
                        )
                    }
                }
            }
        }

        // 2. Classify assets and build final items
        var allItems: [WorkflowGalleryItem] = []
        var missingImages = 0
        var missingManifests = 0
        var workflowCounts: [String: Int] = [:]

        for (_, entry) in aggregated {
            // Workflow count tracks canonical ID across the whole library
            workflowCounts[entry.canonicalWorkflowID, default: 0] += 1

            // Check asset files on disk
            let imageStatus: WorkflowGalleryAssetStatus
            if let imageURL = try? resolver.absoluteURL(for: entry.chartImagePath) {
                imageStatus = fm.fileExists(atPath: imageURL.path) ? .available : .missingFile
            } else {
                imageStatus = .missingFile
            }
            if imageStatus == .missingFile {
                missingImages += 1
            }

            let manifestStatus: WorkflowGalleryAssetStatus
            if let manifestURL = try? resolver.absoluteURL(for: entry.manifestPath) {
                manifestStatus = fm.fileExists(atPath: manifestURL.path) ? .available : .missingFile
            } else {
                manifestStatus = .missingFile
            }
            if manifestStatus == .missingFile {
                missingManifests += 1
            }

            let sortedSamples = entry.sampleKeys.sorted()
            let isMulti = sortedSamples.count > 1
            let hasMeasurement = !entry.chartIdentityKey.isEmpty && allIndexedMeasurementChartKeys.contains(entry.chartIdentityKey)
            let title = cleanDisplayTitle(chartImagePath: entry.chartImagePath, tabKey: entry.tabKey)

            allItems.append(WorkflowGalleryItem(
                chartIdentityKey: entry.chartIdentityKey,
                chartImagePath: entry.chartImagePath,
                manifestPath: entry.manifestPath,
                canonicalWorkflowID: entry.canonicalWorkflowID,
                rawWorkflowID: entry.rawWorkflowID,
                generatedAt: entry.generatedAt,
                tabKey: entry.tabKey,
                associatedSampleKeys: sortedSamples,
                isMultiSample: isMulti,
                imageStatus: imageStatus,
                manifestStatus: manifestStatus,
                hasMeasurementAssociation: hasMeasurement,
                displayTitle: title
            ))
        }

        // 3. Filter by workflowID if specified
        let filteredItems: [WorkflowGalleryItem]
        if let targetWf = workflowID {
            let targetCanonical = WorkflowClassifier.canonicalID(for: targetWf, definitions: workflowDefinitions)
            filteredItems = allItems.filter { $0.canonicalWorkflowID.caseInsensitiveCompare(targetCanonical) == .orderedSame }
        } else {
            filteredItems = allItems
        }

        // 4. Stable sort: generatedAt descending (newest first), tie-break by chartIdentityKey
        let sortedItems = filteredItems.sorted { a, b in
            if a.generatedAt != b.generatedAt {
                return a.generatedAt > b.generatedAt
            }
            return a.id < b.id
        }

        return WorkflowGalleryQueryResult(
            items: sortedItems,
            totalReferenceCount: totalRefs,
            uniqueChartCount: aggregated.count,
            missingImageCount: missingImages,
            missingManifestCount: missingManifests,
            unreadableSampleIndices: unreadableSampleKeys.sorted(),
            workflowCounts: workflowCounts
        )
    }

    // MARK: - Helpers

    static func findSampleKeys(
        at samplesURL: URL,
        resolver: LibraryPathResolver,
        using fm: FileManager
    ) -> [String] {
        guard let enumerator = fm.enumerator(
            at: samplesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var sampleKeys = Set<String>()
        let samplesStandardURL = samplesURL.standardizedFileURL
        let samplesPath = samplesStandardURL.path

        for case let fileURL as URL in enumerator {
            // Guard against symlink escape: do not follow symlinks outside authorized Library root
            if let vals = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
               vals.isSymbolicLink == true {
                let resolved = fileURL.resolvingSymlinksInPath()
                guard (try? resolver.relativePath(for: resolved)) != nil else {
                    enumerator.skipDescendants()
                    continue
                }
            }

            guard fileURL.lastPathComponent == "results_index.json" else { continue }
            let spinlabDirURL = fileURL.deletingLastPathComponent()
            guard spinlabDirURL.lastPathComponent == "_spinlab" else { continue }

            let sampleDirURL = spinlabDirURL.deletingLastPathComponent().standardizedFileURL
            let sampleDirPath = sampleDirURL.path

            // Ensure sample directory is contained strictly within samplesRootURL
            guard sampleDirPath.hasPrefix(samplesPath + "/") else { continue }
            let relativeSampleKey = String(sampleDirPath.dropFirst(samplesPath.count + 1))
            guard !relativeSampleKey.isEmpty else { continue }

            sampleKeys.insert(relativeSampleKey)
        }

        return sampleKeys.sorted()
    }

    private func cleanDisplayTitle(chartImagePath: String, tabKey: String?) -> String {
        WorkflowGalleryItem.cleanDisplayTitle(chartImagePath: chartImagePath, tabKey: tabKey)
    }
}
