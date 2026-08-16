import SwiftUI

/// Inbox's Detail-pane content. Shows the real inspector (`InboxInspectorPanel`) for the
/// currently selected pending import — the same `appState.selectedPendingImport` identity
/// `InboxOperationPanel` (Primary) already reads and drives via its List selection — or a
/// clean empty state when nothing is selected. Mirrors `LibraryDetailView`/`WorkbenchDetailView`:
/// Detail owns no state of its own, it only renders off the shared Inbox state owner.
@MainActor
struct InboxDetailView: View {
    @Environment(SpinLabAppState.self) private var appState

    var body: some View {
        ScrollView(.vertical) {
            Group {
                if let pending = appState.selectedPendingImport {
                    InboxInspectorPanel(pending: pending)
                } else {
                    InboxInspectorEmptyState()
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Shown in place of the inspector when no pending import is selected — e.g. the queue is
/// empty, or the user cleared the selection. Lives inside the real inspector's architecture
/// (this file) rather than as a separate always-present reserved panel type.
private struct InboxInspectorEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(AppFontScale.sectionTitle)
            Text("Select a pending file to inspect its routing and warnings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
