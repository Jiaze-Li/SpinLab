import Testing
import Foundation
@testable import SpinLabApp

/// Gate 7.5B — Baseline tests proving the save coordinator extraction preserved
/// per-workflow metric delegation: each workflow's persistToLibrary still calls
/// its own buildActiveChartMetrics() before delegating to the shared coordinator.
@Suite("V750B Save Coordinator Baseline")
struct V750BMetricDelegationTests {

    // MARK: - Helpers (mirror of V537 pattern)

    private func loadSource(file: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: "Sources/SpinLabApp/Features/Workbench/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractFunction(_ name: String, from source: String) -> String? {
        guard let sig = source.range(of: "func \(name)") else { return nil }
        guard let open = source[sig.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let c = source[index]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return String(source[sig.lowerBound...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    // MARK: - Each persistToLibrary calls workflow-owned buildActiveChartMetrics()

    @Test("AHE persistToLibrary calls buildActiveChartMetrics() before handing off to coordinator")
    func ahePersistCallsBuildMetrics() throws {
        let src = try loadSource(file: "AHEWorkspaceStore.swift")
        let fn = try #require(extractFunction("persistToLibrary", from: src))
        #expect(fn.contains("buildActiveChartMetrics()"))
    }

    @Test("3ω persistToLibrary calls buildActiveChartMetrics() before handing off to coordinator")
    func threeOmegaPersistCallsBuildMetrics() throws {
        let src = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")
        let fn = try #require(extractFunction("persistToLibrary", from: src))
        #expect(fn.contains("buildActiveChartMetrics()"))
    }

    @Test("XY persistToLibrary calls buildActiveChartMetrics() before handing off to coordinator")
    func xyPersistCallsBuildMetrics() throws {
        let src = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let fn = try #require(extractFunction("persistToLibrary", from: src))
        #expect(fn.contains("buildActiveChartMetrics()"))
    }

    // MARK: - Coordinator owns shared async machinery; no physics in coordinator

    @Test("Coordinator executeSave owns persistenceOutcome, currentRunTrace, saveMessage, refreshRelatedCharts")
    func coordinatorOwnsMachinery() throws {
        let src = try loadSource(file: "WorkbenchSaveCoordinating.swift")
        #expect(src.contains("applyPersistenceOutcome(outcome)"),
                "executeSave must delegate outcome write via applyPersistenceOutcome, not set persistenceOutcome directly")
        #expect(src.contains("currentRunTrace = outcome.trace"))
        #expect(src.contains("saveMessage = \"Saved to Library.\""))
        #expect(src.contains("saveMessage = \"Save failed:"))
        #expect(src.contains("refreshRelatedCharts()"))
        #expect(src.contains("didCompleteSave(outcome: outcome)"))
    }

    @Test("Coordinator contains no physics constants or metric name strings")
    func coordinatorContainsNoPhysics() throws {
        let src = try loadSource(file: "WorkbenchSaveCoordinating.swift")
        #expect(!src.contains("1e31"))
        #expect(!src.contains("1e20"))
        #expect(!src.contains("\"Hc\""))
        #expect(!src.contains("\"R_AHE\""))
        #expect(!src.contains("\"alpha\""))
        #expect(!src.contains("\"beta\""))
    }

    // MARK: - Each persistToLibrary delegates orchestration; no duplicate Task body

    @Test("AHE persistToLibrary delegates to executeSave, not Task body")
    func ahePersistDelegatesToExecuteSave() throws {
        let src = try loadSource(file: "AHEWorkspaceStore.swift")
        let fn = try #require(extractFunction("persistToLibrary", from: src))
        #expect(fn.contains("executeSave("))
        #expect(!fn.contains("Task {"))
        #expect(!fn.contains("SaveActiveChartToLibraryUseCase"))
    }

    @Test("3ω persistToLibrary delegates to executeSave, not Task body")
    func threeOmegaPersistDelegatesToExecuteSave() throws {
        let src = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")
        let fn = try #require(extractFunction("persistToLibrary", from: src))
        #expect(fn.contains("executeSave("))
        #expect(!fn.contains("Task {"))
        #expect(!fn.contains("SaveActiveChartToLibraryUseCase"))
    }

    @Test("XY persistToLibrary delegates to executeSave, not Task body")
    func xyPersistDelegatesToExecuteSave() throws {
        let src = try loadSource(file: "XYRotationWorkspaceStore.swift")
        let fn = try #require(extractFunction("persistToLibrary", from: src))
        #expect(fn.contains("executeSave("))
        #expect(!fn.contains("Task {"))
        #expect(!fn.contains("SaveActiveChartToLibraryUseCase"))
    }

    // MARK: - AHE-specific post-save hook

    @Test("AHE provides didCompleteSave override clearing override candidates and bumping persistCount")
    func aheDidCompleteSaveExistsWithAHESpecificState() throws {
        let src = try loadSource(file: "AHEWorkspaceStore.swift")
        #expect(src.contains("func didCompleteSave(outcome:"))
        #expect(src.contains("pendingMetricOverride = nil"))
        #expect(src.contains("pendingRAHEOverride = nil"))
        #expect(src.contains("persistCount += 1"))
    }

    @Test("3ω and XY do not override didCompleteSave")
    func nonAHEDoNotOverrideHook() throws {
        let threeSrc = try loadSource(file: "ThreeOmegaWorkspaceStore+Persistence.swift")
        let xySrc = try loadSource(file: "XYRotationWorkspaceStore.swift")
        #expect(!threeSrc.contains("func didCompleteSave"))
        #expect(!xySrc.contains("func didCompleteSave"))
    }
}
