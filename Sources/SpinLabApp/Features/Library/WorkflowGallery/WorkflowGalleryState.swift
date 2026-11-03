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

    /// Optional hook for testing deterministic out-of-order execution.
    var queryExecutor: ((_ service: WorkflowGalleryQueryService, _ workflowID: String) async -> WorkflowGalleryQueryResult)? = nil

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
                return $0.chartIdentityKey < $1.chartIdentityKey
            }
        case .oldestFirst:
            result.sort {
                if $0.generatedAt != $1.generatedAt {
                    return $0.generatedAt < $1.generatedAt
                }
                return $0.chartIdentityKey < $1.chartIdentityKey
            }
        case .bySample:
            result.sort {
                let s0 = $0.associatedSampleKeys.first ?? ""
                let s1 = $1.associatedSampleKeys.first ?? ""
                if s0 != s1 {
                    return s0.localizedStandardCompare(s1) == .orderedAscending
                }
                return $0.chartIdentityKey < $1.chartIdentityKey
            }
        }

        return result
    }

    /// Loads or refreshes the gallery for the given workflow ID asynchronously.
    func loadGallery(
        workflowID: String,
        libraryRootURL: URL,
        workflowDefinitions: [WorkflowDefinition],
        forceReload: Bool = false
    ) async {
        if !forceReload &&
            hasLoaded &&
            currentWorkflowID == workflowID &&
            loadedLibraryRootURL == libraryRootURL &&
            errorMessage == nil {
            return
        }

        activeQueryGeneration += 1
        let currentGeneration = activeQueryGeneration

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

    func selectItem(_ item: WorkflowGalleryItem?) {
        self.selectedItem = item
    }

    func openFullScreen() {
        if selectedItem != nil {
            isFullScreenPresented = true
        }
    }
}
