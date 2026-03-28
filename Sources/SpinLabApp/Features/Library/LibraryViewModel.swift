import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    @ObservationIgnored
    private weak var appState: SpinLabAppState?
    private var actions = LibraryViewActions()

    var viewState: LibraryViewState {
        guard let appState else {
            return LibraryViewState()
        }
        return LibraryViewState(
            registrySourcePath: appState.library.librarySettings.registrySourcePath,
            libraryRootPath: appState.library.librarySettings.rootPath,
            backupPath: appState.library.librarySettings.backupPath,
            allowedBatchPrefixesText: appState.library.librarySettings.allowedBatchPrefixes.joined(separator: ", "),
            rootVerificationMessage: appState.library.libraryRootVerificationMessage,
            rootVerificationPath: appState.library.libraryRootVerificationPath,
            backupError: appState.library.libraryBackupError,
            backupMessage: appState.library.libraryBackupMessage,
            refreshReview: appState.library.libraryRefreshReview,
            previewMessage: appState.library.libraryPreviewMessage,
            previewWarnings: appState.library.libraryPreviewWarnings,
            drawerMessage: appState.library.libraryDrawerMessage,
            drawerError: appState.library.libraryDrawerError,
            syncStatusMessage: appState.library.librarySyncStatusMessage,
            pendingSelectionChangePrompt: appState.library.libraryPendingSelectionChangePrompt,
            allowedBatchPrefixes: appState.library.librarySettings.allowedBatchPrefixes.map { $0.uppercased() },
            previewGroupsByPrefix: appState.library.libraryPreviewGroups,
            batchSyncStatusByID: appState.library.libraryBatchSyncStatusByID,
            existingGroupsByPrefix: appState.library.libraryExistingGroups,
            selectedPrefix: appState.library.librarySelectedPrefix,
            selectedBatchId: appState.library.librarySelectedBatchId,
            selectedSampleId: appState.library.librarySelectedSampleId,
            activeSelectionSource: appState.library.libraryActiveSelectionSource,
            sampleEditDraft: appState.library.librarySampleEditDraft,
            sampleEditError: appState.library.librarySampleEditError,
            sampleEditMessage: appState.library.librarySampleEditMessage,
            sampleEditIsDirty: appState.library.librarySampleEditIsDirty,
            sampleEditIsSaving: appState.library.librarySampleEditIsSaving,
            canEditSelectedLibrarySample: appState.library.canEditSelectedLibrarySample,
            globalManualLogs: appState.library.libraryGlobalManualLogs,
            globalManualLogError: appState.library.libraryGlobalManualLogError,
            globalManualLogMessage: appState.library.libraryGlobalManualLogMessage,
            metadataSyncLogs: appState.library.libraryMetadataSyncLogs,
            metadataSyncLogError: appState.library.libraryMetadataSyncLogError,
            metadataSyncLogMessage: appState.library.libraryMetadataSyncLogMessage,
            sampleSyncChangesByID: appState.library.librarySampleSyncChangesByID,
            batchSyncChangesByID: appState.library.libraryBatchSyncChangesByID,
            restoredInteractionState: appState.interactionValue(\.libraryView)
        )
    }

    func bindActions(from appState: SpinLabAppState) {
        self.appState = appState

        actions = LibraryViewActions(
            saveAndContinuePendingSelectionChange: {
                appState.saveAndContinuePendingLibrarySelectionChange()
            },
            discardAndContinuePendingSelectionChange: {
                appState.discardAndContinuePendingLibrarySelectionChange()
            },
            cancelPendingSelectionChange: {
                appState.library.cancelPendingSelectionChange()
            },
            verifyLibraryRoot: {
                appState.library.verifyLibraryRoot()
            },
            validateLibraryCacheOnAppear: {
                appState.validateLibraryCacheOnAppear()
            },
            syncLibraryFromFiles: {
                appState.syncLibraryFromFiles()
            },
            updateAllowedBatchPrefixes: { value in
                appState.library.updateAllowedBatchPrefixes(from: value)
            },
            syncLibraryBackup: {
                appState.syncLibraryBackup()
            },
            syncLibraryFromRegistry: {
                appState.syncLibraryFromRegistry()
            },
            applyPreparedLibrarySyncReview: {
                appState.applyPreparedLibrarySyncReview()
            },
            applySelectedRegistryDiff: { batchId in
                appState.applySelectedRegistryDiff(batchId: batchId)
            },
            selectBrowserSample: {
                appState.selectBrowserSample()
            },
            selectExistingDrawer: { prefix, batchId, sampleId in
                appState.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
                appState.selectedArea = .library
            },
            loadLibraryGlobalManualLogs: {
                appState.loadLibraryGlobalManualLogs()
            },
            loadLibraryMetadataSyncLogs: {
                appState.loadLibraryMetadataSyncLogs()
            },
            cancelEditingSelectedLibrarySample: {
                appState.library.cancelEditingSelectedLibrarySample()
            },
            saveLibrarySampleEdits: {
                appState.saveLibrarySampleEdits()
            },
            beginEditingSelectedLibrarySample: {
                appState.library.beginEditingSelectedDrawerSampleIfNeeded()
            },
            markLibraryGlobalManualLogStatus: { rowIndex, status in
                appState.markLibraryGlobalManualLogStatus(rowIndex: rowIndex, status: status)
            },
            updateLibraryRoot: { url in
                appState.updateLibraryRoot(to: url)
            },
            updateLibraryBackupPath: { url in
                appState.library.updateLibraryBackupPath(to: url)
            },
            loadSampleRegistry: { url in
                appState.loadSampleRegistry(from: url)
            },
            reloadSampleRegistry: {
                appState.reloadSampleRegistry()
            },
            persistInteractionState: { state in
                appState.updateInteractionValue(\.libraryView, to: state)
            }
        )
    }

    func saveAndContinuePendingSelectionChange() {
        actions.saveAndContinuePendingSelectionChange()
    }

    func discardAndContinuePendingSelectionChange() {
        actions.discardAndContinuePendingSelectionChange()
    }

    func cancelPendingSelectionChange() {
        actions.cancelPendingSelectionChange()
    }

    func verifyLibraryRoot() {
        actions.verifyLibraryRoot()
    }

    func validateLibraryCacheOnAppear() {
        actions.validateLibraryCacheOnAppear()
    }

    func syncLibraryFromFiles() {
        actions.syncLibraryFromFiles()
    }

    func updateAllowedBatchPrefixes(from value: String) {
        actions.updateAllowedBatchPrefixes(value)
    }

    func syncLibraryBackup() {
        actions.syncLibraryBackup()
    }

    func syncLibraryFromRegistry() {
        actions.syncLibraryFromRegistry()
    }

    func applyPreparedLibrarySyncReview() {
        actions.applyPreparedLibrarySyncReview()
    }

    func applySelectedRegistryDiff(batchId: String?) {
        actions.applySelectedRegistryDiff(batchId)
    }

    func selectBrowserSample() {
        actions.selectBrowserSample()
    }

    func selectExistingDrawer(prefix: String, batchId: String, sampleId: String?) {
        actions.selectExistingDrawer(prefix, batchId, sampleId)
    }

    func loadLibraryGlobalManualLogs() {
        actions.loadLibraryGlobalManualLogs()
    }

    func loadLibraryMetadataSyncLogs() {
        actions.loadLibraryMetadataSyncLogs()
    }

    func cancelEditingSelectedLibrarySample() {
        actions.cancelEditingSelectedLibrarySample()
    }

    func saveLibrarySampleEdits() {
        actions.saveLibrarySampleEdits()
    }

    func beginEditingSelectedLibrarySample() {
        actions.beginEditingSelectedLibrarySample()
    }

    func markLibraryGlobalManualLogStatus(rowIndex: Int, status: LibraryManualLogStatus) {
        actions.markLibraryGlobalManualLogStatus(rowIndex, status)
    }

    func updateLibraryRoot(to url: URL) {
        actions.updateLibraryRoot(url)
    }

    func updateLibraryBackupPath(to url: URL) {
        actions.updateLibraryBackupPath(url)
    }

    func loadSampleRegistry(from url: URL) {
        actions.loadSampleRegistry(url)
    }

    func reloadSampleRegistry() {
        actions.reloadSampleRegistry()
    }

    func persistInteractionState(_ state: LibraryInteractionState) {
        actions.persistInteractionState(state)
    }
}

