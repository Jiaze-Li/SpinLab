import Foundation
import Testing
@testable import SpinLabApp

@Suite("Asset storage: ingest, faithful read, K13, sharing (Task 5A)")
struct AssetIngestAndReadTests {
    typealias T = AssetTestSupport

    @Test("Fixture ingest reads back bit-exact (non-square, 3 channels, NaN/Inf), Source bytes preserved, unique Sample ownership")
    func faithfulRoundTrip() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let expected = try T.expectedDataset(from: file)
        let result = try T.ingest(s, file: file, target: s.uidA)

        #expect(result.sourceID.hasPrefix("src_") && result.datasetIDs.count == 1 && result.datasetIDs[0].hasPrefix("dst_"))
        #expect(result.sampleUID == s.uidA)
        let datasetID = result.datasetIDs[0]
        let loaded = try s.service.loadDataset(datasetID: datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(loaded.dataset, expected))
        #expect(loaded.dataset.channels.count == 3)
        #expect(loaded.dataset.channels[0].values.count == 3 && loaded.dataset.channels[0].values[0].count == 5)
        #expect(loaded.dataset.channels[2].values[0][1].isNaN)
        #expect(loaded.dataset.channels[2].values[1][2] == .infinity)
        #expect(loaded.dataset.channels[2].values[2][3] == -.infinity)
        #expect(loaded.sourceAvailability == .available)
        #expect(loaded.revision == 1)

        let stored = try Data(contentsOf: s.root.appending(path: "storage/\(result.sourceID)/payload.bin"))
        #expect(stored == (try Data(contentsOf: file)), "Source bytes must be identical")

