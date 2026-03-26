import Foundation

struct ConfirmPendingImportUseCase {
    struct Input {
        var pending: SpinLabDomain.PendingImport
        var draft: PendingImportConfirmationDraft
        var pendingImports: [SpinLabDomain.PendingImport]
        var archivedRecords: [SpinLabDomain.ArchivedRecord]
    }

    struct Output {
        var archivedRecords: [SpinLabDomain.ArchivedRecord]
        var pendingImports: [SpinLabDomain.PendingImport]
        var archivedRecord: SpinLabDomain.ArchivedRecord
    }

    func execute(
        input: Input,
        makeArchivedRecord: (SpinLabDomain.PendingImport, PendingImportConfirmationDraft) -> SpinLabDomain.ArchivedRecord
    ) -> Output {
        let record = makeArchivedRecord(input.pending, input.draft)
        var nextArchived = input.archivedRecords
        nextArchived.insert(record, at: 0)

        var nextPending = input.pendingImports
        nextPending.removeAll { $0.id == input.pending.id }

        return Output(
            archivedRecords: nextArchived,
            pendingImports: nextPending,
            archivedRecord: record
        )
    }
}
