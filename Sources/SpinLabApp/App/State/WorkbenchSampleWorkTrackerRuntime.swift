import Foundation

@MainActor
@Observable
final class WorkbenchSampleWorkTrackerRuntime {
    private(set) var summaries: [SampleWorkSummary] = []
    private(set) var isRefreshing: Bool = false
    private(set) var lastRefreshAt: Date? = nil
    private(set) var lastErrorMessage: String? = nil

    private let hitsProvider: @Sendable () async throws -> [WorkflowMeasurementSearchHit]
    private let workflowColumnsProvider: @Sendable () -> [BuildSampleWorkSummariesUseCase.WorkflowColumn]
    private let chartLinkedBasenamesForSample: @Sendable (String) async throws -> Set<String>

    @ObservationIgnored
    var refreshTask: Task<Void, Never>?

    init(
        hitsProvider: @escaping @Sendable () async throws -> [WorkflowMeasurementSearchHit],
        workflowColumnsProvider: @escaping @Sendable () -> [BuildSampleWorkSummariesUseCase.WorkflowColumn],
        chartLinkedBasenamesForSample: @escaping @Sendable (String) async throws -> Set<String>
    ) {
        self.hitsProvider = hitsProvider
        self.workflowColumnsProvider = workflowColumnsProvider
        self.chartLinkedBasenamesForSample = chartLinkedBasenamesForSample
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastErrorMessage = nil

        let useCase = BuildSampleWorkSummariesUseCase(
            chartLinkedBasenamesForSample: chartLinkedBasenamesForSample
        )

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let hits = try await hitsProvider()
                let columns = workflowColumnsProvider()
                let refreshedAt = Date()
                let result = try await useCase.execute(.init(
                    hits: hits,
                    workflowColumns: columns,
                    refreshedAt: refreshedAt
                ))
                self.summaries = result
                self.lastRefreshAt = refreshedAt
                self.isRefreshing = false
            } catch {
                self.lastErrorMessage = error.localizedDescription
                self.isRefreshing = false
            }
        }
    }
}
