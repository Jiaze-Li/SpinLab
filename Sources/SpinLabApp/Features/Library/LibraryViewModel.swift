import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    @ObservationIgnored
    private weak var appState: SpinLabAppState?

    func bindActions(from appState: SpinLabAppState) {
        self.appState = appState
    }

    // MARK: - Action forwarding (cross-store coordination via AppState)

    func saveAndContinuePendingSelectionChange() {
        appState?.saveAndContinuePendingLibrarySelectionChange()
    }

    func discardAndContinuePendingSelectionChange() {
        appState?.discardAndContinuePendingLibrarySelectionChange()
    }

    func validateLibraryCacheOnAppear() {
        appState?.validateLibraryCacheOnAppear()
    }

    func syncLibraryBackup() {
        appState?.syncLibraryBackup()
    }

    func publishWebLibrary() {
        appState?.publishWebLibrary()
    }

    func syncLibraryFromRegistry() {
        appState?.syncLibraryFromRegistry()
    }

    func applyPreparedLibrarySyncReview() {
        appState?.applyPreparedLibrarySyncReview()
    }

    func applySelectedRegistryDiff(batchId: String?) {
        appState?.applySelectedRegistryDiff(batchId: batchId)
    }

    func selectBrowserSample() {
        appState?.selectBrowserSample()
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) {
        appState?.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
        appState?.selectedArea = .library
    }

    func updateLibraryRoot(to url: URL) {
        appState?.updateLibraryRoot(to: url)
    }

    func loadSampleRegistry(from url: URL) {
        appState?.loadSampleRegistry(from: url)
    }

    func reloadSampleRegistry() {
        appState?.reloadSampleRegistry()
    }

    func persistInteractionState(_ state: LibraryInteractionState) {
        appState?.updateInteractionValue(\.libraryView, to: state, source: "libraryInteractionState")
    }

    func restoredInteractionState() -> LibraryInteractionState {
        appState?.interactionValue(\.libraryView) ?? LibraryInteractionState()
    }
}
