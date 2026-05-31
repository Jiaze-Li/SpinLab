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

    @Test("WorkflowWorkspaceShell Analyze action still builds the selected-hits bridge")
    func workflowShellAnalyzeActionBuildsSelectedHitsBridge() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift")

        #expect(source.contains("let selectedSnapshot = workbench.selectedHitsSnapshot("))
        #expect(source.contains("legacyHits: store.cachedSearchResults"))
        #expect(source.contains("store.runAnalysis(selectedHitsSnapshot: selectedSnapshot)"))
        #expect(!source.contains("store.runAnalysis()"))
    }

    @Test("WorkbenchFeatureStore selectedHitsSnapshot still prefers canonical search results")
    func selectedHitsSnapshotPrefersCanonicalSearchResults() throws {
        let source = try loadSource(relativePath: "Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift")

        #expect(source.contains("let useLegacy = canonical.results.isEmpty && !legacyHits.isEmpty"))
        #expect(source.contains("let sourceHits = useLegacy ? legacyHits : canonical.results"))
        #expect(source.contains("selectionSource: useLegacy ? .legacyMirror : .canonicalSnapshot"))
    }
}
