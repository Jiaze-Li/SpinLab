import Foundation
import Testing
@testable import SpinLabApp

/// WP1 step ④ (Task 11 batch A): the coordinator sequences ingest → standardize → AFM follow-up,
/// per target, without cross-step or cross-target transactions. Isolated temporary libraries only.
@Suite("WP1 coordination")
struct WP1CoordinationTests {
    typealias T = AssetTestSupport

    struct Env {
        let s: T.Scenario
        let lease: LibraryWriteLease
        let lockDir: URL
    }

    private func makeEnv() throws -> Env {
        let s = try T.makeScenario()
        let lockDir = FileManager.default.temporaryDirectory.appending(path: "wp1lease_\(UUID().uuidString)", directoryHint: .isDirectory)
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

    private func pending(_ url: URL, workflow: String?) -> SpinLabDomain.PendingImport {
        SpinLabDomain.PendingImport(
            id: UUID(), fileName: url.lastPathComponent, sourceFilePath: url.path, originalFilePath: url.path,
            parsedHints: SpinLabDomain.ParsedFilenameHints(workflowID: workflow)
        )
    }

    private func draft(workflow: String, targets: [V2IngestTarget]) -> PendingImportConfirmationDraft {
        PendingImportConfirmationDraft(
            batchName: "", sampleName: "", measurementName: "", workflowID: workflow, conditionValues: [:],
            selectedExistingProjectName: PendingImportConfirmationDraft.noProjectOption, newProjectName: "", v2Targets: targets
        )
    }

    private func apply(_ e: Env, _ pending: SpinLabDomain.PendingImport, _ draft: PendingImportConfirmationDraft, service: LibraryAssetService? = nil) throws -> InboxArchiveApplyResult {
        let index = try e.s.store.syncIndexFromFilesystem(rootURL: e.s.root)
        let used = service ?? e.s.service
        return try InboxArchiveApplyService(makeAssetService: { _ in used }).apply(
            pending: pending, targets: [], libraryIndex: index, libraryStore: e.s.store, libraryRootURL: e.s.root, draft: draft
        )
    }

    private func counts(_ e: Env, _ uid: String) throws -> (sources: Int, datasets: Int) {
        let all = try e.s.service.listAssets(forSampleUID: uid, rootURL: e.s.root)
        return (all.filter { $0.kind == "source" }.count, all.filter { $0.kind == "dataset" }.count)
    }

    // MARK: AC2/AC5+ — two targets, staged results

    @Test("One target's technical standardize error keeps the entry queued; the retry completes only that stage")
    func partialThenRetry() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let url = try T.writeFixture(name: "run.ibw")
        let item = pending(url, workflow: "afm")
        let d = draft(workflow: "afm", targets: [
            V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "op-a"),
            V2IngestTarget(sampleUID: e.s.uidB, ingestOperationID: "op-b")
        ])
        var standardizeCommits = 0
        e.s.service.faultHook = { point in
            if point == .standardizeBeforeCommit { standardizeCommits += 1; if standardizeCommits == 2 { throw T.Crash() } }
        }
        let first = try apply(e, item, d)
        #expect(first.isIncompleteV2)
        #expect(first.v2TargetResults.map(\.isFinished) == [true, false])
        #expect(first.v2TargetResults[1].sourceID != nil)
        guard case .pending = first.v2TargetResults[1].standardize else { Issue.record("B must stay pending"); return }
        #expect(try counts(e, e.s.uidA) == (1, 1) && counts(e, e.s.uidB) == (1, 0))

