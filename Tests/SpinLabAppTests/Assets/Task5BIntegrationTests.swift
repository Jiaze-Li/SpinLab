import Foundation
import Testing
@testable import SpinLabApp

@Suite("Task 5B: fileExtension rules and V2 Inbox AFM integration")
struct Task5BIntegrationTests {
    typealias T = AssetTestSupport

    @Test("Rule Book fileExtension matches .ibw/.IBW without afm token, while preserving filename/folder precedence and equals semantics")
    func fileExtensionRuleAndPrecedence() throws {
        let bundled = withBundledRules { $0.ruleSet() }
        #expect(bundled.importRules?.supportedFileExtensions.map { $0.lowercased() }.contains("ibw") == true)

        let parser = FilenameRuleParser(ruleSet: bundled)

        // No 'afm' token in filename or folder -> falls back to fileExtension: ibw
        let contactIBW = URL(fileURLWithPath: "/tmp/Batch1/LSMO13_CONTACT_0000.IBW")
        let contactHints = parser.parse(from: contactIBW)
        #expect(contactHints.workflowID == "afm")

        // Explicit workflow token in filename ('AHE') takes precedence over fileExtension
        let aheIBW = URL(fileURLWithPath: "/tmp/Batch1/PN100_AHE_0000.ibw")
        let aheHints = parser.parse(from: aheIBW)
        #expect(aheHints.workflowID == "ahe")

        // 'equals: ibw' does NOT match '.ibw' extension when fileExtension rule is absent
        let equalsOnlySet = FilenameRuleSet(
            version: 1,
            tokenization: FilenameRuleSet.fallback().tokenization,
            sources: [.file],
            sampleId: FilenameRuleSet.fallback().sampleId,
            measurementNameRules: [
                FilenameRuleSet.MapRule(match: .init(type: .equals, value: "ibw"), value: "afm")
            ],
            measurementTagRules: [],
            channel: FilenameRuleSet.fallback().channel,
            conditions: FilenameRuleSet.fallback().conditions,
            conditionDefinitions: [],
            registry: nil,
            importRules: FilenameRuleSet.fallback().importRules,
            substrateConfig: nil
        )
        let equalsParser = FilenameRuleParser(ruleSet: equalsOnlySet)
        #expect(equalsParser.parse(from: contactIBW).workflowID == nil)
    }

