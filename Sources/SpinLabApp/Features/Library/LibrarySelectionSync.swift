import Foundation

struct LibrarySelectionSync {
    struct Input {
        var selectedPrefix: String?
        var selectedBatchId: String?
        var selectedSampleId: String?
    }

    struct Output {
        var selectedPrefix: String?
        var selectedBatchId: String?
        var selectedSampleId: String?
    }

    static func syncBrowserSelection(
        input: Input,
        previewGroupsByPrefix: [String: [LibraryPreviewBatchGroup]]
    ) -> Output {
        var output = Output(
            selectedPrefix: input.selectedPrefix,
            selectedBatchId: input.selectedBatchId,
            selectedSampleId: input.selectedSampleId
        )

        let previewPrefixes = previewGroupsByPrefix.keys.sorted()
        if output.selectedPrefix == nil || !previewPrefixes.contains(output.selectedPrefix ?? "") {
            output.selectedPrefix = previewPrefixes.first
        }

        let groups = previewGroupsByPrefix[output.selectedPrefix ?? ""] ?? []
        if let firstBatch = groups.first?.batchId {
            if output.selectedBatchId == nil || groups.first(where: { $0.batchId == output.selectedBatchId }) == nil {
                output.selectedBatchId = firstBatch
            }
        } else {
            output.selectedBatchId = nil
            output.selectedSampleId = nil
            return output
        }

        let samples = groups.first(where: { $0.batchId == output.selectedBatchId })?.samples ?? []
        if output.selectedSampleId == nil || !samples.contains(where: { $0.id == output.selectedSampleId }) {
            output.selectedSampleId = samples.first?.id
        }

        return output
    }

    static func syncDrawerSelection(
        input: Input,
        existingGroupsByPrefix: [String: [LibraryPreviewBatchGroup]]
    ) -> Output {
        var output = Output(
            selectedPrefix: input.selectedPrefix,
            selectedBatchId: input.selectedBatchId,
            selectedSampleId: input.selectedSampleId
        )

        let existingPrefixes = existingGroupsByPrefix.keys.sorted()
        if output.selectedPrefix == nil || !existingPrefixes.contains(output.selectedPrefix ?? "") {
            output.selectedPrefix = existingPrefixes.first
        }
        guard let prefix = output.selectedPrefix else {
            output.selectedBatchId = nil
            output.selectedSampleId = nil
            return output
        }

        let groups = existingGroupsByPrefix[prefix] ?? []
        let batchIDs = groups.map(\.batchId)
        if output.selectedBatchId == nil || !batchIDs.contains(output.selectedBatchId ?? "") {
            output.selectedBatchId = groups.first?.batchId
        }

        let samples = groups.first(where: { $0.batchId == output.selectedBatchId })?.samples ?? []
        if output.selectedSampleId == nil || !samples.contains(where: { $0.id == output.selectedSampleId }) {
            output.selectedSampleId = samples.first?.id
        }

        return output
    }
}
