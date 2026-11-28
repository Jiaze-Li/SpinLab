import Foundation
import Testing
@testable import SpinLabApp

/// Task 7 batch 1 (AC4/AC5, storage layer): durable intent, receipts, commit guard, preset gate.
@Suite("Task 7: auto plot intent, receipt and commit guard")
struct Task7AutoPlotStorageTests {
    typealias T = AssetTestSupport

    struct Env {
        let s: T.Scenario
        let lease: LibraryWriteLease
        let lockDir: URL
        var service: LibraryAssetService { s.service }
    }

    private func makeEnv() throws -> Env {
        let s = try T.makeScenario()
        let lockDir = FileManager.default.temporaryDirectory.appending(path: "t7lease_\(UUID().uuidString)", directoryHint: .isDirectory)
        let lease = LibraryWriteLease(lockDirectory: lockDir)
        #expect(lease.acquire(rootURL: s.root) == .writable)
        s.service.writeLease = lease
        return Env(s: s, lease: lease, lockDir: lockDir)
    }

    private func cleanup(_ e: Env) {
        e.lease.release()
        try? FileManager.default.removeItem(at: e.s.root)
        try? FileManager.default.removeItem(at: e.lockDir)
    }

    private func preset(enabled: Bool = true, label: String = "HeightRetrace") -> AFMAutoPlotPreset {
        AFMAutoPlotPreset(
            enabled: enabled, presetVersionID: "ignored", channelRule: .init(semanticType: "Height", sourceLabel: label),
            surfaceLevel: .plane, lineFlattenOrder: .off, zeroReference: .none,
            displayState: AFMWorkspaceStore.defaultDisplayState, scaleBar: .init(), globalPlotDefaults: [:]
        )
    }

    private func ingest(_ e: Env, intent: AutoPlotIntent?, op: String = UUID().uuidString, seed: Float = 0, target: String? = nil) throws -> AssetIngestResult {
        try e.service.ingestAsset(
            sourceFileURL: try T.writeFixture(seed: seed), adapter: AFMIBWStandardizationAdapter(),
            targetSampleUID: target ?? e.s.uidA, operationID: op, autoPlotIntent: intent, rootURL: e.s.root
        )
    }

    private func content(_ e: Env, datasetID: String, title: String = "T") throws -> (StandardizedDatasetContent, PlotInputRef) {
        let loaded = try e.service.loadDataset(datasetID: datasetID, codec: AFMDatasetCodec(), rootURL: e.s.root)
        let channel = loaded.dataset.channels[0].id
        let input = PlotInputRef(datasetID: datasetID, channelID: channel, revision: loaded.revision)
        var display = AFMWorkspaceStore.defaultDisplayState
        display.titleOverride = title
        let c = try AFMPlotComputation.run(
            dataset: loaded.dataset, configuration: .init(activeChannelID: channel), display: .init(displayState: display)
        )
        let content = try AFMPlotCodec.encode(
            candidate: c, input: input, sampleUIDs: [e.s.uidA], title: title, displayState: display,
            savedAt: Date(), appVersion: "test"
        )
        return (content, input)
    }

    // MARK: Intent persisted with ingest

    @Test("Intent is stored with the ingest commit; replay returns the original, ignoring a newly supplied one")
    func replayReturnsOriginalIntent() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let first = try ingest(e, intent: AutoPlotIntent(presetVersionID: "v1"), op: "op-a")
        #expect(first.autoPlotIntent == AutoPlotIntent(presetVersionID: "v1"))
        let replay = try ingest(e, intent: AutoPlotIntent(presetVersionID: "v2"), op: "op-a")
        #expect(replay == first)

