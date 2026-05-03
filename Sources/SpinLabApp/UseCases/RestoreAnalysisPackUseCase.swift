import Foundation

struct RestoreAnalysisPackUseCase {
    enum Failure: Error {
        case packNotFound(AnalysisPack.ID)
    }

    @MainActor
    func execute(packID: AnalysisPack.ID, vault: any AnalysisVaultReading) -> Result<AnalysisPack, Failure> {
        guard let pack = vault.get(id: packID) else {
            return .failure(.packNotFound(packID))
        }
        return .success(pack)
    }
}
