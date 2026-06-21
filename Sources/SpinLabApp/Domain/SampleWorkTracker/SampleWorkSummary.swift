import Foundation

struct SampleWorkSummary: Hashable, Sendable, Identifiable {
    let sampleKey: String
    let displayTitle: String
    let workflowRows: [WorkflowWorkSummary]
    let unknownWorkflowIDs: [String]
    let lastRefreshedAt: Date

    var id: String {
        sampleKey.isEmpty ? "__unknown_sample__" : sampleKey
    }

    init(
        sampleKey: String,
        displayTitle: String,
        workflowRows: [WorkflowWorkSummary],
        unknownWorkflowIDs: [String],
        lastRefreshedAt: Date
    ) {
        self.sampleKey = sampleKey
        self.displayTitle = displayTitle
        self.workflowRows = workflowRows
        self.unknownWorkflowIDs = unknownWorkflowIDs
        self.lastRefreshedAt = lastRefreshedAt
    }
}

struct WorkflowWorkSummary: Hashable, Sendable, Identifiable {
    let sampleKey: String
    let workflowID: String
    let workflowDisplayName: String
    let fileCount: Int
    let chartLinkedFileCount: Int
    let status: SampleWorkStatus

    var id: String {
        "\(sampleKey.isEmpty ? "__unknown_sample__" : sampleKey)::\(workflowID)"
    }

    init(
        sampleKey: String,
        workflowID: String,
        workflowDisplayName: String,
        fileCount: Int,
        chartLinkedFileCount: Int,
        status: SampleWorkStatus
    ) {
        self.sampleKey = sampleKey
        self.workflowID = workflowID
        self.workflowDisplayName = workflowDisplayName
        self.fileCount = fileCount
        self.chartLinkedFileCount = chartLinkedFileCount
        self.status = status
    }
}
