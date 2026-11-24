import Foundation
import Testing
@testable import SpinLabApp

@Suite("Storage v2 Layout Routing & Write Protection (Task 10A)")
struct StorageV2LayoutRoutingTests {
    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SpinLab_Task10A_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func assertV2Invariants(at rootURL: URL) throws {
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: rootURL.appending(path: "batches").path), "V2 must not create top-level batches/")
        #expect(!fm.fileExists(atPath: rootURL.appending(path: "samples").path), "V2 must not create top-level samples/")

        let samplesRoot = rootURL.appending(path: "records/samples")
        if fm.fileExists(atPath: samplesRoot.path) {
            let entries = try fm.contentsOfDirectory(at: samplesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            var seenUIDs: Set<String> = []
            let store = LibraryStore()
            for entry in entries {
                let sampleJSON = entry.appending(path: "sample.json")
                if fm.fileExists(atPath: sampleJSON.path), let sample = store.decodeSample(from: sampleJSON) {
                    let uid = sample.sampleUID ?? sample.id
                    #expect(seenUIDs.insert(uid).inserted, "Duplicate sampleUID \(uid) found in V2 tree")
                }
            }
        }
    }

    // MARK: - 1. V1 Regression (both batch path forms)

    @Test("Unmarked V1 libraries (preferred, legacy, and mixed) resolve as V1 and work without regression")
    func v1BothBatchFormsWork() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        #expect(store.resolveLayout(at: root) == .v1)

        // Create a legacy-layout batch directly under batches/<batchID>/
        let legacyBatchURL = store.legacyBatchDirectoryURL(root, batchID: "PN101")
        let legacySampleURL = legacyBatchURL.appending(path: "samples/PN101-STO", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacySampleURL, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyBatch = LibraryBatch(
            id: "PN101", displayName: "PN101", sheetName: "", metadata: [:],
            numericTags: [:], numericDisplay: [:], sampleKeys: ["PN101-STO"], updatedAt: now
        )
        let legacySample = LibrarySample(
            id: "PN101-STO", displayName: "PN101 - STO", batchId: "PN101",
            substrateRaw: "STO(001)", substrateDisplay: "STO(001)", substrateTokens: ["STO", "001"],
            substrateTags: ["STO"], metadata: [:], numericTags: [:], numericDisplay: [:],
            updatedAt: now, sampleUID: SampleIdentityRule.makeRandomUID()
        )
        try store.writeBatchChecked(legacyBatch, to: legacyBatchURL)
        try store.writeSampleChecked(legacySample, to: legacySampleURL)

        // Create a preferred-layout batch via NativeSampleCreationService
        let creation = NativeSampleCreationService()
        let outcome = creation.createSample(
            draft: CreateNativeSampleDraft(batchId: "PN102", substrateDescription: "MgO(001)"),
            rootURL: root,
            libraryStore: store,
            settings: .default
        )
        guard case .success(let createdSample, _, let synced) = outcome else {
            Issue.record("Expected V1 preferred batch creation to succeed, got \(outcome)")
            return
        }
        #expect(synced.batches.contains(where: { $0.id == "PN101" }))
        #expect(synced.batches.contains(where: { $0.id == "PN102" }))
        #expect(synced.samples.contains(where: { $0.id == "PN101-STO" }))
        #expect(synced.samples.contains(where: { $0.id == createdSample.id }))

        // Trash, restore, permanent delete on V1
        let trashed = try store.moveSampleToTrash(sample: createdSample, rootURL: root)
        #expect(trashed.isTrashed)
        let restored = try store.restoreSampleFromTrash(sample: trashed, rootURL: root)
        #expect(!restored.isTrashed)
        let trashedAgain = try store.moveSampleToTrash(sample: restored, rootURL: root)
        try store.permanentlyDeleteTrashedSample(sample: trashedAgain, rootURL: root)
        let afterDelete = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(!afterDelete.samples.contains(where: { $0.id == createdSample.id }))
    }

    // MARK: - 2. Version detection & fail-closed matrix

    @Test("Layout router fail-closed matrix rejects unmarked records, unknown versions, corrupt markers, and mixed layouts")
    func failClosedLayoutMatrix() throws {
        let store = LibraryStore()

        // 2a. records/ without layout_version.json
        let unmarkedRecords = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: unmarkedRecords) }
        try FileManager.default.createDirectory(at: unmarkedRecords.appending(path: "records/batches"), withIntermediateDirectories: true)
        #expect(store.resolveLayout(at: unmarkedRecords) == .invalid(.missingVersionMarkerForRecords))
        #expect(throws: LibraryLayoutError.self) { try store.ensureRootDirectories(at: unmarkedRecords) }
        #expect(!store.scanIndexFromFilesystem(rootURL: unmarkedRecords).issues.isEmpty)

        // 2b. Unknown version
        let unknownVersion = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: unknownVersion) }
        try FileManager.default.createDirectory(at: unknownVersion.appending(path: "_spinlab"), withIntermediateDirectories: true)
        try Data("{\"version\": 99}".utf8).write(to: unknownVersion.appending(path: "_spinlab/layout_version.json"))
        #expect(store.resolveLayout(at: unknownVersion) == .invalid(.unknownVersion(99)))
        #expect(throws: LibraryLayoutError.self) { try store.ensureRootDirectories(at: unknownVersion) }

        // 2c. Corrupt JSON marker
        let corruptMarker = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: corruptMarker) }
        try FileManager.default.createDirectory(at: corruptMarker.appending(path: "_spinlab"), withIntermediateDirectories: true)
        try Data("{not valid json".utf8).write(to: corruptMarker.appending(path: "_spinlab/layout_version.json"))
        #expect(store.resolveLayout(at: corruptMarker).isInvalid)
        #expect(throws: LibraryLayoutError.self) { try store.ensureRootDirectories(at: corruptMarker) }

        // 2d. Mixed batches/ + records/
        let mixed = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: mixed) }
        try FileManager.default.createDirectory(at: mixed.appending(path: "batches"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mixed.appending(path: "records"), withIntermediateDirectories: true)
        #expect(store.resolveLayout(at: mixed).isInvalid)
        #expect(throws: LibraryLayoutError.self) { try store.ensureRootDirectories(at: mixed) }

        // 2e. Marker v2 + batches/ present
        let v2PlusBatches = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: v2PlusBatches) }
        try store.initializeV2Library(at: v2PlusBatches)
        try FileManager.default.createDirectory(at: v2PlusBatches.appending(path: "batches"), withIntermediateDirectories: true)
        #expect(store.resolveLayout(at: v2PlusBatches).isInvalid)
        #expect(throws: LibraryIndexSyncError.self) { try store.syncIndexFromFilesystem(rootURL: v2PlusBatches) }

        // 2f. Marker v2 without records/
        let v2MissingRecords = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: v2MissingRecords) }
        try LibraryLayoutRouter.writeV2Marker(at: v2MissingRecords)
        #expect(store.resolveLayout(at: v2MissingRecords).isInvalid)

        // 2g. Marker v2 with records/ but missing records/samples/ must fail-closed and never recreate empty directory
        let v2MissingSamples = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: v2MissingSamples) }
        try store.initializeV2Library(at: v2MissingSamples)
        try FileManager.default.removeItem(at: store.v2SamplesDirectoryURL(v2MissingSamples))
        #expect(store.resolveLayout(at: v2MissingSamples).isInvalid)
        #expect(throws: LibraryLayoutError.self) { try store.ensureRootDirectories(at: v2MissingSamples) }
        #expect(!FileManager.default.fileExists(atPath: store.v2SamplesDirectoryURL(v2MissingSamples).path))

        // 2h. Marker v2 with records/ but missing records/batches/ must fail-closed
        let v2MissingBatches = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: v2MissingBatches) }
        try store.initializeV2Library(at: v2MissingBatches)
        try FileManager.default.removeItem(at: store.v2BatchesDirectoryURL(v2MissingBatches))
        #expect(store.resolveLayout(at: v2MissingBatches).isInvalid)
        #expect(throws: LibraryLayoutError.self) { try store.ensureRootDirectories(at: v2MissingBatches) }
        #expect(!FileManager.default.fileExists(atPath: store.v2BatchesDirectoryURL(v2MissingBatches).path))
    }

    // MARK: - 3. V2 unique records, sampleKeys retirement, duplicate UID rejection, and trash/delete

    @Test("V2 creates unique records under records/, omits sampleKeys on disk, and rejects duplicate sampleUID")
    func v2UniqueRecordsAndSampleKeysRetirement() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        try store.initializeV2Library(at: root)
        #expect(store.resolveLayout(at: root) == .v2)

        // ensureRoot on V2 must not create batches/ or run legacy migration
        store.ensureRoot(at: root)
        try assertV2Invariants(at: root)

        let creation = NativeSampleCreationService()
        let uid1 = SampleIdentityRule.makeRandomUID()
        let outcome1 = creation.createSample(
            draft: CreateNativeSampleDraft(batchId: "PN200", substrateDescription: "STO(001)", sampleUID: uid1),
            rootURL: root,
            libraryStore: store,
            settings: .default
        )
        guard case .success(let sample1, _, _) = outcome1 else {
            Issue.record("Expected V2 sample creation to succeed, got \(outcome1)")
            return
        }
        #expect(sample1.id == uid1)

        // Verify disk paths
        let expectedSampleJSON = root.appending(path: "records/samples/\(uid1)/sample.json")
        let expectedBatchJSON = root.appending(path: "records/batches/PN200/batch.json")
        #expect(FileManager.default.fileExists(atPath: expectedSampleJSON.path))
        #expect(FileManager.default.fileExists(atPath: expectedBatchJSON.path))

        // Verify batch.json on disk omits "sampleKeys"
        let batchRaw = try String(contentsOf: expectedBatchJSON, encoding: .utf8)
        #expect(!batchRaw.contains("sampleKeys"), "V2 batch.json on disk must omit sampleKeys")

        // Verify in-memory index derives batch.sampleKeys from sample.batchId
        let index = try store.readOnlyCompleteIndex(rootURL: root)
        let batchInIndex = try #require(index.batches.first(where: { $0.id == "PN200" }))
        #expect(batchInIndex.sampleKeys == [uid1])

        // Duplicate sampleUID in a second directory must fail-closed
        let dupDir = root.appending(path: "records/samples/smp_duplicate_folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dupDir, withIntermediateDirectories: true)
        try store.writeSampleChecked(sample1, to: dupDir)
        let dupScan = store.scanIndexFromFilesystem(rootURL: root)
        #expect(!dupScan.issues.isEmpty, "Duplicate sampleUID must fail-closed")
        try FileManager.default.removeItem(at: dupDir)

        // Trash -> restore -> permanent delete on V2
        let trashed = try store.moveSampleToTrash(sample: sample1, rootURL: root)
        #expect(trashed.isTrashed)
        try store.permanentlyDeleteTrashedSample(sample: trashed, rootURL: root)
        #expect(!FileManager.default.fileExists(atPath: expectedSampleJSON.path))
        try assertV2Invariants(at: root)
    }

    // MARK: - 4. Result preservation on V2

    @Test("Result Definitions and Sample Result values work on V2 without touching V1 paths")
    func v2ResultPreservation() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        try store.initializeV2Library(at: root)
        let creation = NativeSampleCreationService()
        let uid = SampleIdentityRule.makeRandomUID()
        guard case .success(let sample, _, _) = creation.createSample(
            draft: CreateNativeSampleDraft(batchId: "PN300", substrateDescription: "LAO(001)", sampleUID: uid),
            rootURL: root,
            libraryStore: store,
            settings: .default
        ) else {
            Issue.record("Failed to create V2 sample")
            return
        }

        let resultService = LibraryResultService(libraryStore: store)
        let def = try resultService.createDefinition(name: "Hc", unit: "Oe", qualifier: "300 K", rootURL: root)
        let updated = try resultService.setValue(
            sample: sample,
            definitionID: def.definitionID,
            newValue: 125.5,
            expectedCurrent: nil,
            rootURL: root
        )
        #expect(updated.results?[def.definitionID]?.value == 125.5)
        #expect(try resultService.usageCount(definitionID: def.definitionID, rootURL: root) == 1)

        try assertV2Invariants(at: root)
    }

    // MARK: - 5. Unmigrated consumer V2 write protection

    @Test("Unmigrated V1 artifact/sidecar/measurement/chart writers refuse on V2 without creating V1 paths")
    func unmigratedConsumersRefuseOnV2() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LibraryStore()
        try store.initializeV2Library(at: root)
        let uid = SampleIdentityRule.makeRandomUID()
        guard case .success(let sample, _, let index) = NativeSampleCreationService().createSample(
            draft: CreateNativeSampleDraft(batchId: "PN400", substrateDescription: "STO(001)", sampleUID: uid),
            rootURL: root,
            libraryStore: store,
            settings: .default
        ) else {
            Issue.record("Failed to create V2 sample")
            return
        }

        let resolver = LibraryPathResolver(libraryRootURL: root)
        let writer = AtomicFileWriter()

        // 1. PersistChartArtifactUseCase
        let chartUseCase = PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
        let payload = WorkbenchPlotPayload(
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            title: "Test",
            axisMapping: WorkbenchAxisMapping(xField: "H", yField: "R"),
            series: [WorkbenchPlotSeries(label: "S1", x: [0, 1], y: [0, 1])]
        )
        #expect(throws: LibraryLayoutError.self) {
            _ = try chartUseCase.execute(sampleKeys: [sample.id], payload: payload, imageData: Data([0x89, 0x50]))
        }

        // 2. PersistMeasurementDataUseCase
        let metricUseCase = PersistMeasurementDataUseCase(writer: writer, pathResolver: resolver)
        let record = WorkbenchMetricRecord(
            recordID: "rec_1",
            sampleKey: sample.id,
            displayKey: sample.displayName,
            workflowID: "ahe",
            metric: "Hc",
            value: 10,
            canonicalUnit: "Oe",
            conditions: ["temperature": "300 K"],
            generatedAt: Date(),
            runID: "run_1"
        )
        #expect(throws: LibraryLayoutError.self) {
            try metricUseCase.execute(sampleKey: sample.id, record: record)
        }

        // 3. LibraryStore+Measurements & MeasurementSets
        let dummyFile = root.appending(path: "tmp_source.dat")
        try Data("x,y\n0,1\n".utf8).write(to: dummyFile)
        defer { try? FileManager.default.removeItem(at: dummyFile) }
        #expect(store.copyMeasurementFile(from: dummyFile.path, to: sample, rootURL: root) == nil)
        #expect(throws: LibraryLayoutError.self) {
            try store.saveMeasurementSets([MeasurementSet(id: "s1", name: "Set 1", workflow: "ahe", memberFileNames: [], createdAt: Date())], for: sample, rootURL: root)
        }

        // 4. InboxArchiveApplyService
        let pending = SpinLabDomain.PendingImport(
            fileName: "tmp_source.dat",
            sourceFilePath: dummyFile.path,
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
        let target = SpinLabDomain.RouteTarget(sampleId: sample.id)
        #expect(throws: LibraryLayoutError.self) {
            _ = try InboxArchiveApplyService().apply(
                pending: pending,
                targets: [target],
                libraryIndex: index,
                libraryStore: store,
                libraryRootURL: root
            )
        }

        // 5. LegacySampleBackfillService
        #expect(throws: LegacySampleBackfillService.BackfillError.self) {
            _ = try LegacySampleBackfillService().run(libraryStore: store, rootURL: root, dryRun: false)
        }

        // 6. Backup on V2 is refused (no point-in-time consistent copy of SQLite + files yet) and writes nothing
        let backupRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: backupRoot) }
        #expect(store.syncBackup(from: root, to: backupRoot) == false)
        #expect(!FileManager.default.fileExists(atPath: backupRoot.appending(path: "_spinlab/layout_version.json").path))
        #expect(!FileManager.default.fileExists(atPath: backupRoot.appending(path: "records/samples/\(uid)/sample.json").path))

        try assertV2Invariants(at: root)
    }
}
