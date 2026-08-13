import SwiftUI

/// Top-level Detail-pane routing for the app-wide workspace. Knows nothing
/// about Inbox/Library/Workbench internals beyond which content to show —
/// each area supplies its own Detail content from its shared state/model.
struct AppDetailContent: View {
    @Environment(SpinLabAppState.self) private var appState
    let inboxViewModel: InboxViewModel
    let libraryState: LibraryWorkspaceState

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if appState.selectedArea != .library {
                    Text(AppVersion.current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.trailing, 16)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.selectedArea {
        case .inbox:
            InboxDetailView()
                .safeAreaPadding(.top, 14)
        case .library:
            LibraryDetailView(state: libraryState)
                .safeAreaPadding(.top, 20)
        case .workbench:
            WorkbenchDetailView()
                .safeAreaPadding(.top, 20)
        }
    }
}
