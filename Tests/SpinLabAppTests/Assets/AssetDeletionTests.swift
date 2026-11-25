import Foundation
import Testing
@testable import SpinLabApp

@Suite("Asset storage: reference-safe deletion, recovery, gates (Task 5A)")
struct AssetDeletionTests {
    typealias T = AssetTestSupport

    private func trash(_ s: T.Scenario, _ sample: LibrarySample) throws {
        _ = try s.store.moveSampleToTrash(sample: sample, rootURL: s.root)
    }

    private func assetRows(_ s: T.Scenario) throws -> Int {
        guard let db = try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false) else { return 0 }
        return Int(try db.query("SELECT COUNT(*) AS n FROM assets;").first?.int("n") ?? 0)
    }

    private func sampleExists(_ s: T.Scenario, _ uid: String) -> Bool {
        T.exists(s, "records/samples/\(uid)/sample.json")
    }

    @Test("Sole owner (including 1-to-many Source->Datasets): registered files deleted with correct counts, unregistered files and unrelated data stay")
    func soleOwner() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let mine = try T.ingest(s, target: s.uidA)
        let mineMulti = try s.service.ingestAsset(
            sourceFileURL: try T.writeFixture(seed: 3, name: "multi.raw"),
            adapter: MultiDatasetTestAdapter(),
            targetSampleUID: s.uidA,
            operationID: "op-multi-del",
            rootURL: s.root
        )
        let others = try T.ingest(s, file: try T.writeFixture(seed: 2), target: s.uidB)
        let stray = s.root.appending(path: "storage/\(mine.datasetIDs[0])/rev_1/stray.txt")
        try Data("keep me".utf8).write(to: stray)

        try trash(s, s.sampleA)
        let plan = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
        let expectedDelete = Set([mine.sourceID] + mine.datasetIDs + [mineMulti.sourceID] + mineMulti.datasetIDs)
        #expect(Set(plan.assetsToDelete) == expectedDelete)
        // mine: 2 source + 2 dataset = 4; mineMulti: 2 source + 1 ds1 + 1 ds2 = 4 => 8 total
        #expect(plan.deleteFileCount == 8 && plan.retainedFileCount == 0 && plan.retainedAssets.isEmpty)

        let result = try s.service.commitPermanentSampleDeletion(plan: plan, operationID: "del-1", rootURL: s.root)
        #expect(Set(result.deletedAssetIDs) == Set(plan.assetsToDelete))
        #expect(!sampleExists(s, s.uidA) && sampleExists(s, s.uidB))
        #expect(!T.exists(s, "storage/\(mine.sourceID)"))
        #expect(!T.exists(s, "storage/\(mine.datasetIDs[0])/rev_1/matrices.bin") && !T.exists(s, "storage/\(mine.datasetIDs[0])/rev_1/manifest.json"))
        #expect(!T.exists(s, "storage/\(mineMulti.sourceID)"))
        #expect(FileManager.default.fileExists(atPath: stray.path), "unregistered files are never deleted")
        #expect(T.exists(s, "storage/\(others.datasetIDs[0])/rev_1/matrices.bin") && T.exists(s, "storage/\(others.sourceID)/payload.bin"))
        #expect(try s.service.listAssets(forSampleUID: s.uidB, rootURL: s.root).count == 2)
        #expect(try assetRows(s) == 2)
        #expect(try s.service.commitPermanentSampleDeletion(plan: plan, operationID: "del-1", rootURL: s.root) == result, "idempotent")
    }

    @Test("Cross-sample Plot & Snapshot retain upstream Source as historical; deleting last active sample cleans historical chain")
    func plotAndSnapshotRetention() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let rA = try T.ingest(s, file: try T.writeFixture(seed: 1), target: s.uidA)
        let rB = try T.ingest(s, file: try T.writeFixture(seed: 2), target: s.uidB)
        let dsA = rA.datasetIDs[0]
        let dsB = rB.datasetIDs[0]

        let plot = try s.service.registerDerivedAsset(kind: "plot", inputAssetIDs: [dsA, dsB], rootURL: s.root)
        let snap = try s.service.registerDerivedAsset(kind: "snapshot", inputAssetIDs: [dsA, dsB], rootURL: s.root)

        try trash(s, s.sampleA)
        let planA = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
        #expect(planA.assetsToDelete.isEmpty)
        #expect(Set(planA.retainedAssets) == [rA.sourceID, dsA, plot, snap])
        #expect(planA.staleLiveAssetIDs == [plot])
        _ = try s.service.commitPermanentSampleDeletion(plan: planA, operationID: "del-a", rootURL: s.root)

        // rA.sourceID keeps its original Sample UID marked as historical (not active!)
        let ownershipA = try s.service.sourceOwnership(sourceID: rA.sourceID, rootURL: s.root)
        #expect(ownershipA == SourceOwnershipRecord(sampleUID: s.uidA, isHistorical: true))
        #expect(try s.service.derivedSampleUIDs(forAssetID: rA.sourceID, rootURL: s.root).isEmpty)
        #expect(try s.service.derivedSampleUIDs(forAssetID: plot, rootURL: s.root) == [s.uidB])

        let forB = try s.service.listAssets(forSampleUID: s.uidB, rootURL: s.root)
        #expect(forB.first { $0.id == plot }?.liveState == "stale", "plot stays but is no longer current")
        #expect(forB.first { $0.id == snap }?.liveState == nil, "snapshot stays untouched")
        #expect(T.exists(s, "storage/\(dsA)/rev_1/matrices.bin"))

        // Now delete sample B too: historical A chain + B chain + plot + snap are all deleted.
        try trash(s, s.sampleB)
        let planB = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidB], rootURL: s.root)
        #expect(Set(planB.assetsToDelete) == [rA.sourceID, dsA, rB.sourceID, dsB, plot, snap])
        #expect(planB.retainedAssets.isEmpty)
        _ = try s.service.commitPermanentSampleDeletion(plan: planB, operationID: "del-b", rootURL: s.root)
        #expect(try assetRows(s) == 0)
    }

    @Test("A plan that changed after confirmation is refused; untrashed samples are refused")
    func planDrift() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s, target: s.uidA)
        #expect(throws: LibraryAssetError.sampleNotTrashed(s.uidA)) {
            _ = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
        }
        try trash(s, s.sampleA)
        let plan = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
        // Another operation changes dependencies of r.datasetIDs[0] after plan confirmation
        _ = try s.service.registerDerivedAsset(kind: "plot", inputAssetIDs: [r.datasetIDs[0]], rootURL: s.root)
        #expect(throws: LibraryAssetError.planChanged) {
            _ = try s.service.commitPermanentSampleDeletion(plan: plan, operationID: "stale-plan", rootURL: s.root)
        }
        #expect(sampleExists(s, s.uidA) && T.exists(s, "storage/\(r.datasetIDs[0])/rev_1/matrices.bin"))
    }

    @Test("Crash at every deletion boundary resumes to a complete, consistent deletion")
    func deletionCrashRecovery() throws {
        let points: [AssetFaultPoint] = [.deleteAfterPendingCommit, .deleteAfterSampleRemoved, .deleteAfterFile(1), .deleteAfterFile(3)]
        for point in points {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let r = try T.ingest(s, target: s.uidA)
            let stray = s.root.appending(path: "storage/\(r.sourceID)/notes.txt")
            try Data("x".utf8).write(to: stray)
            try trash(s, s.sampleA)
            let plan = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
            s.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) {
                _ = try s.service.commitPermanentSampleDeletion(plan: plan, operationID: "del", rootURL: s.root)
            }
            // Half-way state is explicit: the legacy entry refuses, the plan refuses.
            #expect(throws: LibraryAssetError.self) {
                _ = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
            }

            let restarted = LibraryAssetService(libraryStore: s.store)
            let report = try restarted.recoverPendingOperations(rootURL: s.root)
            #expect(report.recoveredOperations == ["del"], "\(point)")
            #expect(!sampleExists(s, s.uidA))
            #expect(!T.exists(s, "storage/\(r.datasetIDs[0])"), "\(point)")
            #expect(try assetRows(s) == 0)
            #expect(FileManager.default.fileExists(atPath: stray.path), "unregistered file survives recovery")
            #expect(!T.exists(s, "storage/\(r.sourceID)/payload.bin"))
        }
    }

    @Test("A permission failure stops deletion with the operation still pending and retryable")
    func cleanupFailureStopsAndRetries() throws {
        let s = try T.makeScenario()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.root.appending(path: "storage").path)
            try? FileManager.default.removeItem(at: s.root)
        }
        let r = try T.ingest(s, target: s.uidA)
        try trash(s, s.sampleA)
        let plan = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
        let srcDir = s.root.appending(path: "storage/\(r.sourceID)")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: srcDir.path)
        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.commitPermanentSampleDeletion(plan: plan, operationID: "del", rootURL: s.root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: srcDir.path)
        let report = try LibraryAssetService(libraryStore: s.store).recoverPendingOperations(rootURL: s.root)
        #expect(report.recoveredOperations == ["del"])
        #expect(try assetRows(s) == 0)
    }

    @Test("The pre-asset permanent-delete entry refuses samples with assets, pending work, or an untrusted database")
    func legacyDeleteGate() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s, target: s.uidA)
        let trashed = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        #expect(throws: LibraryAssetError.deletionPlanRequired(s.uidA)) {
            try s.store.permanentlyDeleteTrashedSample(sample: trashed, rootURL: s.root)
        }
        #expect(sampleExists(s, s.uidA) && T.exists(s, "storage/\(r.datasetIDs[0])/rev_1/matrices.bin"))

        // Sample without assets keeps the existing behaviour even though the database exists.
        let trashedB = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)
        try s.store.permanentlyDeleteTrashedSample(sample: trashedB, rootURL: s.root)
        #expect(!sampleExists(s, s.uidB))

        // Untrusted database: refuse.
        let spinlab = s.root.appending(path: "_spinlab")
        for entry in try FileManager.default.contentsOfDirectory(atPath: spinlab.path) where entry.hasPrefix("library.sqlite") {
            try FileManager.default.removeItem(at: spinlab.appending(path: entry))
        }
        #expect(throws: LibraryAssetError.self) {
            try s.store.permanentlyDeleteTrashedSample(sample: trashed, rootURL: s.root)
        }
        #expect(sampleExists(s, s.uidA))
    }

    @Test("Empty check counts V2 assets as data and reports an unreadable database as unreadable")
    func emptyCheckV2() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let check = LibrarySampleEmptyCheck()
        #expect(check.evaluate(sample: s.sampleB, rootURL: s.root, libraryStore: s.store) == .empty)
        try T.ingest(s, target: s.uidA)
        if case .nonEmpty(let reasons) = check.evaluate(sample: s.sampleA, rootURL: s.root, libraryStore: s.store) {
            #expect(reasons.contains("Has registered data assets"))
        } else {
            Issue.record("sample with assets must not be empty")
        }
        #expect(check.evaluate(sample: s.sampleB, rootURL: s.root, libraryStore: s.store) == .empty)
        let spinlab = s.root.appending(path: "_spinlab")
        for entry in try FileManager.default.contentsOfDirectory(atPath: spinlab.path) where entry.hasPrefix("library.sqlite") {
            try FileManager.default.removeItem(at: spinlab.appending(path: entry))
        }
        if case .unreadable = check.evaluate(sample: s.sampleB, rootURL: s.root, libraryStore: s.store) {} else {
            Issue.record("lost relations must read as unreadable, not empty")
        }
    }

    @Test("V2 backup is refused and nothing is written to the destination")
    func backupRefused() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        try T.ingest(s, target: s.uidA)
        let backup = FileManager.default.temporaryDirectory.appending(path: "SpinLab_Task5A_backup_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: backup) }
        #expect(s.store.syncBackup(from: s.root, to: backup) == false)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }
}
