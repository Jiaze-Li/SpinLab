import Foundation

/// Common orchestration protocol for the async save-to-library flow.
///
/// Protocol: declares the mutable state and the optional post-save hook.
/// Extension: provides `executeSave(input:onComplete:)` — the single shared
///            Task body that previously appeared verbatim in AHE, 3ω, and XY.
///
/// Workflow-specific behaviour (guard messages, override clearing, persistCount)
/// stays in each store. The coordinator owns only the shared async machinery.
@MainActor
protocol WorkbenchSaveCoordinating: AnyObject {
    var saveMessage: String? { get set }
    var persistenceOutcome: PersistenceOutcome? { get }
    var currentRunTrace: WorkbenchRunTraceProjection? { get set }
    func refreshRelatedCharts()
    /// Called by `executeSave` to write the outcome. Each conforming type implements
    /// this to assign its own `private(set) var persistenceOutcome`.
    func applyPersistenceOutcome(_ outcome: PersistenceOutcome)
    /// Called on MainActor after outcome is applied but before saveMessage and
    /// refreshRelatedCharts. Default is a no-op.
    /// AHE overrides to clear pending overrides and increment persistCount.
    func didCompleteSave(outcome: PersistenceOutcome)
}

extension WorkbenchSaveCoordinating {
    func didCompleteSave(outcome: PersistenceOutcome) {}

    func executeSave(input: SaveActiveChartInput, onComplete: (() -> Void)?) {
        Task { [weak self] in
            guard let self else { return }
            let outcome = await Task.detached(priority: .userInitiated) {
                SaveActiveChartToLibraryUseCase().execute(input: input)
            }.value
            self.applyPersistenceOutcome(outcome)
            self.currentRunTrace = outcome.trace
            self.didCompleteSave(outcome: outcome)
            switch outcome {
            case .success:
                self.saveMessage = "Saved to Library."
                self.refreshRelatedCharts()
            case .partial(_, let err):
                self.saveMessage = "Chart saved; metric error: \(err)"
                self.refreshRelatedCharts()
            case .failure(let err):
                self.saveMessage = "Save failed: \(err)"
            }
            onComplete?()
        }
    }
}
