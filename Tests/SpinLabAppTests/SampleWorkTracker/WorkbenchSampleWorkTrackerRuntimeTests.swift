import XCTest
@testable import SpinLabApp

private actor CallCounter {
    private(set) var count = 0
    @discardableResult func increment() -> Int {
        count += 1
        return count
    }
}

@MainActor
final class WorkbenchSampleWorkTrackerRuntimeTests: XCTestCase {

    private func makeHit(
        sampleKey: String = "PN70|B|STO|111",
        sourceFilePath: String = "/lib/run1.dat",
        workflowCanonicalID: String = "3w",
        workflowID: String = "3w",
        workflowDisplayName: String = "3ω"
    ) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/lib/\(sourceFilePath.hashValue).spinlab.json",
            measurementFilePath: "/lib/run1_m.dat",
            sourceFilePath: sourceFilePath,
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            workflowCanonicalID: workflowCanonicalID,
            batchID: "PN70",
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: [:],
            channels: [],
            appliedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private nonisolated func makeColumn(id: String, displayName: String) -> BuildSampleWorkSummariesUseCase.WorkflowColumn {
        .init(id: id, displayName: displayName)
    }

    private func makeRuntime(
        hits: [WorkflowMeasurementSearchHit] = [],
        columns: [BuildSampleWorkSummariesUseCase.WorkflowColumn] = [],
        chartLinkedBySample: [String: Set<String>] = [:],
        hitsError: Error? = nil
    ) -> WorkbenchSampleWorkTrackerRuntime {
        WorkbenchSampleWorkTrackerRuntime(
            hitsProvider: {
                if let error = hitsError { throw error }
                return hits
            },
            workflowColumnsProvider: { columns },
            chartLinkedBasenamesForSample: { sampleKey in
                chartLinkedBySample[sampleKey] ?? []
            }
        )
    }

    // MARK: - Successful refresh

    func test_refresh_updatesSummaries() async throws {
        let hit = makeHit(sampleKey: "PN70|B|STO|111", sourceFilePath: "/lib/run1.dat")
        let runtime = makeRuntime(
            hits: [hit],
            columns: [makeColumn(id: "3w", displayName: "3ω")]
        )

        runtime.refresh()
        await runtime.refreshTask?.value

        XCTAssertFalse(runtime.isRefreshing)
        XCTAssertEqual(runtime.summaries.count, 1)
        XCTAssertEqual(runtime.summaries.first?.sampleKey, "PN70|B|STO|111")
        XCTAssertNil(runtime.lastErrorMessage)
        XCTAssertNotNil(runtime.lastRefreshAt)
    }

    // MARK: - Failure preserves existing summaries

    func test_refresh_failure_preservesOldSummaries() async throws {
        let hit = makeHit()
        let counter = CallCounter()
        // Call 1: succeeds and loads a summary. Call 2: throws.
        let runtime = WorkbenchSampleWorkTrackerRuntime(
            hitsProvider: {
                let n = await counter.increment()
                if n == 1 { return [hit] }
                throw AppError.validation("simulated failure")
            },
            workflowColumnsProvider: { [BuildSampleWorkSummariesUseCase.WorkflowColumn(id: "3w", displayName: "3ω")] },
            chartLinkedBasenamesForSample: { _ in [] }
        )

        runtime.refresh()
        await runtime.refreshTask?.value
        XCTAssertEqual(runtime.summaries.count, 1, "precondition: baseline loaded")

        runtime.refresh()
        await runtime.refreshTask?.value

        XCTAssertEqual(runtime.summaries.count, 1, "summaries must be preserved on failure")
        XCTAssertNotNil(runtime.lastErrorMessage)
        XCTAssertFalse(runtime.isRefreshing)
    }

    // MARK: - Duplicate refresh guard

    func test_refresh_whileAlreadyRefreshing_isIgnored() async {
        let counter = CallCounter()
        let runtime = WorkbenchSampleWorkTrackerRuntime(
            hitsProvider: {
                _ = await counter.increment()
                return []
            },
            workflowColumnsProvider: { [] },
            chartLinkedBasenamesForSample: { _ in [] }
        )

        runtime.refresh()
        runtime.refresh() // must be dropped
        runtime.refresh() // must be dropped

        await runtime.refreshTask?.value

        let callCount = await counter.count
        XCTAssertEqual(callCount, 1, "hitsProvider must be called exactly once despite multiple refresh() calls")
        XCTAssertFalse(runtime.isRefreshing)
    }

    // MARK: - Workflow column propagation

