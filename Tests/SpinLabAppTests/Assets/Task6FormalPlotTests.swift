import Foundation
import Testing
@testable import SpinLabApp

/// Task 6 batch 2 (AC4–AC6, service layer): formal Live Plot publish/update/recover/delete.
@Suite("Task 6: formal Plot commit, recovery, deletion (AC4–AC6)")
struct Task6FormalPlotTests {
    typealias T = AssetTestSupport

    struct Env {
        let s: T.Scenario
        let lease: LibraryWriteLease
        let lockDir: URL
        let d1: String, d2: String, d3: String       // d1,d2 on sample A, d3 on sample B
        let channels: [String]
        var service: LibraryAssetService { s.service }
    }

    private func makeEnv() throws -> Env {
        let s = try T.makeScenario()
        let lockDir = FileManager.default.temporaryDirectory.appending(path: "plotlease_\(UUID().uuidString)", directoryHint: .isDirectory)
        let lease = LibraryWriteLease(lockDirectory: lockDir)
        #expect(lease.acquire(rootURL: s.root) == .writable)
        s.service.writeLease = lease
        let r1 = try T.ingest(s, file: try T.writeFixture(seed: 0), target: s.uidA)
        let r2 = try T.ingest(s, file: try T.writeFixture(seed: 4, name: "b.ibw"), target: s.uidA)
        let r3 = try T.ingest(s, file: try T.writeFixture(seed: 8, name: "c.ibw"), target: s.uidB)
        let channels = try s.service.loadDataset(datasetID: r1.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: s.root).dataset.channels.map(\.id)
        return Env(s: s, lease: lease, lockDir: lockDir, d1: r1.datasetIDs[0], d2: r2.datasetIDs[0], d3: r3.datasetIDs[0], channels: channels)
    }

    private func cleanup(_ e: Env) {
        e.lease.release()
        try? FileManager.default.removeItem(at: e.s.root)
        try? FileManager.default.removeItem(at: e.lockDir)
    }

    private func input(_ e: Env, _ id: String, channel: Int = 0, revision: Int? = nil) throws -> PlotInputRef {
        let rev = try revision ?? e.service.loadDataset(datasetID: id, codec: AFMDatasetCodec(), rootURL: e.s.root).revision
        return PlotInputRef(datasetID: id, channelID: e.channels[channel], revision: rev)
    }

    private func content(_ e: Env, _ inp: PlotInputRef, title: String = "T") throws -> StandardizedDatasetContent {
        let ds = try e.service.loadDataset(datasetID: inp.datasetID, codec: AFMDatasetCodec(), rootURL: e.s.root).dataset
        let cfg = AFMProcessingConfiguration(activeChannelID: inp.channelID, surfaceLevel: .plane)
        var display = AFMWorkspaceStore.defaultDisplayState
        display.titleOverride = title
        let c = try AFMPlotComputation.run(dataset: ds, configuration: cfg, display: .init(displayState: display))
        return try AFMPlotCodec.encode(
            candidate: c, input: inp, sampleUIDs: [e.s.uidA], title: title, displayState: display,
            savedAt: Date(), appVersion: "test"
        )
    }

    private func publish(_ e: Env, _ inp: PlotInputRef, op: String = UUID().uuidString, title: String = "T") throws -> PlotCommitResult {
        try e.service.publishPlot(
            content: try content(e, inp, title: title), inputs: [inp], operationID: op, capturedRootURL: e.s.root, rootURL: e.s.root
        )
    }

    private func update(
        _ e: Env, plot: String, rev: Int, expected: [PlotInputKey], new: [PlotInputRef],
        mode: PlotUpdateMode = .sameSet, op: String = UUID().uuidString, title: String = "U"
    ) throws -> PlotCommitResult {
        try e.service.updatePlot(
            plotID: plot, expectedPlotRevision: rev, expectedUpstream: expected, newInputs: new, mode: mode,
            content: try content(e, new[0], title: title), operationID: op, capturedRootURL: e.s.root, rootURL: e.s.root
        )
    }

    private func key(_ e: Env, _ id: String, channel: Int = 0) -> PlotInputKey { PlotInputKey(datasetID: id, channelID: e.channels[channel]) }
    private func exists(_ e: Env, _ rel: String) -> Bool { T.exists(e.s, rel) }

    // MARK: AC4

