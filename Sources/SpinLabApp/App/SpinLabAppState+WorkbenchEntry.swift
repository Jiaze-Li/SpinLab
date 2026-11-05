import Foundation

extension SpinLabAppState {

    func openPendingImportInWorkbench() {
        guard let area = coordinator.routeToWorkbenchForPendingSelection(
            hasPendingSelection: selectedPendingImport != nil
        ) else {
            return
        }
        requestAreaChange(to: area)
    }

    func openArchivedRecordInWorkbench(_ recordID: UUID) {
        guard let route = coordinator.routeToWorkbenchForArchivedRecord(
            recordID: recordID,
            archivedRecords: workbenchFeatureStore.archivedRecords
        ) else {
            return
        }
        requestAreaChange(to: route.selectedArea) { [self] in
            workbenchFeatureStore.selectArchivedRecord(route.archivedRecordID, analysisModule: analysisModule)
        }
    }

    func saveWorkbenchResult() {
        guard let updated = workbenchFeatureStore.saveWorkbenchResult(analysisModule: analysisModule) else {
            return
        }
        replaceArchivedRecords(updated)
    }
}
