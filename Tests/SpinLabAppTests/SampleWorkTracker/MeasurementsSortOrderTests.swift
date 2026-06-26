import XCTest
@testable import SpinLabApp

final class MeasurementsSortOrderTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSummary(
        sampleKey: String,
        displayTitle: String,
        lastActivityAt: Date? = nil
    ) -> SampleWorkSummary {
        SampleWorkSummary(
            sampleKey: sampleKey,
            displayTitle: displayTitle,
            workflowRows: [],
            unknownWorkflowIDs: [],
            lastRefreshedAt: fixedDate,
            lastActivityAt: lastActivityAt
        )
    }

    // MARK: - Sample name sort

    func test_sampleName_returnsInputOrderUnchanged() {
        let a = makeSummary(sampleKey: "A", displayTitle: "Alpha")
        let b = makeSummary(sampleKey: "B", displayTitle: "Beta")
        let c = makeSummary(sampleKey: "C", displayTitle: "Gamma")
        let sorted = MeasurementsSortOrder.sampleName.sort([c, a, b])
        XCTAssertEqual(sorted.map { $0.sampleKey }, ["C", "A", "B"])
    }

    // MARK: - Latest activity sort

    func test_latestActivity_newerSampleComesFirst() {
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = Date(timeIntervalSince1970: 2_000_000)
        let older = makeSummary(sampleKey: "A", displayTitle: "Alpha", lastActivityAt: t1)
        let newer = makeSummary(sampleKey: "B", displayTitle: "Beta", lastActivityAt: t2)
        let sorted = MeasurementsSortOrder.latestActivity.sort([older, newer])
        XCTAssertEqual(sorted.map { $0.sampleKey }, ["B", "A"])
    }

    func test_latestActivity_nilTimestamp_sortsAfterTimestamped() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let withDate = makeSummary(sampleKey: "A", displayTitle: "Alpha", lastActivityAt: t)
        let withoutDate = makeSummary(sampleKey: "B", displayTitle: "Beta", lastActivityAt: nil)
        let sorted = MeasurementsSortOrder.latestActivity.sort([withoutDate, withDate])
        XCTAssertEqual(sorted.map { $0.sampleKey }, ["A", "B"])
    }

    func test_latestActivity_twoNilTimestamps_sortByDisplayTitle() {
        let a = makeSummary(sampleKey: "X", displayTitle: "Zebra", lastActivityAt: nil)
        let b = makeSummary(sampleKey: "Y", displayTitle: "Apple", lastActivityAt: nil)
        let sorted = MeasurementsSortOrder.latestActivity.sort([a, b])
        XCTAssertEqual(sorted.map { $0.displayTitle }, ["Apple", "Zebra"])
    }

    func test_latestActivity_sameTimestamp_sortByDisplayTitle() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let b = makeSummary(sampleKey: "B", displayTitle: "Mango", lastActivityAt: t)
        let a = makeSummary(sampleKey: "A", displayTitle: "Apple", lastActivityAt: t)
        let sorted = MeasurementsSortOrder.latestActivity.sort([b, a])
        XCTAssertEqual(sorted.map { $0.displayTitle }, ["Apple", "Mango"])
    }

    func test_latestActivity_unknownSampleKey_alwaysLast() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let unknown = makeSummary(sampleKey: "", displayTitle: "Unknown / Unmatched", lastActivityAt: t)
        let known = makeSummary(sampleKey: "A", displayTitle: "Alpha", lastActivityAt: nil)
        let sorted = MeasurementsSortOrder.latestActivity.sort([unknown, known])
        XCTAssertEqual(sorted.map { $0.sampleKey }, ["A", ""])
    }
}