private struct LibraryViewActions {
    var saveAndContinuePendingSelectionChange: () -> Void = {}
    var discardAndContinuePendingSelectionChange: () -> Void = {}
    var cancelPendingSelectionChange: () -> Void = {}
    var verifyLibraryRoot: () -> Void = {}
    var validateLibraryCacheOnAppear: () -> Void = {}
    var syncLibraryFromFiles: () -> Void = {}
    var updateAllowedBatchPrefixes: (String) -> Void = { _ in }
    var syncLibraryBackup: () -> Void = {}
    var syncLibraryFromRegistry: () -> Void = {}
    var applyPreparedLibrarySyncReview: () -> Void = {}
    var applySelectedRegistryDiff: (String?) -> Void = { _ in }
    var selectBrowserSample: () -> Void = {}
    var selectExistingDrawer: (String, String, String?) -> Void = { _, _, _ in }
    var loadLibraryGlobalManualLogs: () -> Void = {}
    var loadLibraryMetadataSyncLogs: () -> Void = {}
    var cancelEditingSelectedLibrarySample: () -> Void = {}
    var saveLibrarySampleEdits: () -> Void = {}
    var beginEditingSelectedLibrarySample: () -> Void = {}
    var markLibraryGlobalManualLogStatus: (Int, LibraryManualLogStatus) -> Void = { _, _ in }
    var updateLibraryRoot: (URL) -> Void = { _ in }
    var updateLibraryBackupPath: (URL) -> Void = { _ in }
    var loadSampleRegistry: (URL) -> Void = { _ in }
    var reloadSampleRegistry: () -> Void = {}
    var persistInteractionState: (LibraryInteractionState) -> Void = { _ in }
}

