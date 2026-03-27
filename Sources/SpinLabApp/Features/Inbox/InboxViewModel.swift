import Foundation
import Observation

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

    func restoreInteractionState(from appState: SpinLabAppState) {
        let restored = appState.interactionValue(\.inboxView)
        isImportSourceExpanded = restored.isImportSourceExpanded
        isPendingQueueExpanded = restored.isPendingQueueExpanded
        isRoutingReviewExpanded = restored.isRoutingReviewExpanded
        isApplyExpanded = restored.isApplyExpanded
    }

    func persistInteractionState(to appState: SpinLabAppState) {
        appState.updateInteractionValue(
            \.inboxView,
            to: InboxInteractionState(
                isImportSourceExpanded: isImportSourceExpanded,
                isPendingQueueExpanded: isPendingQueueExpanded,
                isRoutingReviewExpanded: isRoutingReviewExpanded,
                isApplyExpanded: isApplyExpanded
            )
        )
    }

    func filteredPendingImports(
        from appState: SpinLabAppState,
        routePresentationByID: [UUID: PendingRoutePresentation]
    ) -> [SpinLabDomain.PendingImport] {
        switch fileFilter {
        case .all:
            return appState.inbox.pendingImports
        case .libraryMatched:
            return appState.inbox.pendingImports.filter { routePresentationByID[$0.id]?.isLibraryMatched == true }
        case .reviewRequired:
            return appState.inbox.pendingImports.filter { routePresentationByID[$0.id]?.isLibraryMatched != true }
        }
    }
}
