import Foundation

struct SampleWorkSummary: Hashable, Sendable, Identifiable {
    let id: UUID
    let sampleKey: String
    let displayTitle: String
    let workflowRows: [WorkflowWorkSummary]
    let unknownWorkflowIDs: [String]
    let lastRefreshedAt: Date

    init(
        id: UUID = UUID(),
        sampleKey: String,
        displayTitle: String,
        workflowRows: [WorkflowWorkSummary],
        unknownWorkflowIDs: [String],
        lastRefreshedAt: Date
    ) {
        self.id = id
        self.sampleKey = sampleKey
        self.displayTitle = displayTitle
        self.workflowRows = workflowRows
        self.unknownWorkflowIDs = unknownWorkflowIDs
        self.lastRefreshedAt = lastRefreshedAt
    }
}

struct WorkflowWorkSummary: Hashable, Sendable, Identifiable {
    let id: UUID
    let sampleKey: String
    let workflowID: String
    let workflowDisplayName: String
    let fileCount: Int
    let chartLinkedFileCount: Int
    let status: SampleWorkStatus

    init(
        id: UUID = UUID(),
        sampleKey: String,
        workflowID: String,
        workflowDisplayName: String,
        fileCount: Int,
        chartLinkedFileCount: Int,
        status: SampleWorkStatus
    ) {
        self.id = id
        self.sampleKey = sampleKey
        self.workflowID = workflowID
        self.workflowDisplayName = workflowDisplayName
        self.fileCount = fileCount
        self.chartLinkedFileCount = chartLinkedFileCount
        self.status = status
    }
}
