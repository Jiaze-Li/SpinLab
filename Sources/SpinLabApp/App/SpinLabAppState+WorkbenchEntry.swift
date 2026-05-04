import Foundation

extension SpinLabAppState {

    func openPendingImportInWorkbench() {
        guard let area = coordinator.routeToWorkbenchForPendingSelection(
            hasPendingSelection: selectedPendingImport != nil
        ) else {
            return
        }
        selectedArea = area
    }

    func openArchivedRecordInWorkbench(_ recordID: UUID) {
        guard let route = coordinator.routeToWorkbenchForArchivedRecord(
            recordID: recordID,
            archivedRecords: workbenchFeatureStore.archivedRecords
        ),
        workbenchFeatureStore.selectArchivedRecord(route.archivedRecordID, analysisModule: analysisModule) else {
            return
        }
        selectedArea = route.selectedArea
    }

    func saveWorkbenchResult() {
        guard let updated = workbenchFeatureStore.saveWorkbenchResult(analysisModule: analysisModule) else {
            return
        }
        replaceArchivedRecords(updated)
    }
}
