import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.3 AppEnvironment Integration")
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
            managedStorage: SpinLabManagedStorage(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: MockDataActor()
        )
        let appState = SpinLabAppState(environment: environment)

        appState.importFiles(from: [importURL])

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
            managedStorage: SpinLabManagedStorage(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: MockDataActor(loadError: AppError.io("mock registry parse failure"))
        )
        let appState = SpinLabAppState(environment: environment)

        appState.loadSampleRegistry(from: registryURL)
        try await waitUntil(timeoutMS: 3_000) { appState.activeAlert != nil }

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
            managedStorage: SpinLabManagedStorage(rootURL: root.appendingPathComponent("storage", isDirectory: true)),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: MockDataActor()
        )

        let appState = SpinLabAppState(environment: environment)

        #expect(appState.activeAlert?.title == "Rules Updated")
        #expect(appState.activeAlert?.message.contains("Sync Registry") == true)
        #expect(appState.interactionValue(\.lastSeenRoutingRuleFingerprint) == appState.inbox.routingRuleFingerprint)
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
}
