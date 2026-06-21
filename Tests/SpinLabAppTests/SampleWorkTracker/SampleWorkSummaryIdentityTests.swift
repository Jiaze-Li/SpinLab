import XCTest
@testable import SpinLabApp

final class SampleWorkSummaryIdentityTests: XCTestCase {

    private func makeSummary(sampleKey: String) -> SampleWorkSummary {
        SampleWorkSummary(
            sampleKey: sampleKey,
            displayTitle: "Title",
            workflowRows: [],
            unknownWorkflowIDs: [],
            lastRefreshedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeWorkflowRow(sampleKey: String, workflowID: String) -> WorkflowWorkSummary {
        WorkflowWorkSummary(
            sampleKey: sampleKey,
            workflowID: workflowID,
            workflowDisplayName: "Name",
            fileCount: 0,
            chartLinkedFileCount: 0,
            status: .noData
        )
    }

    func test_sampleSummary_sameKey_producesSameID() {
        let a = makeSummary(sampleKey: "PN70|B|STO|111")
        let b = makeSummary(sampleKey: "PN70|B|STO|111")
        XCTAssertEqual(a.id, b.id)
    }

    func test_sampleSummary_id_equalsSampleKey() {
        let summary = makeSummary(sampleKey: "PN70|B|STO|111")
        XCTAssertEqual(summary.id, "PN70|B|STO|111")
    }

    func test_sampleSummary_emptySampleKey_usesStableUnknownID() {
        let summary = makeSummary(sampleKey: "")
        XCTAssertEqual(summary.id, "__unknown_sample__")
    }

    func test_workflowRow_sameKeyAndWorkflow_producesSameID() {
        let a = makeWorkflowRow(sampleKey: "PN70|B|STO|111", workflowID: "3w")
        let b = makeWorkflowRow(sampleKey: "PN70|B|STO|111", workflowID: "3w")
        XCTAssertEqual(a.id, b.id)
    }

    func test_workflowRow_differentWorkflowID_producesDifferentID() {
        let a = makeWorkflowRow(sampleKey: "PN70|B|STO|111", workflowID: "3w")
        let b = makeWorkflowRow(sampleKey: "PN70|B|STO|111", workflowID: "ahe")
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_workflowRow_emptySampleKey_usesStableUnknownPrefix() {
        let row = makeWorkflowRow(sampleKey: "", workflowID: "iv")
        XCTAssertEqual(row.id, "__unknown_sample__::iv")
    }
}
