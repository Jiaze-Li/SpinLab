import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.15 SpinLabAppState Characterization", .serialized)
struct V5115SpinLabAppStateCharacterizationTests {

    // MARK: - Helpers

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5115-appstate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAppState(
        root: URL,
        pendingImports: [SpinLabDomain.PendingImport] = [],
        archivedRecords: [SpinLabDomain.ArchivedRecord] = [],
        snapshot: SpinLabInteractionSnapshot = SpinLabInteractionSnapshot()
    ) -> SpinLabAppState {
        SpinLabAppState(environment: AppEnvironment(
            persistence: LocalPersistenceStub(
                pendingImports: pendingImports,
                archivedRecords: archivedRecords,
                projects: [],
                interactionSnapshot: snapshot
            ),
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: AppStateCharStubActor()
        ))
    }

    private func makePending(
        fileName: String = "PN20_RT_1mA.dat",
        sourcePath: String = "/tmp/v5115-char-test/PN20_RT_1mA.dat"
    ) -> SpinLabDomain.PendingImport {
        SpinLabDomain.PendingImport(
            fileName: fileName,
            sourceFilePath: sourcePath,
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
    }

    // MARK: - 1. navigate(.inbox) sets selectedArea to inbox

    @Test("navigate(.inbox) sets selectedArea to inbox")
    func navigateToInboxSetsArea() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        state.navigate(to: .inbox)
        #expect(state.selectedArea == .inbox)
    }

    // MARK: - 2. navigate(.workbench) sets selectedArea to workbench

