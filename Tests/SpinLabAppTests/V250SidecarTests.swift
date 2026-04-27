import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.5.0 Sidecar Writing")
struct V250SidecarTests {
    @Test("known workflow writes only declared condition fields")
    func knownWorkflowWritesDeclaredConditions() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN80"])
        defer { fixture.cleanup() }

        var pending = try fixture.makePending(fileName: "PN80_XY_80K.dat", contents: "known-workflow")
        pending.parsedHints.workflowID = "XY"
        pending.parsedHints.measurementTags = ["XRD"]
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "PN80",
            measurementName: pending.fileName,
            workflowID: "XY",
            conditionValues: [
                "temperature": "80K",
                "field": "8T",
                "current": "1mA"
            ],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        let service = InboxArchiveApplyService()
        _ = try service.apply(
            pending: pending,
            targets: [SpinLabDomain.RouteTarget(sampleId: "PN80", channels: ["XRD"])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            draft: draft,
            workflowDefinitions: [
                WorkflowDefinition(
                    id: "XY",
                    displayName: "XY Rotation",
                    
                    conditionFields: [
                        WorkflowConditionField(definitionID: "temperature"),
                        WorkflowConditionField(definitionID: "field")
                    ]
                )
            ]
        )

        let sidecar = try fixture.decodeSidecar(sampleID: "PN80", category: "XY", fileName: pending.fileName)
        #expect(sidecar.workflow == "XY")
        #expect(sidecar.effectiveConditions == ["temperature": "80K", "field": "8T"])
        #expect(sidecar.channels == ["XRD"])
    }

    @Test("unknown workflow writes fallback non-empty condition values")
    func unknownWorkflowFallbackWritesAllConditions() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN81"])
        defer { fixture.cleanup() }

        var pending = try fixture.makePending(fileName: "PN81_unknown.dat", contents: "unknown-workflow")
        pending.parsedHints.workflowID = "UnknownWF"
        pending.parsedHints.measurementTags = ["AMR"]
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "PN81",
            measurementName: pending.fileName,
            workflowID: "UnknownWF",
            conditionValues: [
                "temperature": "300K",
                "current": "1mA",
                "field": "   ",
                "device": "Device-A"
            ],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        let service = InboxArchiveApplyService()
        _ = try service.apply(
            pending: pending,
            targets: [SpinLabDomain.RouteTarget(sampleId: "PN81", channels: ["file"])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            draft: draft,
            workflowDefinitions: []
        )

        let sidecar = try fixture.decodeSidecar(sampleID: "PN81", category: "UnknownWF", fileName: pending.fileName)
        #expect(sidecar.workflow == "UnknownWF")
        #expect(sidecar.effectiveConditions == ["temperature": "300K", "current": "1mA", "device": "Device-A"])
    }

    @Test("known workflow with empty draft conditions keeps sidecar conditions empty")
    func knownWorkflowKeepsDraftConditionBoundaryWhenDraftEmpty() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN86"])
        defer { fixture.cleanup() }

        var pending = try fixture.makePending(fileName: "PN86_AHE_170K_8T.dat", contents: "parsed-fallback")
        pending.parsedHints.workflowID = "AHE"
        pending.parsedHints.conditionValues["temperature"] = "170K"
        pending.parsedHints.conditionValues["field"] = "8T"
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "PN86",
            measurementName: pending.fileName,
            workflowID: "AHE",
            conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        let service = InboxArchiveApplyService()
        _ = try service.apply(
            pending: pending,
            targets: [SpinLabDomain.RouteTarget(sampleId: "PN86", channels: ["file"])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            draft: draft,
            workflowDefinitions: [
                WorkflowDefinition(
                    id: "AHE",
                    displayName: "AHE",
                    
                    conditionFields: [
                        WorkflowConditionField(definitionID: "temperature"),
                        WorkflowConditionField(definitionID: "field"),
                        WorkflowConditionField(definitionID: "device")
                    ]
                )
            ]
        )

        let sidecar = try fixture.decodeSidecar(sampleID: "PN86", category: "AHE", fileName: pending.fileName)
        #expect(sidecar.workflow == "AHE")
        #expect(sidecar.effectiveConditions.isEmpty)
    }

    @Test("fan-out writes one sidecar per destination drawer")
    func fanoutWritesSidecarPerDrawer() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN82", "PN83"])
        defer { fixture.cleanup() }

