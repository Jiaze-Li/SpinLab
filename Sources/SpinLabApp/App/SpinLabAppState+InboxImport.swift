import Foundation

extension SpinLabAppState {

    func importFiles(from urls: [URL]) {
        inboxFacade.importFiles(from: urls)
    }

    func clearPendingImports() {
        inboxFacade.clearPendingImports()
    }

    func clearSelectedPendingImport() {
        inboxFacade.clearSelectedPendingImport()
    }

    func recomputeAllPendingParsedHints() {
        inboxFacade.recomputeAllPendingParsedHints()
    }

    func dryRunConditionRuleRecompute() -> [ConditionChangeProposal] {
        inboxFacade.dryRunConditionRecompute()
    }

    func applyConditionRuleProposals(pendingIDs: Set<UUID>) {
        inboxFacade.applyConditionProposals(pendingIDs: pendingIDs)
    }

    func pendingImportEditableContents(for pending: SpinLabDomain.PendingImport) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pending.sourceFilePath)) else {
            return nil
        }

        for encoding in [String.Encoding.utf8, .ascii, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        return nil
    }
}