        let a = try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root)
        let b = try s.service.listAssets(forSampleUID: s.uidB, rootURL: s.root)
        #expect(Set(a.map(\.id)) == [result.sourceID, datasetID])
        #expect(b.isEmpty)
        #expect(try s.service.derivedSampleUIDs(forAssetID: result.sourceID, rootURL: s.root) == [s.uidA])
        #expect(try s.service.derivedSampleUIDs(forAssetID: datasetID, rootURL: s.root) == [s.uidA])

        let groups = try s.service.listSampleSourceGroups(forSampleUID: s.uidA, rootURL: s.root)
        #expect(groups.count == 1 && groups[0].source.id == result.sourceID && groups[0].datasets.map(\.id) == [datasetID])
    }

    @Test("One Source produces multiple independent Datasets (controlled fixture), derived to one Sample, atomic crash recovery")
    func oneSourceManyDatasets() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture(name: "multi.raw")

        let result = try s.service.ingestAsset(
            sourceFileURL: file,
            adapter: MultiDatasetTestAdapter(),
            targetSampleUID: s.uidA,
            operationID: "multi-op",
            rootURL: s.root
        )
        #expect(result.datasetIDs.count == 2)
        #expect(result.datasetIDs[0] != result.datasetIDs[1])

        let d1 = try s.service.loadDataset(datasetID: result.datasetIDs[0], codec: MultiSliceTestCodec(), rootURL: s.root)
        let d2 = try s.service.loadDataset(datasetID: result.datasetIDs[1], codec: MultiSliceTestCodec(), rootURL: s.root)
        #expect(d1.dataset == MultiSliceTestDataset(sliceID: "300K", values: [1.0, 2.0]))
        #expect(d2.dataset == MultiSliceTestDataset(sliceID: "100K", values: [3.0, 4.0]))

        for dsID in result.datasetIDs {
            #expect(try s.service.derivedSampleUIDs(forAssetID: dsID, rootURL: s.root) == [s.uidA])
        }
        let groups = try s.service.listSampleSourceGroups(forSampleUID: s.uidA, rootURL: s.root)
        #expect(groups.count == 1 && Set(groups[0].datasets.map(\.id)) == Set(result.datasetIDs))

        // Idempotent replay of the whole 1-to-many dataset group
        let replay = try s.service.ingestAsset(
            sourceFileURL: file,
            adapter: MultiDatasetTestAdapter(),
            targetSampleUID: s.uidA,
            operationID: "multi-op",
            rootURL: s.root
        )
        #expect(replay == result)
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 3)

        // Crash before commit on a multi-dataset ingest cleans up all dataset directories.
        let sCrash = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: sCrash.root) }
        sCrash.service.faultHook = { if $0 == .ingestBeforeCommit { throw T.Crash() } }
        #expect(throws: T.Crash.self) {
            _ = try sCrash.service.ingestAsset(
                sourceFileURL: file,
                adapter: MultiDatasetTestAdapter(),
                targetSampleUID: sCrash.uidA,
                operationID: "multi-crash",
                rootURL: sCrash.root
            )
        }
        let report = try LibraryAssetService(libraryStore: sCrash.store).recoverPendingOperations(rootURL: sCrash.root)
        #expect(report.abortedOperations == ["multi-crash"])
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: sCrash.root.appending(path: "storage").path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test("SQLite enforces unique Source->Sample, source-only links, and unique Dataset->Source cardinality")
    func sqliteOwnershipAndCardinalityConstraints() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s, target: s.uidA)
        let datasetID = r.datasetIDs[0]
        let db = try #require(try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false))

        // Cannot assign a second Sample owner to the same Source
        #expect(throws: LibraryAssetError.self) {
            try db.execute(
                "INSERT INTO sample_asset_links(asset_id, sample_uid, ownership_status, linked_at) VALUES (?, ?, 'active', '2026-01-01T00:00:00Z');",
                [.text(r.sourceID), .text(s.uidB)]
            )
        }
        // Cannot link a Dataset directly in sample_asset_links
        #expect(throws: LibraryAssetError.self) {
            try db.execute(
                "INSERT INTO sample_asset_links(asset_id, sample_uid, ownership_status, linked_at) VALUES (?, ?, 'active', '2026-01-01T00:00:00Z');",
                [.text(datasetID), .text(s.uidA)]
            )
        }
        // Cannot add a second Source for the same Dataset
        let r2 = try T.ingest(s, file: try T.writeFixture(seed: 9), target: s.uidB)
        #expect(throws: LibraryAssetError.self) {
            try db.execute(
                "INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, 'dataset_source', NULL);",
                [.text(datasetID), .text(r2.sourceID)]
            )
        }
        // Cannot register a Plot/Snapshot directly on a Source (only Dataset inputs are allowed)
        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.registerDerivedAsset(kind: "plot", inputAssetIDs: [r.sourceID], rootURL: s.root)
        }
    }

    @Test("Unknown/non-length data units are kept as-is, never relabelled as nm")
    func unknownUnitStaysUnknown() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let result = try T.ingest(s, file: try T.writeFixture(dataUnit: "V"))
        let loaded = try s.service.loadDataset(datasetID: result.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(loaded.dataset.channels.allSatisfy { $0.canonicalUnit == "V" && $0.sourceUnit == "V" })
    }

    @Test("Corrupt / unsupported IBW never becomes Ready and leaves nothing behind")
    func corruptSourceRejected() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        var bytes = T.fixtureIBW()
        bytes[100] ^= 0xFF
        let dir = FileManager.default.temporaryDirectory.appending(path: "SpinLab_Task5A_bad_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = dir.appending(path: "bad.ibw")
        try bytes.write(to: bad)
        #expect(throws: IBWReadError.self) { try T.ingest(s, file: bad) }
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).isEmpty)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage").path)) ?? []
        #expect(entries.isEmpty)
    }

    @Test("Standard data reads without the Source; Source problems are reported separately; damaged dataset fails closed")
    func independentReadAndDiagnostics() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let expected = try T.expectedDataset(from: file)
        let r = try T.ingest(s, file: file)
        let payload = s.root.appending(path: "storage/\(r.sourceID)/payload.bin")

        let original = try Data(contentsOf: payload)
        try FileManager.default.removeItem(at: payload)
        var loaded = try s.service.loadDataset(datasetID: r.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(loaded.dataset, expected))
        #expect(loaded.sourceAvailability == .missing)

        try Data(original.dropLast()).write(to: payload)
        loaded = try s.service.loadDataset(datasetID: r.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        if case .corrupt = loaded.sourceAvailability {} else { Issue.record("expected corrupt source, got \(loaded.sourceAvailability)") }
        #expect(T.bitEqual(loaded.dataset, expected))

        let matrices = s.root.appending(path: "storage/\(r.datasetIDs[0])/rev_1/matrices.bin")
        var blob = try Data(contentsOf: matrices)
        blob[0] ^= 0x01
        try blob.write(to: matrices)
        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.loadDataset(datasetID: r.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        }
    }

    @Test("Missing / corrupt / unknown-version database fails closed instead of reading as empty (K13)")
    func databaseFailClosed() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        // Never enabled: reads are empty.
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).isEmpty)
        try T.ingest(s)
        let spinlab = s.root.appending(path: "_spinlab")

        // Unknown schema version
        do {
            let db = try #require(try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false))
            try db.execute("UPDATE schema_meta SET value = '99' WHERE key = 'schema_version';")
        }
        #expect(throws: LibraryAssetError.databaseUnknownVersion("99")) {
            _ = try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root)
        }
        // Corrupt file
        for entry in try FileManager.default.contentsOfDirectory(atPath: spinlab.path) where entry.hasPrefix("library.sqlite") {
            try FileManager.default.removeItem(at: spinlab.appending(path: entry))
        }
        try Data("this is not sqlite at all, just garbage bytes".utf8).write(to: spinlab.appending(path: "library.sqlite"))
        #expect(throws: LibraryAssetError.self) { _ = try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root) }
        #expect(throws: LibraryAssetError.self) { try T.ingest(s) }

        // Missing database but storage is not empty: relations lost, must not be rebuilt as empty.
        try FileManager.default.removeItem(at: spinlab.appending(path: "library.sqlite"))
        #expect(throws: LibraryAssetError.databaseRelationsLost) {
            _ = try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root)
        }
        #expect(throws: LibraryAssetError.databaseRelationsLost) { try T.ingest(s) }
        #expect(!FileManager.default.fileExists(atPath: spinlab.appending(path: "library.sqlite").path))
    }

    @Test("Same operation submitted twice yields one result; trash / restore keep assets and ownership")
    func idempotencyAndLinks() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let r1 = try T.ingest(s, file: file, op: "op-1")
        let r2 = try T.ingest(s, file: file, op: "op-1")
        #expect(r1 == r2)
        // Replaying the same committed operationID with a different target sample must fail closed
        #expect(throws: LibraryAssetError.self) {
            _ = try T.ingest(s, file: file, target: s.uidB, op: "op-1")
        }
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 2)
        #expect(T.exists(s, "storage/\(r1.datasetIDs[0])/rev_1/matrices.bin"))

        let trashed = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        #expect(T.exists(s, "storage/\(r1.datasetIDs[0])/rev_1/matrices.bin"))
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 2)
        _ = try s.store.restoreSampleFromTrash(sample: trashed, rootURL: s.root)
        #expect(try s.service.derivedSampleUIDs(forAssetID: r1.datasetIDs[0], rootURL: s.root) == [s.uidA])
    }

    @Test("Same-sample source reuse succeeds; cross-sample source reuse is forbidden")
    func duplicateSourceReuse() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let r1 = try T.ingest(s, file: file, target: s.uidA)
        let sha = AssetHashing.sha256Hex(try Data(contentsOf: file))
        #expect(try s.service.findSources(sha256: sha, ownedBySampleUID: s.uidA, rootURL: s.root).map(\.id) == [r1.sourceID])
        #expect(try s.service.findSources(sha256: sha, ownedBySampleUID: s.uidB, rootURL: s.root).isEmpty)

        // Same-sample reuse succeeds
        let r2 = try T.ingest(s, file: file, target: s.uidA, reuse: r1.sourceID)
        #expect(r2.reusedSource && r2.sourceID == r1.sourceID && r2.datasetIDs != r1.datasetIDs)

        // Cross-sample reuse is rejected
        #expect(throws: LibraryAssetError.self) {
            _ = try T.ingest(s, file: file, target: s.uidB, reuse: r1.sourceID)
        }
        let other = try T.writeFixture(seed: 5)
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, file: other, target: s.uidA, reuse: r1.sourceID) }
    }

    @Test("Ingest on V1 libraries and for invalid/empty/trashed targets is refused")
    func guards() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, target: "smp_not-a-real-one") }
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, target: "") }
        _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, target: s.uidA) }

        let v1 = FileManager.default.temporaryDirectory.appending(path: "SpinLab_Task5A_v1_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: v1) }
        let store = LibraryStore()
        try FileManager.default.createDirectory(at: v1, withIntermediateDirectories: true)
        try store.ensureRootDirectories(at: v1)
        #expect(throws: LibraryAssetError.v2Required) {
            _ = try s.service.listAssets(forSampleUID: s.uidA, rootURL: v1)
        }
    }

    @Test("Ingest crashes before the commit point leave no visible or leftover data and can be retried")
    func ingestCrashRecovery() throws {
        for point in [AssetFaultPoint.ingestAfterSourceWritten, .ingestBeforeCommit] {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            s.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) { try T.ingest(s, op: "crash-op") }
            // Nothing is visible while staging.
            #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).isEmpty)

            let restarted = LibraryAssetService(libraryStore: s.store)
            let report = try restarted.recoverPendingOperations(rootURL: s.root)
            #expect(report.abortedOperations == ["crash-op"])
            #expect(report.unknownResidue.isEmpty)
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage").path)) ?? []
            #expect(leftovers.isEmpty, "no orphan directories after recovery (\(point))")

            let retry = try restarted.ingestAsset(
                sourceFileURL: try T.writeFixture(), adapter: AFMIBWStandardizationAdapter(),
                targetSampleUID: s.uidA, operationID: "crash-op", rootURL: s.root
            )
            #expect(try restarted.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 2)
            #expect(retry.datasetRevision == 1)
        }
    }

    private static var configuredRealIBWPath: String? {
        guard let raw = ProcessInfo.processInfo.environment["SPINLAB_REAL_IBW"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    // Regular test runs without SPINLAB_REAL_IBW explicitly mark this test as skipped so CI and
    // other developer machines stay green without committing real instrument data. Local real-file
    // acceptance MUST set SPINLAB_REAL_IBW and observe this test execute and pass; if set to a
    // missing or empty file, the test fails explicitly.
    @Test(
        "Real instrument .ibw (isolated copy): source/standard comparison, restart read, Source removed",
        .enabled(if: configuredRealIBWPath != nil, "SPINLAB_REAL_IBW not set; real-file acceptance separated from regular test runs")
    )
    func realFileRoundTrip() throws {
        guard let path = Self.configuredRealIBWPath else {
            Issue.record("SPINLAB_REAL_IBW must be set when real-file acceptance is enabled")
            return
        }
        guard FileManager.default.fileExists(atPath: path),
              let original = try? Data(contentsOf: URL(fileURLWithPath: path)), !original.isEmpty else {
            Issue.record("REQUIRED real AFM sample at SPINLAB_REAL_IBW='\(path)' not found or empty")
            return
        }
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let copyDir = FileManager.default.temporaryDirectory.appending(path: "SpinLab_Task5A_real_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: copyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: copyDir) }
        let copy = copyDir.appending(path: "real.ibw")
        try original.write(to: copy)

        let expected = try T.expectedDataset(from: copy)
        let r = try T.ingest(s, file: copy)
        let restarted = LibraryAssetService(libraryStore: LibraryStore())
        let loaded = try restarted.loadDataset(datasetID: r.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(loaded.dataset, expected))
        #expect(loaded.dataset.channels.count >= 1)
        #expect(try Data(contentsOf: s.root.appending(path: "storage/\(r.sourceID)/payload.bin")) == original)

        try FileManager.default.removeItem(at: copy)
        try FileManager.default.removeItem(at: s.root.appending(path: "storage/\(r.sourceID)/payload.bin"))
        let again = try restarted.loadDataset(datasetID: r.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(again.dataset, expected))
        #expect(again.sourceAvailability == .missing)
    }

    @Test("Corrupt AFM manifest with overflowing matrix dimensions or channel byte offsets throws CodecError instead of trapping")
    func corruptManifestOverflowThrows() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let dataset = try T.expectedDataset(from: file)
        let encoded = try AFMDatasetCodec().encode(dataset)
        let manifestData = try #require(encoded.files.first(where: { $0.name == AFMDatasetCodec.manifestName })?.data)
        let blobData = try #require(encoded.files.first(where: { $0.name == AFMDatasetCodec.matricesName })?.data)
        let manifest = try JSONDecoder().decode(AFMDatasetCodec.Manifest.self, from: manifestData)

        let overflowManifest = AFMDatasetCodec.Manifest(
            schemaVersion: manifest.schemaVersion,
            format: manifest.format,
            title: manifest.title,
            xUnit: manifest.xUnit,
            yUnit: manifest.yUnit,
            nX: Int.max,
            nY: 2,
            xCoordinates: manifest.xCoordinates,
            yCoordinates: manifest.yCoordinates,
            sourceMetadata: manifest.sourceMetadata,
            matricesSHA256: manifest.matricesSHA256,
            matricesByteLength: manifest.matricesByteLength,
            channels: manifest.channels
        )
        let badManifestData = try JSONEncoder().encode(overflowManifest)
        #expect(throws: AFMDatasetCodec.CodecError.self) {
            _ = try AFMDatasetCodec().decode(files: [
                AFMDatasetCodec.manifestName: badManifestData,
                AFMDatasetCodec.matricesName: blobData
            ])
        }

        if let first = manifest.channels.first {
            let overflowChannel = AFMDatasetCodec.Manifest.Channel(
                id: first.id,
                sourceIndex: first.sourceIndex,
                sourceLabel: first.sourceLabel,
                semanticTypeRaw: first.semanticTypeRaw,
                displayLabel: first.displayLabel,
                canonicalUnit: first.canonicalUnit,
                sourceUnit: first.sourceUnit,
                provenance: first.provenance,
                byteOffset: Int.max,
                byteLength: first.byteLength,
                dtype: first.dtype,
                nonFiniteCount: first.nonFiniteCount
            )
            let channelOverflowManifest = AFMDatasetCodec.Manifest(
                schemaVersion: manifest.schemaVersion,
                format: manifest.format,
                title: manifest.title,
                xUnit: manifest.xUnit,
                yUnit: manifest.yUnit,
                nX: manifest.nX,
                nY: manifest.nY,
                xCoordinates: manifest.xCoordinates,
                yCoordinates: manifest.yCoordinates,
                sourceMetadata: manifest.sourceMetadata,
                matricesSHA256: manifest.matricesSHA256,
                matricesByteLength: manifest.matricesByteLength,
                channels: [overflowChannel] + Array(manifest.channels.dropFirst())
            )
            let channelBadData = try JSONEncoder().encode(channelOverflowManifest)
            #expect(throws: AFMDatasetCodec.CodecError.self) {
                _ = try AFMDatasetCodec().decode(files: [
                    AFMDatasetCodec.manifestName: channelBadData,
                    AFMDatasetCodec.matricesName: blobData
                ])
            }
        }
    }

    @Test("Corrupt files_json in SQLite fails closed instead of decoding as empty file list (K13)")
    func corruptFilesJSONFailsClosed() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s)
        do {
            let db = try #require(try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false))
            try db.execute("UPDATE assets SET files_json = '{not-json' WHERE asset_id = ?;", [.text(r.datasetIDs[0])])
        }
        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root)
        }
        _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
        }
    }
}
