import Foundation
import Observation

/// Library's cross-pane shared state — the state that genuinely needs one
/// identity visible from both `LibraryPrimaryView` and `LibraryDetailView`
/// (rendered in separate `NSHostingView`s under `AppWorkspaceShell`).
///
/// Only state with a real cross-pane reason lives here:
/// - dialogs/sheets triggered from Detail but presented from Primary
/// - disclosure state rendered only in Detail but persisted by Primary's
///   interaction-state effect
/// - preview-derived data computed by Primary's effects and read by Detail
///
/// Everything else (search fields, section-collapse flags that are both set
/// and read within one pane, transient task handles) stays local `@State` on
/// the pane that owns it — see `LibraryPrimaryView`/`LibraryDetailView`.
@MainActor
@Observable
final class LibraryWorkspaceState {
    let viewModel = LibraryViewModel()

    // MARK: - Dialogs/sheets set in Detail, presented from Primary

    var isShowingSampleChangeLog = false
    var isShowingGlobalManualLog = false
    var isShowingMetadataSyncLog = false
    var conditionDetailMeasurement: AppliedMeasurement?

    // MARK: - Detail-rendered, Primary-persisted interaction state

    var isMetadataSectionExpanded = true
    var expandedWorkflows: Set<String> = []
    var expandedSets: Set<String> = []
    var expandedUncategorized: Set<String> = []

    // MARK: - Computed by Primary's effects, read by both panes

    var previewDerivedData = PreviewDerivedData()
}

struct PreviewDerivedData {
    var previewPrefixes: [String] = []
    var previewGroupsForSelectedPrefix: [LibraryPreviewBatchGroup] = []
}

extension LibraryWorkspaceState {
    func selectedBatchSamples(_ appState: SpinLabAppState) -> [LibrarySample] {
        guard let batchId = appState.library.librarySelectedBatchId else { return [] }
        return previewDerivedData.previewGroupsForSelectedPrefix
            .first(where: { $0.batchId == batchId })?.samples ?? []
    }

    func selectedExistingSample(_ appState: SpinLabAppState) -> LibrarySample? {
        guard let prefix = appState.library.librarySelectedPrefix,
              let batchId = appState.library.librarySelectedBatchId,
              let sampleId = appState.library.librarySelectedSampleId else {
            return nil
        }
        let groups = appState.library.libraryExistingGroups[prefix] ?? []
        let samples = groups.first(where: { $0.batchId == batchId })?.samples ?? []
        return samples.first(where: { $0.id == sampleId })
    }

    func selectedExistingBatchSamples(_ appState: SpinLabAppState) -> [LibrarySample] {
        guard let prefix = appState.library.librarySelectedPrefix,
              let batchId = appState.library.librarySelectedBatchId else {
            return []
        }
        let groups = appState.library.libraryExistingGroups[prefix] ?? []
        return groups.first(where: { $0.batchId == batchId })?.samples ?? []
    }

    func selectionEntry(_ appState: SpinLabAppState) -> SelectionEntry {
        SelectionEntry(
            source: appState.library.libraryActiveSelectionSource,
            browserSampleId: appState.library.librarySelectedSampleId,
            drawerPrefix: appState.library.librarySelectedPrefix,
            drawerBatchId: appState.library.librarySelectedBatchId,
            drawerSampleId: appState.library.librarySelectedSampleId
        )
    }

    func resolveSelectedSample(from entry: SelectionEntry, appState: SpinLabAppState) -> LibrarySample? {
        switch entry.source {
        case .browser:
            guard let sampleId = entry.browserSampleId else {
                return nil
            }
            return selectedBatchSamples(appState).first(where: { $0.id == sampleId })
        case .drawer:
            return selectedExistingSample(appState)
        }
    }

    func selectedSample(_ appState: SpinLabAppState) -> LibrarySample? {
        resolveSelectedSample(from: selectionEntry(appState), appState: appState)
    }
}
