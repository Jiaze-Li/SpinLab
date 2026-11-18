import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("Task 9 Trash and Tiered Deletion")
struct LibraryTrashAndTieredDeletionTests {
    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-trash-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSample(
        id: String = "PN101-STO-001",
        displayName: String = "PN101-STO-001",
        batchId: String = "PN101",
        metadata: [String: String] = [:],
        numericTags: [String: Double] = [:],
        numericDisplay: [String: String] = [:],
        appliedMeasurements: [AppliedMeasurement] = [],
        origin: String? = "native",
        deletedAt: Date? = nil
    ) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: displayName,
            batchId: batchId,
            substrateRaw: "STO(001)",
            substrateDisplay: "STO(001)",
            substrateTokens: ["STO", "001"],
            substrateTags: ["STO"],
            metadata: metadata,
            orderedMetadata: [],
            numericTags: numericTags,
            numericDisplay: numericDisplay,
            updatedAt: Date(),
            appliedMeasurements: appliedMeasurements,
            measurementSets: [],
            sampleUID: UUID().uuidString,
            legacySampleKey: nil,
            origin: origin,
            deletedAt: deletedAt
        )
    }

    private func makeBatch(id: String = "PN101", sampleKeys: [String] = ["PN101-STO-001"], origin: String? = "native") -> LibraryBatch {
        LibraryBatch(
            id: id,
            displayName: id,
            sheetName: "",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: sampleKeys,
            updatedAt: Date(),
            origin: origin
        )
    }

    private func makeIndex(batches: [LibraryBatch], samples: [LibrarySample]) -> LibraryIndex {
        LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: batches,
            samples: samples
        )
    }

    @Test("legacy sample.json without deletedAt decodes as active sample")
    func legacySampleJSONDecodesWithoutDeletedAt() throws {
        let json = """
        {
          "id": "PN10-STO-1",
          "displayName": "PN10-STO-1",
          "batchId": "PN10",
          "substrateRaw": "STO",
          "substrateDisplay": "STO",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sample = try decoder.decode(LibrarySample.self, from: Data(json.utf8))
        #expect(sample.deletedAt == nil)
        #expect(sample.isTrashed == false)
    }

    @Test("empty check classifies truly empty vs metadata, numeric, measurement, chart, and corrupt samples")
    func emptyCheckClassifications() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        let checker = LibrarySampleEmptyCheck()

        // 1. Truly empty native sample
        let emptySample = makeSample(id: "PN101-EMPTY", displayName: "PN101-EMPTY")
        let batch = makeBatch(sampleKeys: ["PN101-EMPTY"])
        try store.createDrawer(for: emptySample, batch: batch, rootURL: root)
        #expect(checker.evaluate(sample: emptySample, rootURL: root, libraryStore: store) == .empty)

        // 2. Metadata parameter present
        let metaSample = makeSample(id: "PN101-META", metadata: ["Note": "annealed"])
        try store.createDrawer(for: metaSample, batch: makeBatch(sampleKeys: ["PN101-META"]), rootURL: root)
        #expect(checker.evaluate(sample: metaSample, rootURL: root, libraryStore: store).requiresConfirmation == true)

        // 3. Numeric tag present
        let numericSample = makeSample(id: "PN101-NUM", numericTags: ["Thickness": 12.0], numericDisplay: ["Thickness": "12"])
        try store.createDrawer(for: numericSample, batch: makeBatch(sampleKeys: ["PN101-NUM"]), rootURL: root)
        #expect(checker.evaluate(sample: numericSample, rootURL: root, libraryStore: store).requiresConfirmation == true)

        // 4. Drawer file present (e.g., measurement sidecar)
        let fileSample = makeSample(id: "PN101-FILE")
        try store.createDrawer(for: fileSample, batch: makeBatch(sampleKeys: ["PN101-FILE"]), rootURL: root)
        let sampleDir = store.sampleDirectoryURL(root, batchID: "PN101", sampleKey: "PN101-FILE")
        let measurementFile = sampleDir.appending(path: "measurements/ahe.dat")
        try Data("x,y\n1,2\n".utf8).write(to: measurementFile)
        #expect(checker.evaluate(sample: fileSample, rootURL: root, libraryStore: store).requiresConfirmation == true)

        // 5. Results index present
        let chartSample = makeSample(id: "PN101-CHART")
        try store.createDrawer(for: chartSample, batch: makeBatch(sampleKeys: ["PN101-CHART"]), rootURL: root)
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let chartIndexStore = LibraryChartIndexStore(layout: layout)
        let ref = WorkbenchResultReference(
            chartIdentityKey: "chart-1",
            chartImagePath: "samples/PN101-CHART/charts/chart-1.png",
            manifestPath: "samples/PN101-CHART/charts/chart-1.manifest.json",
            workflowID: "AHE",
            generatedAt: Date()
        )
        let resultsIndex = WorkbenchResultsIndex(sampleKey: "PN101-CHART", updatedAt: Date(), references: [ref])
        let resultsURL = try layout.resultsIndexURL(sampleKey: "PN101-CHART")
        try FileManager.default.createDirectory(at: resultsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try chartIndexStore.encodeResultsIndex(resultsIndex).write(to: resultsURL)
        #expect(checker.evaluate(sample: chartSample, rootURL: root, libraryStore: store).requiresConfirmation == true)

        // 6. Corrupt measurement_data.json -> fail-closed (.unreadable, requiresConfirmation == true)
        let corruptSample = makeSample(id: "PN101-CORRUPT")
        try store.createDrawer(for: corruptSample, batch: makeBatch(sampleKeys: ["PN101-CORRUPT"]), rootURL: root)
        let measURL = try layout.measurementDataURL(sampleKey: "PN101-CORRUPT")
        try FileManager.default.createDirectory(at: measURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not valid json".utf8).write(to: measURL)
        let corruptResult = checker.evaluate(sample: corruptSample, rootURL: root, libraryStore: store)
        #expect(corruptResult.requiresConfirmation == true)
        if case .unreadable = corruptResult {
            // expected
        } else {
            Issue.record("Expected .unreadable for corrupt measurement_data.json, got \(corruptResult)")
        }
    }

    @Test("soft delete preserves disk files and identity, and restore brings sample back intact")
    func softDeleteAndRestorePreserveDiskFiles() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        let sample = makeSample(id: "PN102-S1", displayName: "PN102-S1", batchId: "PN102")
        let batch = makeBatch(id: "PN102", sampleKeys: ["PN102-S1"])
        try store.createDrawer(for: sample, batch: batch, rootURL: root)

        let sampleDir = store.sampleDirectoryURL(root, batchID: "PN102", sampleKey: "PN102-S1")
        let dataFile = sampleDir.appending(path: "measurements/run1.csv")
        let payload = Data("H,R\n0.1,10.2\n".utf8)
        try payload.write(to: dataFile)

        // Move to trash
        let trashed = try store.moveSampleToTrash(sample: sample, rootURL: root)
        #expect(trashed.isTrashed == true)
        #expect(trashed.id == sample.id)
        #expect(trashed.sampleUID == sample.sampleUID)
        #expect(FileManager.default.fileExists(atPath: dataFile.path))
        #expect(try Data(contentsOf: dataFile) == payload)

        // Preview groups exclude trashed sample
        let indexAfterTrash = try #require(store.loadIndex(from: root))
        let groupsAfterTrash = LibraryPreviewComputationService().buildPreviewGroups(from: indexAfterTrash)
        #expect(groupsAfterTrash.isEmpty)

        // Restore from trash
        let restored = try store.restoreSampleFromTrash(sample: trashed, rootURL: root)
        #expect(restored.isTrashed == false)
        #expect(restored.deletedAt == nil)
        #expect(try Data(contentsOf: dataFile) == payload)

        let indexAfterRestore = try #require(store.loadIndex(from: root))
        let groupsAfterRestore = LibraryPreviewComputationService().buildPreviewGroups(from: indexAfterRestore)
        let restoredBatch = try #require(groupsAfterRestore["PN"]?.first)
        #expect(restoredBatch.samples.map(\.id) == ["PN102-S1"])
    }

    @Test("trashed samples are hidden from Workbench sidecar search and single-sample Gallery, while shared multi-sample charts stay visible")
    func searchAndGalleryIsolation() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        let sampleA = makeSample(id: "PN103-A", displayName: "PN103-A", batchId: "PN103")
        let sampleB = makeSample(id: "PN103-B", displayName: "PN103-B", batchId: "PN103")
        let batch = makeBatch(id: "PN103", sampleKeys: ["PN103-A", "PN103-B"])
        try store.createDrawer(for: sampleA, batch: batch, rootURL: root)
        try store.createDrawer(for: sampleB, batch: batch, rootURL: root)

        // Add sidecars for A and B
        for sk in ["PN103-A", "PN103-B"] {
            let dir = store.sampleDirectoryURL(root, batchID: "PN103", sampleKey: sk)
            let measDir = dir.appending(path: "measurements", directoryHint: .isDirectory)
            let sidecarURL = measDir.appending(path: "\(sk).spinlab.json")
            let sidecar = SpinLabFileSidecar(
                workflow: "AHE",
                workflowDisplayName: "AHE",
                channels: [],
                sourceFilePath: measDir.appending(path: "\(sk).dat").path,
                appliedAt: Date(),
                ruleSnapshot: SidecarRuleSnapshot(
                    ruleSetVersion: 1,
                    ruleSetFingerprint: "test",
                    appliedAt: Date(),
                    fields: SidecarRuleFields(sampleID: nil, conditions: [:], substrateTags: [])
                ),
                sampleKey: sk
            )
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            try enc.encode(sidecar).write(to: sidecarURL)
            try Data("x,y\n".utf8).write(to: measDir.appending(path: "\(sk).dat"))
        }

        // Add single-sample chart for A and shared chart for A+B
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let indexStore = LibraryChartIndexStore(layout: layout)
        let singleRefA = WorkbenchResultReference(
            chartIdentityKey: "single-A",
            chartImagePath: "samples/PN103-A/charts/single-A.png",
            manifestPath: "samples/PN103-A/charts/single-A.manifest.json",
            workflowID: "AHE",
            generatedAt: Date()
        )
        let sharedRef = WorkbenchResultReference(
            chartIdentityKey: "shared-AB",
            chartImagePath: "_spinlab/multi-sample/charts/shared.png",
            manifestPath: "_spinlab/multi-sample/charts/shared.manifest.json",
            workflowID: "AHE",
            generatedAt: Date()
        )
        let urlA = try layout.resultsIndexURL(sampleKey: "PN103-A")
        try FileManager.default.createDirectory(at: urlA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try indexStore.encodeResultsIndex(WorkbenchResultsIndex(sampleKey: "PN103-A", updatedAt: Date(), references: [singleRefA, sharedRef])).write(to: urlA)

        let urlB = try layout.resultsIndexURL(sampleKey: "PN103-B")
        try FileManager.default.createDirectory(at: urlB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try indexStore.encodeResultsIndex(WorkbenchResultsIndex(sampleKey: "PN103-B", updatedAt: Date(), references: [sharedRef])).write(to: urlB)

        // Trash sample A
        _ = try store.moveSampleToTrash(sample: sampleA, rootURL: root)

        // Workbench sidecar search should return only B
        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "AHE"),
            libraryRootURL: root
        )
        #expect(hits.map(\.sampleKey) == ["PN103-B"])

        // Workflow Gallery should hide single-A and keep shared-AB
        let gallery = WorkflowGalleryQueryService(libraryRootURL: root).execute()
        #expect(gallery.items.map(\.chartIdentityKey) == ["shared-AB"])
    }

    @Test("Registry diff skips trashed samples without resurrecting or triggering removal refusal")
    func registryDiffIsolatesTrashedSamples() {
        let engine = LibraryDiffEngine()
        let trashed = makeSample(
            id: "PN104-TRASH",
            displayName: "PN104-TRASH",
            batchId: "PN104",
            metadata: ["Note": "old"],
            origin: nil,
            deletedAt: Date()
        )
        let active = makeSample(
            id: "PN104-ACTIVE",
            displayName: "PN104-ACTIVE",
            batchId: "PN104",
            metadata: ["Note": "old"],
            origin: nil,
            deletedAt: nil
        )
        let current = makeIndex(
            batches: [makeBatch(id: "PN104", sampleKeys: ["PN104-TRASH", "PN104-ACTIVE"], origin: nil)],
            samples: [trashed, active]
        )

        // Case 1: Trashed sample still in Registry with updated metadata -> skipped, not changed
        var incomingTrashed = trashed
        incomingTrashed.deletedAt = nil
        incomingTrashed.metadata = ["Note": "new"]
        var incomingActive = active
        incomingActive.metadata = ["Note": "new"]

        let diffWithTrashedPresent = engine.diff(
            current: current,
            updated: makeIndex(
                batches: [makeBatch(id: "PN104", sampleKeys: ["PN104-TRASH", "PN104-ACTIVE"], origin: nil)],
                samples: [incomingTrashed, incomingActive]
            )
        )
        #expect(diffWithTrashedPresent.changedSamples.map(\.sample.id) == ["PN104-ACTIVE"])
        #expect(diffWithTrashedPresent.removedSamples.isEmpty)

        // Case 2: Trashed sample missing from Registry -> NOT in removedSamples; active sample still protected
        let diffWithTrashedRemoved = engine.diff(
            current: current,
            updated: makeIndex(
                batches: [makeBatch(id: "PN104", sampleKeys: ["PN104-ACTIVE"], origin: nil)],
                samples: [incomingActive]
            )
        )
        #expect(diffWithTrashedRemoved.removedSamples.isEmpty)
        #expect(diffWithTrashedRemoved.changedSamples.map(\.sample.id) == ["PN104-ACTIVE"])

        // Case 3: Active sample missing from Registry -> still goes into removedSamples
        let diffWithActiveRemoved = engine.diff(
            current: current,
            updated: makeIndex(
                batches: [makeBatch(id: "PN104", sampleKeys: [], origin: nil)],
                samples: []
            )
        )
        #expect(diffWithActiveRemoved.removedSamples.map(\.id) == ["PN104-ACTIVE"])
    }

    @Test("permanent delete requires trash, deletes only sample own folders, preserves shared multi-sample charts, and keeps batch delete closed")
    func permanentDeleteSafetyAndSharedChartPreservation() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        let sampleA = makeSample(id: "PN105-A", displayName: "PN105-A", batchId: "PN105")
        let sampleB = makeSample(id: "PN105-B", displayName: "PN105-B", batchId: "PN105")
        let batch = makeBatch(id: "PN105", sampleKeys: ["PN105-A", "PN105-B"])
        try store.createDrawer(for: sampleA, batch: batch, rootURL: root)
        try store.createDrawer(for: sampleB, batch: batch, rootURL: root)

        // Non-trashed sample cannot be permanently deleted
        #expect(throws: LibraryDrawerError.permanentDeleteRequiresTrash(sampleId: "PN105-A")) {
            try store.permanentlyDeleteTrashedSample(sample: sampleA, rootURL: root)
        }

        // Batch deletion remains closed
        #expect(throws: LibraryDrawerError.deletionDisabled) {
            try store.deleteBatchDrawer(batchID: "PN105", rootURL: root)
        }

        // Create shared chart and per-sample artifacts
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let sharedDir = root.appending(path: "_spinlab/multi-sample/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let sharedPNG = sharedDir.appending(path: "shared.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sharedPNG)

        let singleDirA = root.appending(path: "samples/PN105-A/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: singleDirA, withIntermediateDirectories: true)
        try Data([0x01]).write(to: singleDirA.appending(path: "a.png"))

        let resultsBURL = try layout.resultsIndexURL(sampleKey: "PN105-B")
        try FileManager.default.createDirectory(at: resultsBURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let resultsBData = Data("{\"schemaVersion\":1}".utf8)
        try resultsBData.write(to: resultsBURL)

        // Trash A then permanently delete A
        let trashedA = try store.moveSampleToTrash(sample: sampleA, rootURL: root)
        try store.permanentlyDeleteTrashedSample(sample: trashedA, rootURL: root)

        let drawerA = store.sampleDirectoryURL(root, batchID: "PN105", sampleKey: "PN105-A")
        #expect(!FileManager.default.fileExists(atPath: drawerA.path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "samples/PN105-A").path))

        // Shared chart and sample B's index remain untouched
        #expect(FileManager.default.fileExists(atPath: sharedPNG.path))
        #expect(try Data(contentsOf: resultsBURL) == resultsBData)

        // batch.json and library_index.json updated
        let batchJSON = store.resolvedBatchDirectoryURL(root, batchID: "PN105").appending(path: "batch.json")
        let updatedBatch = try #require(store.decodeBatch(from: batchJSON))
        #expect(updatedBatch.sampleKeys == ["PN105-B"])
        let updatedIndex = try #require(store.loadIndex(from: root))
        #expect(updatedIndex.samples.map(\.id) == ["PN105-B"])
    }

    @Test("AppRouter round-trips library/trash route")
    func routerRoundTripsLibraryTrash() {
        let router = AppRouter()
        #expect(router.routePath(for: .libraryTrash) == .libraryTrash)
        #expect(router.deepLink(for: .libraryTrash) == "library/trash")
        #expect(router.deepLinkToRouteStack("library/trash")?.terminalPath == .libraryTrash)
    }
}