        e.s.service.faultHook = nil
        try FileManager.default.removeItem(at: url)   // the retry never needs the external file for A's stored target
        let second = try apply(e, item, d)
        #expect(second.v2TargetResults.map(\.isFinished) == [true, true] || second.v2TargetResults[1].problem != nil)
        // B's ingest replays the stored receipt only if the file is not needed: it is not.
        #expect(!second.isIncompleteV2)
        #expect(try counts(e, e.s.uidA) == (1, 1) && counts(e, e.s.uidB) == (1, 1))
        #expect(second.v2TargetResults[0].sourceID == first.v2TargetResults[0].sourceID)
        #expect(second.v2TargetResults[1].sourceID == first.v2TargetResults[1].sourceID)
    }

    @Test("An invalid target fails at ingest only; the other target is stored and not duplicated on retry")
    func ingestFailureIsolated() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let url = try T.writeFixture(name: "run.ibw")
        _ = try e.s.store.moveSampleToTrash(sample: e.s.sampleB, rootURL: e.s.root)
        let item = pending(url, workflow: "afm")
        let d = draft(workflow: "afm", targets: [
            V2IngestTarget(sampleUID: e.s.uidB, ingestOperationID: "op-b"),
            V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "op-a")
        ])
        let first = try apply(e, item, d)
        guard case .failed = first.v2TargetResults[0].ingest else { Issue.record("trashed target must fail"); return }
        #expect(first.v2TargetResults[1].isFinished && first.isIncompleteV2)
        let second = try apply(e, item, d)
        #expect(second.v2TargetResults[1].sourceID == first.v2TargetResults[1].sourceID)
        #expect(try counts(e, e.s.uidA) == (1, 1) && counts(e, e.s.uidB) == (0, 0))
    }

    @Test("Refused standardization is a final answer: the entry is finished and the file stays Source-only")
    func refusalIsFinal() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let dir = FileManager.default.temporaryDirectory.appending(path: "wp1_odd_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "sample.dat")
        try Data("hello".utf8).write(to: url)
        // Confirmed MR: no adapter at all. Unknown workflow: adapter by suffix, refuses the layout.
        for (workflow, expected) in [("MR", "no_adapter"), ("", "unsupported_layout")] {
            let result = try apply(e, pending(url, workflow: nil), draft(workflow: workflow, targets: [V2IngestTarget(sampleUID: e.s.uidA)]))
            #expect(!result.isIncompleteV2 && result.v2TargetResults[0].standardize == .notStandardized(code: expected))
            #expect(result.autoPlotTriggers.isEmpty)
        }
        #expect(try counts(e, e.s.uidA) == (2, 0))
    }

    @Test("Unknown workflow does not stop faithful standardization of a table file")
    func unknownWorkflowStandardizes() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let url = try WP1SourceIngestTests.writeFile(Data(WP2StandardizationTests.ppms.utf8), name: "run.dat")
        let result = try apply(e, pending(url, workflow: nil), draft(workflow: "", targets: [V2IngestTarget(sampleUID: e.s.uidA)]))
        #expect(result.v2TargetResults[0].standardize == .standardized && result.autoPlotTriggers.isEmpty)
        let status = try #require(try e.s.service.sourceStatusSummaries(forSampleUID: e.s.uidA, rootURL: e.s.root).first)
        #expect(status.workflowID == nil && status.workflowOrigin == .unknown && status.effectiveChannels == nil && status.datasetCount == 1)
    }

    @Test("Channels and confirmed workflow are stored per target; one file for two samples never shares channels")
    func perTargetChannels() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let url = try WP1SourceIngestTests.writeFile(Data(WP2StandardizationTests.ppms.utf8), name: "AHE_run.dat")
        let result = try apply(e, pending(url, workflow: "ahe"), draft(workflow: "ahe", targets: [
            V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "a", effectiveChannelIDs: ["ch1"]),
            V2IngestTarget(sampleUID: e.s.uidB, ingestOperationID: "b", effectiveChannelIDs: ["ch2", "ch3"])
        ]))
        #expect(!result.isIncompleteV2 && result.autoPlotTriggers.isEmpty)
        let a = try #require(result.v2TargetResults[0].sourceID), b = try #require(result.v2TargetResults[1].sourceID)
        #expect(a != b)
        #expect(try e.s.service.effectiveChannels(sourceID: a, rootURL: e.s.root)?.map(\.id) == ["ch1"])
        #expect(try e.s.service.effectiveChannels(sourceID: b, rootURL: e.s.root)?.map(\.id) == ["ch2", "ch3"])
        let context = try #require(try e.s.service.sourceContext(sourceID: a, rootURL: e.s.root))
        #expect(context.workflowID == "ahe" && context.workflowOrigin == .rule && context.legacyPath == url.path && context.sourceMTime != nil)
    }

    // MARK: AC5++ — AFM follow-up bound to the standardize receipt

    private func enablePreset(_ e: Env) throws -> AFMAutoPlotPreset {
        try e.s.service.applyAutoPlotPreset(AFMAutoPlotPreset(
            enabled: true, presetVersionID: "x", channelRule: .init(semanticType: "Height", sourceLabel: "HeightRetrace"),
            surfaceLevel: .plane, lineFlattenOrder: .off, zeroReference: .none,
            displayState: AFMWorkspaceStore.defaultDisplayState, scaleBar: .init(), globalPlotDefaults: [:]
        ), rootURL: e.s.root)
    }

    @Test("A crash after the standardize commit leaves a pending follow-up that recovery finds exactly once")
    func followupRecovery() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let preset = try enablePreset(e)
        let url = try T.writeFixture(name: "run.ibw")
        e.s.service.faultHook = { if $0 == .standardizeAfterCommit { throw T.Crash() } }
        let first = try apply(e, pending(url, workflow: "afm"), draft(workflow: "afm", targets: [V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "op")]))
        #expect(first.isIncompleteV2)   // the crash surfaced as a pending standardize stage
        e.s.service.faultHook = nil
        let restarted = LibraryAssetService(libraryStore: e.s.store); restarted.writeLease = e.lease
        let pendingIntents = try restarted.pendingAutoPlotIntents(presetVersionID: preset.presetVersionID, format: AFMDatasetCodec().datasetFormat, rootURL: e.s.root)
        #expect(pendingIntents.count == 1)
        let again = try apply(e, pending(url, workflow: "afm"), draft(workflow: "afm", targets: [V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "op")]), service: restarted)
        let c1 = try counts(e, e.s.uidA)
        #expect(!again.isIncompleteV2 && again.autoPlotTriggers.count == 1 && c1 == (1, 1))
        #expect(again.autoPlotTriggers[0].datasetIDs == pendingIntents.map(\.datasetID))
    }

    @Test("A refused AFM standardization closes its follow-up and never plots; another operation cannot reuse it")
    func followupRefused() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let preset = try enablePreset(e)
        let dir = FileManager.default.temporaryDirectory.appending(path: "wp1_bad_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var bytes = T.fixtureIBW(); bytes[100] ^= 0xFF
        let bad = dir.appending(path: "bad.ibw"); try bytes.write(to: bad)
        let result = try apply(e, pending(bad, workflow: "afm"), draft(workflow: "afm", targets: [V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "bad")]))
        #expect(result.v2TargetResults[0].standardize == .notStandardized(code: "parse_error") && result.autoPlotTriggers.isEmpty)
        #expect(try e.s.service.pendingAutoPlotIntents(presetVersionID: preset.presetVersionID, format: AFMDatasetCodec().datasetFormat, rootURL: e.s.root).isEmpty)
        let sourceID = try #require(result.v2TargetResults[0].sourceID)
        #expect(try e.s.service.followupStates(sourceID: sourceID, rootURL: e.s.root).values.allSatisfy { $0 == "done" })
        #expect(try counts(e, e.s.uidA) == (1, 0))
    }

    @Test("Non-AFM targets write no follow-up row and trigger no automatic plot, even with the AFM preset on")
    func nonAFMHasNoFollowup() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        _ = try enablePreset(e)
        let url = try WP1SourceIngestTests.writeFile(Data(WP2StandardizationTests.ppms.utf8), name: "run.dat")
        let result = try apply(e, pending(url, workflow: "ahe"), draft(workflow: "ahe", targets: [V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "x")]))
        #expect(result.autoPlotTriggers.isEmpty && result.v2TargetResults[0].plot == .none)
        let sourceID = try #require(result.v2TargetResults[0].sourceID)
        #expect(try e.s.service.followupStates(sourceID: sourceID, rootURL: e.s.root).isEmpty)
    }

    @Test("A second standardization of the same Source does not trigger the first operation's follow-up")
    func followupBoundToReceipt() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let preset = try enablePreset(e)
        let url = try T.writeFixture(name: "run.ibw")
        let result = try apply(e, pending(url, workflow: "afm"), draft(workflow: "afm", targets: [V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "op")]))
        let sourceID = try #require(result.v2TargetResults[0].sourceID)
        // Standardize again under a new operation ID: idempotent, no new follow-up, no extra Dataset.
        let coordinator = V2SourceStandardizationCoordinator(service: e.s.service, rootURL: e.s.root)
        let again = try coordinator.standardize(
            sourceID: sourceID, sampleUID: e.s.uidA, operationID: "again", fileName: "run.ibw", confirmedWorkflowID: "afm",
            autoPlotIntent: AutoPlotIntent(presetVersionID: preset.presetVersionID)
        )
        let c2 = try counts(e, e.s.uidA)
        #expect(again.autoPlotTrigger == nil && c2 == (1, 1))
        #expect(try e.s.service.followupStates(sourceID: sourceID, rootURL: e.s.root).count == 1)
    }

    // MARK: Unavailable copy, applicability, draft migration

    @Test("A damaged Library copy is reported as pending technical state, never as a refusal")
    func damagedCopyIsNotRefusal() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let url = try WP1SourceIngestTests.writeFile(Data(WP2StandardizationTests.ppms.utf8), name: "run.dat")
        let item = pending(url, workflow: "ahe")
        let d = draft(workflow: "ahe", targets: [V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "x")])
        e.s.service.faultHook = { if $0 == .standardizeBeforeCommit { throw T.Crash() } }
        let first = try apply(e, item, d)
        e.s.service.faultHook = nil
        let sourceID = try #require(first.v2TargetResults[0].sourceID)
        try Data("tampered".utf8).write(to: e.s.root.appending(path: "storage/\(sourceID)/payload.bin"))
        let second = try apply(e, item, d)
        #expect(second.isIncompleteV2)
        guard case .pending = second.v2TargetResults[0].standardize else { Issue.record("expected pending"); return }
        #expect(try e.s.service.sourceStatusSummaries(forSampleUID: e.s.uidA, rootURL: e.s.root).first?.standardization == .pending)
    }

    @Test("canApplyV2 needs valid targets only: no adapter, no workflow and no channels required")
    func applicability() {
        func d(_ targets: [V2IngestTarget], workflow: String = "") -> PendingImportConfirmationDraft {
            PendingImportConfirmationDraft(batchName: "", sampleName: "", measurementName: "", workflowID: workflow, conditionValues: [:],
                                           selectedExistingProjectName: "None", newProjectName: "", v2Targets: targets)
        }
        let live: (String) -> Bool = { $0 == "smp_ok" }
        #expect(InboxArchiveApplyService.canApplyV2(draft: d([V2IngestTarget(sampleUID: "smp_ok")]), isValidActiveSample: live))
        #expect(!InboxArchiveApplyService.canApplyV2(draft: d([]), isValidActiveSample: live))
        #expect(!InboxArchiveApplyService.canApplyV2(draft: nil, isValidActiveSample: live))
        #expect(!InboxArchiveApplyService.canApplyV2(draft: d([V2IngestTarget(sampleUID: "smp_ok"), V2IngestTarget(sampleUID: "smp_gone")]), isValidActiveSample: live))
        #expect(!InboxArchiveApplyService.canApplyV2(draft: d([V2IngestTarget(sampleUID: "smp_ok"), V2IngestTarget(sampleUID: "smp_ok")]), isValidActiveSample: live))
        // A target whose file is already stored stays applicable even if its Sample left the live set.
        #expect(InboxArchiveApplyService.canApplyV2(draft: d([V2IngestTarget(sampleUID: "smp_gone", ingestedSourceID: "src_1")]), isValidActiveSample: live))
    }

    @Test("Old single-target drafts migrate to one target without channels; old multi-target lists are not guessed")
    func draftMigration() throws {
        func decode(_ json: String) throws -> PendingImportConfirmationDraft {
            try JSONDecoder().decode(PendingImportConfirmationDraft.self, from: Data(json.utf8))
        }
        let single = try decode(#"{"workflowID":"afm","v2TargetSampleUID":"smp_1","v2OperationID":"op-1","v2ReuseSourceID":"src_9"}"#)
        #expect(single.v2Targets == [V2IngestTarget(sampleUID: "smp_1", ingestOperationID: "op-1", effectiveChannelIDs: nil, reuseSourceID: "src_9")])
        let multi = try decode(#"{"workflowID":"afm","v2TargetSampleUIDs":["smp_1","smp_2"]}"#)
        #expect(multi.v2Targets.isEmpty && multi.v2LegacyTargetsDiscarded)
        let roundTrip = try JSONDecoder().decode(PendingImportConfirmationDraft.self, from: JSONEncoder().encode(single))
        #expect(roundTrip == single)
    }
}

extension WP1CoordinationTests {
    @Test("Editing workflow after a target is stored does not break the retry of that target")
    func storedTargetIgnoresLaterEdits() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let url = try WP1SourceIngestTests.writeFile(Data(WP2StandardizationTests.ppms.utf8), name: "run.dat")
        let item = pending(url, workflow: "ahe")
        let first = try apply(e, item, draft(workflow: "ahe", targets: [V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "a")]))
        let sourceID = try #require(first.v2TargetResults[0].sourceID)
        var stored = V2IngestTarget(sampleUID: e.s.uidA, ingestOperationID: "a")
        stored.ingestedSourceID = sourceID
        let second = try apply(e, item, draft(workflow: "mr", targets: [stored]))
        #expect(!second.isIncompleteV2 && second.v2TargetResults[0].sourceID == sourceID)
    }

    @Test("A non-UTF-8 LVM file is a refusal, not an endless technical retry")
    func nonUTF8LVMIsRefusal() throws {
        let e = try makeEnv(); defer { cleanup(e) }
        let url = try WP1SourceIngestTests.writeFile(Data([0xFF, 0xFE, 0xFA, 0x80, 0x81]), name: "bad.lvm")
        let result = try apply(e, pending(url, workflow: nil), draft(workflow: "", targets: [V2IngestTarget(sampleUID: e.s.uidA)]))
        #expect(!result.isIncompleteV2)
        guard case .notStandardized = result.v2TargetResults[0].standardize else { Issue.record("expected refusal"); return }
    }
}
