import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 Rules Book State", .serialized)
struct V515RulesBookStateTests {

    private func makeWorkflowJSON(entries: [(id: String, displayName: String, conditionFieldIDs: [String])]) -> Data {
        let workflows = entries.map { entry -> [String: Any] in
            [
                "id": entry.id,
                "displayName": entry.displayName,
                "matchRules": [] as [[String: Any]],
                "conditionFieldIDs": entry.conditionFieldIDs
            ]
        }
        let json: [String: Any] = ["version": 1, "workflows": workflows, "measurementTagRules": []]
        return try! JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
    }

    private func writeWorkflowJSON(
        to url: URL,
        entries: [(id: String, displayName: String, conditionFieldIDs: [String])]
    ) throws {
        try makeWorkflowJSON(entries: entries).write(to: url)
    }

    // MARK: - notConfigured

    @Test("no paths → state is notConfigured")
    func noPathsIsNotConfigured() {
        let store = RulesManagementStore(rulesBookPaths: nil)
        #expect(store.rulesBookState == .notConfigured)
    }

    @Test("nil paths after present() → state stays notConfigured")
    func noPathsAfterPresentStaysNotConfigured() {
        let store = RulesManagementStore(rulesBookPaths: nil)
        store.present()
        #expect(store.rulesBookState == .notConfigured)
    }

    @Test("updateRulesBookPaths(nil) → reverts to notConfigured")
    func updateToNilRevertToNotConfigured() throws {
        try withTempRulesDirectory(prefix: "SL-state-nil") { _, paths in
            let store = RulesManagementStore(rulesBookPaths: paths)
            // starts incompleteBook since dir is empty
            guard case .incompleteBook = store.rulesBookState else {
                Issue.record("Expected .incompleteBook with empty dir"); return
            }

            store.updateRulesBookPaths(nil)
            #expect(store.rulesBookState == .notConfigured)
        }
    }

    // MARK: - incompleteBook

    @Test("empty dir → state is incompleteBook with all 5 filenames")
    func emptyDirIsIncompleteBook() throws {
        try withTempRulesDirectory(prefix: "SL-state-empty") { _, paths in
            let store = RulesManagementStore(rulesBookPaths: paths)
            guard case .incompleteBook(let missing) = store.rulesBookState else {
                Issue.record("Expected .incompleteBook for empty dir"); return
            }
            #expect(missing.count == 5)
            #expect(missing.contains("import_filters.json"))
            #expect(missing.contains("filename_tokenization.json"))
            #expect(missing.contains("sample_identification.json"))
            #expect(missing.contains("workflow.json"))
            #expect(missing.contains("measuring_condition.json"))
        }
    }

    @Test("4-of-5 files present → incompleteBook lists only missing file")
    func fourOfFiveFilesIsIncompleteBook() throws {
        try withTempRulesDirectory(prefix: "SL-state-partial") { _, paths in
            // Write 4 of 5 files — omit workflow.json
            for url in [paths.importFiltersURL, paths.filenameTokenizationURL,
                        paths.sampleIdentificationURL, paths.measuringConditionURL] {
                try Data("{}".utf8).write(to: url)
            }

            let store = RulesManagementStore(rulesBookPaths: paths)
            guard case .incompleteBook(let missing) = store.rulesBookState else {
                Issue.record("Expected .incompleteBook with one file missing"); return
            }
            #expect(missing == ["workflow.json"])
        }
    }

    @Test("all 5 files present → state is ready")
    func allFilesReadyState() throws {
        try withTempRulesBook(prefix: "SL-state-ready") { paths, _ in
            let store = RulesManagementStore(rulesBookPaths: paths)
            #expect(store.rulesBookState == .ready)
        }
    }

    // MARK: - RuleLoader source isolation

    @Test("RuleLoader only reads from configured book path")
    func ruleLoaderOnlyReadsFromConfiguredBook() throws {
        try withTempRulesBook(
            prefix: "SL-isolation",
            batchPrefix: "ISOLATION",
            supportedExtensions: ["dat"]
        ) { paths, _ in
            let result = RuleLoader.shared.reloadCached()

            // importRules is the cleanest cross-check: "dat" is only in this isolated book, not the bundle
            #expect(result.ruleSet.importRules?.supportedFileExtensions.contains("dat") == true)
            #expect(result.metadata.sourceLabel == "RulesBook")
            #expect(result.metadata.sourcePath.contains(paths.configDirectoryURL.path))
        }
    }

    @Test("RuleLoader.load() with no configured paths returns NotConfigured metadata")
    func ruleLoaderNotConfiguredMetadata() throws {
        withUnconfiguredRules {
            let result = RuleLoader.shared.load()
            #expect(result.metadata.sourceLabel == "NotConfigured")
            #expect(result.metadata.sourcePath == "not-configured")
            #expect(result.warnings.contains(where: { $0.contains("No Rules Book") }))
        }
    }

