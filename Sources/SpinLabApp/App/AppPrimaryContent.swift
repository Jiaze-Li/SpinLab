import SwiftUI

/// Top-level Primary-pane routing for the app-wide workspace. Knows nothing
/// about Inbox/Library/Workbench internals beyond which content to show —
/// each area supplies its own Primary content from its shared state/model.
struct AppPrimaryContent: View {
    @Environment(SpinLabAppState.self) private var appState
    let inboxViewModel: InboxViewModel
    let libraryState: LibraryWorkspaceState

    var body: some View {
        switch appState.selectedArea {
        case .inbox:
            InboxPrimaryView(viewModel: inboxViewModel)
                .safeAreaPadding(.top, 14)
        case .library:
            // Management, Sample Workspace and Search each have their own page.
            switch appState.library.currentRoute {
            case .management:
                LibraryPrimaryView(state: libraryState, mode: .management)
                    .safeAreaPadding(.top, 20)
            case .sampleWorkspace:
                LibrarySampleWorkspacePrimaryView(state: libraryState)
                    .safeAreaPadding(.top, 20)
            case .search:
                LibrarySearchPrimaryView(state: libraryState)
                    .safeAreaPadding(.top, 20)
            case let .workflowGallery(workflowID):
                WorkflowGalleryPrimaryView(workflowID: workflowID, galleryState: libraryState.galleryState)
                    .safeAreaPadding(.top, 20)
            }
        case .workbench:
            WorkbenchPrimaryView()
                .safeAreaPadding(.top, 20)
        }
    }
}
