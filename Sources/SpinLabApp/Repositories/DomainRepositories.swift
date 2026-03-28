import Foundation

final class InboxRepository {
    private let persistence: SpinLabPersistence
    private(set) var pendingImports: [SpinLabDomain.PendingImport]
    let pendingImportsStream: AsyncStream<[SpinLabDomain.PendingImport]>
    private let pendingImportsContinuation: AsyncStream<[SpinLabDomain.PendingImport]>.Continuation
    private var transactionDepth = 0
    private var pendingPersist = false
    private var pendingEmit = false

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
            if transactionDepth > 0 {
                pendingPersist = true
            } else {
                persistence.savePendingImports(imports)
            }
        }
        scheduleEmission()
        return pendingImports
    }

    @discardableResult
    func removePendingImport(id: UUID, persist: Bool = true) -> [SpinLabDomain.PendingImport] {
        var next = pendingImports
        next.removeAll { $0.id == id }
        return replacePendingImports(next, persist: persist)
    }

    @discardableResult
    func performTransaction(
        persist: Bool = true,
        _ operation: (inout [SpinLabDomain.PendingImport]) -> Void
    ) -> [SpinLabDomain.PendingImport] {
        transactionDepth += 1
        defer {
            transactionDepth -= 1
            flushTransactionIfNeeded()
        }

        var working = pendingImports
        operation(&working)
        pendingImports = working
        if persist {
            pendingPersist = true
        }
        pendingEmit = true
        return pendingImports
    }

    private func scheduleEmission() {
        if transactionDepth > 0 {
            pendingEmit = true
            return
        }
        pendingImportsContinuation.yield(pendingImports)
    }

    private func flushTransactionIfNeeded() {
        guard transactionDepth == 0 else {
            return
        }
        if pendingPersist {
            persistence.savePendingImports(pendingImports)
            pendingPersist = false
        }
        if pendingEmit {
            pendingImportsContinuation.yield(pendingImports)
            pendingEmit = false
        }
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
    private var transactionDepth = 0
    private var pendingPersistArchivedRecords = false
    private var pendingPersistProjects = false
    private var pendingEmitArchivedRecords = false
    private var pendingEmitProjects = false

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
            if transactionDepth > 0 {
                pendingPersistArchivedRecords = true
            } else {
                persistence.saveArchivedRecords(records)
            }
        }
        scheduleArchivedRecordsEmission()
        return archivedRecords
    }

    @discardableResult
    func replaceProjects(_ projects: [SpinLabDomain.Project], persist: Bool = true) -> [SpinLabDomain.Project] {
        self.projects = projects
        if persist {
            if transactionDepth > 0 {
                pendingPersistProjects = true
            } else {
                persistence.saveProjects(projects)
            }
        }
        scheduleProjectsEmission()
        return self.projects
    }

    @discardableResult
    func prependArchivedRecord(_ record: SpinLabDomain.ArchivedRecord, persist: Bool = true) -> [SpinLabDomain.ArchivedRecord] {
        var next = archivedRecords
        next.insert(record, at: 0)
        return replaceArchivedRecords(next, persist: persist)
    }

    @discardableResult
    func performTransaction(
        persist: Bool = true,
        _ operation: (_ archivedRecords: inout [SpinLabDomain.ArchivedRecord], _ projects: inout [SpinLabDomain.Project]) -> Void
    ) -> (archivedRecords: [SpinLabDomain.ArchivedRecord], projects: [SpinLabDomain.Project]) {
        transactionDepth += 1
        defer {
            transactionDepth -= 1
            flushTransactionIfNeeded()
        }

        var nextArchivedRecords = archivedRecords
        var nextProjects = projects
        operation(&nextArchivedRecords, &nextProjects)
        archivedRecords = nextArchivedRecords
        projects = nextProjects
        if persist {
            pendingPersistArchivedRecords = true
            pendingPersistProjects = true
        }
        pendingEmitArchivedRecords = true
        pendingEmitProjects = true
        return (archivedRecords, projects)
    }

    private func scheduleArchivedRecordsEmission() {
        if transactionDepth > 0 {
            pendingEmitArchivedRecords = true
            return
        }
        archivedRecordsContinuation.yield(archivedRecords)
    }

    private func scheduleProjectsEmission() {
        if transactionDepth > 0 {
            pendingEmitProjects = true
            return
        }
        projectsContinuation.yield(projects)
    }

    private func flushTransactionIfNeeded() {
        guard transactionDepth == 0 else {
            return
        }
        if pendingPersistArchivedRecords {
            persistence.saveArchivedRecords(archivedRecords)
            pendingPersistArchivedRecords = false
        }
        if pendingPersistProjects {
            persistence.saveProjects(projects)
            pendingPersistProjects = false
        }
        if pendingEmitArchivedRecords {
            archivedRecordsContinuation.yield(archivedRecords)
            pendingEmitArchivedRecords = false
        }
        if pendingEmitProjects {
            projectsContinuation.yield(projects)
            pendingEmitProjects = false
        }
    }
}
