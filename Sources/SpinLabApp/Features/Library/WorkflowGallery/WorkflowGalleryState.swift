import AppKit
import Foundation
import Observation

enum WorkflowGallerySortOrder: String, CaseIterable, Identifiable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case bySample = "By Sample"

    var id: String { rawValue }
}

enum WorkflowGalleryFilter: String, CaseIterable, Identifiable {
    case all = "All Charts"
    case validOnly = "Valid Only"
    case missingOnly = "Missing Files"
    case multiSampleOnly = "Multi-Sample"

    var id: String { rawValue }
}

@MainActor
@Observable
final class WorkflowGalleryState {
    var selectedItem: WorkflowGalleryItem?
    var previewImage: NSImage?
    var imageLoadingError: String?
    var manifest: WorkbenchRunManifest?
    var manifestLoadingError: String?
    var items: [WorkflowGalleryItem] = []
    var queryResult: WorkflowGalleryQueryResult?
    var isLoading: Bool = false
    var hasLoaded: Bool = false
    var loadedLibraryRootURL: URL?
    var errorMessage: String? = nil
    var currentWorkflowID: String?
    var isFullScreenPresented: Bool = false
    var sortOrder: WorkflowGallerySortOrder = .newestFirst
    var filterOption: WorkflowGalleryFilter = .all
    var searchText: String = ""

    private var activeQueryGeneration: Int = 0
    private var activeDetailGeneration: Int = 0

    /// Optional hook for testing deterministic out-of-order execution.
    var queryExecutor: ((_ service: WorkflowGalleryQueryService, _ workflowID: String) async -> WorkflowGalleryQueryResult)? = nil

    /// Optional hook for testing deterministic thumbnail decoding races.
    var thumbnailLoader: ((_ url: URL, _ key: String, _ maxPixelSize: CGFloat) async -> NSImage?)? = nil

