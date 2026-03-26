import Foundation

final class InboxRepository {
    private let persistence: SpinLabPersistence
    private(set) var pendingImports: [SpinLabDomain.PendingImport]
    let pendingImportsStream: AsyncStream<[SpinLabDomain.PendingImport]>
    private let pendingImportsContinuation: AsyncStream<[SpinLabDomain.PendingImport]>.Continuation

    init(persistence: SpinLabPersistence) {
        let stream = AsyncStream<[SpinLabDomain.PendingImport]>.makeStream()
        self.pendingImportsStream = stream.stream
        self.pendingImportsContinuation = stream.continuation
        self.persistence = persistence
        self.pendingImports = persistence.loadPendingImports()
        pendingImportsContinuation.yield(self.pendingImports)
    }

    deinit {
        pendingImportsContinuation.finish()
    }

    @discardableResult
    func replacePendingImports(_ imports: [SpinLabDomain.PendingImport], persist: Bool = true) -> [SpinLabDomain.PendingImport] {
        pendingImports = imports
        if persist {
            persistence.savePendingImports(imports)
        }
        pendingImportsContinuation.yield(pendingImports)
        return pendingImports
    }

    @discardableResult
    func removePendingImport(id: UUID, persist: Bool = true) -> [SpinLabDomain.PendingImport] {
        var next = pendingImports
        next.removeAll { $0.id == id }
        return replacePendingImports(next, persist: persist)
    }
}

final class LibraryRepository {
    private let persistence: SpinLabPersistence
    private(set) var archivedRecords: [SpinLabDomain.ArchivedRecord]
    private(set) var projects: [SpinLabDomain.Project]
    let archivedRecordsStream: AsyncStream<[SpinLabDomain.ArchivedRecord]>
    let projectsStream: AsyncStream<[SpinLabDomain.Project]>
    private let archivedRecordsContinuation: AsyncStream<[SpinLabDomain.ArchivedRecord]>.Continuation
    private let projectsContinuation: AsyncStream<[SpinLabDomain.Project]>.Continuation

    init(persistence: SpinLabPersistence) {
        let archivedStream = AsyncStream<[SpinLabDomain.ArchivedRecord]>.makeStream()
        let projectsStream = AsyncStream<[SpinLabDomain.Project]>.makeStream()
        self.archivedRecordsStream = archivedStream.stream
        self.projectsStream = projectsStream.stream
        self.archivedRecordsContinuation = archivedStream.continuation
        self.projectsContinuation = projectsStream.continuation
        self.persistence = persistence
        self.archivedRecords = persistence.loadArchivedRecords()
        self.projects = persistence.loadProjects()
        archivedRecordsContinuation.yield(self.archivedRecords)
        projectsContinuation.yield(self.projects)
    }

    deinit {
        archivedRecordsContinuation.finish()
        projectsContinuation.finish()
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
        archivedRecordsContinuation.yield(archivedRecords)
        return archivedRecords
    }

    @discardableResult
    func replaceProjects(_ projects: [SpinLabDomain.Project], persist: Bool = true) -> [SpinLabDomain.Project] {
        self.projects = projects
        if persist {
            persistence.saveProjects(projects)
        }
        projectsContinuation.yield(self.projects)
        return self.projects
    }

    @discardableResult
    func prependArchivedRecord(_ record: SpinLabDomain.ArchivedRecord, persist: Bool = true) -> [SpinLabDomain.ArchivedRecord] {
        var next = archivedRecords
        next.insert(record, at: 0)
        return replaceArchivedRecords(next, persist: persist)
    }
}