    @Test("navigate(.workbench) sets selectedArea to workbench")
    func navigateToWorkbenchSetsArea() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        state.navigate(to: .workbench)
        #expect(state.selectedArea == .workbench)
    }

    // MARK: - 3. navigate(.library) sets selectedArea to library

    @Test("navigate(.library) sets selectedArea to library")
    func navigateToLibrarySetsArea() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        state.navigate(to: .library)
        #expect(state.selectedArea == .library)
    }

    // MARK: - 4. navigate(.workbenchWorkflow) sets selectedArea to workbench

    @Test("navigate(.workbenchWorkflow) sets selectedArea to workbench")
    func navigateToWorkbenchWorkflowSetsArea() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        state.navigate(to: .workbenchWorkflow(id: "3Omega"))
        #expect(state.selectedArea == .workbench)
    }

    // MARK: - 5. navigate(to: AppRouteStack) applies terminal path

    @Test("navigate(to: AppRouteStack) applies all paths in order")
    func navigateViaRouteStackAppliesTerminalPath() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        let stack = AppRouteStack(paths: [.inbox, .library])
        state.navigate(to: stack)
        #expect(state.selectedArea == .library)
    }

    // MARK: - 6. openDeepLink inbox → true, navigates to inbox

    @Test("openDeepLink inbox returns true and navigates to inbox")
    func openDeepLinkInboxNavigates() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        let result = state.openDeepLink("inbox")
        #expect(result == true)
        #expect(state.selectedArea == .inbox)
    }

    // MARK: - 7. openDeepLink workbench → true, navigates to workbench

    @Test("openDeepLink workbench returns true and navigates to workbench")
    func openDeepLinkWorkbenchNavigates() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        let result = state.openDeepLink("workbench")
        #expect(result == true)
        #expect(state.selectedArea == .workbench)
    }

    // MARK: - 8. openDeepLink library/P/B001 → true, navigates to library

    @Test("openDeepLink library/P/B001 returns true and navigates to library")
    func openDeepLinkLibraryDrawerNavigates() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        let result = state.openDeepLink("library/P/B001")
        #expect(result == true)
        #expect(state.selectedArea == .library)
    }

    // MARK: - 9. openDeepLink unknown path → false

    @Test("openDeepLink unknown path returns false")
    func openDeepLinkUnknownReturnsFalse() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        let result = state.openDeepLink("no-such-route")
        #expect(result == false)
    }

    // MARK: - 10. openDeepLink empty string → false

    @Test("openDeepLink empty string returns false")
    func openDeepLinkEmptyReturnsFalse() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        let result = state.openDeepLink("")
        #expect(result == false)
    }

    // MARK: - 11. selectedArea setter captures into interaction snapshot

    @Test("selectedArea setter captures into interaction snapshot immediately")
    func selectedAreaSetterCapturesSnapshot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        state.selectedArea = .library
        #expect(state.interactionValue(\.selectedArea) == .library)
    }

    // MARK: - 12. flushInteractionSnapshotNow writes to persistence

    @Test("flushInteractionSnapshotNow writes current snapshot to persistence")
    func flushInteractionSnapshotNowWritesToPersistence() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = LocalPersistenceStub(
            pendingImports: [],
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let state = SpinLabAppState(environment: AppEnvironment(
            persistence: persistence,
            inboxImportFilter: InboxImportFilterService(),
            libraryArchiveScan: LibraryArchiveScanService(rootURL: root),
            sampleRegistry: SnapshotSampleRegistryIndex(snapshot: .empty()),
            registrySubstrateRules: RegistrySubstrateRuleBook(),
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability(),
            dataActor: AppStateCharStubActor()
        ))
        state.selectedArea = .workbench
        state.flushInteractionSnapshotNow()
        #expect(persistence.loadInteractionSnapshot().selectedArea == .workbench)
    }

    // MARK: - 13. pendingDrawerMatchByID: empty when no pending imports

    @Test("pendingDrawerMatchByID is empty when no pending imports")
    func pendingDrawerMatchByIDEmptyWhenNoPending() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        #expect(state.pendingDrawerMatchByID.isEmpty)
    }

    // MARK: - 14. pendingDrawerMatchByID: keys match pending import IDs

    @Test("pendingDrawerMatchByID keys match all pending import IDs")
    func pendingDrawerMatchByIDKeysMatchIDs() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let p1 = makePending(fileName: "file1.dat", sourcePath: "/tmp/v5115/file1.dat")
        let p2 = makePending(fileName: "file2.dat", sourcePath: "/tmp/v5115/file2.dat")
        let state = makeAppState(root: root, pendingImports: [p1, p2])
        let matchByID = state.pendingDrawerMatchByID
        #expect(matchByID.keys.contains(p1.id))
        #expect(matchByID.keys.contains(p2.id))
        #expect(matchByID.count == 2)
    }

    // MARK: - 15. hasAnyAllGoodPendingImports: false with no pending

    @Test("hasAnyAllGoodPendingImports is false when no pending imports")
    func hasAnyAllGoodPendingImportsFalseWhenEmpty() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        #expect(state.hasAnyAllGoodPendingImports() == false)
    }

    // MARK: - 16. pendingTagReadiness: .notLibraryMatched for unrouted pending

    @Test("pendingTagReadiness returns .notLibraryMatched for unrouted pending import")
    func pendingTagReadinessNotLibraryMatchedForUnrouted() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = makePending()
        let state = makeAppState(root: root, pendingImports: [pending])
        if case .notLibraryMatched = state.pendingTagReadiness(for: pending) {
            // expected
        } else {
            Issue.record("Expected .notLibraryMatched for unrouted pending import")
        }
    }

    // MARK: - 17. nameConflictChecker wired: false without library root

    @Test("nameConflictChecker returns false when no library root is configured")
    func nameConflictCheckerReturnsFalseWithoutLibraryRoot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        // Library root not configured; checker must return false for any input
        let result = state.inbox.inboxRoutingState.nameExistsInLibraryDrawer("test.dat", "S001", "3Omega")
        #expect(result == false)
    }

    // MARK: - 18. interactionValue / updateInteractionValue round-trip

    @Test("updateInteractionValue round-trips through interactionValue")
    func interactionValueUpdateRoundTrip() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeAppState(root: root)
        state.updateInteractionValue(\.lastSeenRoutingRuleFingerprint, to: "fp-abc-123")
        #expect(state.interactionValue(\.lastSeenRoutingRuleFingerprint) == "fp-abc-123")
    }

    // MARK: - 19. init restores selectedArea from saved interaction snapshot

    @Test("init restores selectedArea from pre-populated interaction snapshot")
    func initRestoresSelectedAreaFromSnapshot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var savedSnapshot = SpinLabInteractionSnapshot()
        savedSnapshot.selectedArea = .library
        let state = makeAppState(root: root, snapshot: savedSnapshot)
        #expect(state.selectedArea == .library)
    }
}

// MARK: - Stub data actor

private actor AppStateCharStubActor: SpinLabDataActing {
    func loadRegistrySnapshot(from xlsxURL: URL, previewRowCount: Int) async throws -> SampleRegistrySnapshot {
        SampleRegistrySnapshot.empty(sourceFilePath: xlsxURL.path)
    }

    func parseLibraryPreview(registryPath: String, settings: LibrarySettings) async throws -> LibraryPreviewParseSnapshot {
        LibraryPreviewParseSnapshot(
            index: LibraryIndex(
                createdAt: .now,
                updatedAt: .now,
                registryInternalPath: registryPath,
                registrySourcePath: nil,
                metadataColumnOrder: [],
                batches: [],
                samples: []
            ),
            warnings: []
        )
    }

    func searchWorkflowMeasurements(
        libraryRootPath: String,
        query: WorkflowSearchQuery,
        workflowDefinitions: [WorkflowDefinition]
    ) async throws -> [WorkflowMeasurementSearchHit] {
        []
    }

    func lookupSampleNumericDisplay(libraryRootPath: String, sampleKey: String) async throws -> [String: String] {
        [:]
    }
}
