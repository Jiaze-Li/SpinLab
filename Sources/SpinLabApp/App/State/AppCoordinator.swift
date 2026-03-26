import Foundation

struct WorkbenchRouteResolution {
    var archivedRecordID: UUID
    var selectedArea: AppArea
}

struct PendingConfirmationRouteResolution {
    var archivedRecordID: UUID
    var nextPendingID: UUID?
    var selectedArea: AppArea
}

struct AppCoordinator {
    func routeToWorkbenchForPendingSelection(hasPendingSelection: Bool) -> AppArea? {
        guard hasPendingSelection else {
            return nil
        }
        return .workbench
    }

    func routeToWorkbenchForArchivedRecord(
        recordID: UUID,
        archivedRecords: [SpinLabDomain.ArchivedRecord]
    ) -> WorkbenchRouteResolution? {
        guard archivedRecords.contains(where: { $0.id == recordID }) else {
            return nil
        }
        return WorkbenchRouteResolution(
            archivedRecordID: recordID,
            selectedArea: .workbench
        )
    }

    func routeAfterPendingConfirmation(
        archivedRecordID: UUID,
        nextPendingID: UUID?
    ) -> PendingConfirmationRouteResolution {
        PendingConfirmationRouteResolution(
            archivedRecordID: archivedRecordID,
            nextPendingID: nextPendingID,
            selectedArea: .library
        )
    }
}
