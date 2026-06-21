import Foundation

struct BuildSampleWorkSummariesUseCase {

    struct WorkflowColumn: Hashable, Sendable {
        let id: String
        let displayName: String

        init(id: String, displayName: String) {
            self.id = id
            self.displayName = displayName
        }
    }

    struct Input {
        let hits: [WorkflowMeasurementSearchHit]
        let workflowColumns: [WorkflowColumn]
        let refreshedAt: Date
    }

    let chartLinkedBasenamesForSample: @Sendable (String) async throws -> Set<String>

    init(chartLinkedBasenamesForSample: @escaping @Sendable (String) async throws -> Set<String>) {
        self.chartLinkedBasenamesForSample = chartLinkedBasenamesForSample
    }

    func execute(_ input: Input) async throws -> [SampleWorkSummary] {
        let workflowColumns = input.workflowColumns.map {
            WorkflowColumn(
                id: normalizedIdentifier($0.id),
                displayName: $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let workflowIDs = Set(workflowColumns.map(\.id))

        let groupedHits = Dictionary(grouping: input.hits) { normalizedSampleKey($0.sampleKey) }
        var summaries: [SampleWorkSummary] = []
        summaries.reserveCapacity(groupedHits.count)

        for (sampleKey, hits) in groupedHits {
            let chartLinkedBasenames = try await chartLinkedBasenamesForSample(sampleKey)
            let workflowRows = buildWorkflowRows(
                sampleKey: sampleKey,
                hits: hits,
                workflowColumns: workflowColumns,
                chartLinkedBasenames: chartLinkedBasenames
            )
            let unknownWorkflowIDs = buildUnknownWorkflowIDs(
                hits: hits,
                knownWorkflowIDs: workflowIDs
            )
            let displayTitle = buildDisplayTitle(sampleKey: sampleKey, hits: hits)

            summaries.append(
                SampleWorkSummary(
                    sampleKey: sampleKey,
                    displayTitle: displayTitle,
                    workflowRows: workflowRows,
                    unknownWorkflowIDs: unknownWorkflowIDs,
                    lastRefreshedAt: input.refreshedAt
                )
            )
        }

        return summaries.sorted(by: compareSummaries(_:_:))
    }

    private func buildWorkflowRows(
        sampleKey: String,
        hits: [WorkflowMeasurementSearchHit],
        workflowColumns: [WorkflowColumn],
        chartLinkedBasenames: Set<String>
    ) -> [WorkflowWorkSummary] {
        let hitsByWorkflowID = Dictionary(grouping: hits) { effectiveWorkflowID(for: $0) }

        return workflowColumns.map { column in
            let workflowHits = hitsByWorkflowID[column.id] ?? []
            let fileBasenames = Set(workflowHits.map(sourceBasename(for:)))
            let fileCount = fileBasenames.count
            let chartLinkedFileCount = fileBasenames.intersection(chartLinkedBasenames).count
            return WorkflowWorkSummary(
                sampleKey: sampleKey,
                workflowID: column.id,
                workflowDisplayName: column.displayName,
                fileCount: fileCount,
                chartLinkedFileCount: chartLinkedFileCount,
                status: SampleWorkStatus.derive(
                    fileCount: fileCount,
                    chartLinkedFileCount: chartLinkedFileCount
                )
            )
        }
    }

    private func buildUnknownWorkflowIDs(
        hits: [WorkflowMeasurementSearchHit],
        knownWorkflowIDs: Set<String>
    ) -> [String] {
        let unknownIDs = Set(hits.compactMap { hit -> String? in
            let effective = effectiveWorkflowID(for: hit)
            guard !effective.isEmpty, !knownWorkflowIDs.contains(effective) else {
                return nil
            }
            return effective
        })
        return unknownIDs.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func buildDisplayTitle(sampleKey: String, hits: [WorkflowMeasurementSearchHit]) -> String {
        guard !sampleKey.isEmpty else {
            return "Unknown / Unmatched"
        }

        for hit in hits {
            let title = hit.sampleBatchAndSubstrate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }

        return sampleKey
    }

    private func sourceBasename(for hit: WorkflowMeasurementSearchHit) -> String {
        if let basename = basenameIfPresent(hit.sourceFilePath) {
            return basename
        }
        if let basename = basenameIfPresent(hit.measurementFilePath) {
            return basename
        }
        if let basename = basenameIfPresent(hit.sidecarPath) {
            return basename
        }
        return "unknown-\(normalizedIdentifier(hit.workflowCanonicalID))-\(normalizedIdentifier(hit.workflowID))-\(Int(hit.appliedAt.timeIntervalSince1970))"
    }

    private func basenameIfPresent(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private func normalizedSampleKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func effectiveWorkflowID(for hit: WorkflowMeasurementSearchHit) -> String {
        let canonical = normalizedIdentifier(hit.workflowCanonicalID)
        if !canonical.isEmpty {
            return canonical
        }
        return normalizedIdentifier(hit.workflowID)
    }

    private func compareSummaries(_ lhs: SampleWorkSummary, _ rhs: SampleWorkSummary) -> Bool {
        let lhsUnknown = lhs.sampleKey.isEmpty
        let rhsUnknown = rhs.sampleKey.isEmpty
        if lhsUnknown != rhsUnknown {
            return rhsUnknown
        }

        let titleComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.sampleKey.localizedCaseInsensitiveCompare(rhs.sampleKey) == .orderedAscending
    }
}