    func test_refresh_workflowColumns_arePassedToUseCase() async throws {
        let hit = makeHit(workflowCanonicalID: "ahe", workflowID: "ahe")
        var capturedColumns: [BuildSampleWorkSummariesUseCase.WorkflowColumn] = []
        let expectedColumns = [makeColumn(id: "ahe", displayName: "AHE"), makeColumn(id: "3w", displayName: "3ω")]

        let runtime = WorkbenchSampleWorkTrackerRuntime(
            hitsProvider: { [hit] },
            workflowColumnsProvider: {
                capturedColumns = expectedColumns
                return expectedColumns
            },
            chartLinkedBasenamesForSample: { _ in [] }
        )

        runtime.refresh()
        await runtime.refreshTask?.value

        XCTAssertEqual(capturedColumns.map(\.id), ["ahe", "3w"],
                       "runtime must pass all workflow columns from provider to use case")
        XCTAssertEqual(runtime.summaries.first?.workflowRows.count, 2,
                       "one row per workflow column")
    }

    // MARK: - Dynamic settings (Bug-fix coverage: stale snapshot / security-scoped access)

    /// hitsProvider must read settings from a live source, not a one-time captured snapshot.
    /// This mirrors the contract that WorkbenchFeatureStore.setLiveLibrarySettingsProvider() establishes:
    /// the closure reads current settings on every call so a Library Root change is picked up immediately.
    func test_refresh_hitsProvider_readsDynamicSettingsNotInitialSnapshot() async throws {
        var currentRootPath = "/root-initial"
        var capturedRootPath: String?

        let runtime = WorkbenchSampleWorkTrackerRuntime(
            hitsProvider: {
                capturedRootPath = currentRootPath
                return []
            },
            workflowColumnsProvider: { [] },
            chartLinkedBasenamesForSample: { _ in [] }
        )

        runtime.refresh()
        await runtime.refreshTask?.value
        XCTAssertEqual(capturedRootPath, "/root-initial")

        currentRootPath = "/root-changed"

        runtime.refresh()
        await runtime.refreshTask?.value
        XCTAssertEqual(capturedRootPath, "/root-changed",
            "hitsProvider must use current settings on every refresh, not the initial snapshot")
    }

    /// chartLinkedBasenamesForSample must resolve paths against the current Library Root URL,
    /// not a stale raw string captured at initialization.
    /// This mirrors the contract that LibraryRootAccess.withAccess() provides: the security-scoped
    /// bookmark is re-resolved and the access token is held for the duration of each file read.
    func test_refresh_chartLinkedBasenames_usesCurrentRootURLNotStaleRoot() async throws {
        let hit = makeHit(sampleKey: "PN70|B|STO|111")
        var currentRootURL = URL(fileURLWithPath: "/root-a")
        var capturedRoot: URL?

        let runtime = WorkbenchSampleWorkTrackerRuntime(
            hitsProvider: { [hit] },
            workflowColumnsProvider: { [BuildSampleWorkSummariesUseCase.WorkflowColumn(id: "3w", displayName: "3ω")] },
            chartLinkedBasenamesForSample: { _ in
                capturedRoot = currentRootURL
                return []
            }
        )

        runtime.refresh()
        await runtime.refreshTask?.value
        XCTAssertEqual(capturedRoot, URL(fileURLWithPath: "/root-a"))

        currentRootURL = URL(fileURLWithPath: "/root-b")

        runtime.refresh()
        await runtime.refreshTask?.value
        XCTAssertEqual(capturedRoot, URL(fileURLWithPath: "/root-b"),
            "chartLinkedBasenamesForSample must use the current Library Root URL on every refresh")
    }

    // MARK: - Chart-linked basename loader usage

    func test_refresh_chartLinkedBasenameLoader_isCalledPerSampleKey() async throws {
        let hit1 = makeHit(sampleKey: "S1|A|X|1", sourceFilePath: "/lib/s1.dat")
        let hit2 = makeHit(sampleKey: "S2|B|Y|2", sourceFilePath: "/lib/s2.dat")
        var queriedSampleKeys: Set<String> = []

        let runtime = WorkbenchSampleWorkTrackerRuntime(
            hitsProvider: { [hit1, hit2] },
            workflowColumnsProvider: { [BuildSampleWorkSummariesUseCase.WorkflowColumn(id: "3w", displayName: "3ω")] },
            chartLinkedBasenamesForSample: { sampleKey in
                queriedSampleKeys.insert(sampleKey)
                if sampleKey == "S1|A|X|1" { return ["s1.dat"] }
                return []
            }
        )

        runtime.refresh()
        await runtime.refreshTask?.value

        XCTAssertEqual(queriedSampleKeys, ["S1|A|X|1", "S2|B|Y|2"],
                       "chart-linked basename loader must be invoked for every distinct sampleKey")

        let s1 = runtime.summaries.first { $0.sampleKey == "S1|A|X|1" }
        let s2 = runtime.summaries.first { $0.sampleKey == "S2|B|Y|2" }
        XCTAssertEqual(s1?.workflowRows.first?.status, .hasChart)
        XCTAssertEqual(s2?.workflowRows.first?.status, .todo)
    }
}
