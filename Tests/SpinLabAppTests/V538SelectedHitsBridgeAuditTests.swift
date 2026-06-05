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

    @Test("WorkflowWorkspaceShell Analyze action still builds the selected-hits bridge")
    func workflowShellAnalyzeActionBuildsSelectedHitsBridge() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift")
        let analyzeBlock = try sourceSlice(
            source,
            startMarker: "let selectedSnapshot = workbench.selectedHitsSnapshot(",
            endMarker: "WorkflowWorkspaceLoadPackPlacement("
        )

        #expect(analyzeBlock.contains("let selectedSnapshot = workbench.selectedHitsSnapshot("))
        #expect(analyzeBlock.contains("legacyHits: store.cachedSearchResults"))
        #expect(analyzeBlock.contains("store.runAnalysis(selectedHitsSnapshot: selectedSnapshot)"))
    }

    @Test("WorkbenchFeatureStore selectedHitsSnapshot still prefers canonical search results")
    func selectedHitsSnapshotPrefersCanonicalSearchResults() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift")

        #expect(source.contains("let useLegacy = canonical.results.isEmpty && !legacyHits.isEmpty"))
        #expect(source.contains("let sourceHits = useLegacy ? legacyHits : canonical.results"))
        #expect(source.contains("selectionSource: useLegacy ? .legacyMirror : .canonicalSnapshot"))
    }
}
