import XCTest
@testable import SpinLabApp

final class BuildSampleWorkSummariesUseCaseTests: XCTestCase {

    private let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeUseCase(chartLinkedBySample: [String: Set<String>] = [:]) -> BuildSampleWorkSummariesUseCase {
        BuildSampleWorkSummariesUseCase { sampleKey in
            chartLinkedBySample[sampleKey] ?? []
        }
    }

    private func makeWorkflowColumn(id: String, displayName: String) -> BuildSampleWorkSummariesUseCase.WorkflowColumn {
        .init(id: id, displayName: displayName)
    }

    private func makeHit(
        sampleKey: String = "PN70|B|STO|111",
        batchID: String = "PN70",
        sampleSubstrate: String = "STO111",
        sourceFilePath: String = "/tmp/run1.dat",
        measurementFilePath: String = "/tmp/run1_measurement.dat",
        workflowID: String = "3w",
        workflowCanonicalID: String = "3w",
        workflowDisplayName: String = "3ω",
        id: String = UUID().uuidString
    ) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(id).spinlab.json",
            measurementFilePath: measurementFilePath,
            sourceFilePath: sourceFilePath,
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            workflowCanonicalID: workflowCanonicalID,
            batchID: batchID,
            sampleKey: sampleKey,
            sampleSubstrate: sampleSubstrate,
            conditions: [:],
            channels: [],
            appliedAt: refreshedAt
        )
    }

    private func execute(
        hits: [WorkflowMeasurementSearchHit],
        workflowColumns: [BuildSampleWorkSummariesUseCase.WorkflowColumn],
        chartLinkedBySample: [String: Set<String>] = [:]
    ) async throws -> [SampleWorkSummary] {
        let useCase = makeUseCase(chartLinkedBySample: chartLinkedBySample)
        return try await useCase.execute(
            .init(
                hits: hits,
                workflowColumns: workflowColumns,
                refreshedAt: refreshedAt
            )
        )
    }

    func test_emptyHits_returnsEmptySummaries() async throws {
        let summaries = try await execute(
            hits: [],
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        XCTAssertTrue(summaries.isEmpty)
    }

    func test_oneSample_oneWorkflow_noChartLinkedFiles_isTodo() async throws {
        let hit = makeHit(sourceFilePath: "/tmp/run1.dat")
        let summaries = try await execute(
            hits: [hit],
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        XCTAssertEqual(summaries.count, 1)
        guard let row = summaries.first?.workflowRows.first else {
            XCTFail("Expected one workflow row")
            return
        }
        XCTAssertEqual(row.fileCount, 1)
        XCTAssertEqual(row.chartLinkedFileCount, 0)
        XCTAssertEqual(row.status, SampleWorkStatus.todo)
    }

    func test_oneSample_oneWorkflow_allFilesChartLinked_isHasChart() async throws {
        let hit = makeHit(sourceFilePath: "/tmp/run1.dat")
        let summaries = try await execute(
            hits: [hit],
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")],
            chartLinkedBySample: ["PN70|B|STO|111": ["run1.dat"]]
        )

        guard let row = summaries.first?.workflowRows.first else {
            XCTFail("Expected one workflow row")
            return
        }
        XCTAssertEqual(row.fileCount, 1)
        XCTAssertEqual(row.chartLinkedFileCount, 1)
        XCTAssertEqual(row.status, SampleWorkStatus.hasChart)
    }

    func test_oneSample_oneWorkflow_partialChartLinked_isPartial() async throws {
        let hits = [
            makeHit(sourceFilePath: "/tmp/run1.dat"),
            makeHit(sourceFilePath: "/tmp/run2.dat")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")],
            chartLinkedBySample: ["PN70|B|STO|111": ["run1.dat"]]
        )

        guard let row = summaries.first?.workflowRows.first else {
            XCTFail("Expected one workflow row")
            return
        }
        XCTAssertEqual(row.fileCount, 2)
        XCTAssertEqual(row.chartLinkedFileCount, 1)
        XCTAssertEqual(row.status, SampleWorkStatus.partial)
    }

    func test_workflowColumnExists_butSampleHasNoHitsForThatWorkflow_isNoData() async throws {
        let hits = [
            makeHit(sourceFilePath: "/tmp/run1.dat", workflowCanonicalID: "3w"),
            makeHit(sourceFilePath: "/tmp/iv1.dat", workflowID: "IV", workflowCanonicalID: "IV")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [
                makeWorkflowColumn(id: "3w", displayName: "3ω"),
                makeWorkflowColumn(id: "ahe", displayName: "AHE")
            ]
        )

        guard let summary = summaries.first else {
            XCTFail("Expected a sample summary")
            return
        }
        XCTAssertEqual(summary.workflowRows.map { $0.workflowID }, ["3w", "ahe"])
        guard let secondRow = summary.workflowRows.last else {
            XCTFail("Expected a second workflow row")
            return
        }
        XCTAssertEqual(secondRow.fileCount, 0)
        XCTAssertEqual(secondRow.chartLinkedFileCount, 0)
        XCTAssertEqual(secondRow.status, SampleWorkStatus.noData)
    }

    func test_twoHits_sameBatchDifferentSampleKey_becomeSeparateSummaries() async throws {
        let hits = [
            makeHit(sampleKey: "PN70|B|STO|111", batchID: "PN70", sourceFilePath: "/tmp/a.dat"),
            makeHit(sampleKey: "PN70|B|LAO|001", batchID: "PN70", sampleSubstrate: "LAO001", sourceFilePath: "/tmp/b.dat")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.map { $0.sampleKey }.sorted(), ["PN70|B|LAO|001", "PN70|B|STO|111"])
    }

    func test_sameSampleKey_twoWorkflows_oneSummary_twoRows() async throws {
        let hits = [
            makeHit(sourceFilePath: "/tmp/run1.dat", workflowCanonicalID: "3w"),
            makeHit(sourceFilePath: "/tmp/iv1.dat", workflowID: "IV", workflowCanonicalID: "IV", workflowDisplayName: "IV")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [
                makeWorkflowColumn(id: "3w", displayName: "3ω"),
                makeWorkflowColumn(id: "IV", displayName: "IV")
            ]
        )

        XCTAssertEqual(summaries.count, 1)
        guard let summary = summaries.first else {
            XCTFail("Expected a sample summary")
            return
        }
        XCTAssertEqual(summary.workflowRows.count, 2)
        XCTAssertEqual(summary.workflowRows.map { $0.workflowID }, ["3w", "IV"])
    }

    func test_chartLinkedBasenameFromOtherWorkflow_doesNotCountTowardThisWorkflow() async throws {
        let hits = [
            makeHit(sourceFilePath: "/tmp/3w_run.dat", workflowCanonicalID: "3w", workflowDisplayName: "3ω"),
            makeHit(sourceFilePath: "/tmp/iv_run.dat", workflowID: "IV", workflowCanonicalID: "IV", workflowDisplayName: "IV")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [
                makeWorkflowColumn(id: "3w", displayName: "3ω"),
                makeWorkflowColumn(id: "IV", displayName: "IV")
            ],
            chartLinkedBySample: ["PN70|B|STO|111": ["iv_run.dat"]]
        )

        guard let summary = summaries.first else {
            XCTFail("Expected a sample summary")
            return
        }
        guard let threeWRow = summary.workflowRows.first, let ivRow = summary.workflowRows.last else {
            XCTFail("Expected two workflow rows")
            return
        }
        XCTAssertEqual(threeWRow.fileCount, 1)
        XCTAssertEqual(threeWRow.chartLinkedFileCount, 0)
        XCTAssertEqual(threeWRow.status, SampleWorkStatus.todo)
        XCTAssertEqual(ivRow.fileCount, 1)
        XCTAssertEqual(ivRow.chartLinkedFileCount, 1)
        XCTAssertEqual(ivRow.status, SampleWorkStatus.hasChart)
    }

    func test_unknownWorkflowID_populatesUnknownWorkflowIDs_withoutAdHocRow() async throws {
        let hits = [
            makeHit(sourceFilePath: "/tmp/zzz1.dat", workflowCanonicalID: "zzz", workflowDisplayName: "ZZZ"),
            makeHit(sourceFilePath: "/tmp/aaa1.dat", workflowCanonicalID: "aaa", workflowDisplayName: "AAA"),
            makeHit(sourceFilePath: "/tmp/zzz2.dat", workflowCanonicalID: "zzz", workflowDisplayName: "ZZZ")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        guard let summary = summaries.first else {
            XCTFail("Expected a sample summary")
            return
        }
        XCTAssertEqual(summary.workflowRows.count, 1)
        XCTAssertEqual(summary.unknownWorkflowIDs, ["aaa", "zzz"])
    }

    func test_knownCanonicalWithAliasWorkflowID_doesNotPopulateUnknownWorkflowIDs() async throws {
        let hits = [
            makeHit(
                sourceFilePath: "/tmp/run1.dat",
                workflowID: "three-omega-legacy",
                workflowCanonicalID: "3w",
                workflowDisplayName: "3ω"
            )
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        guard let summary = summaries.first else {
            XCTFail("Expected a sample summary")
            return
        }
        XCTAssertEqual(summary.workflowRows.map { $0.workflowID }, ["3w"])
        XCTAssertEqual(summary.unknownWorkflowIDs, [])
    }

    func test_emptyCanonicalKnownWorkflowID_countsUnderWorkflowRow() async throws {
        let hits = [
            makeHit(
                sourceFilePath: "/tmp/run1.dat",
                workflowID: "3w",
                workflowCanonicalID: "",
                workflowDisplayName: "3ω"
            )
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        guard let row = summaries.first?.workflowRows.first else {
            XCTFail("Expected one workflow row")
            return
        }
        XCTAssertEqual(row.fileCount, 1)
        XCTAssertEqual(row.status, SampleWorkStatus.todo)
        XCTAssertEqual(summaries.first?.unknownWorkflowIDs ?? [], [])
    }

    func test_emptyCanonicalUnknownWorkflowID_populatesUnknownWorkflowIDs() async throws {
        let hits = [
            makeHit(
                sourceFilePath: "/tmp/run1.dat",
                workflowID: "legacy-unknown",
                workflowCanonicalID: "",
                workflowDisplayName: "Legacy"
            )
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        guard let summary = summaries.first else {
            XCTFail("Expected a sample summary")
            return
        }
        XCTAssertEqual(summary.unknownWorkflowIDs, ["legacy-unknown"])
    }

    func test_emptySampleKey_usesStableUnknownBucket() async throws {
        let hits = [
            makeHit(sampleKey: " ", batchID: "", sourceFilePath: "/tmp/unknown.dat", workflowCanonicalID: "3w"),
            makeHit(sampleKey: "", batchID: "", sourceFilePath: "/tmp/unknown2.dat", workflowCanonicalID: "3w", id: "u2")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        XCTAssertEqual(summaries.count, 1)
        guard let summary = summaries.first else {
            XCTFail("Expected one summary")
            return
        }
        XCTAssertEqual(summary.id, "__unknown_sample__")
        XCTAssertEqual(summary.sampleKey, "")
        XCTAssertEqual(summary.displayTitle, "Unknown / Unmatched")
    }

    func test_duplicateHitsSameSourceBasename_countOnce() async throws {
        let hits = [
            makeHit(sourceFilePath: "/tmp/one/run1.dat"),
            makeHit(sourceFilePath: "/var/tmp/another/run1.dat")
        ]
        let summaries = try await execute(
            hits: hits,
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")]
        )

        guard let row = summaries.first?.workflowRows.first else {
            XCTFail("Expected one workflow row")
            return
        }
        XCTAssertEqual(row.fileCount, 1)
        XCTAssertEqual(row.chartLinkedFileCount, 0)
        XCTAssertEqual(row.status, SampleWorkStatus.todo)
    }

    func test_emptyChartLinkedSet_doesNotError_andCountsZero() async throws {
        let hit = makeHit(sourceFilePath: "/tmp/run1.dat")
        let summaries = try await execute(
            hits: [hit],
            workflowColumns: [makeWorkflowColumn(id: "3w", displayName: "3ω")],
            chartLinkedBySample: ["PN70|B|STO|111": []]
        )

        guard let row = summaries.first?.workflowRows.first else {
            XCTFail("Expected one workflow row")
            return
        }
        XCTAssertEqual(row.fileCount, 1)
        XCTAssertEqual(row.chartLinkedFileCount, 0)
        XCTAssertEqual(row.status, SampleWorkStatus.todo)
    }
}
