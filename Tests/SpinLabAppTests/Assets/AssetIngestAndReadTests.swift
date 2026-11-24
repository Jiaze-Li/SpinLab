import Foundation
import Testing
@testable import SpinLabApp

@Suite("Asset storage: ingest, faithful read, K13, sharing (Task 5A)")
struct AssetIngestAndReadTests {
    typealias T = AssetTestSupport

    @Test("Fixture ingest reads back bit-exact (non-square, 3 channels, NaN/Inf), Source bytes preserved, two samples share IDs")
    func faithfulRoundTrip() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let expected = try T.expectedDataset(from: file)
        let result = try T.ingest(s, file: file, targets: [s.uidA, s.uidB])

        #expect(result.sourceID.hasPrefix("src_") && result.datasetID.hasPrefix("dst_"))
        let loaded = try s.service.loadDataset(datasetID: result.datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
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
        #expect(Set(a.map(\.id)) == [result.sourceID, result.datasetID])
        #expect(Set(b.map(\.id)) == Set(a.map(\.id)))
    }

    @Test("Unknown/non-length data units are kept as-is, never relabelled as nm")
    func unknownUnitStaysUnknown() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let result = try T.ingest(s, file: try T.writeFixture(dataUnit: "V"))
        let loaded = try s.service.loadDataset(datasetID: result.datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
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
        var loaded = try s.service.loadDataset(datasetID: r.datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(loaded.dataset, expected))
        #expect(loaded.sourceAvailability == .missing)

        try Data(original.dropLast()).write(to: payload)
        loaded = try s.service.loadDataset(datasetID: r.datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
        if case .corrupt = loaded.sourceAvailability {} else { Issue.record("expected corrupt source, got \(loaded.sourceAvailability)") }
        #expect(T.bitEqual(loaded.dataset, expected))

        let matrices = s.root.appending(path: "storage/\(r.datasetID)/rev_1/matrices.bin")
        var blob = try Data(contentsOf: matrices)
        blob[0] ^= 0x01
        try blob.write(to: matrices)
        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.loadDataset(datasetID: r.datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
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
            try db.execute("UPDATE schema_meta SET value = '2' WHERE key = 'schema_version';")
        }
        #expect(throws: LibraryAssetError.databaseUnknownVersion("2")) {
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

    @Test("Same operation submitted twice yields one result; unlink / trash / restore keep assets; relink keeps IDs")
    func idempotencyAndLinks() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let r1 = try T.ingest(s, file: file, op: "op-1")
        let r2 = try T.ingest(s, file: file, op: "op-1")
        #expect(r1 == r2)
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 2)

        try s.service.linkAsset(assetID: r1.datasetID, toSampleUID: s.uidB, rootURL: s.root)
        try s.service.linkAsset(assetID: r1.datasetID, toSampleUID: s.uidB, rootURL: s.root)
        #expect(try s.service.linkedSampleUIDs(assetID: r1.datasetID, rootURL: s.root) == [s.uidA, s.uidB].sorted())

        try s.service.unlinkAsset(assetID: r1.datasetID, fromSampleUID: s.uidB, rootURL: s.root)
        #expect(try s.service.linkedSampleUIDs(assetID: r1.datasetID, rootURL: s.root) == [s.uidA])
        #expect(T.exists(s, "storage/\(r1.datasetID)/rev_1/matrices.bin"))

        let trashed = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        #expect(T.exists(s, "storage/\(r1.datasetID)/rev_1/matrices.bin"))
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 2)
        _ = try s.store.restoreSampleFromTrash(sample: trashed, rootURL: s.root)
        try s.service.linkAsset(assetID: r1.datasetID, toSampleUID: s.uidB, rootURL: s.root)
        #expect(try s.service.listAssets(forSampleUID: s.uidB, rootURL: s.root).map(\.id) == [r1.datasetID])
    }

    @Test("Duplicate content is reported for an explicit reuse choice; reuse links the same Source")
    func duplicateSourceReuse() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try T.writeFixture()
        let r1 = try T.ingest(s, file: file)
        let sha = AssetHashing.sha256Hex(try Data(contentsOf: file))
        let found = try s.service.findSources(sha256: sha, rootURL: s.root)
        #expect(found.map(\.id) == [r1.sourceID])

        let r2 = try T.ingest(s, file: file, targets: [s.uidB], reuse: r1.sourceID)
        #expect(r2.reusedSource && r2.sourceID == r1.sourceID && r2.datasetID != r1.datasetID)
        let other = try T.writeFixture(seed: 5)
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, file: other, reuse: r1.sourceID) }
    }

    @Test("Ingest on V1 libraries and for invalid/trashed targets is refused")
    func guards() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, targets: ["smp_not-a-real-one"]) }
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, targets: []) }
        _ = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        #expect(throws: LibraryAssetError.self) { try T.ingest(s, targets: [s.uidA]) }

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
                targetSampleUIDs: [s.uidA], operationID: "crash-op", rootURL: s.root
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
        let loaded = try restarted.loadDataset(datasetID: r.datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(loaded.dataset, expected))
        #expect(loaded.dataset.channels.count >= 1)
        #expect(try Data(contentsOf: s.root.appending(path: "storage/\(r.sourceID)/payload.bin")) == original)

        try FileManager.default.removeItem(at: copy)
        try FileManager.default.removeItem(at: s.root.appending(path: "storage/\(r.sourceID)/payload.bin"))
        let again = try restarted.loadDataset(datasetID: r.datasetID, codec: AFMDatasetCodec(), rootURL: s.root)
        #expect(T.bitEqual(again.dataset, expected))
        #expect(again.sourceAvailability == .missing)
    }
}
