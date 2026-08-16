import AppKit
import Observation
import SwiftUI

/// Inbox's Primary-pane content. Takes the shared `InboxViewModel` (owned by
/// `RootSplitView`, the stable ancestor for the app-wide workspace) directly
/// rather than through a host struct — the `@Observable` view model is
/// already a reference type, so passing it by value is enough to share one
/// live instance across Primary and Detail without an intermediate box.
struct InboxPrimaryView: View {
    @Environment(SpinLabAppState.self) private var appState
    var viewModel: InboxViewModel

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        let applyProgress = appState.applyProgressState
        let importProgress = appState.inbox.importProgressState
        let isBusy = applyProgress.isRunning || importProgress.isRunning

        ZStack {
            InboxOperationPanel(
                inboxViewModel: viewModel,
                isPendingQueueExpanded: $bindableViewModel.isPendingQueueExpanded,
                applySelected: { viewModel.applySelected() },
                applyAll: { viewModel.applyAll() }
            )

            if applyProgress.isRunning {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                ApplyProgressOverlay(progress: applyProgress)
                    .frame(maxWidth: 460)
            } else if importProgress.isRunning {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                ImportProgressOverlay(progress: importProgress)
                    .frame(maxWidth: 460)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(!isBusy)
        .dropDestination(for: URL.self) { items, _ in
            appState.importFiles(from: items)
            return !items.isEmpty
        } isTargeted: { _ in }
        .onAppear {
            viewModel.applySelected = { appState.applySelectedPendingImport() }
            viewModel.applyAll = { appState.applyAllPendingImports() }
            viewModel.restoreInteractionState(from: appState)
            // Not persisted here: restoreInteractionState() just loaded this exact state
            // from disk, so writing it back immediately would be a no-op save.
        }
        .onChange(of: viewModel.isPendingQueueExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.fileFilter) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onDisappear {
            viewModel.persistInteractionState(to: appState)
        }
    }
}
