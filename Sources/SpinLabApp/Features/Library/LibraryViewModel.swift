import Foundation
import Observation

@Observable
final class LibraryViewModel {
    private(set) var viewState = LibraryViewState()
    private var actions = LibraryViewActions()

    func bindActions(from appState: SpinLabAppState) {
        actions = LibraryViewActions(
            saveAndContinuePendingSelectionChange: {
                appState.saveAndContinuePendingLibrarySelectionChange()
                self.syncState(from: appState)
            },
            discardAndContinuePendingSelectionChange: {
                appState.discardAndContinuePendingLibrarySelectionChange()
                self.syncState(from: appState)
            },
            cancelPendingSelectionChange: {
                appState.cancelPendingLibrarySelectionChange()
                self.syncState(from: appState)
            },
            verifyLibraryRoot: {
                appState.verifyLibraryRoot()
                self.syncState(from: appState)
            },
            validateLibraryCacheOnAppear: {
                appState.validateLibraryCacheOnAppear()
                self.syncState(from: appState)
            },
            syncLibraryFromFiles: {
                appState.syncLibraryFromFiles()
                self.syncState(from: appState)
            },
            updateAllowedBatchPrefixes: {
                appState.updateAllowedBatchPrefixes(from: $0)
                self.syncState(from: appState)
            },
            syncLibraryBackup: {
                appState.syncLibraryBackup()
                self.syncState(from: appState)
            },
            syncLibraryFromRegistry: {
                appState.syncLibraryFromRegistry {
                    self.syncState(from: appState)
                }
                self.syncState(from: appState)
            },
            applyPreparedLibrarySyncReview: {
                appState.applyPreparedLibrarySyncReview()
                self.syncState(from: appState)
            },
            applySelectedRegistryDiff: {
                appState.applySelectedRegistryDiff(batchId: $0)
                self.syncState(from: appState)
            },
            selectBrowserSample: {
                appState.selectBrowserSample()
                self.syncState(from: appState)
            },
            selectExistingDrawer: { prefix, batchId, sampleId in
                appState.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
                appState.selectedArea = .library
                self.syncState(from: appState)
            },
            loadLibraryGlobalManualLogs: {
                appState.loadLibraryGlobalManualLogs()
                self.syncState(from: appState)
            },
            loadLibraryMetadataSyncLogs: {
                appState.loadLibraryMetadataSyncLogs()
                self.syncState(from: appState)
            },
            cancelEditingSelectedLibrarySample: {
                appState.cancelEditingSelectedLibrarySample()
                self.syncState(from: appState)
            },
            saveLibrarySampleEdits: {
                appState.saveLibrarySampleEdits()
                self.syncState(from: appState)
            },
            beginEditingSelectedLibrarySample: {
                appState.beginEditingSelectedLibrarySample()
                self.syncState(from: appState)
            },
            markLibraryGlobalManualLogStatus: { rowIndex, status in
                appState.markLibraryGlobalManualLogStatus(rowIndex: rowIndex, status: status)
                self.syncState(from: appState)
            },
            updateLibraryRoot: { url in
                appState.updateLibraryRoot(to: url)
                self.syncState(from: appState)
            },
            updateLibraryBackupPath: { url in
                appState.updateLibraryBackupPath(to: url)
                self.syncState(from: appState)
            },
            persistInteractionState: { state in
                appState.updateInteractionValue(\.libraryView, to: state)
            }
        )
        syncState(from: appState)
    }

    func syncState(from appState: SpinLabAppState) {
        viewState = LibraryViewState(
            registrySourcePath: appState.librarySettings.registrySourcePath ?? appState.registrySourceFilePath,
            libraryRootPath: appState.librarySettings.rootPath,
            backupPath: appState.librarySettings.backupPath,
            allowedBatchPrefixesText: appState.librarySettings.allowedBatchPrefixes.joined(separator: ", "),
            rootVerificationMessage: appState.libraryRootVerificationMessage,
            rootVerificationPath: appState.libraryRootVerificationPath,
            backupError: appState.libraryBackupError,
            backupMessage: appState.libraryBackupMessage,
            refreshReview: appState.libraryRefreshReview,
            previewMessage: appState.libraryPreviewMessage,
            previewWarnings: appState.libraryPreviewWarnings,
            drawerMessage: appState.libraryDrawerMessage,
            drawerError: appState.libraryDrawerError,
            syncStatusMessage: appState.librarySyncStatusMessage,
            pendingSelectionChangePrompt: appState.libraryPendingSelectionChangePrompt,
            allowedBatchPrefixes: appState.librarySettings.allowedBatchPrefixes.map { $0.uppercased() },
            previewGroupsByPrefix: appState.libraryPreviewGroups,
            batchSyncStatusByID: appState.libraryBatchSyncStatusByID,
            existingGroupsByPrefix: appState.libraryExistingGroups,
            restoredInteractionState: appState.interactionValue(\.libraryView)
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
    var restoredInteractionState = LibraryInteractionState()
}
