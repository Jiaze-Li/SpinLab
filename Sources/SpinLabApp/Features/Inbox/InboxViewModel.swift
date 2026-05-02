import Foundation
import Observation

struct InboxOperationProjection {
    let libraryMatchedCount: Int
    let reviewRequiredCount: Int
    let filteredPendingImports: [SpinLabDomain.PendingImport]
    let routePresentationByID: [UUID: PendingRoutePresentation]
}

@MainActor
@Observable
final class InboxViewModel {
    enum FileFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case libraryMatched = "Library Matched"
        case reviewRequired = "Review Required"

        var id: String { rawValue }
    }

    var isImportSourceExpanded = true
    var isPendingQueueExpanded = true
    var isRoutingReviewExpanded = true
    var isApplyExpanded = true
    var fileFilter: FileFilter = .all
    var applySelected: () -> Void = { }
    var applyAll: () -> Void = { }

    func restoreInteractionState(from appState: SpinLabAppState) {
        let restored = appState.interactionValue(\.inboxView)
        isImportSourceExpanded = restored.isImportSourceExpanded
        isPendingQueueExpanded = restored.isPendingQueueExpanded
        isRoutingReviewExpanded = restored.isRoutingReviewExpanded
        isApplyExpanded = restored.isApplyExpanded
        fileFilter = restored.fileFilter.flatMap { FileFilter(rawValue: $0) } ?? .all
    }

    func persistInteractionState(to appState: SpinLabAppState) {
        appState.updateInteractionValue(
            \.inboxView,
            to: InboxInteractionState(
                isImportSourceExpanded: isImportSourceExpanded,
                isPendingQueueExpanded: isPendingQueueExpanded,
                isRoutingReviewExpanded: isRoutingReviewExpanded,
                isApplyExpanded: isApplyExpanded,
                fileFilter: fileFilter.rawValue
            )
        )
    }

    func projection(from appState: SpinLabAppState) -> InboxOperationProjection {
        _ = appState.inbox.routingSnapshotRevision  // @Observable invalidation trigger — do not remove
        let routePresentationByID = appState.pendingRoutePresentationByID()

        let libraryMatchedCount = appState.inbox.pendingImports.reduce(into: 0) { partial, pending in
            if routePresentationByID[pending.id]?.isLibraryMatched == true { partial += 1 }
        }
        let reviewRequiredCount = max(0, appState.inbox.pendingImports.count - libraryMatchedCount)

        let filtered: [SpinLabDomain.PendingImport]
        switch fileFilter {
        case .all:
            filtered = appState.inbox.pendingImports
        case .libraryMatched:
            filtered = appState.inbox.pendingImports.filter { routePresentationByID[$0.id]?.isLibraryMatched == true }
        case .reviewRequired:
            filtered = appState.inbox.pendingImports.filter { routePresentationByID[$0.id]?.isLibraryMatched != true }
        }

        return InboxOperationProjection(
            libraryMatchedCount: libraryMatchedCount,
            reviewRequiredCount: reviewRequiredCount,
            filteredPendingImports: filtered,
            routePresentationByID: routePresentationByID
        )
    }
}
