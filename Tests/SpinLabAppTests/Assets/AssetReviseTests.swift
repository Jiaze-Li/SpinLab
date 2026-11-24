import Foundation
import Testing
@testable import SpinLabApp

@Suite("Asset storage: corrections, ABA, crash recovery (Task 5A)")
struct AssetReviseTests {
    typealias T = AssetTestSupport

    private func content(seed: Float) throws -> StandardizedDatasetContent {
        let url = try T.writeFixture(seed: seed)
        return try AFMIBWStandardizationAdapter().standardize(sourceFileURL: url).dataset
    }

    private func dataset(_ s: T.Scenario, _ id: String) throws -> CanonicalAFMDataset {
        try LibraryAssetService(libraryStore: s.store).loadDataset(datasetID: id, codec: AFMDatasetCodec(), rootURL: s.root).dataset
    }

    @Test("Correction keeps the dataset ID, bumps the revision, stales Live only, and replays idempotently")
    func reviseStableIDAndStaleness() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s)
        let plot = try s.service.registerDerivedAsset(kind: "plot", inputAssetIDs: [r.datasetID], sampleUIDs: [s.uidA], rootURL: s.root)
        let snap = try s.service.registerDerivedAsset(kind: "snapshot", inputAssetIDs: [r.datasetID], sampleUIDs: [s.uidA], rootURL: s.root)

        let revised = try s.service.reviseDataset(
            datasetID: r.datasetID, expectedRevision: 1, content: try content(seed: 3), operationID: "rev-A", rootURL: s.root
        )
        #expect(revised.datasetID == r.datasetID && revised.revision == 2)
        #expect(revised.staleLiveAssetIDs == [plot])
        #expect(!T.exists(s, "storage/\(r.datasetID)/rev_1"), "superseded revision is cleaned")
        #expect(T.exists(s, "storage/\(r.datasetID)/rev_2/matrices.bin"))

        let assets = try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root)
        #expect(assets.first(where: { $0.id == plot })?.liveState == "stale")
        #expect(assets.first(where: { $0.id == snap })?.liveState == nil, "Snapshots are never changed")
        #expect(assets.first(where: { $0.id == r.datasetID })?.currentRevision == 2)

        let replay = try s.service.reviseDataset(
            datasetID: r.datasetID, expectedRevision: 1, content: try content(seed: 3), operationID: "rev-A", rootURL: s.root
        )
        #expect(replay == revised, "the same operation never takes effect twice")
        let expected = try T.expectedDataset(from: try T.writeFixture(seed: 3))
        let now = try dataset(s, r.datasetID)
        #expect(now.channels.map { $0.values.map { $0.map(\.bitPattern) } } == expected.channels.map { $0.values.map { $0.map(\.bitPattern) } })
    }

    @Test("Late writer A is rejected after B committed, also across A→B→A content")
    func lateWriterAndABA() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s)
        let contentA = try content(seed: 0)   // same numbers as the original
        let contentB = try content(seed: 7)

        // A starts at revision 1; B starts at revision 1 and commits first.
        _ = try s.service.reviseDataset(datasetID: r.datasetID, expectedRevision: 1, content: contentB, operationID: "B", rootURL: s.root)
        #expect(throws: LibraryAssetError.staleRevision(datasetID: r.datasetID, expected: 1, current: 2)) {
            _ = try s.service.reviseDataset(datasetID: r.datasetID, expectedRevision: 1, content: contentA, operationID: "A", rootURL: s.root)
        }
        #expect(T.exists(s, "storage/\(r.datasetID)/rev_2/matrices.bin"))
        let stagingLeft = (try? FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage/\(r.datasetID)").path)) ?? []
        #expect(stagingLeft == ["rev_2"], "rejected writer leaves no staging, formal revision untouched")

        // A→B→A: content returns to the original bytes, the revision number still differs.
        _ = try s.service.reviseDataset(datasetID: r.datasetID, expectedRevision: 2, content: contentA, operationID: "A2", rootURL: s.root)
        #expect(throws: LibraryAssetError.self) {
            _ = try s.service.reviseDataset(datasetID: r.datasetID, expectedRevision: 1, content: contentB, operationID: "late", rootURL: s.root)
        }
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).first { $0.id == r.datasetID }?.currentRevision == 3)
    }

    @Test("Two concurrent corrections from the same revision: exactly one wins")
    func concurrentCorrections() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s)
        let c1 = try content(seed: 1)
        let c2 = try content(seed: 2)
        let outcomes = OutcomeBox()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let service = LibraryAssetService(libraryStore: LibraryStore())
            do {
                _ = try service.reviseDataset(
                    datasetID: r.datasetID, expectedRevision: 1, content: index == 0 ? c1 : c2,
                    operationID: "op-\(index)", rootURL: s.root
                )
                outcomes.add(true)
            } catch {
                outcomes.add(false)
            }
        }
        #expect(outcomes.values.filter { $0 }.count == 1)
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).first { $0.id == r.datasetID }?.currentRevision == 2)
        #expect(T.exists(s, "storage/\(r.datasetID)/rev_2/matrices.bin"))
        #expect(!T.exists(s, "storage/\(r.datasetID)/rev_1"))
    }

    @Test("Crash during a correction recovers to a consistent state and does not block the next correction")
    func reviseCrashRecovery() throws {
        for point in [AssetFaultPoint.reviseAfterStaging, .reviseAfterPublish, .reviseAfterCommit] {
            let s = try T.makeScenario()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let r = try T.ingest(s)
            let original = try dataset(s, r.datasetID)
            s.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) {
                _ = try s.service.reviseDataset(
                    datasetID: r.datasetID, expectedRevision: 1, content: try content(seed: 4), operationID: "crash-rev", rootURL: s.root
                )
            }
            if point == .reviseAfterPublish { #expect(T.exists(s, "storage/\(r.datasetID)/rev_2")) }

            let restarted = LibraryAssetService(libraryStore: s.store)
            let report = try restarted.recoverPendingOperations(rootURL: s.root)
            #expect(report.unknownResidue.isEmpty)
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage/\(r.datasetID)").path)) ?? []).sorted()
            let current = try restarted.listAssets(forSampleUID: s.uidA, rootURL: s.root).first { $0.id == r.datasetID }?.currentRevision

            if point == .reviseAfterCommit {
                #expect(current == 2 && names == ["rev_2"], "committed correction is kept and its cleanup finished")
                #expect(!T.bitEqual(try dataset(s, r.datasetID), original))
            } else {
                #expect(current == 1 && names == ["rev_1"], "uncommitted correction is rolled back: \(point) \(names)")
                #expect(T.bitEqual(try dataset(s, r.datasetID), original))
                let next = try restarted.reviseDataset(
                    datasetID: r.datasetID, expectedRevision: 1, content: try content(seed: 4), operationID: "after", rootURL: s.root
                )
                #expect(next.revision == 2, "recovery must not leave a stale rev_2 that blocks the next correction")
            }
        }
    }

    @Test("Recovery of an aborted late writer never removes another correction's committed revision")
    func abortedLoserKeepsWinnerRevision() throws {
        let s = try T.makeScenario()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let r = try T.ingest(s)
        // Loser A crashes after staging; winner B commits revision 2; then recovery aborts A.
        s.service.faultHook = { if $0 == .reviseAfterStaging { throw T.Crash() } }
        #expect(throws: T.Crash.self) {
            _ = try s.service.reviseDataset(datasetID: r.datasetID, expectedRevision: 1, content: try content(seed: 8), operationID: "A", rootURL: s.root)
        }
        // B runs on a fresh service: its entry recovery aborts A first, then B commits cleanly.
        let b = LibraryAssetService(libraryStore: s.store)
        let result = try b.reviseDataset(datasetID: r.datasetID, expectedRevision: 1, content: try content(seed: 9), operationID: "B", rootURL: s.root)
        #expect(result.revision == 2)
        #expect(T.exists(s, "storage/\(r.datasetID)/rev_2/matrices.bin"))
        #expect(try b.recoverPendingOperations(rootURL: s.root).unknownResidue.isEmpty)
        #expect(T.exists(s, "storage/\(r.datasetID)/rev_2/matrices.bin"))
    }
}

final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []
    func add(_ value: Bool) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [Bool] { lock.lock(); defer { lock.unlock() }; return storage }
}
