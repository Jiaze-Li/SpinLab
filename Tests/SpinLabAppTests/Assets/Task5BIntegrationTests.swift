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
}
