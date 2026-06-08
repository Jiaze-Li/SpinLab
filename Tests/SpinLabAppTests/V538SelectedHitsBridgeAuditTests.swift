import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.3.8 Selected Hits Bridge Audit")
struct V538SelectedHitsBridgeAuditTests {

    private func loadSource(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func sourceSlice(
        _ source: String,
        startMarker: String,
        endMarker: String
    ) throws -> Substring {
        guard let start = source.range(of: startMarker) else {
            Issue.record("Missing start marker: \(startMarker)")
            throw NSError(domain: "V538SelectedHitsBridgeAuditTests", code: 1, userInfo: nil)
        }
        guard let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            Issue.record("Missing end marker: \(endMarker)")
            throw NSError(domain: "V538SelectedHitsBridgeAuditTests", code: 2, userInfo: nil)
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("WorkflowWorkspaceShell Analyze action calls selectedHitsSnapshot via facade")
    func workflowShellAnalyzeActionCallsSelectedHitsSnapshotFacade() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift")

        #expect(source.contains("workbench.selectedHitsSnapshot(for: workflowID)"))
        #expect(source.contains("store.runAnalysis(selectedHitsSnapshot:"))
    }

    @Test("WorkbenchFeatureStore selectedHitsSnapshot(for:) reads from selection runtime")
    func selectedHitsSnapshotReadsFromSelectionRuntime() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/App/State/WorkbenchMainSearchRuntime.swift")

        // The no-arg facade reads selection from the runtime
        #expect(source.contains("func selectedHitsSnapshot("))
        #expect(source.contains("selectionSource:"))
    }
}