        var pending = try fixture.makePending(fileName: "PN82_PN83_RT.dat", contents: "fan-out")
        pending.parsedHints.workflowID = "RT"
        pending.parsedHints.measurementTags = ["R_xx"]
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "",
            measurementName: pending.fileName,
            workflowID: "RT",
            conditionValues: ["current": "1mA"],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )
        let targets = [
            SpinLabDomain.RouteTarget(sampleId: "PN82", channels: ["ch1"]),
            SpinLabDomain.RouteTarget(sampleId: "PN83", channels: ["ch2"])
        ]

        let service = InboxArchiveApplyService()
        _ = try service.apply(
            pending: pending,
            targets: targets,
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            draft: draft,
            workflowDefinitions: [
                WorkflowDefinition(
                    id: "RT",
                    displayName: "RT",
                    
                    conditionFields: [WorkflowConditionField(definitionID: "current")]
                )
            ]
        )

        let sidecar1 = try fixture.decodeSidecar(sampleID: "PN82", category: "RT", fileName: pending.fileName)
        let sidecar2 = try fixture.decodeSidecar(sampleID: "PN83", category: "RT", fileName: pending.fileName)
        #expect(sidecar1.channels == ["ch1"])
        #expect(sidecar2.channels == ["ch2"])
    }

    @Test("sidecar write failure rolls back both data and sidecar")
    func sidecarWriteFailureRollsBackAllArtifacts() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN84"])
        defer { fixture.cleanup() }

        var pending = try fixture.makePending(fileName: "PN84_RT_rollback.dat", contents: "rollback")
        pending.parsedHints.workflowID = "RT"
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "PN84",
            measurementName: pending.fileName,
            workflowID: "RT",
            conditionValues: ["current": "1mA"],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        let blocker = fixture.workflowDirectory(sampleID: "PN84", category: "RT")
        try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("blocker".utf8).write(to: blocker)

        let service = InboxArchiveApplyService()
        do {
            _ = try service.apply(
                pending: pending,
                targets: [SpinLabDomain.RouteTarget(sampleId: "PN84", channels: ["file"])],
                libraryIndex: fixture.libraryIndex,
                libraryStore: fixture.libraryStore,
                libraryRootURL: fixture.libraryRootURL,
                draft: draft,
                workflowDefinitions: [
                    WorkflowDefinition(
                        id: "RT",
                        displayName: "RT",
                        
                        conditionFields: [WorkflowConditionField(definitionID: "current")]
                    )
                ]
            )
            Issue.record("Expected apply to fail when workflow directory path is blocked by a file.")
        } catch {
            #expect(Bool(true))
        }

        let destination = fixture.destination(sampleID: "PN84", category: "RT", fileName: pending.fileName)
        let sidecar = fixture.sidecarDestination(sampleID: "PN84", category: "RT", fileName: pending.fileName)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
    }

    @Test("sidecar JSON remains decode-stable across write and reload")
    func sidecarJSONDecodeStable() throws {
        let fixture = try Fixture.make(sampleIDs: ["PN85"])
        defer { fixture.cleanup() }

        var pending = try fixture.makePending(fileName: "PN85_XY_stable.dat", contents: "stable")
        pending.parsedHints.workflowID = "XY"
        pending.parsedHints.measurementTags = ["XRD"]
        let draft = PendingImportConfirmationDraft(
            batchName: "",
            sampleName: "PN85",
            measurementName: pending.fileName,
            workflowID: "xy",
            conditionValues: ["temperature": "100K", "field": "5T"],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption,
            newProjectName: ""
        )

        let service = InboxArchiveApplyService()
        _ = try service.apply(
            pending: pending,
            targets: [SpinLabDomain.RouteTarget(sampleId: "PN85", channels: ["XRD"])],
            libraryIndex: fixture.libraryIndex,
            libraryStore: fixture.libraryStore,
            libraryRootURL: fixture.libraryRootURL,
            draft: draft,
            workflowDefinitions: [
                WorkflowDefinition(
                    id: "XY",
                    displayName: "XY Rotation",
                    
                    conditionFields: [
                        WorkflowConditionField(definitionID: "temperature"),
                        WorkflowConditionField(definitionID: "field")
                    ]
                )
            ]
        )

        let sidecar = try fixture.decodeSidecar(sampleID: "PN85", category: "XY", fileName: pending.fileName)
        #expect(sidecar.version == 2)
        #expect(sidecar.workflow == "XY")
        #expect(sidecar.effectiveConditions == ["temperature": "100K", "field": "5T"])
        #expect(sidecar.sourceFilePath == pending.sourceFilePath)
        let appliedAtDelta = abs(sidecar.appliedAt.timeIntervalSinceNow)
        #expect(appliedAtDelta <= 5)
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
            .appendingPathComponent("spinlab-v250-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let libraryRootURL = rootURL.appendingPathComponent("library", isDirectory: true)
        let libraryStore = LibraryStore()
        libraryStore.ensureRoot(at: libraryRootURL)

        let batch = LibraryBatch(
            id: "PN",
            displayName: "PN",
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

    func workflowDirectory(sampleID: String, category: String) -> URL {
        let sample = samplesByID[sampleID]!
        let drawerRoot = libraryStore.drawerRootURL(for: sample, rootURL: libraryRootURL)
        return drawerRoot
            .appending(path: "measurements", directoryHint: .isDirectory)
            .appending(path: category, directoryHint: .isDirectory)
    }

    func destination(sampleID: String, category: String, fileName: String) -> URL {
        workflowDirectory(sampleID: sampleID, category: category)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    func sidecarDestination(sampleID: String, category: String, fileName: String) -> URL {
        workflowDirectory(sampleID: sampleID, category: category)
            .appending(path: fileName + ".spinlab.json", directoryHint: .notDirectory)
    }

    func decodeSidecar(sampleID: String, category: String, fileName: String) throws -> SpinLabFileSidecar {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecarURL = sidecarDestination(sampleID: sampleID, category: category, fileName: fileName)
        let data = try Data(contentsOf: sidecarURL)
        return try decoder.decode(SpinLabFileSidecar.self, from: data)
    }
}