        let none = try ingest(e, intent: nil, op: "op-b", seed: 1)
        #expect(none.autoPlotIntent == nil)
        let replayNone = try ingest(e, intent: AutoPlotIntent(presetVersionID: "v2"), op: "op-b", seed: 1)
        #expect(replayNone.autoPlotIntent == nil && replayNone == none)
    }

    @Test("A record written before the field existed decodes with no intent")
    func oldRecordDecodes() throws {
        let json = #"{"sourceID":"s","datasetIDs":["d"],"sampleUID":"u","datasetRevision":1,"reusedSource":false}"#
        let decoded = try JSONDecoder().decode(AssetIngestResult.self, from: Data(json.utf8))
        #expect(decoded.autoPlotIntent == nil)
    }

    @Test("A crash before the ingest commit leaves no intent; the retry persists it")
    func crashBeforeCommitLeavesNoIntent() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        e.service.faultHook = { if $0 == .ingestBeforeCommit { throw T.Crash() } }
        #expect(throws: T.Crash.self) { _ = try ingest(e, intent: AutoPlotIntent(presetVersionID: "v1"), op: "op-c") }
        e.service.faultHook = nil
        #expect(try e.service.pendingAutoPlotIntents(presetVersionID: "v1", format: AFMDatasetCodec().datasetFormat, rootURL: e.s.root).isEmpty)
        let retried = try ingest(e, intent: AutoPlotIntent(presetVersionID: "v1"), op: "op-c")
        #expect(retried.autoPlotIntent?.presetVersionID == "v1")
        #expect(try e.service.pendingAutoPlotIntents(presetVersionID: "v1", format: AFMDatasetCodec().datasetFormat, rootURL: e.s.root).count == 1)
    }

    // MARK: Receipt and idempotence

    @Test("Auto publish is idempotent per Dataset revision: a re-render returns the receipt, not a mismatch")
    func publishIsIdempotent() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let ingestResult = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID))
        let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        let (c1, input) = try content(e, datasetID: ingestResult.datasetIDs[0], title: "first")
        let out1 = try e.service.publishAutoPlot(content: c1, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx)
        guard case let .published(result) = out1 else { Issue.record("expected published"); return }
        let opID = AutoPlotIdentity.operationID(datasetID: input.datasetID, revision: input.revision)
        #expect(try e.service.plotPublishReceipt(operationID: opID, rootURL: e.s.root)?.result == result)

        let (c2, _) = try content(e, datasetID: ingestResult.datasetIDs[0], title: "second render")
        #expect(c1 != c2)
        let out2 = try e.service.publishAutoPlot(content: c2, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx)
        #expect(out2 == .alreadyPublished)
        #expect(try e.service.listPlots(rootURL: e.s.root).count == 1)
    }

    @Test("A manually deleted automatic plot is not redrawn and its receipt remains")
    func deletedPlotNotResurrected() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let r = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID))
        let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        let (c, input) = try content(e, datasetID: r.datasetIDs[0])
        guard case let .published(result) = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx) else {
            Issue.record("expected published"); return
        }
        let plan = try e.service.planAssetDeletion(target: .plot(result.plotID), rootURL: e.s.root)
        _ = try e.service.commitAssetDeletion(target: .plot(result.plotID), plan: plan, operationID: "del-1", rootURL: e.s.root)
        #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty)

        let opID = AutoPlotIdentity.operationID(datasetID: input.datasetID, revision: input.revision)
        #expect(try e.service.plotPublishReceipt(operationID: opID, rootURL: e.s.root) != nil)
        #expect(try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx) == .alreadyPublished)
        #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty)
        // Recovery also skips it.
        #expect(try e.service.pendingAutoPlotIntents(presetVersionID: applied.presetVersionID, format: AFMDatasetCodec().datasetFormat, rootURL: e.s.root).isEmpty)
    }

    @Test("Commit-time faults: crash before/after commit never yield two plots; lost receipt is found on retry")
    func crashPointsNeverDuplicate() throws {
        for point in [AssetFaultPoint.plotAfterStaging, .plotBeforeCommit, .plotAfterCommit] {
            let e = try makeEnv(); defer { cleanup(e) }
            let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
            let r = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID))
            let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
            let (c, input) = try content(e, datasetID: r.datasetIDs[0])
            e.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) {
                _ = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx)
            }
            e.service.faultHook = nil
            let (c2, _) = try content(e, datasetID: r.datasetIDs[0], title: "retry")
            let retry = try e.service.publishAutoPlot(content: c2, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx)
            if point == .plotAfterCommit { #expect(retry == .alreadyPublished) } else if case .published = retry {} else { Issue.record("retry should publish at \(point)") }
            #expect(try e.service.listPlots(rootURL: e.s.root).count == 1)
        }
    }

    @Test("Two independent Datasets are not de-duplicated against each other")
    func independentDatasetsBothPublish() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let a = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID), seed: 0)
        let b = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID), seed: 3)
        let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        for r in [a, b] {
            let (c, input) = try content(e, datasetID: r.datasetIDs[0])
            guard case .published = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx) else {
                Issue.record("expected published"); return
            }
        }
        #expect(try e.service.listPlots(rootURL: e.s.root).count == 2)
    }

    // MARK: Commit guard (AC5)

    @Test("Apply, disable, session change and Library switch between compute and commit all withdraw the publish")
    func guardWithdrawsPublish() throws {
        enum Change { case apply, disable, reopenSameLibrary, switchLibrary }
        for change in [Change.apply, .disable, .reopenSameLibrary, .switchLibrary] {
            let e = try makeEnv(); defer { cleanup(e) }
            let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
            let r = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID))
            let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
            let (c, input) = try content(e, datasetID: r.datasetIDs[0])
            // The change lands exactly between staging and the commit transaction.
            e.service.faultHook = { point in
                guard point == .plotBeforeCommit else { return }
                switch change {
                case .apply: _ = try e.service.applyAutoPlotPreset(preset(label: "Other"), rootURL: e.s.root)
                case .disable: _ = try e.service.setAutoPlotEnabled(false, rootURL: e.s.root)
                case .reopenSameLibrary: _ = e.lease.acquire(rootURL: e.s.root)
                case .switchLibrary: _ = e.lease.acquire(rootURL: e.s.root.appending(path: "other"))
                }
            }
            #expect(throws: LibraryAssetError.self) {
                _ = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx)
            }
            e.service.faultHook = nil
            #expect(try e.service.listPlots(rootURL: e.s.root).isEmpty, "\(change)")
            let opID = AutoPlotIdentity.operationID(datasetID: input.datasetID, revision: input.revision)
            #expect(try e.service.plotPublishReceipt(operationID: opID, rootURL: e.s.root) == nil, "\(change)")
        }
    }

    @Test("A→B→A: an old task cannot publish after the Library is reopened; a fresh session sees the same preset")
    func abaSession() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let r = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID))
        let old = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        _ = e.lease.acquire(rootURL: e.s.root.appending(path: "other"))
        #expect(e.lease.acquire(rootURL: e.s.root) == .writable)
        let (c, input) = try content(e, datasetID: r.datasetIDs[0])
        #expect(throws: LibraryAssetError.self) {
            _ = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: old)
        }
        let fresh = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        #expect(fresh.sessionID != old.sessionID && fresh.presetVersionID == old.presetVersionID)
        if case .published = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: fresh) {} else {
            Issue.record("fresh session should publish")
        }
    }

    @Test("Dataset revised after the intent: publish is refused and the pending query drops it")
    func revisionChangeWithdraws() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let r = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID))
        let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        let (c, input) = try content(e, datasetID: r.datasetIDs[0])
        let loaded = try e.service.loadDataset(datasetID: r.datasetIDs[0], codec: AFMDatasetCodec(), rootURL: e.s.root)
        _ = try e.service.reviseDataset(
            datasetID: r.datasetIDs[0], expectedRevision: 1, content: try AFMDatasetCodec().encode(loaded.dataset),
            operationID: "rev-1", rootURL: e.s.root
        )
        #expect(throws: LibraryAssetError.self) {
            _ = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx)
        }
        #expect(try e.service.pendingAutoPlotIntents(presetVersionID: applied.presetVersionID, format: AFMDatasetCodec().datasetFormat, rootURL: e.s.root).isEmpty)
    }

    // MARK: Recovery query

    @Test("Pending intents: only the applied version, active samples, ready datasets, without a receipt")
    func pendingQuery() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let v = applied.presetVersionID
        let format = AFMDatasetCodec().datasetFormat
        let a = try ingest(e, intent: AutoPlotIntent(presetVersionID: v), seed: 0)
        let b = try ingest(e, intent: AutoPlotIntent(presetVersionID: v), seed: 1, target: e.s.uidB)
        _ = try ingest(e, intent: AutoPlotIntent(presetVersionID: "stale"), seed: 2)
        _ = try ingest(e, intent: nil, seed: 3)
        var pending = try e.service.pendingAutoPlotIntents(presetVersionID: v, format: format, rootURL: e.s.root)
        #expect(Set(pending.map(\.datasetID)) == Set([a.datasetIDs[0], b.datasetIDs[0]]))

        // A published one drops out.
        let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        let (c, input) = try content(e, datasetID: a.datasetIDs[0])
        _ = try e.service.publishAutoPlot(content: c, input: input, capturedRootURL: e.s.root, rootURL: e.s.root, context: ctx)
        pending = try e.service.pendingAutoPlotIntents(presetVersionID: v, format: format, rootURL: e.s.root)
        #expect(pending.map(\.datasetID) == [b.datasetIDs[0]])

        // A trashed sample drops out; restoring it brings the (still valid) intent back.
        let trashed = try e.s.store.moveSampleToTrash(sample: e.s.sampleB, rootURL: e.s.root)
        #expect(try e.service.pendingAutoPlotIntents(presetVersionID: v, format: format, rootURL: e.s.root).isEmpty)
        _ = try e.s.store.restoreSampleFromTrash(sample: trashed, rootURL: e.s.root)
        #expect(try e.service.pendingAutoPlotIntents(presetVersionID: v, format: format, rootURL: e.s.root).count == 1)

        // A new Apply invalidates every older intent.
        let reapplied = try e.service.applyAutoPlotPreset(preset(label: "Other"), rootURL: e.s.root)
        #expect(try e.service.pendingAutoPlotIntents(presetVersionID: reapplied.presetVersionID, format: format, rootURL: e.s.root).isEmpty)
    }

    // MARK: Preset file and gate

    @Test("Preset is off by default; Apply and switch mint new version IDs; unreadable file fails closed")
    func presetLifecycle() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        #expect(try e.service.beginAutoPlotTask(rootURL: e.s.root) == nil)
        let a1 = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let a2 = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        #expect(a1.presetVersionID != a2.presetVersionID)
        #expect(try e.service.currentAutoPlotPreset(rootURL: e.s.root).load == .loaded(a2))
        let off = try e.service.setAutoPlotEnabled(false, rootURL: e.s.root)
        #expect(off.presetVersionID != a2.presetVersionID && !off.enabled)
        #expect(try e.service.beginAutoPlotTask(rootURL: e.s.root) == nil)

        // Damage: a fresh session reads it as off and reports why.
        try Data("not json".utf8).write(to: e.service.autoPlotPresetURL(rootURL: e.s.root))
        _ = e.lease.acquire(rootURL: e.s.root)
        let load = try e.service.currentAutoPlotPreset(rootURL: e.s.root).load
        guard case .unreadable = load else { Issue.record("expected unreadable"); return }
        #expect(try e.service.beginAutoPlotTask(rootURL: e.s.root) == nil)
    }

    @Test("A failed preset write restores the gate")
    func failedWriteRestoresGate() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        let ctx = try #require(try e.service.beginAutoPlotTask(rootURL: e.s.root))
        // Make the folder read-only so the atomic write fails.
        let folder = e.service.autoPlotPresetURL(rootURL: e.s.root).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        #expect(throws: Error.self) { _ = try e.service.applyAutoPlotPreset(preset(label: "Other"), rootURL: e.s.root) }
        #expect(AutoPlotGate.shared.snapshot(rootPath: ctx.rootPath)?.presetVersionID == applied.presetVersionID)
        #expect(throws: Never.self) { try e.service.autoPlotGuard(ctx)() }
    }

    @Test("An enabled preset without a channel rule is refused")
    func enabledNeedsRule() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        var p = preset(); p.channelRule = .init(semanticType: nil, sourceLabel: "  ")
        #expect(throws: LibraryAssetError.self) { _ = try e.service.applyAutoPlotPreset(p, rootURL: e.s.root) }
    }

    @Test("Read-only instance cannot Apply")
    func readOnlyCannotApply() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        // Another instance takes the Library first, so this one opens it read-only.
        e.lease.release()
        let other = LibraryWriteLease(lockDirectory: e.lockDir)
        #expect(other.acquire(rootURL: e.s.root) == .writable)
        defer { other.release() }
        guard case .readOnly = e.lease.acquire(rootURL: e.s.root) else { Issue.record("expected read-only"); return }
        #expect(throws: (any Error).self) { try e.service.applyAutoPlotPreset(preset(label: "HeightRetrace"), rootURL: e.s.root) }
        #expect(throws: (any Error).self) { try e.service.setAutoPlotEnabled(true, rootURL: e.s.root) }
        // Nothing was written: the Library still reads as having no preset applied.
        #expect(!FileManager.default.fileExists(atPath: e.s.root.appending(path: "_spinlab/afm_auto_plot_preset.json").path))
    }

    // MARK: Channel selection

    @Test("Channel rule selects exactly one channel and never falls back")
    func channelSelection() throws {
        let ds = try T.expectedDataset(from: try T.writeFixture())
        let height = AFMAutoChannelSelector.select(rule: .init(semanticType: "height", sourceLabel: nil), in: ds.channels)
        guard case let .selected(id) = height else { Issue.record("expected single height channel"); return }
        #expect(ds.channels.first { $0.id == id }?.sourceLabel == "HeightRetrace")
        #expect(AFMAutoChannelSelector.select(rule: .init(semanticType: "Phase", sourceLabel: "PhaseRetrace"), in: ds.channels) != .noMatch)
        #expect(AFMAutoChannelSelector.select(rule: .init(semanticType: "Height", sourceLabel: "HeightTrace"), in: ds.channels) == .noMatch)
        #expect(AFMAutoChannelSelector.select(rule: .init(semanticType: nil, sourceLabel: nil), in: ds.channels) == .ruleNotUsable)
        let twin = ds.channels + ds.channels.filter { $0.isSemanticHeight }
        #expect(AFMAutoChannelSelector.select(rule: .init(semanticType: "Height", sourceLabel: nil), in: twin) == .ambiguous(count: 2))
    }
}

