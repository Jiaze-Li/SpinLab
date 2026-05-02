import AppKit
import Observation
import SwiftUI

struct InboxView: View {
    @Environment(SpinLabAppState.self) private var appState
    @State private var viewModel = InboxViewModel()

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        let applyProgress = appState.applyProgressState
        let importProgress = appState.inbox.importProgressState
        let isBusy = applyProgress.isRunning || importProgress.isRunning

        ZStack {
            AppColumnShell(columnKey: "inbox", defaults: .inbox) {
                InboxOperationPanel(
                    inboxViewModel: viewModel,
                    isImportSourceExpanded: $bindableViewModel.isImportSourceExpanded,
                    isPendingQueueExpanded: $bindableViewModel.isPendingQueueExpanded,
                    isRoutingReviewExpanded: $bindableViewModel.isRoutingReviewExpanded,
                    isApplyExpanded: $bindableViewModel.isApplyExpanded,
                    applySelected: { viewModel.applySelected() },
                    applyAll: { viewModel.applyAll() }
                )
            } right: {
                InboxInspectorReservedPanel()
            }

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
            viewModel.persistInteractionState(to: appState)
        }
        .onChange(of: viewModel.isImportSourceExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.isPendingQueueExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.isRoutingReviewExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.isApplyExpanded) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onChange(of: viewModel.fileFilter) { _, _ in viewModel.persistInteractionState(to: appState) }
        .onDisappear {
            viewModel.persistInteractionState(to: appState)
        }
    }
}