    @Test("saved Rules Book config is applied before workflow definitions load")
    func startupLoadsConfiguredWorkflowDefinitions() throws {
        try withTempRulesBook(prefix: "SL-startup-rules") { paths, _ in
            try writeWorkflowJSON(
                to: paths.workflowURL,
                entries: [
                    (id: "LaunchA", displayName: "Launch A", conditionFieldIDs: ["temperature"]),
                    (id: "LaunchB", displayName: "Launch B", conditionFieldIDs: ["field"])
                ]
            )

            try withTempRulesDirectory(prefix: "SL-startup-support") { supportDir, _ in
                let savedSettings = RulesBookSettings(
                    internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir)
                )
                savedSettings.configure(url: paths.configDirectoryURL)

                let loadedSettings = RulesBookSettings(
                    internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir)
                )
                let state = SpinLabAppState(
                    environment: AppEnvironment(
                        persistence: LocalJSONPersistence(),
                        inboxImportFilter: InboxImportFilterService(),
                        libraryArchiveScan: LibraryArchiveScanService(),
                        sampleRegistry: XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10),
                        registrySubstrateRules: RegistrySubstrateRuleBook(),
                        routingCapabilities: .live,
                        ruleRuntime: DefaultRuleRuntimeCapability(),
                        dataActor: SpinLabDataActor()
                    ),
                    rulesBookSettings: loadedSettings
                )

                #expect(state.workbench.workflowDefinitions.count == 2)
                #expect(state.workbench.workflowDefinitions.contains { $0.id == "LaunchA" })
                #expect(state.workbench.workflowDefinitions.contains { $0.id == "LaunchB" })
                #expect(state.workflowDefinitions.map(\.id) == ["LaunchA", "LaunchB"])
            }
        }
    }

    @Test("switching Rules Book refreshes workflow definitions and app metadata")
    func switchingRulesBookRefreshesWorkflowDefinitions() throws {
        try withTempRulesBook(prefix: "SL-switch-start") { startPaths, _ in
            try writeWorkflowJSON(
                to: startPaths.workflowURL,
                entries: [
                    (id: "StartOnly", displayName: "Start Only", conditionFieldIDs: ["temperature"])
                ]
            )

            try withTempRulesBook(prefix: "SL-switch-next") { nextPaths, _ in
                try writeWorkflowJSON(
                    to: nextPaths.workflowURL,
                    entries: [
                        (id: "NextA", displayName: "Next A", conditionFieldIDs: ["field"]),
                        (id: "NextB", displayName: "Next B", conditionFieldIDs: ["current"])
                    ]
                )

                try withTempRulesDirectory(prefix: "SL-switch-support") { supportDir, _ in
                    let savedSettings = RulesBookSettings(
                        internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir)
                    )
                    savedSettings.configure(url: startPaths.configDirectoryURL)
                    let loadedSettings = RulesBookSettings(
                        internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir)
                    )

                    let state = SpinLabAppState(
                        environment: AppEnvironment(
                            persistence: LocalJSONPersistence(),
                            inboxImportFilter: InboxImportFilterService(),
                            libraryArchiveScan: LibraryArchiveScanService(),
                            sampleRegistry: XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10),
                            registrySubstrateRules: RegistrySubstrateRuleBook(),
                            routingCapabilities: .live,
                            ruleRuntime: DefaultRuleRuntimeCapability(),
                            dataActor: SpinLabDataActor()
                        ),
                        rulesBookSettings: loadedSettings
                    )

                    #expect(state.workbench.workflowDefinitions.map(\.id) == ["StartOnly"])

                    state.configureRulesBook(at: nextPaths.configDirectoryURL)

                    #expect(state.workbench.workflowDefinitions.map(\.id) == ["NextA", "NextB"])
                    #expect(state.workflowDefinitions.map(\.id) == ["NextA", "NextB"])
                    #expect(state.inbox.routingRuleSourcePath.contains(nextPaths.configDirectoryURL.path))
                }
            }
        }
    }

    @Test("configureRulesBook runs migration path and still loads rules correctly")
    func configureRulesBookRunsMigrationBeforeLoad() throws {
        try withTempRulesBook(prefix: "SL-migrate-initial") { initialPaths, _ in
            try withTempRulesBook(prefix: "SL-migrate-target") { targetPaths, _ in
                try writeWorkflowJSON(
                    to: targetPaths.workflowURL,
                    entries: [
                        (id: "PostMigrate", displayName: "Post Migrate", conditionFieldIDs: ["field"])
                    ]
                )
                try withTempRulesDirectory(prefix: "SL-migrate-support") { supportDir, _ in
                    let settings = RulesBookSettings(
                        internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir)
                    )
                    settings.configure(url: initialPaths.configDirectoryURL)
                    let loadedSettings = RulesBookSettings(
                        internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir)
                    )
                    let state = SpinLabAppState(
                        environment: AppEnvironment(
                            persistence: LocalJSONPersistence(),
                            inboxImportFilter: InboxImportFilterService(),
                            libraryArchiveScan: LibraryArchiveScanService(),
                            sampleRegistry: XLSXPrefixSampleRegistryIndex.fromEnvironment(previewRowCount: 10),
                            registrySubstrateRules: RegistrySubstrateRuleBook(),
                            routingCapabilities: .live,
                            ruleRuntime: DefaultRuleRuntimeCapability(),
                            dataActor: SpinLabDataActor()
                        ),
                        rulesBookSettings: loadedSettings
                    )

                    // Switching to a book exercises the migration/retirement path before reload.
                    // If those steps were skipped, a legacy book could fail to decode.
                    // Asserting the state is ready after configure confirms the path is traversed without error.
                    state.configureRulesBook(at: targetPaths.configDirectoryURL)

                    #expect(state.workbench.workflowDefinitions.map(\.id) == ["PostMigrate"])
                    #expect(state.rulesPanel.rulesBookState == .ready)
                }
            }
        }
    }
}