    /// Filtered and sorted items ready for display in the grid.
    var displayItems: [WorkflowGalleryItem] {
        var result = items

        // 1. Filter by status / type
        switch filterOption {
        case .all:
            break
        case .validOnly:
            result = result.filter { $0.imageStatus == .available }
        case .missingOnly:
            result = result.filter { $0.imageStatus == .missingFile }
        case .multiSampleOnly:
            result = result.filter { $0.isMultiSample }
        }

        // 2. Filter by search text
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.displayTitle.lowercased().contains(query) ||
                item.associatedSampleKeys.contains { $0.lowercased().contains(query) } ||
                (item.tabKey?.lowercased().contains(query) ?? false)
            }
        }

        // 3. Sort stably
        switch sortOrder {
        case .newestFirst:
            result.sort {
                if $0.generatedAt != $1.generatedAt {
                    return $0.generatedAt > $1.generatedAt
                }
                return $0.id < $1.id
            }
        case .oldestFirst:
            result.sort {
                if $0.generatedAt != $1.generatedAt {
                    return $0.generatedAt < $1.generatedAt
                }
                return $0.id < $1.id
            }
        case .bySample:
            result.sort {
                let s0 = $0.associatedSampleKeys.first ?? ""
                let s1 = $1.associatedSampleKeys.first ?? ""
                if s0 != s1 {
                    return s0.localizedStandardCompare(s1) == .orderedAscending
                }
                return $0.id < $1.id
            }
        }

        return result
    }

    /// Invalidates both pending queries and preview state when no Library Root is configured.
    func clearForUnconfiguredRoot() {
        activeQueryGeneration += 1
        activeDetailGeneration += 1
        clearGalleryContent()
        currentWorkflowID = nil
        loadedLibraryRootURL = nil
        hasLoaded = false
        isLoading = false
        errorMessage = nil
    }

    private func clearGalleryContent() {
        items = []
        queryResult = nil
        selectedItem = nil
        manifest = nil
        manifestLoadingError = nil
        previewImage = nil
        imageLoadingError = nil
        isFullScreenPresented = false
    }

    /// Loads or refreshes the gallery for the given workflow ID asynchronously.
    func loadGallery(
        workflowID: String,
        libraryRootURL: URL,
        workflowDefinitions: [WorkflowDefinition],
        forceReload: Bool = false
    ) async {
        // Advance monotonic generation token immediately to invalidate any in-flight queries
        activeQueryGeneration += 1
        let currentGeneration = activeQueryGeneration

        // If the requested workflow and root are already loaded and intact, skip re-querying.
        // Advancing activeQueryGeneration above guarantees no previous in-flight query can overwrite this state.
        if !forceReload &&
            hasLoaded &&
            currentWorkflowID == workflowID &&
            loadedLibraryRootURL == libraryRootURL &&
            errorMessage == nil {
            isLoading = false
            if selectedItem == nil {
                selectedItem = items.first
            }
            return
        }

        // Hide the previous context's provenance while retaining the last successful
        // query as a fast return target if an in-flight switch is cancelled.
        if currentWorkflowID != workflowID || loadedLibraryRootURL != libraryRootURL {
            selectedItem = nil
            manifest = nil
            manifestLoadingError = nil
            previewImage = nil
            imageLoadingError = nil
            isFullScreenPresented = false
        }

        isLoading = true
        errorMessage = nil

        let service = WorkflowGalleryQueryService(
            libraryRootURL: libraryRootURL,
            workflowDefinitions: workflowDefinitions
        )

        // Read query result in background off the main thread to prevent UI freezing
        let result: WorkflowGalleryQueryResult
        if let executor = queryExecutor {
            result = await executor(service, workflowID)
        } else {
            result = await Task.detached(priority: .userInitiated) {
                service.execute(workflowID: workflowID)
            }.value
        }

        // Stale query race & cancellation protection: ignore result if cancelled or superseded
        guard !Task.isCancelled,
              currentGeneration == self.activeQueryGeneration else {
            // If this was the active query and was cancelled, reset isLoading so UI is not stuck spinning
            if currentGeneration == self.activeQueryGeneration {
                self.isLoading = false
            }
            return
        }

        // Commit state atomically upon successful query completion
        self.currentWorkflowID = workflowID
        self.loadedLibraryRootURL = libraryRootURL
        self.queryResult = result
        self.items = result.items
        self.isLoading = false
        self.hasLoaded = true

        if result.items.isEmpty && !result.unreadableSampleIndices.isEmpty {
            self.errorMessage = "Failed to query charts: results_index.json could not be read for \(result.unreadableSampleIndices.count) samples (\(result.unreadableSampleIndices.joined(separator: ", ")))."
        }

        // Maintain selection or select first item if none selected
        if let currentSelected = selectedItem {
            if let updated = result.items.first(where: { $0.id == currentSelected.id }) {
                self.selectedItem = updated
            } else {
                self.selectedItem = result.items.first
            }
        } else {
            self.selectedItem = result.items.first
        }
    }

    /// Only expose a selected chart to Detail when it belongs to the active route/root.
    /// When `workflowID` is nil, scopes to the current root without workflow-type filtering (e.g. for sample-level gallery).
    func visibleItem(for workflowID: String? = nil, libraryRootURL: URL?) -> WorkflowGalleryItem? {
        guard let libraryRootURL,
              hasLoaded,
              loadedLibraryRootURL == libraryRootURL else {
            return nil
        }
        if let workflowID, currentWorkflowID != workflowID {
            return nil
        }
        return selectedItem
    }

    /// Configures the state for a specific sample's items without running a full-library scan.
    func configureForSample(
        items: [WorkflowGalleryItem],
        libraryRootURL: URL?,
        preselectedItem: WorkflowGalleryItem? = nil
    ) {
        self.currentWorkflowID = nil
        self.loadedLibraryRootURL = libraryRootURL
        self.items = items
        self.queryResult = WorkflowGalleryQueryResult(
            items: items,
            totalReferenceCount: items.count,
            uniqueChartCount: items.count,
            missingImageCount: items.filter { $0.imageStatus == .missingFile }.count,
            missingManifestCount: items.filter { $0.manifestStatus == .missingFile }.count
        )
        self.isLoading = false
        self.hasLoaded = true
        if let preselectedItem, items.contains(where: { $0.id == preselectedItem.id }) {
            self.selectedItem = preselectedItem
        } else {
            self.selectedItem = items.first
        }
    }

    func selectItem(_ item: WorkflowGalleryItem?) {
        self.selectedItem = item
    }

    func openFullScreen() {
        if selectedItem != nil {
            isFullScreenPresented = true
        }
    }

    /// Loads detail manifest and preview image asynchronously with monotonic generation race protection.
    func loadSelectedDetail(item: WorkflowGalleryItem?, libraryRootURL: URL?) async {
        activeDetailGeneration += 1
        let currentGeneration = activeDetailGeneration

        // Clear the previous image/error before loading the next item's provenance.
        manifest = nil
        previewImage = nil
        manifestLoadingError = nil
        imageLoadingError = nil

        guard let item else {
            manifest = nil
            previewImage = nil
            manifestLoadingError = nil
            imageLoadingError = nil
            return
        }

        guard let libraryRootURL else {
            manifest = nil
            previewImage = nil
            manifestLoadingError = "Library root not configured"
            imageLoadingError = "Library root not configured"
            return
        }

        let requestedItemID = item.id

        // Load manifest synchronously
        let manifestURL = libraryRootURL.appending(path: item.manifestPath)
        if FileManager.default.fileExists(atPath: manifestURL.path),
           let data = try? Data(contentsOf: manifestURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(WorkbenchRunManifest.self, from: data) {
                self.manifest = decoded
                self.manifestLoadingError = nil
            } else {
                self.manifest = nil
                self.manifestLoadingError = "Corrupted manifest"
            }
        } else {
            self.manifest = nil
            self.manifestLoadingError = "Manifest not found"
        }

        // Load preview image asynchronously
        if item.imageStatus == .available {
            let cacheKey = WorkflowThumbnailCache.cacheKey(rootURL: libraryRootURL, relativePath: item.chartImagePath, maxPixelSize: 960)
            let fullURL = libraryRootURL.appending(path: item.chartImagePath)

            let image: NSImage?
            if let loader = thumbnailLoader {
                image = await loader(fullURL, cacheKey, 960)
            } else {
                image = await WorkflowThumbnailCache.shared.loadThumbnailAsync(
                    url: fullURL,
                    key: cacheKey,
                    maxPixelSize: 960
                )
            }

            // Late image load protection: ensure task was not cancelled, and this generation is still active
            guard !Task.isCancelled,
                  currentGeneration == self.activeDetailGeneration,
                  self.selectedItem?.id == requestedItemID else {
                return
            }

            self.previewImage = image
            if image == nil {
                self.imageLoadingError = "Image file is unreadable or corrupt on disk."
            } else {
                self.imageLoadingError = nil
            }
        } else if item.imageStatus == .missingFile {
            self.previewImage = nil
            self.imageLoadingError = nil
        } else {
            self.previewImage = nil
            self.imageLoadingError = "Image file is damaged or unreadable."
        }
    }
}
