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

    @Test("V2 Inbox apply ingests AFM .ibw for multiple samples, is idempotent by operationID, supports source reuse, and rejects unadapted workflows")
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

        // 1. Ingest for two samples with explicit operationID
        let opID = "inbox-op-\(UUID().uuidString)"
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "",
            measurementName: "",
            workflowID: "afm",
            conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: "",
            v2TargetSampleUIDs: [s.uidA, s.uidB],
            v2OperationID: opID,
            v2ReuseSourceID: nil
        )

        let res1 = try applyService.apply(
            pending: pending,
            targets: [],
            libraryIndex: index,
            libraryStore: s.store,
            libraryRootURL: s.root,
            draft: draft
        )
        #expect(res1.copiedTargetCount == 2)

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
        #expect(Set(assetsA.map(\.id)) == Set(assetsB.map(\.id)))

        let datasetRecord = try #require(assetsA.first(where: { $0.kind == "dataset" }))
        let sourceRecord = try #require(assetsA.first(where: { $0.kind == "source" }))

        // Restart read
        let restarted = LibraryAssetService(libraryStore: LibraryStore())
        let loaded = try restarted.loadDataset(datasetID: datasetRecord.id, codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(loaded.dataset, expected))

        // 3. Unadapted workflow on V2 is explicitly rejected
        let aheDraft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "",
            measurementName: "",
            workflowID: "ahe",
            conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: "",
            v2TargetSampleUIDs: [s.uidA],
            v2OperationID: "op-ahe",
            v2ReuseSourceID: nil
        )
        #expect(throws: LibraryLayoutError.self) {
            _ = try applyService.apply(
                pending: pending,
                targets: [],
                libraryIndex: index,
                libraryStore: s.store,
                libraryRootURL: s.root,
                draft: aheDraft
            )
        }

        // 4. Duplicate content detection finds sourceRecord and reuse links it
        let sha = AssetHashing.sha256Hex(try Data(contentsOf: ibwURL))
        let matches = try restarted.findSources(sha256: sha, rootURL: s.root)
        #expect(matches.map(\.id) == [sourceRecord.id])

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
            v2TargetSampleUIDs: [s.uidB],
            v2OperationID: "op-trashed",
            v2ReuseSourceID: nil
        )
        #expect(throws: LibraryAssetError.self) {
            _ = try applyService.apply(
                pending: pending,
                targets: [],
                libraryIndex: index,
                libraryStore: s.store,
                libraryRootURL: s.root,
                draft: trashedDraft
            )
        }
    }

    @Test("Unified deletion service: A+B share -> delete A retains; delete A+B deletes once; A+B+C share -> delete A+B retains for C; crash resumes")
    func unifiedDeletionSharedAndBatchRecovery() throws {
        // 1. A & B share asset, delete only A -> retained
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let file = try T.writeFixture(name: "shared-a-only.ibw")
            let r = try T.ingest(s, file: file, targets: [s.uidA, s.uidB])
            _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)

            let planA = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
            #expect(planA.assetsToDelete.isEmpty)
            #expect(Set(planA.retainedAssets) == [r.sourceID, r.datasetID])
            let resA = try s.service.commitPermanentSampleDeletion(plan: planA, operationID: "del-a-only", rootURL: s.root)
            #expect(resA.deletedAssetIDs.isEmpty)
            #expect(try s.service.listAssets(forSampleUID: s.uidB, rootURL: s.root).count == 2)
        }

        // 2. A & B share asset, delete A & B together -> deleted once
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let file = try T.writeFixture(name: "shared-ab.ibw")
            let r = try T.ingest(s, file: file, targets: [s.uidA, s.uidB])
            _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
            _ = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)

            let planAB = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA, s.uidB], rootURL: s.root)
            #expect(Set(planAB.assetsToDelete) == [r.sourceID, r.datasetID])
            #expect(planAB.retainedAssets.isEmpty)
            #expect(planAB.deleteFileCount == 4)
            #expect(planAB.retainedFileCount == 0)

            let result = try s.service.commitPermanentSampleDeletion(
                plan: planAB,
                operationID: "empty-trash-batch",
                rootURL: s.root
            )
            #expect(Set(result.deletedAssetIDs) == [r.sourceID, r.datasetID])
            #expect(result.retainedAssetIDs.isEmpty)
            let storageEntries = try FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage").path)
            #expect(storageEntries.isEmpty)
        }

        // 3. A, B, C share asset, delete A & B together -> retained for C
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let sampleC = try T.makeSample(store: s.store, root: s.root, batch: "PN503")
            let uidC = try #require(sampleC.sampleUID)
            let file = try T.writeFixture(name: "shared-abc.ibw")
            let r = try T.ingest(s, file: file, targets: [s.uidA, s.uidB, uidC])
            _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
            _ = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)

            let planAB = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA, s.uidB], rootURL: s.root)
            #expect(planAB.assetsToDelete.isEmpty)
            #expect(Set(planAB.retainedAssets) == [r.sourceID, r.datasetID])
            #expect(planAB.deleteFileCount == 0)
            #expect(planAB.retainedFileCount == 4)

            let resAB = try s.service.commitPermanentSampleDeletion(plan: planAB, operationID: "del-ab-keep-c", rootURL: s.root)
            #expect(resAB.deletedAssetIDs.isEmpty)
            #expect(Set(resAB.retainedAssetIDs) == [r.sourceID, r.datasetID])
            #expect(try s.service.listAssets(forSampleUID: uidC, rootURL: s.root).count == 2)
        }

        // 4. Crash during batch deletion resumes via recoverPendingOperations and completes
        do {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let file = try T.writeFixture(name: "batch-crash.ibw")
            _ = try T.ingest(s, file: file, targets: [s.uidA, s.uidB])
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

    @Test("V2 ApplyCoordinator and InboxArchiveApplyService reject auto-matched targets when v2TargetSampleUIDs is empty")
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
    }
}