    @Test("V2 Inbox apply ingests AFM .ibw for single sample, is idempotent by operationID, supports same-sample reuse, rejects cross-sample reuse & unadapted workflows")
    func v2InboxApplyLifecycle() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }

        let ibwURL = try T.writeFixture(name: "LSMO13_CONTACT_0000.ibw")
        let expected = try T.expectedDataset(from: ibwURL)
        let pending = SpinLabDomain.PendingImport(
            id: UUID(),
            fileName: ibwURL.lastPathComponent,
            sourceFilePath: ibwURL.path,
            originalFilePath: ibwURL.path,
            parsedHints: SpinLabDomain.ParsedFilenameHints(workflowID: "afm")
        )
        let index = try s.store.syncIndexFromFilesystem(rootURL: s.root)
        let applyService = InboxArchiveApplyService()

        // 1. Ingest for a single sample with explicit operationID
        let opID = "inbox-op-\(UUID().uuidString)"
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "",
            measurementName: "",
            workflowID: "afm",
            conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: "",
            v2Targets: [V2IngestTarget(sampleUID: s.uidA, ingestOperationID: opID, reuseSourceID: nil)]
        )

        let res1 = try applyService.apply(
            pending: pending,
            targets: [],
            libraryIndex: index,
            libraryStore: s.store,
            libraryRootURL: s.root,
            draft: draft
        )
        #expect(res1.copiedTargetCount == 1)

        // 2. Idempotent retry with same operationID produces no duplicate assets
        let res2 = try applyService.apply(
            pending: pending,
            targets: [],
            libraryIndex: index,
            libraryStore: s.store,
            libraryRootURL: s.root,
            draft: draft
        )
        #expect(res2 == res1)

        let assetsA = try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root)
        let assetsB = try s.service.listAssets(forSampleUID: s.uidB, rootURL: s.root)
        #expect(assetsA.count == 2) // 1 source + 1 dataset
        #expect(assetsB.isEmpty)

        let datasetRecord = try #require(assetsA.first(where: { $0.kind == "dataset" }))
        let sourceRecord = try #require(assetsA.first(where: { $0.kind == "source" }))

        // Restart read
        let restarted = LibraryAssetService(libraryStore: LibraryStore())
        let loaded = try restarted.loadDataset(datasetID: datasetRecord.id, codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(loaded.dataset, expected))

        // 3. An unadapted file is still stored (P2): Source-only, reason recorded, no Dataset
        let oddDir = FileManager.default.temporaryDirectory.appending(path: "SpinLab_5B_odd_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: oddDir, withIntermediateDirectories: true)
        let oddURL = oddDir.appending(path: "notes.dat")
        try Data("not a measurement table".utf8).write(to: oddURL)
        let oddPending = SpinLabDomain.PendingImport(
            id: UUID(), fileName: "notes.dat", sourceFilePath: oddURL.path, originalFilePath: oddURL.path,
            parsedHints: SpinLabDomain.ParsedFilenameHints(workflowID: "ahe")
        )
        let aheDraft = PendingImportConfirmationDraft(
            batchName: "", sampleName: "", measurementName: "", workflowID: "ahe", conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption, newProjectName: "",
            v2Targets: [V2IngestTarget(sampleUID: s.uidA, ingestOperationID: "op-ahe")]
        )
        let oddResult = try applyService.apply(
            pending: oddPending, targets: [], libraryIndex: index, libraryStore: s.store, libraryRootURL: s.root, draft: aheDraft
        )
        #expect(!oddResult.isIncompleteV2)
        #expect(oddResult.v2TargetResults.first?.standardize == .notStandardized(code: "unsupported_layout"))
        #expect(try restarted.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 3)   // 2 Sources + 1 AFM Dataset

        // 4. Duplicate content detection finds sourceRecord only for owning sample; cross-sample reuse is rejected
        let sha = AssetHashing.sha256Hex(try Data(contentsOf: ibwURL))
        #expect(try restarted.findSources(sha256: sha, ownedBySampleUID: s.uidA, rootURL: s.root).map(\.id) == [sourceRecord.id])
        #expect(try restarted.findSources(sha256: sha, ownedBySampleUID: s.uidB, rootURL: s.root).isEmpty)

        let crossReuseDraft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "",
            measurementName: "",
            workflowID: "afm",
            conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: "",
            v2Targets: [V2IngestTarget(sampleUID: s.uidB, ingestOperationID: "op-cross-reuse", reuseSourceID: sourceRecord.id)]
        )
        let crossResult = try applyService.apply(
            pending: pending, targets: [], libraryIndex: index, libraryStore: s.store, libraryRootURL: s.root, draft: crossReuseDraft
        )
        #expect(crossResult.isIncompleteV2)
        guard case .failed? = crossResult.v2TargetResults.first?.ingest else { Issue.record("cross-sample reuse must fail at ingest"); return }

        // 5. Trashed sample target is refused
        _ = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)
        let trashedDraft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "",
            measurementName: "",
            workflowID: "afm",
            conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: "",
            v2Targets: [V2IngestTarget(sampleUID: s.uidB, ingestOperationID: "op-trashed", reuseSourceID: nil)]
        )
        let trashedResult = try applyService.apply(
            pending: pending, targets: [], libraryIndex: index, libraryStore: s.store, libraryRootURL: s.root, draft: trashedDraft
        )
        #expect(trashedResult.isIncompleteV2)
        guard case .failed? = trashedResult.v2TargetResults.first?.ingest else { Issue.record("a trashed target must fail at ingest"); return }
    }

    @Test("Unified deletion service: cross-sample Plot retention & batch deletion across A, B, C; crash resumes")
    func unifiedDeletionSharedAndBatchRecovery() throws {
        // 1. A & B have independent datasets linked by a cross-sample Plot; delete only A -> Plot & A's inputs retained
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let rA = try T.ingest(s, file: try T.writeFixture(seed: 1, name: "a.ibw"), target: s.uidA)
            let rB = try T.ingest(s, file: try T.writeFixture(seed: 2, name: "b.ibw"), target: s.uidB)
            let plot = try s.service.registerDerivedAsset(kind: "plot", inputAssetIDs: [rA.datasetIDs[0], rB.datasetIDs[0]], rootURL: s.root)
            _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)

            let planA = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
            #expect(planA.assetsToDelete.isEmpty)
            #expect(Set(planA.retainedAssets) == [rA.sourceID, rA.datasetIDs[0], plot])
            let resA = try s.service.commitPermanentSampleDeletion(plan: planA, operationID: "del-a-only", rootURL: s.root)
            #expect(resA.deletedAssetIDs.isEmpty)
            #expect(try s.service.listAssets(forSampleUID: s.uidB, rootURL: s.root).contains { $0.id == plot && $0.liveState == "stale" })
        }

        // 2. A & B have independent datasets linked by a Plot; delete A & B together -> everything deleted once
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let rA = try T.ingest(s, file: try T.writeFixture(seed: 1, name: "ab-a.ibw"), target: s.uidA)
            let rB = try T.ingest(s, file: try T.writeFixture(seed: 2, name: "ab-b.ibw"), target: s.uidB)
            let plot = try s.service.registerDerivedAsset(kind: "plot", inputAssetIDs: [rA.datasetIDs[0], rB.datasetIDs[0]], rootURL: s.root)
            _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
            _ = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)

            let planAB = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA, s.uidB], rootURL: s.root)
            #expect(Set(planAB.assetsToDelete) == [rA.sourceID, rA.datasetIDs[0], rB.sourceID, rB.datasetIDs[0], plot])
            #expect(planAB.retainedAssets.isEmpty)
            #expect(planAB.deleteFileCount == 8)
            #expect(planAB.retainedFileCount == 0)

            let result = try s.service.commitPermanentSampleDeletion(
                plan: planAB,
                operationID: "empty-trash-batch",
                rootURL: s.root
            )
            #expect(Set(result.deletedAssetIDs) == Set(planAB.assetsToDelete))
            #expect(result.retainedAssetIDs.isEmpty)
            let storageEntries = try FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage").path)
            #expect(storageEntries.isEmpty)
        }

        // 3. A, B, C linked by a Plot; delete A & B together -> Plot & A/B inputs retained for C
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let sampleC = try T.makeSample(store: s.store, root: s.root, batch: "PN503")
            let uidC = try #require(sampleC.sampleUID)
            let rA = try T.ingest(s, file: try T.writeFixture(seed: 1, name: "abc-a.ibw"), target: s.uidA)
            let rB = try T.ingest(s, file: try T.writeFixture(seed: 2, name: "abc-b.ibw"), target: s.uidB)
            let rC = try T.ingest(s, file: try T.writeFixture(seed: 3, name: "abc-c.ibw"), target: uidC)
            let plot = try s.service.registerDerivedAsset(
                kind: "plot", inputAssetIDs: [rA.datasetIDs[0], rB.datasetIDs[0], rC.datasetIDs[0]], rootURL: s.root
            )
            _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
            _ = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)

            let planAB = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA, s.uidB], rootURL: s.root)
            #expect(planAB.assetsToDelete.isEmpty)
            #expect(Set(planAB.retainedAssets) == [rA.sourceID, rA.datasetIDs[0], rB.sourceID, rB.datasetIDs[0], plot])
            #expect(planAB.deleteFileCount == 0)
            #expect(planAB.retainedFileCount == 8)

            let resAB = try s.service.commitPermanentSampleDeletion(plan: planAB, operationID: "del-ab-keep-c", rootURL: s.root)
            #expect(resAB.deletedAssetIDs.isEmpty)
            #expect(Set(resAB.retainedAssetIDs) == Set(planAB.retainedAssets))
            #expect(try s.service.listAssets(forSampleUID: uidC, rootURL: s.root).count == 3)
        }

        // 4. Crash during batch deletion resumes via recoverPendingOperations and completes
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            _ = try T.ingest(s, file: try T.writeFixture(seed: 1, name: "batch-crash-a.ibw"), target: s.uidA)
            _ = try T.ingest(s, file: try T.writeFixture(seed: 2, name: "batch-crash-b.ibw"), target: s.uidB)
            _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
            _ = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)

            let plan = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA, s.uidB], rootURL: s.root)
            struct InjectedCrash: Error {}
            let crashing = LibraryAssetService(libraryStore: s.store)
            crashing.faultHook = { point in
                if case .deleteAfterFile(1) = point { throw InjectedCrash() }
            }
            #expect(throws: InjectedCrash.self) {
                _ = try crashing.commitPermanentSampleDeletion(plan: plan, operationID: "batch-crash-op", rootURL: s.root)
            }

            let recovered = try LibraryAssetService(libraryStore: s.store).recoverPendingOperations(rootURL: s.root)
            #expect(recovered.recoveredOperations == ["batch-crash-op"])
            let storageEntries = try FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage").path)
            #expect(storageEntries.isEmpty)
            #expect(try s.store.syncIndexFromFilesystem(rootURL: s.root).samples.isEmpty)
        }
    }

    @Test("V2 ApplyCoordinator and InboxArchiveApplyService reject auto-matched targets when v2TargetSampleUID is nil")
    func v2ApplyAllCannotBypassExplicitSampleConfirmation() async throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }

        let ibwURL = try T.writeFixture(name: "PN100_AFM_0000.ibw")
        let pending = SpinLabDomain.PendingImport(
            id: UUID(),
            fileName: ibwURL.lastPathComponent,
            sourceFilePath: ibwURL.path,
            originalFilePath: ibwURL.path,
            parsedHints: SpinLabDomain.ParsedFilenameHints(workflowID: "afm")
        )
        let index = try s.store.syncIndexFromFilesystem(rootURL: s.root)
        let autoMatchedSnapshot = SpinLabDomain.PendingRoutingSnapshot(
            mode: .fileLevel,
            verdict: .libraryMatched,
            scopes: [],
            routePlan: SpinLabDomain.RoutePlan(
                planningStatus: .libraryMatched,
                targets: [SpinLabDomain.RouteTarget(sampleId: s.sampleA.id, channels: [])],
                channelResolutions: [],
                unresolvedChannels: [],
                conflicts: []
            )
        )
        let context = ApplyCoordinator.ApplyContext(
            pendingImports: [pending],
            routingSnapshots: [pending.id: autoMatchedSnapshot],
            libraryIndex: index,
            libraryRootURL: s.root
        )

        let coordinator = ApplyCoordinator()
        let emptyDraftOutcome = await coordinator.apply(
            scope: .all,
            context: context,
            libraryStore: s.store,
            applyService: InboxArchiveApplyService(),
            draftFor: { _ in nil }
        )
        #expect(emptyDraftOutcome == .nothingToApply)
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).isEmpty)

        #expect(throws: LibraryAssetError.self) {
            _ = try InboxArchiveApplyService().apply(
                pending: pending,
                targets: autoMatchedSnapshot.routePlan.targets,
                libraryIndex: index,
                libraryStore: s.store,
                libraryRootURL: s.root,
                draft: nil
            )
        }

        // Trashed or missing target UID in draft is also rejected by ApplyCoordinator gate
        _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        let trashedIndex = try s.store.syncIndexFromFilesystem(rootURL: s.root)
        let trashedContext = ApplyCoordinator.ApplyContext(
            pendingImports: [pending],
            routingSnapshots: [pending.id: autoMatchedSnapshot],
            libraryIndex: trashedIndex,
            libraryRootURL: s.root
        )
        let trashedDraft = PendingImportConfirmationDraft(
            batchName: "", sampleName: "", measurementName: "", workflowID: "afm",
            conditionValues: [:], selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: "", v2Targets: [V2IngestTarget(sampleUID: s.uidA, ingestOperationID: "op-stale-uid", reuseSourceID: nil)]
        )
        let trashedOutcome = await coordinator.apply(
            scope: .all,
            context: trashedContext,
            libraryStore: s.store,
            applyService: InboxArchiveApplyService(),
            draftFor: { _ in trashedDraft }
        )
        #expect(trashedOutcome == .nothingToApply)
    }
}
