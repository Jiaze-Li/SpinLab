import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.3.8 Workbench Readiness Consumption")
struct V538WorkbenchReadinessConsumptionTests {

    private func loadSource(relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("WorkflowWorkspaceActionBar consumes readiness projection for selection and analysis gating")
    func actionBarConsumesReadinessProjection() throws {
        let source = try loadSource(
            relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift"
        )

        #expect(source.contains("let readiness = workbench.readinessProjection(for: workflowID, store: store)"))
        #expect(source.contains(".disabled(!readiness.hasFoundData)"))
        #expect(source.contains(".disabled(!readiness.hasSelectedData || store.isAnalyzing)"))
        #expect(source.contains("legacyHits: store.cachedSearchResults"))
    }

    @Test("WorkflowWorkspaceResultArea keeps result-header availability on store.hasAnalysisResult")
    func resultAreaConsumesReadinessProjectionSafely() throws {
        let source = try loadSource(
            relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultArea.swift"
        )
        let shellSource = try loadSource(
            relativePath: "Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift"
        )

        #expect(source.contains("WorkbenchResultHeaderShell("))
        #expect(source.contains("isAnalyzing: store.isAnalyzing"))
        #expect(source.contains("hasAnalysisResult: store.hasAnalysisResult"))
        #expect(source.contains("hasActiveImageData: store.activeImageData != nil"))
        #expect(shellSource.contains("if store.matchingVaultPack != nil"))
        #expect(shellSource.contains("if let pack = store.matchingVaultPack"))
        #expect(shellSource.contains("Button(\"Save Analysis\")"))
        #expect(shellSource.contains("Button(\"Update Analysis\")"))
        #expect(shellSource.contains(".disabled(!hasAnalysisResult)"))
    }

    @Test("Explicit library-root and vault availability checks remain direct preflights")
    func directPreflightsRemainExplicit() throws {
        let actionBarSource = try loadSource(
            relativePath: "Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift"
        )
        let loadPackSource = try loadSource(
            relativePath: "Sources/SpinLabApp/Features/Workbench/WorkbenchLoadPackPopover.swift"
        )

        #expect(actionBarSource.contains("appState.library.librarySettings.rootPath == nil"))
        #expect(loadPackSource.contains(".disabled(allPacks.isEmpty)"))
        #expect(loadPackSource.contains("store.hasUnsavedAnalysis"))
    }
}
