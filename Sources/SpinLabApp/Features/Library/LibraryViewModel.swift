import Foundation

final class LibraryViewModel: ObservableObject {
    private var actions = LibraryViewActions()

    func bindActions(from appState: SpinLabAppState) {
        actions = LibraryViewActions(
            saveAndContinuePendingSelectionChange: { appState.saveAndContinuePendingLibrarySelectionChange() },
            discardAndContinuePendingSelectionChange: { appState.discardAndContinuePendingLibrarySelectionChange() },
            cancelPendingSelectionChange: { appState.cancelPendingLibrarySelectionChange() },
            verifyLibraryRoot: { appState.verifyLibraryRoot() },
            syncLibraryFromFiles: { appState.syncLibraryFromFiles() },
            updateAllowedBatchPrefixes: { appState.updateAllowedBatchPrefixes(from: $0) },
            syncLibraryBackup: { appState.syncLibraryBackup() },
            syncLibraryFromRegistry: { appState.syncLibraryFromRegistry() },
            applyPreparedLibrarySyncReview: { appState.applyPreparedLibrarySyncReview() },
            applySelectedRegistryDiff: { appState.applySelectedRegistryDiff(batchId: $0) },
            selectBrowserSample: { appState.selectBrowserSample() },
            selectExistingDrawer: { prefix, batchId, sampleId in
                appState.selectExistingDrawer(prefix: prefix, batchId: batchId, sampleId: sampleId)
                appState.selectedArea = .library
            },
            loadLibraryGlobalManualLogs: { appState.loadLibraryGlobalManualLogs() },
            loadLibraryMetadataSyncLogs: { appState.loadLibraryMetadataSyncLogs() },
            cancelEditingSelectedLibrarySample: { appState.cancelEditingSelectedLibrarySample() },
            saveLibrarySampleEdits: { appState.saveLibrarySampleEdits() },
            beginEditingSelectedLibrarySample: { appState.beginEditingSelectedLibrarySample() },
            markLibraryGlobalManualLogStatus: { rowIndex, status in
                appState.markLibraryGlobalManualLogStatus(rowIndex: rowIndex, status: status)
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
}

private struct LibraryViewActions {
    var saveAndContinuePendingSelectionChange: () -> Void = {}
    var discardAndContinuePendingSelectionChange: () -> Void = {}
    var cancelPendingSelectionChange: () -> Void = {}
    var verifyLibraryRoot: () -> Void = {}
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
}