extension Task7AutoPlotStorageTests {
    @Test("Measured: the recovery query over 20,000 committed ingests stays fast (SQL-side filtering)")
    func recoveryQueryScales() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let applied = try e.service.applyAutoPlotPreset(preset(), rootURL: e.s.root)
        _ = try ingest(e, intent: AutoPlotIntent(presetVersionID: applied.presetVersionID))   // one real, plus bulk below
        let db = try #require(try LibraryAssetDatabase.open(rootURL: e.s.root, createIfMissing: false, fileManager: .default))
        let format = AFMDatasetCodec().datasetFormat
        let version = applied.presetVersionID
        try db.transaction {
            for i in 0..<20_000 {
                let ds = "dst_bulk\(i)", src = "src_bulk\(i)"
                let payload = #"{"result":{"standardized":{"datasetIDs":["\#(ds)"],"datasetRevision":1}}}"#
                try db.execute("INSERT INTO asset_operations(operation_id, op_type, state, payload_json, created_at, updated_at) VALUES (?, 'standardize', 'committed', ?, 'x', 'x');", [.text("bulk-\(i)"), .text(payload)])
                for (id, kind, fmt) in [(ds, "dataset", format), (src, "source", "ibw")] {
                    try db.execute("INSERT INTO assets(asset_id, kind, format, status, storage_rel_path, current_revision, files_json, created_at, updated_at) VALUES (?, ?, ?, 'ready', ?, 1, '[]', 'x', 'x');", [.text(id), .text(kind), .text(fmt), .text("storage/\(id)/rev_1")])
                }
                try db.execute("INSERT INTO asset_dependencies(consumer_asset_id, upstream_asset_id, dependency_kind, signal_locator) VALUES (?, ?, 'dataset_source', '[]');", [.text(ds), .text(src)])
                try db.execute("INSERT INTO sample_asset_links(asset_id, sample_uid, ownership_status, linked_at) VALUES (?, ?, 'active', 'x');", [.text(src), .text(e.s.uidA)])
                let intent = #"{"presetVersionID":"\#(i % 2 == 0 ? version : "old")"}"#
                try db.execute("INSERT INTO coordinator_followup(standardize_operation_id, source_id, kind, request_json, state) VALUES (?, ?, 'auto_plot', ?, 'pending');", [.text("bulk-\(i)"), .text(src), .text(intent)])
            }
        }
        let start = Date()
        let pending = try e.service.pendingAutoPlotIntents(presetVersionID: version, format: format, rootURL: e.s.root)
        let elapsed = Date().timeIntervalSince(start)
        print("T7-PERF pendingAutoPlotIntents: \(pending.count) candidates from 20000 ingests in \(String(format: "%.3f", elapsed)) s")
        #expect(pending.count == 10_001)
        #expect(elapsed < 5)
    }
}
