import Foundation

final class InboxRepository {
    private let persistence: SpinLabPersistence
    private(set) var pendingImports: [SpinLabDomain.PendingImport]

    init(persistence: SpinLabPersistence) {
        self.persistence = persistence
        self.pendingImports = persistence.loadPendingImports()
    }

    @discardableResult
    func replacePendingImports(_ imports: [SpinLabDomain.PendingImport], persist: Bool = true) -> [SpinLabDomain.PendingImport] {
        pendingImports = imports
        if persist {
            persistence.savePendingImports(imports)
        }
        return pendingImports
    }
}

final class LibraryRepository {
    private let persistence: SpinLabPersistence
    private(set) var archivedRecords: [SpinLabDomain.ArchivedRecord]
    private(set) var projects: [SpinLabDomain.Project]

    init(persistence: SpinLabPersistence) {
        self.persistence = persistence
        self.archivedRecords = persistence.loadArchivedRecords()
        self.projects = persistence.loadProjects()
    }

    @discardableResult
    func replaceArchivedRecords(
        _ records: [SpinLabDomain.ArchivedRecord],
        persist: Bool = true
    ) -> [SpinLabDomain.ArchivedRecord] {
        archivedRecords = records
        if persist {
            persistence.saveArchivedRecords(records)
        }
        return archivedRecords
    }

    @discardableResult
    func replaceProjects(_ projects: [SpinLabDomain.Project], persist: Bool = true) -> [SpinLabDomain.Project] {
        self.projects = projects
        if persist {
            persistence.saveProjects(projects)
        }
        return self.projects
    }
}