struct LibraryViewState {
    var registrySourcePath: String?
    var libraryRootPath: String?
    var backupPath: String?
    var allowedBatchPrefixesText: String = ""
    var rootVerificationMessage: String?
    var rootVerificationPath: String?
    var backupError: String?
    var backupMessage: String?
    var refreshReview: LibraryRefreshReview?
    var previewMessage: String?
    var previewWarnings: [LibraryWarning] = []
    var drawerMessage: String?
    var drawerError: String?
    var syncStatusMessage: String?
    var pendingSelectionChangePrompt: String?
    var allowedBatchPrefixes: [String] = []
    var previewGroupsByPrefix: [String: [LibraryPreviewBatchGroup]] = [:]
    var batchSyncStatusByID: [String: LibrarySyncBatchStatus] = [:]
    var existingGroupsByPrefix: [String: [LibraryPreviewBatchGroup]] = [:]
    var selectedPrefix: String?
    var selectedBatchId: String?
    var selectedSampleId: String?
    var activeSelectionSource: LibrarySelectionSource = .browser
    var sampleEditDraft: LibrarySampleEditDraft?
    var sampleEditError: String?
    var sampleEditMessage: String?
    var sampleEditIsDirty: Bool = false
    var sampleEditIsSaving: Bool = false
    var canEditSelectedLibrarySample: Bool = false
    var globalManualLogs: [LibraryManualUpdateLogEntry] = []
    var globalManualLogError: String?
    var globalManualLogMessage: String?
    var metadataSyncLogs: [LibraryMetadataSyncLogEntry] = []
    var metadataSyncLogError: String?
    var metadataSyncLogMessage: String?
    var sampleSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    var batchSyncChangesByID: [String: [LibraryFieldChange]] = [:]
    var restoredInteractionState = LibraryInteractionState()
}
