import Foundation
import Testing
@testable import SpinLabApp

/// Gate SearchExcludeFolderAndPathTokens-1
///
/// Verifies that ordinary text search does not match a file solely because
/// a workflow identifier appears in its folder path, sidecar path, or raw filename.
/// Only sidecar-resolved workflow metadata produces workflow tokens.
@Suite("SearchExcludeFolderAndPathTokens")
struct SearchExcludeFolderPathTokensTests {

    // MARK: - Fixture

    private struct Fixture {
        let rootURL: URL
        private let fileManager = FileManager.default

        init() throws {
            rootURL = fileManager.temporaryDirectory
                .appending(path: "spinlab-exclude-path-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        /// Writes a sidecar at the standard library path.
        /// - Parameters:
        ///   - sidecarWorkflow: the `workflow` field in the sidecar (empty = no resolved workflow).
        ///   - workflowFolder: the folder component under `measurements/`.
        func writeSidecar(
            batchID: String = "PN80",
            sampleKey: String = "PN80|b|STO|111",
            workflowFolder: String,
            measurementFileName: String = "data.lvm",
            sidecarWorkflow: String,
            conditions: [String: String] = [:]
        ) throws {
            let dir = rootURL
                .appending(path: "batches/PN/\(batchID)/samples/\(sampleKey)/measurements/\(workflowFolder)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            let measurementURL = dir.appending(path: measurementFileName)
            try Data("x,y\n1,2\n".utf8).write(to: measurementURL)

            let sidecarURL = dir.appending(path: "\(measurementFileName).spinlab.json")
            let conditionFields = conditions.mapValues { v in SourcedValue(value: v, source: "test:fixture") }
            let sidecar = SpinLabFileSidecar(
                workflow: sidecarWorkflow,
                workflowDisplayName: sidecarWorkflow,
                channels: ["ch1"],
                sourceFilePath: measurementURL.path,
                appliedAt: .distantPast,
                ruleSnapshot: SidecarRuleSnapshot(
                    ruleSetVersion: 0,
                    ruleSetFingerprint: "test",
                    appliedAt: .distantPast,
                    fields: SidecarRuleFields(sampleID: nil, conditions: conditionFields, substrateTags: [])
                )
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(sidecar).write(to: sidecarURL)
        }

        func search(_ rawText: String) throws -> [WorkflowMeasurementSearchHit] {
            try SearchWorkflowMeasurementsUseCase().execute(
                query: WorkflowSearchQuery(rawText: rawText),
                libraryRootURL: rootURL
            )
        }

        func cleanup() { try? fileManager.removeItem(at: rootURL) }
    }

    // MARK: - 1. Folder path "3w" does not match when sidecar workflow is absent

    @Test("query '3w' does not match a file stored in /measurements/3w/ with no sidecar workflow")
    func folderPathNotMatchedWithNoSidecarWorkflow() throws {
        let f = try Fixture()
        defer { f.cleanup() }

        // sidecarWorkflow = "" → resolvedWorkflow = "" → no workflow tokens generated.
        // workflowFolder = "3w" → must not produce a "3w" search token.
        try f.writeSidecar(workflowFolder: "3w", sidecarWorkflow: "")

        let hits = try f.search("3w")
        #expect(hits.isEmpty, "folder path '3w' must not cause a match when the sidecar has no resolved workflow")
    }

    // MARK: - 2. Sidecar workflow "3w" still matches

    @Test("query '3w' matches a file whose sidecar workflow is '3w'")
    func sidecarWorkflowThreeWIsMatchable() throws {
        let f = try Fixture()
        defer { f.cleanup() }

        try f.writeSidecar(workflowFolder: "3w", sidecarWorkflow: "3w")

        let hits = try f.search("3w")
        #expect(hits.count == 1, "sidecar workflow '3w' must still match query '3w'")
    }

    // MARK: - 3. IV sidecar in 3w folder does not match "3w"

    @Test("query '3w' does not match a file with sidecar workflow 'IV' stored in /measurements/3w/")
    func ivSidecarInThreeWFolderNoThreeWMatch() throws {
        let f = try Fixture()
        defer { f.cleanup() }

        try f.writeSidecar(workflowFolder: "3w", sidecarWorkflow: "IV")

        let hits = try f.search("3w")
        #expect(hits.isEmpty, "folder path '3w' must not override a sidecar workflow of 'IV'")
    }

    // MARK: - 4. Sample token still matches

    @Test("query 'PN80' still matches a file by its sample key")
    func sampleTokenStillMatches() throws {
        let f = try Fixture()
        defer { f.cleanup() }

        try f.writeSidecar(batchID: "PN80", sampleKey: "PN80|b|STO|111", workflowFolder: "3w", sidecarWorkflow: "")

        let hits = try f.search("PN80")
        #expect(hits.count == 1, "sample token 'PN80' must remain searchable regardless of workflow state")
    }

    // MARK: - 5. Condition token still matches

    @Test("query '60deg' still matches a file by its condition value")
    func conditionTokenStillMatches() throws {
        let f = try Fixture()
        defer { f.cleanup() }

        try f.writeSidecar(
            workflowFolder: "IV",
            measurementFileName: "60deg_data.lvm",
            sidecarWorkflow: "IV",
            conditions: ["angle": "60deg"]
        )

        let hits = try f.search("60deg")
        #expect(hits.count == 1, "condition value '60deg' must remain searchable")
    }

    // MARK: - 6. Empty query returns all hits

    @Test("empty query returns all hits regardless of sidecar workflow presence")
    func emptyQueryReturnsAll() throws {
        let f = try Fixture()
        defer { f.cleanup() }

        try f.writeSidecar(workflowFolder: "3w", sidecarWorkflow: "")
        try f.writeSidecar(
            batchID: "PN81",
            sampleKey: "PN81|b|STO|111",
            workflowFolder: "IV",
            sidecarWorkflow: "IV"
        )

        let hits = try f.search("")
        #expect(hits.count == 2, "empty query must return all hits")
    }
}
