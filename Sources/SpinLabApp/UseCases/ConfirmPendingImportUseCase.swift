import Foundation

struct ConfirmPendingImportUseCase {
    struct Input {
        var pending: SpinLabDomain.PendingImport
        var draft: PendingImportConfirmationDraft
    }

    struct Output {
        var archivedRecords: [SpinLabDomain.ArchivedRecord]
        var pendingImports: [SpinLabDomain.PendingImport]
        var archivedRecord: SpinLabDomain.ArchivedRecord
    }

    func execute(
        input: Input,
        inboxRepository: InboxRepository,
        libraryRepository: LibraryRepository,
        makeArchivedRecord: (SpinLabDomain.PendingImport, PendingImportConfirmationDraft) -> SpinLabDomain.ArchivedRecord
    ) -> Result<Output, AppError> {
        guard inboxRepository.pendingImports.contains(where: { $0.id == input.pending.id }) else {
            return .failure(.notFound("Pending import was not found. Refresh the queue and retry."))
        }

        let record = makeArchivedRecord(input.pending, input.draft)
        var nextArchived = libraryRepository.archivedRecords
        nextArchived.insert(record, at: 0)
        let archivedRecords = libraryRepository.replaceArchivedRecords(nextArchived)

        var nextPending = inboxRepository.pendingImports
        nextPending.removeAll { $0.id == input.pending.id }
        let pendingImports = inboxRepository.replacePendingImports(nextPending)

        return .success(Output(
            archivedRecords: archivedRecords,
            pendingImports: pendingImports,
            archivedRecord: record
        ))
    }
}
