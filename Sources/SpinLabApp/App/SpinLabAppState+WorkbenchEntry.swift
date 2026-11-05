import Foundation

extension SpinLabAppState {

    func openPendingImportInWorkbench() {
        guard coordinator.routeToWorkbenchForPendingSelection(
            hasPendingSelection: selectedPendingImport != nil
        ) != nil else {
            return
        }
        // Area-only target: keeps the Workbench's own route, same as before.
        navigate(to: .workbenchArea)
    }

    func openArchivedRecordInWorkbench(_ recordID: UUID) {
        // The record ID travels inside the typed target, so a deferral behind
        // the unsaved-edit prompt still opens exactly this record afterwards.
        navigate(to: .workbenchArchivedRecord(id: recordID))
    }

    func saveWorkbenchResult() {
        guard let updated = workbenchFeatureStore.saveWorkbenchResult(analysisModule: analysisModule) else {
            return
        }
        replaceArchivedRecords(updated)
    }
}
