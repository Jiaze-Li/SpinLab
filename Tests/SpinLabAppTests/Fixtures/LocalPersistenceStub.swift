import Foundation
@testable import SpinLabApp

final class LocalPersistenceStub: SpinLabPersistence {
    private var pendingImports: [SpinLabDomain.PendingImport]
    private var archivedRecords: [SpinLabDomain.ArchivedRecord]
    private var projects: [SpinLabDomain.Project]
    private var interactionSnapshot: SpinLabInteractionSnapshot

    init(
        pendingImports: [SpinLabDomain.PendingImport] = SampleData.pendingImports,
        archivedRecords: [SpinLabDomain.ArchivedRecord] = SampleData.archivedRecords,
        projects: [SpinLabDomain.Project] = SampleData.projects,
        interactionSnapshot: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()
    ) {
        self.pendingImports = pendingImports
        self.archivedRecords = archivedRecords
        self.projects = projects
        self.interactionSnapshot = interactionSnapshot
    }

    func loadPendingImports() -> [SpinLabDomain.PendingImport] {
        pendingImports
    }

    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) {
        pendingImports = imports
    }

    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] {
        archivedRecords
    }

    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) {
        archivedRecords = records
    }

    func loadProjects() -> [SpinLabDomain.Project] {
        projects
    }

    func saveProjects(_ projects: [SpinLabDomain.Project]) {
        self.projects = projects
    }

    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot {
        interactionSnapshot
    }

    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) {
        interactionSnapshot = snapshot
    }
}
