import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.3.0 Apply")
struct V230ApplyTests {
    @Test("single-target selected apply copies file and removes pending from queue")
    func singleTargetSelectedApply() async throws {
        let fixture = try Fixture.make(sampleIDs: ["PN38"])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(fileName: "PN38_RT_1mA.dat", contents: "single-target")
        let target = SpinLabDomain.RouteTarget(sampleId: "PN38", channels: ["file"])
        let snapshot = matchedSnapshot(targets: [target])
        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()

        let outcome = await applySelected(
            coordinator: coordinator,
            pendingID: pending.id,
            pendingImports: [pending],
            routingSnapshots: [pending.id: snapshot],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        #expect(outcome == .success(appliedIDs: [pending.id], skippedIDs: []))
        #expect(FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN38", category: "General", fileName: pending.fileName).path))

        let inboxStore = fixture.makeInboxStore(pendingImports: [pending])
        inboxStore.applyPending(processedIDs: outcome.processedIDs)
        #expect(inboxStore.pendingImports.isEmpty)
    }

    @Test("multi-target selected apply copies file into all matched drawers")
    func multiTargetSelectedApply() async throws {
        let fixture = try Fixture.make(sampleIDs: ["PN36", "PN37"])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(fileName: "RT_ch1_PN36_ch3_PN37.dat", contents: "multi-target")
        let targets = [
            SpinLabDomain.RouteTarget(sampleId: "PN36", channels: ["file"]),
            SpinLabDomain.RouteTarget(sampleId: "PN37", channels: ["file"])
        ]
        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()

        let outcome = await applySelected(
            coordinator: coordinator,
            pendingID: pending.id,
            pendingImports: [pending],
            routingSnapshots: [pending.id: matchedSnapshot(targets: targets)],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        #expect(outcome == .success(appliedIDs: [pending.id], skippedIDs: []))
        #expect(FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN36", category: "General", fileName: pending.fileName).path))
        #expect(FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN37", category: "General", fileName: pending.fileName).path))
    }

    @Test("multi-target apply failure leaves no partial artifacts")
    func multiTargetRollbackOnFailure() async throws {
        let fixture = try Fixture.make(sampleIDs: ["PN40", "PN41"])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(fileName: "RT_ch1_PN40_ch2_PN41.dat", contents: "rollback-target")
        let targets = [
            SpinLabDomain.RouteTarget(sampleId: "PN40", channels: ["file"]),
            SpinLabDomain.RouteTarget(sampleId: "PN41", channels: ["file"])
        ]

        let brokenDrawerRoot = fixture.libraryStore.drawerRootURL(for: fixture.samplesByID["PN41"]!, rootURL: fixture.libraryRootURL)
        try FileManager.default.removeItem(at: brokenDrawerRoot)
        try Data("not-a-directory".utf8).write(to: brokenDrawerRoot)

        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()
        let outcome = await applySelected(
            coordinator: coordinator,
            pendingID: pending.id,
            pendingImports: [pending],
            routingSnapshots: [pending.id: matchedSnapshot(targets: targets)],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        if case .failure = outcome {
            // Expected path.
        } else {
            Issue.record("Expected apply failure for broken drawer root.")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN40", category: "General", fileName: pending.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN41", category: "General", fileName: pending.fileName).path))
    }

    @Test("apply-all processes library-matched and skips review-required")
    func applyAllMixedQueue() async throws {
        let fixture = try Fixture.make(sampleIDs: ["PN50", "PN51"])
        defer { fixture.cleanup() }

        let matchedPending = try fixture.makePending(fileName: "PN50_XRD.dat", contents: "matched")
        let reviewPending = try fixture.makePending(fileName: "unknown_file.dat", contents: "review")

        let snapshots: [UUID: SpinLabDomain.PendingRoutingSnapshot] = [
            matchedPending.id: matchedSnapshot(targets: [SpinLabDomain.RouteTarget(sampleId: "PN50", channels: ["file"])]),
            reviewPending.id: reviewRequiredSnapshot()
        ]

        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()
        let outcome = await applyAll(
            coordinator: coordinator,
            pendingImports: [matchedPending, reviewPending],
            routingSnapshots: snapshots,
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        #expect(outcome == .success(appliedIDs: [matchedPending.id], skippedIDs: []))
        #expect(FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN50", category: "General", fileName: matchedPending.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN51", category: "General", fileName: reviewPending.fileName).path))
    }

    @Test("channel alone falls back to measurements/General when workflow tag is absent")
    func channelWithoutWorkflowFallsBackToGeneral() async throws {
        let fixture = try Fixture.make(sampleIDs: ["PN60"])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(fileName: "PN60_XRD.dat", contents: "xrd-measurements")
        let target = SpinLabDomain.RouteTarget(sampleId: "PN60", channels: ["XRD"])
        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()

        let outcome = await applySelected(
            coordinator: coordinator,
            pendingID: pending.id,
            pendingImports: [pending],
            routingSnapshots: [pending.id: matchedSnapshot(targets: [target])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        #expect(outcome == .success(appliedIDs: [pending.id], skippedIDs: []))
        #expect(FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN60", category: "General", fileName: pending.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: fixture.testDestination(sampleID: "PN60", channel: "XRD", fileName: pending.fileName).path))
    }

    @Test("workflow tag routes file into measurements/RT")
    func workflowCategoryRouting() async throws {
        let fixture = try Fixture.make(sampleIDs: ["PN61"])
        defer { fixture.cleanup() }

        var pending = try fixture.makePending(fileName: "PN61_RT_1mA.dat", contents: "workflow-rt")
        pending.parsedHints.workflowID = "RT"
        let target = SpinLabDomain.RouteTarget(sampleId: "PN61", channels: ["file"])
        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()

        let outcome = await applySelected(
            coordinator: coordinator,
            pendingID: pending.id,
            pendingImports: [pending],
            routingSnapshots: [pending.id: matchedSnapshot(targets: [target])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        #expect(outcome == .success(appliedIDs: [pending.id], skippedIDs: []))
        #expect(FileManager.default.fileExists(atPath: fixture.destination(sampleID: "PN61", category: "RT", fileName: pending.fileName).path))
    }

    @Test("existing destination is skipped and pending is removed as processed")
    func existingDestinationIsSkippedAndProcessed() async throws {
        let fixture = try Fixture.make(sampleIDs: ["PN62"])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(fileName: "PN62_RT_1mA.dat", contents: "skip-existing")
        let destination = fixture.destination(sampleID: "PN62", category: "General", fileName: pending.fileName)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("already-there".utf8).write(to: destination)

        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()
        let outcome = await applySelected(
            coordinator: coordinator,
            pendingID: pending.id,
            pendingImports: [pending],
            routingSnapshots: [pending.id: matchedSnapshot(targets: [SpinLabDomain.RouteTarget(sampleId: "PN62", channels: ["file"])])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        #expect(outcome == .success(appliedIDs: [], skippedIDs: [pending.id]))

        let inboxStore = fixture.makeInboxStore(pendingImports: [pending])
        inboxStore.applyPending(processedIDs: outcome.processedIDs)
        #expect(inboxStore.pendingImports.isEmpty)
    }

    @Test("display-name key is rejected when apply expects canonical sample id")
    func displayNameKeyIsRejected() async throws {
        let fixture = try Fixture.make(samples: [Fixture.SampleSeed(id: "PT23|HF|STO|111", displayName: "PT23 - HF STO(111)")])
        defer { fixture.cleanup() }

        let pending = try fixture.makePending(fileName: "PT23_HF_STO111_RT.dat", contents: "display-key")
        let target = SpinLabDomain.RouteTarget(sampleId: "PT23 - HF STO(111)", channels: ["file"])
        let coordinator = ApplyCoordinator()
        let service = InboxArchiveApplyService()

        let outcome = await applySelected(
            coordinator: coordinator,
            pendingID: pending.id,
            pendingImports: [pending],
            routingSnapshots: [pending.id: matchedSnapshot(targets: [target])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            applyService: service
        )

        if case .failure = outcome {
            // Expected: apply now accepts canonical id only.
        } else {
            Issue.record("Expected apply failure when target key is display-name format.")
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.destination(sampleID: "PT23|HF|STO|111", category: "General", fileName: pending.fileName).path
            )
        )
    }

    private func applySelected(
        coordinator: ApplyCoordinator,
        pendingID: UUID?,
        pendingImports: [SpinLabDomain.PendingImport],
        routingSnapshots: [UUID: SpinLabDomain.PendingRoutingSnapshot],
        libraryIndex: LibraryIndex,
        libraryStore: LibraryStore,
        libraryRootURL: URL,
        applyService: InboxArchiveApplyService
    ) async -> InboxApplyOutcome {
        let context = ApplyCoordinator.ApplyContext(
            pendingImports: pendingImports,
            routingSnapshots: routingSnapshots,
            libraryIndex: libraryIndex,
            libraryRootURL: libraryRootURL
        )
        return await coordinator.apply(
            scope: .selected(pendingID),
            context: context,
            libraryStore: libraryStore,
            applyService: applyService
        )
    }

    private func applyAll(
        coordinator: ApplyCoordinator,
        pendingImports: [SpinLabDomain.PendingImport],
        routingSnapshots: [UUID: SpinLabDomain.PendingRoutingSnapshot],
        libraryIndex: LibraryIndex,
        libraryStore: LibraryStore,
        libraryRootURL: URL,
        applyService: InboxArchiveApplyService
    ) async -> InboxApplyOutcome {
        let context = ApplyCoordinator.ApplyContext(
            pendingImports: pendingImports,
            routingSnapshots: routingSnapshots,
            libraryIndex: libraryIndex,
            libraryRootURL: libraryRootURL
        )
        return await coordinator.apply(
            scope: .all,
            context: context,
            libraryStore: libraryStore,
            applyService: applyService
        )
    }

    private func matchedSnapshot(targets: [SpinLabDomain.RouteTarget]) -> SpinLabDomain.PendingRoutingSnapshot {
        SpinLabDomain.PendingRoutingSnapshot(
            mode: .fileLevel,
            verdict: .libraryMatched,
            scopes: [],
            unresolvedScopes: [],
            conflicts: [],
            routePlan: SpinLabDomain.RoutePlan(
                planningStatus: .reviewRequired,
                targets: targets,
                channelResolutions: [],
                unresolvedChannels: [],
                conflicts: []
            )
        )
    }

    private func reviewRequiredSnapshot() -> SpinLabDomain.PendingRoutingSnapshot {
        SpinLabDomain.PendingRoutingSnapshot(
            mode: .fileLevel,
            verdict: .reviewRequired,
            scopes: [],
            unresolvedScopes: ["file"],
            conflicts: [],
            routePlan: SpinLabDomain.RoutePlan(
                planningStatus: .reviewRequired,
                targets: [],
                channelResolutions: [],
                unresolvedChannels: ["file"],
                conflicts: []
            )
        )
    }
}

@MainActor
private struct Fixture {
    var rootURL: URL
    var libraryRootURL: URL
    var libraryStore: LibraryStore
    var libraryIndex: LibraryIndex
    var samplesByID: [String: LibrarySample]

    struct SampleSeed {
        let id: String
        let displayName: String
    }

    static func make(sampleIDs: [String]) throws -> Fixture {
        let seeds = sampleIDs.map { SampleSeed(id: $0, displayName: $0) }
        return try make(samples: seeds)
    }

    static func make(samples: [SampleSeed]) throws -> Fixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-v230-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let libraryRootURL = rootURL.appendingPathComponent("library", isDirectory: true)
        let libraryStore = LibraryStore()
        libraryStore.ensureRoot(at: libraryRootURL)

        let batch = LibraryBatch(
            id: "PN38",
            displayName: "PN38",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [],
            updatedAt: .now
        )
        var samplesByID: [String: LibrarySample] = [:]
        for sampleSeed in samples {
            let sample = LibrarySample(
                id: sampleSeed.id,
                displayName: sampleSeed.displayName,
                batchId: batch.id,
                substrateRaw: "STO(111)",
                substrateDisplay: "STO(111)",
                substrateTokens: ["STO", "111"],
                substrateTags: ["STO", "111"],
                metadata: [:],
                orderedMetadata: [],
                numericTags: [:],
                numericDisplay: [:],
                sourceSheetName: "Sheet1",
                sourceRowNumber: 1,
                updatedAt: .now
            )
            samplesByID[sampleSeed.id] = sample
            libraryStore.createDrawer(for: sample, batch: batch, rootURL: libraryRootURL)
        }

        let libraryIndex = libraryStore.syncIndexFromFilesystem(rootURL: libraryRootURL)
        return Fixture(
            rootURL: rootURL,
            libraryRootURL: libraryRootURL,
            libraryStore: libraryStore,
            libraryIndex: libraryIndex,
            samplesByID: samplesByID
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makePending(fileName: String, contents: String) throws -> SpinLabDomain.PendingImport {
        let sourceURL = rootURL.appendingPathComponent(fileName)
        try Data(contents.utf8).write(to: sourceURL)
        return SpinLabDomain.PendingImport(
            workflow: .amrPhe,
            fileName: fileName,
            sourceFilePath: sourceURL.path,
            originalFilePath: sourceURL.path,
            importedAt: .now,
            status: .needsConfirmation,
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
    }

    func destination(sampleID: String, category: String, fileName: String) -> URL {
        let sample = samplesByID[sampleID]!
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        return drawerRoot
            .appending(path: "measurements", directoryHint: .isDirectory)
            .appending(path: category, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    func testDestination(sampleID: String, channel: String, fileName: String) -> URL {
        let sample = samplesByID[sampleID]!
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        return drawerRoot
            .appending(path: "tests", directoryHint: .isDirectory)
            .appending(path: channel, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    func makeInboxStore(pendingImports: [SpinLabDomain.PendingImport]) -> InboxFeatureStore {
        let persistence = LocalPersistenceStub(
            pendingImports: pendingImports,
            archivedRecords: [],
            projects: [],
            interactionSnapshot: SpinLabInteractionSnapshot()
        )
        let repository = InboxRepository(persistence: persistence)
        return InboxFeatureStore(
            inboxRepository: repository,
            routingCapabilities: .live,
            ruleRuntime: DefaultRuleRuntimeCapability()
        )
    }
}
