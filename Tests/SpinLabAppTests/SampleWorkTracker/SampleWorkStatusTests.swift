import XCTest
@testable import SpinLabApp

final class SampleWorkStatusTests: XCTestCase {

    // MARK: - Full derivation truth table

    func test_noData_whenFileCountIsZero() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 0, chartLinkedFileCount: 0), .noData)
    }

    func test_todo_whenFilesExistButNoChartLinked() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 3, chartLinkedFileCount: 0), .todo)
    }

    func test_partial_whenSomeFilesChartLinked_one() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 3, chartLinkedFileCount: 1), .partial)
    }

    func test_partial_whenSomeFilesChartLinked_two() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 3, chartLinkedFileCount: 2), .partial)
    }

    func test_hasChart_whenAllFilesChartLinked() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 3, chartLinkedFileCount: 3), .hasChart)
    }

    // MARK: - Boundary cases

    func test_partial_notHasChart_whenChartLinkedIsFilesMinusOne() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 5, chartLinkedFileCount: 4), .partial)
    }

    func test_hasChart_notPartial_whenChartLinkedEqualsFiles() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 5, chartLinkedFileCount: 5), .hasChart)
    }

    // MARK: - Malformed / edge inputs

    func test_negativeFileCount_doesNotCrash() {
        let status = SampleWorkStatus.derive(fileCount: -1, chartLinkedFileCount: 0)
        XCTAssertEqual(status, .noData)
    }

    func test_negativeChartLinkedCount_doesNotCrash() {
        let status = SampleWorkStatus.derive(fileCount: 3, chartLinkedFileCount: -5)
        XCTAssertEqual(status, .todo)
    }

    func test_chartLinkedExceedsFileCount_doesNotCrash_resolvesToHasChart() {
        let status = SampleWorkStatus.derive(fileCount: 3, chartLinkedFileCount: 10)
        XCTAssertEqual(status, .hasChart)
    }

    func test_bothNegative_doesNotCrash() {
        let status = SampleWorkStatus.derive(fileCount: -2, chartLinkedFileCount: -3)
        XCTAssertEqual(status, .noData)
    }

    func test_singleFile_singleChartLinked_isHasChart() {
        XCTAssertEqual(SampleWorkStatus.derive(fileCount: 1, chartLinkedFileCount: 1), .hasChart)
    }
}