    @Test("Publish creates a ready Plot readable with matrix, manifest, input revision; Sample derived via Dataset; nothing else changes")
    func publishAndReadBack() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let before = try e.service.listAssets(forSampleUID: e.s.uidB, rootURL: e.s.root).map(\.id)
        let inp = try input(e, e.d1)
        let r = try publish(e, inp, title: "Hello")
        #expect(r.revision == 1 && r.plotID.hasPrefix("plt_"))

        let rows = try e.service.listPlots(rootURL: e.s.root)
        #expect(rows.count == 1 && rows[0].id == r.plotID && rows[0].record.liveState == "current")
        #expect(rows[0].inputs == [key(e, e.d1)] && rows[0].sampleUIDs == [e.s.uidA] && !rows[0].isCorrupt)
        #expect(try e.service.derivedSampleUIDs(forAssetID: r.plotID, rootURL: e.s.root) == [e.s.uidA])
        #expect(try e.service.listAssets(forSampleUID: e.s.uidB, rootURL: e.s.root).map(\.id) == before)

        let loaded = try e.service.loadPlot(plotID: r.plotID, rootURL: e.s.root)
        let stored = try AFMPlotCodec.decode(files: loaded.files)
        #expect(stored.manifest.input == .init(datasetID: e.d1, datasetRevision: 1, channelID: e.channels[0]))
        #expect(stored.manifest.title == "Hello" && stored.manifest.processingConfiguration.surfaceLevel == .plane)
        let direct = try AFMPlotComputation.process(
            dataset: try e.service.loadDataset(datasetID: e.d1, codec: AFMDatasetCodec(), rootURL: e.s.root).dataset,
            configuration: stored.manifest.processingConfiguration
        )
        #expect(stored.values.flatMap { $0 }.map(\.bitPattern) == direct.values.flatMap { $0 }.map(\.bitPattern))
        #expect(!stored.png.isEmpty && stored.manifest.nonFiniteCount == direct.nonFiniteCount)
        // PDF is redrawn from the stored matrix alone.
        #expect(try AFMPlotCodec.render(stored: stored, styleDefaults: [:]).pdfData.count > 100)
        // Input Dataset untouched.
        #expect(try e.service.loadDataset(datasetID: e.d1, codec: AFMDatasetCodec(), rootURL: e.s.root).revision == 1)
    }

    @Test("Relation-only fixtures and other formats never appear as replaceable Plots")
    func fixturesFiltered() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        _ = try e.service.registerDerivedAsset(kind: "plot", inputAssetIDs: [e.d1], rootURL: e.s.root)
        _ = try e.service.registerDerivedAsset(kind: "snapshot", inputAssetIDs: [e.d1], rootURL: e.s.root)
        #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty)
    }

    @Test("Update replaces in place: new revision, old revision removed, Plot ID and same inputs kept, stale Plot becomes current")
    func updateInPlace() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let r = try publish(e, try input(e, e.d1))
        let u = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [try input(e, e.d1)], title: "Second")
        #expect(u.plotID == r.plotID && u.revision == 2)
        #expect(!exists(e, "storage/\(r.plotID)/rev_1/manifest.json") && exists(e, "storage/\(r.plotID)/rev_2/manifest.json"))
        let stored = try AFMPlotCodec.decode(files: try e.service.loadPlot(plotID: r.plotID, rootURL: e.s.root).files)
        #expect(stored.manifest.title == "Second")
        #expect(try e.service.listPlots(rootURL: e.s.root).count == 1)

        // Dataset correction makes it stale; an update to the new revision makes it current again.
        let ds = try e.service.loadDataset(datasetID: e.d1, codec: AFMDatasetCodec(), rootURL: e.s.root).dataset
        _ = try e.service.reviseDataset(
            datasetID: e.d1, expectedRevision: 1, content: try AFMDatasetCodec().encode(ds), operationID: "rev-op", rootURL: e.s.root
        )
        #expect(try e.service.listPlots(rootURL: e.s.root)[0].record.liveState == "stale")
        let u2 = try update(e, plot: r.plotID, rev: 2, expected: [key(e, e.d1)], new: [try input(e, e.d1)])
        #expect(u2.revision == 3)
        #expect(try e.service.listPlots(rootURL: e.s.root)[0].record.liveState == "current")
    }

    // MARK: AC5

    @Test("A and B read rev1; B updates first; A is rejected and nothing of A is written")
    func expectedPlotRevision() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let r = try publish(e, try input(e, e.d1))
        let inp = try input(e, e.d1)
        _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [inp], title: "B")
        #expect(throws: LibraryAssetError.self) {
            _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [inp], title: "A")
        }
        let stored = try AFMPlotCodec.decode(files: try e.service.loadPlot(plotID: r.plotID, rootURL: e.s.root).files)
        #expect(stored.manifest.title == "B")
        #expect(!exists(e, "storage/\(r.plotID)/rev_3"))
    }

    @Test("Captured Dataset revision: correction, correction back (A→B→A), or ownership change reject the late publish")
    func datasetRevisionAndOwnership() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let captured = try input(e, e.d1)            // rev 1
        let ds = try e.service.loadDataset(datasetID: e.d1, codec: AFMDatasetCodec(), rootURL: e.s.root).dataset
        let same = try AFMDatasetCodec().encode(ds)
        _ = try e.service.reviseDataset(datasetID: e.d1, expectedRevision: 1, content: same, operationID: "r1", rootURL: e.s.root)
        _ = try e.service.reviseDataset(datasetID: e.d1, expectedRevision: 2, content: same, operationID: "r2", rootURL: e.s.root)
        // Content equals the original but the revision is monotonic: the stale capture is rejected.
        #expect(throws: LibraryAssetError.self) { _ = try publish(e, captured) }
        #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty)
        #expect(try publish(e, try input(e, e.d1)).revision == 1)

        // Historical ownership rejects publish for that Dataset.
        let r3 = try e.service.listSampleSourceGroups(forSampleUID: e.s.uidB, rootURL: e.s.root)[0].source.id
        let db = try #require(try LibraryAssetDatabase.open(rootURL: e.s.root, createIfMissing: false, fileManager: .default))
        try db.execute("UPDATE sample_asset_links SET ownership_status = 'historical' WHERE asset_id = ?;", [.text(r3)])
        #expect(throws: LibraryAssetError.self) { _ = try publish(e, try input(e, e.d3)) }
    }

    @Test("Trash first: publish refused; restore: publish succeeds; Plot of trashed Sample cannot be updated")
    func trashRace() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let inp = try input(e, e.d1)
        let r = try publish(e, inp)
        let trashed = try e.s.store.moveSampleToTrash(sample: e.s.sampleA, rootURL: e.s.root)
        #expect(throws: LibraryAssetError.self) { _ = try publish(e, inp) }
        #expect(throws: LibraryAssetError.self) {
            _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [inp])
        }
        _ = try e.s.store.restoreSampleFromTrash(sample: trashed, rootURL: e.s.root)
        #expect(try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [inp]).revision == 2)
    }

    @Test("Same Dataset set but a different channel is not a same-set update; manual swap changes inputs and ownership atomically")
    func manualSwap() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let r = try publish(e, try input(e, e.d1, channel: 0))
        // sameSet may not change the channel.
        #expect(throws: LibraryAssetError.self) {
            _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [try input(e, e.d1, channel: 1)])
        }
        // Channel-only manual change updates the locator.
        let c = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [try input(e, e.d1, channel: 1)], mode: .manualSwap)
        #expect(try e.service.listPlots(rootURL: e.s.root)[0].inputs == [key(e, e.d1, channel: 1)])
        // Swap to a Dataset of another Sample: row replaced, Sample derivation follows.
        let s = try update(
            e, plot: r.plotID, rev: c.revision, expected: [key(e, e.d1, channel: 1)],
            new: [try input(e, e.d3, channel: 2)], mode: .manualSwap
        )
        let row = try e.service.listPlots(rootURL: e.s.root)[0]
        #expect(s.revision == 3 && row.inputs == [key(e, e.d3, channel: 2)] && row.sampleUIDs == [e.s.uidB])
        #expect(try e.service.derivedSampleUIDs(forAssetID: r.plotID, rootURL: e.s.root) == [e.s.uidB])
        // The first Dataset's Source is no longer protected by this Plot; the new one is.
        func source(_ uid: String) throws -> String { try e.service.listSampleSourceGroups(forSampleUID: uid, rootURL: e.s.root)[0].source.id }
        let srcA = try e.service.listSampleSourceGroups(forSampleUID: e.s.uidA, rootURL: e.s.root).first { $0.datasets.map(\.id).contains(e.d1) }!.source.id
        #expect(try e.service.planAssetDeletion(target: .source(srcA), rootURL: e.s.root).assetsToDelete.contains(e.d1))
        #expect(throws: LibraryAssetError.self) { _ = try e.service.planAssetDeletion(target: .source(try source(e.s.uidB)), rootURL: e.s.root) }
    }

    @Test("Default replace of {D1} racing a manual swap to {D2}: the loser is rejected, no intermediate dependency state")
    func replaceVersusSwapRace() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let r = try publish(e, try input(e, e.d1))
        _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [try input(e, e.d2)], mode: .manualSwap)
        #expect(throws: LibraryAssetError.self) {
            _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [try input(e, e.d1)])
        }
        #expect(try e.service.listPlots(rootURL: e.s.root)[0].inputs == [key(e, e.d2)])
        // Even with the right revision, a stale expected upstream set is refused.
        #expect(throws: LibraryAssetError.plotInputsChanged(r.plotID)) {
            _ = try update(e, plot: r.plotID, rev: 2, expected: [key(e, e.d1)], new: [try input(e, e.d1)], mode: .manualSwap)
        }
    }

    @Test("Same operation retried returns the first result without a second Plot; reused id with other content is refused")
    func idempotentRetry() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let inp = try input(e, e.d1)
        let c = try content(e, inp)
        let first = try e.service.publishPlot(content: c, inputs: [inp], operationID: "op-1", capturedRootURL: e.s.root, rootURL: e.s.root)
        let again = try e.service.publishPlot(content: c, inputs: [inp], operationID: "op-1", capturedRootURL: e.s.root, rootURL: e.s.root)
        let listed = try e.service.listPlots(rootURL: e.s.root)
        #expect(first == again && listed.count == 1)
        let other = try content(e, inp, title: "different")
        #expect(throws: LibraryAssetError.operationRequestMismatch("op-1")) {
            _ = try e.service.publishPlot(content: other, inputs: [inp], operationID: "op-1", capturedRootURL: e.s.root, rootURL: e.s.root)
        }
        // Lost receipt after commit: the retry resolves to the committed result.
        let e2 = try makeEnv(); defer { cleanup(e2) }
        let inp2 = try input(e2, e2.d1)
        e2.service.faultHook = { if $0 == .plotAfterCommit { throw T.Crash() } }
        let c2 = try content(e2, inp2)
        #expect(throws: T.Crash.self) {
            _ = try e2.service.publishPlot(content: c2, inputs: [inp2], operationID: "lost", capturedRootURL: e2.s.root, rootURL: e2.s.root)
        }
        e2.service.faultHook = nil
        let retried = try e2.service.publishPlot(content: c2, inputs: [inp2], operationID: "lost", capturedRootURL: e2.s.root, rootURL: e2.s.root)
        #expect(try e2.service.listPlots(rootURL: e2.s.root).map(\.id) == [retried.plotID])
    }

    @Test("Library switch or lost write lease: commit refused, nothing visible")
    func contextAndLease() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let inp = try input(e, e.d1)
        let other = FileManager.default.temporaryDirectory.appending(path: "other_\(UUID().uuidString)")
        #expect(throws: LibraryAssetError.self) {
            _ = try e.service.publishPlot(content: try content(e, inp), inputs: [inp], operationID: "sw", capturedRootURL: other, rootURL: e.s.root)
        }
        e.lease.release()
        #expect(throws: LibraryAssetError.self) { _ = try publish(e, inp) }
        let second = LibraryWriteLease(lockDirectory: e.lockDir)
        _ = second.acquire(rootURL: e.s.root)
        #expect(second.holdsWritableLease(for: e.s.root))
        let blocked = LibraryWriteLease(lockDirectory: e.lockDir)
        #expect(blocked.acquire(rootURL: e.s.root) != .writable)
        e.s.service.writeLease = blocked
        #expect(throws: LibraryAssetError.self) { _ = try publish(e, inp) }
        second.release()
        #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty)
    }

    // MARK: AC6

    @Test("Crash during publish (after staging / before commit): not visible, no files, no staging row; next Save works")
    func publishCrashes() throws {
        for point in [AssetFaultPoint.plotAfterStaging, .plotBeforeCommit] {
            let e = try makeEnv(); defer { cleanup(e) }
            let inp = try input(e, e.d1)
            e.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) { _ = try publish(e, inp) }
            e.service.faultHook = nil
            let report = try LibraryAssetService(libraryStore: e.s.store).recoverPendingOperations(rootURL: e.s.root)
            #expect(report.abortedOperations.count == 1 && report.unknownResidue.isEmpty)
            #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty)
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: e.s.root.appending(path: "storage").path)) ?? []
            #expect(leftovers.allSatisfy { !$0.hasPrefix("plt_") })
            let db = try #require(try LibraryAssetDatabase.open(rootURL: e.s.root, createIfMissing: false, fileManager: .default))
            #expect(try db.query("SELECT 1 FROM assets WHERE kind = 'plot';").isEmpty)
            #expect(try publish(e, inp).revision == 1)
        }
    }

    @Test("Crash during update: old revision stays readable, uncommitted revision invisible, residue removed, next update works")
    func updateCrashes() throws {
        for point in [AssetFaultPoint.plotAfterStaging, .plotBeforeCommit] {
            let e = try makeEnv(); defer { cleanup(e) }
            let inp = try input(e, e.d1)
            let r = try publish(e, inp, title: "old")
            e.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) { _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [inp], title: "new") }
            e.service.faultHook = nil
            // Before recovery the committed old version is what readers see.
            let during = try AFMPlotCodec.decode(files: try e.service.loadPlot(plotID: r.plotID, rootURL: e.s.root).files)
            #expect(during.manifest.title == "old")
            let report = try LibraryAssetService(libraryStore: e.s.store).recoverPendingOperations(rootURL: e.s.root)
            #expect(report.abortedOperations.count == 1 && report.unknownResidue.isEmpty)
            #expect(!exists(e, "storage/\(r.plotID)/rev_2/manifest.json"))
            let dirs = try FileManager.default.contentsOfDirectory(atPath: e.s.root.appending(path: "storage/\(r.plotID)").path)
            #expect(dirs == ["rev_1"])
            #expect(try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [inp], title: "retry").revision == 2)
        }
    }

    @Test("Crash after update commit: new revision is the truth; recovery finishes cleaning the old one")
    func updateCrashAfterCommit() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let inp = try input(e, e.d1)
        let r = try publish(e, inp)
        e.service.faultHook = { if $0 == .plotAfterCommit { throw T.Crash() } }
        #expect(throws: T.Crash.self) { _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [inp], title: "new") }
        e.service.faultHook = nil
        #expect(try AFMPlotCodec.decode(files: try e.service.loadPlot(plotID: r.plotID, rootURL: e.s.root).files).manifest.title == "new")
        let report = try LibraryAssetService(libraryStore: e.s.store).recoverPendingOperations(rootURL: e.s.root)
        #expect(!report.recoveredOperations.isEmpty && !exists(e, "storage/\(r.plotID)/rev_1/manifest.json"))
    }

    @Test("Independent permanent delete of a Plot: files and rows go, Dataset and Sample keep working; crash mid-delete recovers")
    func deletePlot() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let inp = try input(e, e.d1)
        let r = try publish(e, inp)
        // A Dataset in use by a Plot is protected.
        #expect(throws: LibraryAssetError.self) { _ = try e.service.planAssetDeletion(target: .dataset(e.d1), rootURL: e.s.root) }
        let plan = try e.service.planAssetDeletion(target: .plot(r.plotID), rootURL: e.s.root)
        #expect(plan.assetsToDelete == [r.plotID] && plan.retainedAssets == [e.d1])
        // Crash after files are partly gone: recovery completes the delete.
        e.service.faultHook = { if $0 == .deleteAfterFile(1) { throw T.Crash() } }
        #expect(throws: T.Crash.self) {
            _ = try e.service.commitAssetDeletion(target: .plot(r.plotID), plan: plan, operationID: "del", rootURL: e.s.root)
        }
        e.service.faultHook = nil
        _ = try LibraryAssetService(libraryStore: e.s.store).recoverPendingOperations(rootURL: e.s.root)
        #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty && !exists(e, "storage/\(r.plotID)"))
        #expect(try e.service.loadDataset(datasetID: e.d1, codec: AFMDatasetCodec(), rootURL: e.s.root).revision == 1)
        // Dataset is deletable again (its sibling-free source rule aside) — at least no longer "in use".
        let again = try publish(e, inp)
        #expect(again.plotID != r.plotID)
    }

    @Test("Replacing across Datasets keeps Dataset files and leaves unrelated Samples untouched")
    func inputsUntouched() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        func fileState(_ id: String) throws -> [AssetFileEntry] {
            try e.service.listAssets(forSampleUID: e.s.uidA, rootURL: e.s.root).first { $0.id == id }?.files ?? []
        }
        let before = try fileState(e.d1)
        let bBefore = try e.service.listAssets(forSampleUID: e.s.uidB, rootURL: e.s.root).map(\.id)
        let r = try publish(e, try input(e, e.d1))
        _ = try update(e, plot: r.plotID, rev: 1, expected: [key(e, e.d1)], new: [try input(e, e.d2)], mode: .manualSwap)
        #expect(try fileState(e.d1) == before)
        #expect(try e.service.listAssets(forSampleUID: e.s.uidB, rootURL: e.s.root).map(\.id) == bBefore)
    }
}
