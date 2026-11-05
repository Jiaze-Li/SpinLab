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
            // Management / Sample Workspace / Search share the legacy page; branch
            // on gallery-vs-not so switching among them never remounts it.
            switch appState.library.currentRoute {
            case .management, .sampleWorkspace, .search:
                LibraryPrimaryView(state: libraryState)
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
