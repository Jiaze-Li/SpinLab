import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.3 AppEnvironment Integration", .serialized)
struct V223AppEnvironmentIntegrationTests {
    @Test("importing files projects into repository-backed app state")
    func importFlowProjectsIntoRepositoryAndAppState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-env-int-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let importURL = root.appendingPathComponent("PN20_RT_1mA.dat")
        try Data("test".utf8).write(to: importURL)

        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let environment = AppEnvironment(
            persistence: persistence,
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: makeBundleRuleRuntime(),
            dataActor: MockDataActor()
        )
        let appState = SpinLabAppState(environment: environment, rulesBookSettings: makeBundleRulesBookSettings())

        // Retries the scan on every tick: RuleLoader.shared is process-global, so a concurrently
        // running unrelated suite can transiently reconfigure it between this call and the read
        // inside it. Re-issuing the (idempotent) scan makes this test robust to that instead of
        // depending on winning a race against other suites' test isolation.
        try await waitUntil(timeoutMS: 120_000) {
            if appState.inbox.pendingImports.isEmpty {
                appState.importFiles(from: [importURL])
            }
            return appState.inbox.pendingImports.count == 1
                && persistence.loadPendingImports().count == 1
                && appState.inbox.importProgressState.isRunning == false
        }

        #expect(appState.inbox.pendingImports.count == 1)
        #expect(persistence.loadPendingImports().count == 1)
        #expect(appState.selectedPendingImportID == appState.inbox.pendingImports.first?.id)
    }

    @Test("registry load surfaces data actor failure into app alert")
    func registryLoadFailureSurfacesAlert() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-env-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registryURL = root.appendingPathComponent("registry.xlsx")
        try Data("not-a-real-xlsx".utf8).write(to: registryURL)

        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let environment = AppEnvironment(
            persistence: persistence,
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: makeBundleRuleRuntime(),
            dataActor: MockDataActor(loadError: AppError.io("mock registry parse failure"))
        )
        let appState = SpinLabAppState(environment: environment)

        appState.loadSampleRegistry(from: registryURL)
        try await waitUntil(timeoutMS: 120_000) { appState.activeAlert != nil }

        #expect(appState.activeAlert?.title == "Registry Load Failed")
    }

    @Test("rule fingerprint change surfaces rebuild reminder on startup")
    func ruleFingerprintChangeSurfacesRebuildReminderOnStartup() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-env-rules-reminder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var snapshot = SpinLabInteractionSnapshot()
        snapshot.lastSeenRoutingRuleFingerprint = "v1:legacy-rule-fingerprint"
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: snapshot
        )
        let environment = AppEnvironment(
            persistence: persistence,
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: makeBundleRuleRuntime(),
            dataActor: MockDataActor()
        )

        let appState = SpinLabAppState(environment: environment)

        #expect(appState.activeAlert?.title == "Rules Updated")
        #expect(appState.activeAlert?.message.contains("Sync Registry") == true)
        #expect(appState.interactionValue(\.lastSeenRoutingRuleFingerprint) == appState.inbox.routingRuleFingerprint)
    }

    @Test("workflow parser value is resolved to workflow id by case-insensitive token match")
    func workflowValueNormalizesToWorkflowID() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-env-workflow-normalize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let importURL = root.appendingPathComponent("PN20_AHE_1mA.dat")
        try Data("test".utf8).write(to: importURL)

        let workflowDefURL = root.appendingPathComponent("workflow_def.json")
        try """
        {"version":3,"workflows":[{"id":"ahe","displayName":"AHE","matchRules":[{"type":"equals","value":"AHE"}],"conditionFieldIDs":[]}],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: workflowDefURL)

        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let environment = AppEnvironment(
            persistence: persistence,
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: makeBundleRuleRuntime(),
            dataActor: MockDataActor(),
            workflowDefinitionStore: WorkflowDefinitionStore(fileURL: workflowDefURL)
        )
        let bundleRuleProvider = InlineRuleProvider(loadResult: RuleLoader().loadFromBundleOnly())
        let workflowBundle = WorkflowBundle(
            workflowExtension: AMRPHEWorkflowExtension(),
            metadataExtension: AMRPHEMetadataExtension(ruleProvider: bundleRuleProvider),
            analysisModule: AMRPHEAnalysisModuleExtension(),
            viewExtension: AMRPHEViewExtension()
        )
        let appState = SpinLabAppState(
            workflowBundle: workflowBundle,
            environment: environment,
            rulesBookSettings: makeBundleRulesBookSettings()
        )

        try await waitUntil(timeoutMS: 120_000) {
            if appState.inbox.pendingImports.isEmpty {
                appState.importFiles(from: [importURL])
            }
            return appState.inbox.pendingImports.count == 1
                && appState.inbox.importProgressState.isRunning == false
        }

        guard let pending = appState.inbox.pendingImports.first else {
            Issue.record("Expected one imported pending item.")
            return
        }
        let draft = appState.pendingDisplayDraft(for: pending)
        #expect(draft.workflowID == "ahe")
    }

    @Test("library sidecar original path is excluded from inbox import")
    func librarySidecarOriginalPathIsExcludedFromImport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-env-library-dedup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let importURL = root.appendingPathComponent("PN20_RT_1mA.dat")
        try Data("test".utf8).write(to: importURL)

        let libraryRoot = root.appendingPathComponent("library", isDirectory: true)
        let sidecarURL = libraryRoot
            .appendingPathComponent("batches", isDirectory: true)
            .appendingPathComponent("PN20", isDirectory: true)
            .appendingPathComponent("sample", isDirectory: true)
            .appendingPathComponent("entry.spinlab.json")
        try FileManager.default.createDirectory(at: sidecarURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sidecar = SpinLabFileSidecar(
            workflow: "AHE",
            workflowDisplayName: "AHE",
            channels: [],
            sourceFilePath: importURL.standardizedFileURL.path,
            appliedAt: .now,
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 0,
                ruleSetFingerprint: "test:fixture",
                appliedAt: .now,
                fields: SidecarRuleFields(sampleID: nil, conditions: [:], substrateTags: [])
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sidecarData = try encoder.encode(sidecar)
        try sidecarData.write(to: sidecarURL, options: .atomic)

        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let environment = AppEnvironment(
            persistence: persistence,
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: makeBundleRuleRuntime(),
            dataActor: MockDataActor()
        )
        let appState = SpinLabAppState(environment: environment, rulesBookSettings: makeBundleRulesBookSettings())
        appState.library.librarySettings.rootPath = libraryRoot.path

        appState.importFiles(from: [importURL])
        try await waitUntil(timeoutMS: 120_000) {
            appState.inbox.importProgressState.isRunning == false
        }

        #expect(appState.inbox.pendingImports.isEmpty)
        #expect(persistence.loadPendingImports().isEmpty)
    }

    // Load rules from bundle (unaffected by V515's runtime config dir manipulation).
    private func makeBundleRuleRuntime() -> DefaultRuleRuntimeCapability {
        DefaultRuleRuntimeCapability(
            ruleProvider: InlineRuleProvider(loadResult: RuleLoader().loadFromBundleOnly())
        )
    }

    /// A `RulesBookSettings` explicitly pointed at the bundled dev fixture rules (same source
    /// `makeBundleRuleRuntime()` uses for routing), backed by an isolated Application Support
    /// directory so it never touches the real on-disk settings. Pass this to `SpinLabAppState`
    /// so `SpinLabAppState.init`'s own `rulesBookSettings.prepareAndConfigureRuleLoader()` call
    /// configures `RuleLoader.shared` (the default `SpinLabRuleProviding` behind
    /// `SpinLabImportPipeline`'s import filtering) consistently — rather than a bare
    /// `RuleLoader.configure()` in the test, which `SpinLabAppState.init` would immediately
    /// overwrite with its own (unconfigured) `RulesBookSettings()`.
    private func makeBundleRulesBookSettings() -> RulesBookSettings {
        let configDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let supportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v223-appsupport-\(UUID().uuidString)", isDirectory: true)
        let settings = RulesBookSettings(internalPaths: AppInternalPaths(appSupportDirectoryURL: supportDir))
        settings.configure(url: configDir)
        return settings
    }

    private func waitUntil(timeoutMS: UInt64, condition: @escaping () -> Bool) async throws {
        let intervalNS: UInt64 = 20_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutMS * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: intervalNS)
        }
        Issue.record("Timed out waiting for condition.")
    }
}

private actor MockDataActor: SpinLabDataActing {
    private let loadError: AppError?
    private let previewError: AppError?

    init(loadError: AppError? = nil, previewError: AppError? = nil) {
        self.loadError = loadError
        self.previewError = previewError
    }

    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot {
        if let loadError {
            throw loadError
        }
        return SampleRegistrySnapshot.empty(sourceFilePath: xlsxURL.path)
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot {
        if let previewError {
            throw previewError
        }
        return LibraryPreviewParseSnapshot(
            index: LibraryIndex(
                createdAt: .now,
                updatedAt: .now,
                registryInternalPath: registryPath,
                registrySourcePath: settings.registrySourcePath,
                metadataColumnOrder: [],
                batches: [],
                samples: []
            ),
            warnings: []
        )
    }

    func searchWorkflowMeasurements(
        settings: LibrarySettings,
        query: WorkflowSearchQuery,
        workflowDefinitions: [WorkflowDefinition]
    ) async throws -> [WorkflowMeasurementSearchHit] {
        []
    }

    func lookupSampleNumericDisplay(libraryRootPath: String, sampleKey: String) async throws -> [String: String] {
        [:]
    }
}
