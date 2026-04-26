import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 WorkflowRegistryRetirement", .serialized)
struct V515WorkflowRegistryRetirementTests {

    private static let backupExtension = "v515-retirement-backup"

    private struct IsolationContext {
        let paths: RulesConfigPaths
        let configBackup: URL?
        let outerRegistryURL: URL
        let outerRegistryDir: URL
    }

    private func acquireIsolation() throws -> IsolationContext {
        let paths = RulesConfigPaths()
        let fm = FileManager.default

        var configBackup: URL? = nil
        if fm.fileExists(atPath: paths.configDirectoryURL.path) {
            let candidate = paths.configDirectoryURL
                .appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: paths.configDirectoryURL, to: candidate)
            configBackup = candidate
        }
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)

        let outerRegistryDir = paths.configDirectoryURL.deletingLastPathComponent()
        let outerRegistryURL = outerRegistryDir.appendingPathComponent("workflow_registry.json")

        // Remove any leftover outer registry from prior tests
        try? fm.removeItem(at: outerRegistryURL)

        return IsolationContext(
            paths: paths,
            configBackup: configBackup,
            outerRegistryURL: outerRegistryURL,
            outerRegistryDir: outerRegistryDir
        )
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        let fm = FileManager.default
        if fm.fileExists(atPath: ctx.paths.configDirectoryURL.path) {
            try? fm.removeItem(at: ctx.paths.configDirectoryURL)
        }
        if let configBackup = ctx.configBackup, fm.fileExists(atPath: configBackup.path) {
            try? fm.moveItem(at: configBackup, to: ctx.paths.configDirectoryURL)
        }
        // Clean up any outer registry remnants
        try? fm.removeItem(at: ctx.outerRegistryURL)
        if let items = try? fm.contentsOfDirectory(atPath: ctx.outerRegistryDir.path) {
            for item in items where item.hasPrefix("workflow_registry.json.backup-") {
                try? fm.removeItem(at: ctx.outerRegistryDir.appendingPathComponent(item))
            }
        }
        _ = RuleLoader.shared.reloadCached()
    }

    private func makeWorkflowJSON(entries: [(id: String, displayName: String, matchValues: [String], conditionFieldIDs: [String])]) throws -> Data {
        let workflows = entries.map { entry -> [String: Any] in
            [
                "id": entry.id,
                "displayName": entry.displayName,
                "matchRules": entry.matchValues.map { ["scope": "tokens", "type": "equals", "value": $0] },
                "conditionFieldIDs": entry.conditionFieldIDs
            ]
        }
        let json: [String: Any] = ["version": 1, "workflows": workflows, "measurementTagRules": []]
        return try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
    }

    private func makeOuterRegistry(entries: [(id: String, displayName: String, conditionFieldIDs: [String])]) throws -> Data {
        let records = entries.map { entry -> [String: Any] in
            [
                "id": entry.id,
                "displayName": entry.displayName,
                "conditionFields": entry.conditionFieldIDs.map { ["definitionID": $0] }
            ]
        }
        return try JSONSerialization.data(withJSONObject: records, options: .prettyPrinted)
    }

    @Test("same ID: displayName and conditionFieldIDs updated, matchRules preserved")
    func sameidUpdateDisplayNameAndConditions() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        let workflowData = try makeWorkflowJSON(entries: [
            (id: "XY", displayName: "XY Old", matchValues: ["xy"], conditionFieldIDs: ["temperature"])
        ])
        try workflowData.write(to: ctx.paths.workflowURL)

        let registryData = try makeOuterRegistry(entries: [
            (id: "XY", displayName: "XY New", conditionFieldIDs: ["temperature", "field"])
        ])
        try registryData.write(to: ctx.outerRegistryURL)

        WorkflowRegistryRetirementService(paths: ctx.paths).runIfNeeded()

        let merged = try JSONDecoder().decode(WorkflowFileDraft.self, from: Data(contentsOf: ctx.paths.workflowURL))
        let xy = try #require(merged.workflows.first { $0.id == "XY" })

        #expect(xy.displayName == "XY New")
        #expect(xy.conditionFieldIDs == ["temperature", "field"])
        // matchRules preserved from workflow.json
        #expect(xy.matchRules.count == 1)
        #expect(xy.matchRules.first?.value == "xy")

        // Outer registry retired
        #expect(!FileManager.default.fileExists(atPath: ctx.outerRegistryURL.path))
    }

    @Test("registry-only ID: appended with empty matchRules")
    func registryOnlyIDAppendedWithEmptyMatchRules() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        let workflowData = try makeWorkflowJSON(entries: [
            (id: "XY", displayName: "XY", matchValues: ["xy"], conditionFieldIDs: ["temperature"])
        ])
        try workflowData.write(to: ctx.paths.workflowURL)

        let registryData = try makeOuterRegistry(entries: [
            (id: "NewWorkflow", displayName: "New", conditionFieldIDs: ["current"])
        ])
        try registryData.write(to: ctx.outerRegistryURL)

        WorkflowRegistryRetirementService(paths: ctx.paths).runIfNeeded()

        let merged = try JSONDecoder().decode(WorkflowFileDraft.self, from: Data(contentsOf: ctx.paths.workflowURL))
        let newEntry = try #require(merged.workflows.first { $0.id == "NewWorkflow" })

        #expect(newEntry.displayName == "New")
        #expect(newEntry.conditionFieldIDs == ["current"])
        #expect(newEntry.matchRules.isEmpty)
        // Existing XY preserved
        #expect(merged.workflows.contains { $0.id == "XY" })
    }

    @Test("registry decode failure: outer registry backed up, workflow.json unchanged")
    func registryDecodeFailureBacksUpAndSkips() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        let workflowData = try makeWorkflowJSON(entries: [
            (id: "XY", displayName: "XY", matchValues: ["xy"], conditionFieldIDs: [])
        ])
        try workflowData.write(to: ctx.paths.workflowURL)
        let originalWorkflowData = try Data(contentsOf: ctx.paths.workflowURL)

        // Write garbage outer registry
        try "not valid json".data(using: .utf8)!.write(to: ctx.outerRegistryURL)

        WorkflowRegistryRetirementService(paths: ctx.paths).runIfNeeded()

        // workflow.json unchanged
        let currentData = try Data(contentsOf: ctx.paths.workflowURL)
        #expect(currentData == originalWorkflowData)

        // Outer registry backed up and removed
        #expect(!FileManager.default.fileExists(atPath: ctx.outerRegistryURL.path))
    }

    @Test("second startup: no outer registry → no-op")
    func secondStartupIsNoOp() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        let workflowData = try makeWorkflowJSON(entries: [
            (id: "XY", displayName: "XY", matchValues: ["xy"], conditionFieldIDs: [])
        ])
        try workflowData.write(to: ctx.paths.workflowURL)
        let originalData = try Data(contentsOf: ctx.paths.workflowURL)

        // No outer registry present
        WorkflowRegistryRetirementService(paths: ctx.paths).runIfNeeded()

        let currentData = try Data(contentsOf: ctx.paths.workflowURL)
        #expect(currentData == originalData)
    }
}
