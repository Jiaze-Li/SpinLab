import Foundation

@MainActor
protocol AnalysisVaultReading {
    func get(id: AnalysisPack.ID) -> AnalysisPack?
}

extension AnalysisVault: AnalysisVaultReading {}
