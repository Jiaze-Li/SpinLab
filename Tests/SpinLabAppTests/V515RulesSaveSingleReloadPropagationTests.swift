import Foundation
import Testing
@testable import SpinLabApp

// Regression coverage for the RulesManagementStore.persist -> SpinLabAppState.refreshAfterRulesBookChange
// chain: a single Rules save must not require a second disk reload of the canonical RuleLoader for
// derived consumers (routing metadata, Workbench workflow/condition state) to observe the new rules.
@MainActor
@Suite("V5.1.5 Rules Save Single Reload Propagation", .serialized)
struct V515RulesSaveSingleReloadPropagationTests {

    private func writeWorkflowJSON(to url: URL, ids: [String]) throws {
        let workflows = ids.map { id -> [String: Any] in
            [
                "id": id,
                "displayName": id,
                "matchRules": [["type": "equals", "value": id]],
                "conditionFieldIDs": [] as [String]
            ]
        }
        let json: [String: Any] = ["version": 1, "workflows": workflows, "measurementTagRules": []]
        try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted).write(to: url)
    }

    @Test("Single save propagates to routing metadata and Workbench workflow definitions without a manual second reload")
    func singleSavePropagatesToAllDerivedConsumers() throws {
        try withTempRulesDirectory(prefix: "SL-single-reload") { supportDir, _ in
            try withTempRulesDirectory(prefix: "SL-single-reload-book") { _, bookPaths in
                try writeMinimalRulesBook(to: bookPaths)
                try writeWorkflowJSON(to: bookPaths.workflowURL, ids: ["Initial"])

                let settings = RulesBookSettings(internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir))
                settings.configure(url: bookPaths.configDirectoryURL)

                let state = SpinLabAppState(
                    environment: AppEnvironment(
                        persistence: NoOpPersistenceForSingleReloadTest(),
                        inboxImportFilter: InboxImportFilterService(),
                        libraryArchiveScan: LibraryArchiveScanService(
                            rootURL: FileManager.default.temporaryDirectory
                                .appendingPathComponent("spinlab-single-reload-\(UUID().uuidString)", isDirectory: true)
                        ),
                        sampleRegistry: XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10),
                        registrySubstrateRules: RegistrySubstrateRuleBook(),
                        routingCapabilities: .live,
                        ruleRuntime: DefaultRuleRuntimeCapability(),
                        dataActor: SpinLabDataActor()
                    ),
                    rulesBookSettings: settings
                )

                #expect(state.workbench.workflowDefinitions.map(\.id) == ["Initial"])
                state.rulesPanel.present()
                let fingerprintBeforeSave = state.rulesPanel.rulesBookState

                var draft = try #require(state.rulesPanel.workflowDraft)
                draft.workflows.append(
                    WorkflowFileDraft.WorkflowEntry(
                        id: "AddedBySave",
                        displayName: "Added By Save",
                        matchRules: [WorkflowFileDraft.WorkflowMatchSpec(type: "equals", value: "AddedBySave")],
                        conditionFieldIDs: []
                    )
                )
                state.rulesPanel.updateWorkflow(draft)
                state.rulesPanel.selectSection(.workflow)

                let outcome = state.rulesPanel.saveCurrent()
                switch outcome {
                case .saved:
                    break
                case .validationFailed(let errors):
                    Issue.record("Expected .saved, got validationFailed(\(errors))")
                    return
                case .externalConflict(let checksum):
                    Issue.record("Expected .saved, got externalConflict(\(checksum))")
                    return
                case .ioError(let error):
                    Issue.record("Expected .saved, got ioError(\(error))")
                    return
                }

                // No manual RuleLoader/refresh call here — onRulesSaved -> refreshAfterRulesBookChange
                // must be the only thing that propagates this save to derived state.
                #expect(state.workbench.workflowDefinitions.map(\.id).contains("AddedBySave"),
                        "Workbench workflow definitions must reflect the new rules immediately after save")
                #expect(state.inbox.routingRuleSourcePath.contains(bookPaths.configDirectoryURL.path),
                        "Routing metadata must still point at the active rules book after save")
                #expect(fingerprintBeforeSave == .ready)
            }
        }
    }
}

private final class NoOpPersistenceForSingleReloadTest: SpinLabPersistence {
    func loadPendingImports() -> [SpinLabDomain.PendingImport] { [] }
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) {}
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] { [] }
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) {}
    func loadProjects() -> [SpinLabDomain.Project] { [] }
    func saveProjects(_ projects: [SpinLabDomain.Project]) {}
    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot { SpinLabInteractionSnapshot() }
    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) {}
}
