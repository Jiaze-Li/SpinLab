import Foundation
import Testing
@testable import SpinLabApp

@Suite("Unified Sample creation, legacy backfill and authority guard (PR 220)")
struct UnifiedSampleCreationTests {
    // MARK: helpers

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-unified-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = e?.nextObject() as? URL {
            if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { continue }
            if url.lastPathComponent == "_smp_backfill.lock" { continue } // empty housekeeping file, holds no library data
            out[String(url.path.dropFirst(root.path.count))] = try Data(contentsOf: url)
        }
        return out
    }

    private func registrySample(cue: String, batchId: String = "B1", note: String = "") -> LibrarySample {
        LibrarySample(
            id: cue, displayName: "\(batchId) - STO(001)", batchId: batchId,
            substrateRaw: "STO(001)", substrateDisplay: "STO(001)", substrateTokens: ["STO", "001"], substrateTags: ["STO"],
            metadata: note.isEmpty ? [:] : ["Note": note], orderedMetadata: [], numericTags: [:], numericDisplay: [:],
            sourceSheetName: "Sheet1", sourceRowNumber: 2, updatedAt: Date(),
            legacySampleKey: cue, origin: "registry"
        )
    }

    private func registryPreview(samples: [LibrarySample], batchId: String = "B1") -> LibraryPreview {
        let batch = LibraryBatch(
            id: batchId, displayName: batchId, sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:],
            sampleKeys: samples.map(\.id), updatedAt: Date()
        )
        let index = LibraryIndex(
            version: 1, createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil,
            metadataColumnOrder: [], batches: [batch], samples: samples
        )
        return LibraryPreview(index: index, warnings: [])
    }

    private func syncService(_ store: LibraryStore) -> LibrarySyncService {
        LibrarySyncService(libraryStore: store, libraryDiffEngine: LibraryDiffEngine())
    }

    private func legacyDrawer(_ store: LibraryStore, root: URL, id: String, batchId: String = "OLD") throws {
        let sample = LibrarySample(
            id: id, displayName: id, batchId: batchId, substrateRaw: "", substrateDisplay: "", substrateTokens: [],
            substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:],
            sourceSheetName: "Hist", sourceRowNumber: 3, updatedAt: Date()
        )
        let batch = LibraryBatch(id: batchId, displayName: batchId, sheetName: "Hist", metadata: [:], numericTags: [:],
                                 numericDisplay: [:], sampleKeys: [id], updatedAt: Date())
        // Batch may already hold other keys.
        let existing = store.decodeBatch(from: store.resolvedBatchDirectoryURL(root, batchID: batchId).appending(path: "batch.json"))
        var merged = batch
        if let existing { merged.sampleKeys = Array(Set(existing.sampleKeys + [id])).sorted() }
        try store.createDrawer(for: sample, batch: merged, rootURL: root)
    }

    // MARK: AC-1 one rule, one issuer

    @Test("Identity rule validates, derives phone UIDs deterministically and the issuer reuses valid UIDs")
    func identityRuleAndIssuer() {
        let random = SampleIdentityRule.makeRandomUID()
        #expect(SampleIdentityRule.isValidUID(random))
        #expect(!SampleIdentityRule.isValidUID("smp_"))
        #expect(!SampleIdentityRule.isValidUID("smp_XYZ"))
        #expect(!SampleIdentityRule.isValidUID("LEGACY_01"))
        #expect(!SampleIdentityRule.isValidUID("smp_٣abc"), "Arabic-Indic digit is not ASCII hex")
        #expect(!SampleIdentityRule.isValidUID("smp_abc²"), "superscript digit is not ASCII hex")
        #expect(!SampleIdentityRule.isValidUID("smp_abc½"), "fraction is not ASCII hex")
        #expect(SampleIdentityRule.isValidUID("smp_0a1b-2c"))
        #expect(SampleIdentityRule.uid(forSubmissionId: "ABC-123", index: 0) == "smp_abc-123")
        #expect(SampleIdentityRule.uid(forSubmissionId: "ABC-123", index: 1) == "smp_abc-123-2")
        #expect(SampleIdentityRule.uid(forSubmissionId: "ABC-123", index: 2) == "smp_abc-123-3")
        #expect(PhoneSamplePickup.sampleUID(forSubmission: "ABC-123") == "smp_abc-123")
        #expect(NewSampleFields.sampleUID(base: "smp_abc-123", index: 1) == "smp_abc-123-2")
        #expect(NativeSampleCreationService.makeSampleUID().hasPrefix("smp_"))
        #expect(SampleIDIssuer.issueForNewSample(preferredUID: "smp_abc-1") == "smp_abc-1")
        #expect(SampleIDIssuer.issueForNewSample(preferredUID: "not-valid") != "not-valid")
        #expect(SampleIdentityRule.isValidUID(SampleIDIssuer.issueForNewSample()))
    }

    @Test("Hand-made, phone-style and XLSX creation all go through createSample and get a valid smp_ UID")
    func threePathsOneEntry() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        let settings = LibrarySettings.default
        let service = NativeSampleCreationService()

        // desktop
        guard case let .success(desktop, _, _) = service.createSample(
            draft: CreateNativeSampleDraft(batchId: "B1", substrateDescription: "STO(001)"),
            rootURL: root, libraryStore: store, settings: settings) else { Issue.record("desktop"); return }
        // phone: deterministic UID, repeated pull is idempotent
        var phoneDraft = CreateNativeSampleDraft(batchId: "B1", substrateDescription: "LAO(001)")
        phoneDraft.sampleUID = PhoneSamplePickup.sampleUID(forSubmission: UUID().uuidString)
        guard case let .success(phone, _, _) = service.createSample(draft: phoneDraft, rootURL: root, libraryStore: store, settings: settings),
              case let .success(phoneAgain, _, again) = service.createSample(draft: phoneDraft, rootURL: root, libraryStore: store, settings: settings)
        else { Issue.record("phone"); return }
        #expect(phone.id == phoneAgain.id)
        #expect(again.samples.filter { $0.id == phone.id }.count == 1)
        // XLSX
        let preview = registryPreview(samples: [registrySample(cue: "B1||STO|001")])
        _ = try syncService(store).applyAll(preview: preview, rootURL: root, settings: settings)
        let index = try store.readOnlyCompleteIndex(rootURL: root)
        let registry = try #require(index.samples.first { $0.origin == "registry" })

        for s in [desktop, phone, registry] {
            #expect(SampleIdentityRule.isValidUID(s.sampleUID ?? ""))
            #expect(s.id == s.sampleUID)
        }
        #expect(desktop.origin == "native" && phone.origin == "native")
        #expect(registry.legacySampleKey == "B1||STO|001")
        #expect(registry.sourceSheetName == "Sheet1" && registry.sourceRowNumber == 2)
        #expect(Set(index.samples.map(\.id)).count == 3)
    }

    // MARK: AC-2 / AC-3 sync behaviour

    @Test("Syncing the same XLSX twice updates the stored sample and never creates a second one")
    func repeatedSyncUpdatesInPlace() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        let settings = LibrarySettings.default
        let svc = syncService(store)
        let cue = "B1||STO|001"

        _ = try svc.applyAll(preview: registryPreview(samples: [registrySample(cue: cue)]), rootURL: root, settings: settings)
        let first = try #require(try store.readOnlyCompleteIndex(rootURL: root).samples.first)

        let second = registryPreview(samples: [registrySample(cue: cue, note: "edited")])
        let diff = LibraryDiffEngine().diff(current: try store.readOnlyCompleteIndex(rootURL: root), updated: second.index)
        #expect(diff.newSamples.isEmpty, "the row must be recognised through its legacy key")
        _ = try svc.applyAll(preview: second, rootURL: root, settings: settings)

        let after = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(after.samples.count == 1)
        let s = try #require(after.samples.first)
        #expect(s.id == first.id && s.sampleUID == first.sampleUID && s.legacySampleKey == cue)
        #expect(s.metadata["Note"] == "edited")
        #expect(after.batches.first?.sampleKeys == [first.id], "batch lists the issued id, not the old key")

        // applyBatch path
        let third = registryPreview(samples: [registrySample(cue: cue, note: "again")])
        _ = try svc.applyBatch(batchId: "B1", preview: third, rootURL: root, settings: settings)
        let end = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(end.samples.count == 1 && end.samples[0].id == first.id && end.samples[0].metadata["Note"] == "again")
    }

    @Test("Creating the same Registry row twice from a stale baseline reuses the first sample (no duplicate)")
    func registryCreatorIsIdempotentOnStaleBaseline() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        let creator = RegistrySampleCreator(libraryStore: store, settings: LibrarySettings.default)
        let sample = registrySample(cue: "B1||STO|001")
        let preview = registryPreview(samples: [sample])
        let batch = try #require(preview.index.batches.first)

        guard case let .success(first, _, _) = creator.create(sample, batch: batch, rootURL: root) else { Issue.record("first create must succeed"); return }
        guard case let .success(second, _, _) = creator.create(sample, batch: batch, rootURL: root) else { Issue.record("repeat create must succeed"); return }
        #expect(second.id == first.id && second.sampleUID == first.sampleUID)
        #expect(try store.readOnlyCompleteIndex(rootURL: root).samples.count == 1)
    }

    @Test("A hand-made sample with the same batch and substrate coexists with the XLSX one and is never touched")
    func nativeAndRegistryCoexist() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        let settings = LibrarySettings.default
        let cue = "B1||STO|001"
        guard case let .success(native, _, _) = NativeSampleCreationService().createSample(
            draft: CreateNativeSampleDraft(batchId: "B1", substrateDescription: "STO(001)"),
            rootURL: root, libraryStore: store, settings: settings) else { Issue.record("native"); return }
        let nativeBytes = try Data(contentsOf: store.sampleDirectoryURL(root, batchID: "B1", sampleKey: native.id).appending(path: "sample.json"))

        let svc = syncService(store)
        for note in ["", "v2"] {
            _ = try svc.applyAll(preview: registryPreview(samples: [registrySample(cue: cue, note: note)]), rootURL: root, settings: settings)
        }
        let index = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(index.samples.count == 2)
        #expect(index.samples.filter { $0.origin == "native" }.count == 1)
        #expect(index.samples.filter { $0.origin == "registry" }.count == 1)
        #expect(Set(index.samples.compactMap(\.sampleUID)).count == 2)
        #expect(try Data(contentsOf: store.sampleDirectoryURL(root, batchID: "B1", sampleKey: native.id).appending(path: "sample.json")) == nativeBytes)
        #expect(Set(try #require(index.batches.first).sampleKeys) == Set(index.samples.map(\.id)))
    }

    @Test("A legacy sample is matched by its old key, keeps its id and folder, and is updated not duplicated")
    func legacySampleMatchedByOldKey() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        try legacyDrawer(store, root: root, id: "B1||STO|001", batchId: "B1")
        let preview = registryPreview(samples: [registrySample(cue: "B1||STO|001", note: "n")])
        _ = try syncService(store).applyAll(preview: preview, rootURL: root, settings: .default)
        let index = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(index.samples.count == 1 && index.samples[0].id == "B1||STO|001")
        #expect(index.samples[0].metadata["Note"] == "n")
    }

    // MARK: AC-4 / AC-5 backfill

    @Test("Backfill: dry run writes nothing; real run issues smp_ in place, records the old key and is idempotent")
    func backfillHappyPathAndIdempotence() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        try legacyDrawer(store, root: root, id: "LEG_01")
        try legacyDrawer(store, root: root, id: "LEG_02")
        let measurement = store.sampleDirectoryURL(root, batchID: "OLD", sampleKey: "LEG_01").appending(path: "measurements/data.dat")
        try FileManager.default.createDirectory(at: measurement.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "1 2 3".write(to: measurement, atomically: true, encoding: .utf8)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        let before = try snapshot(root)
        let dry = try LegacySampleBackfillService().run(libraryStore: store, rootURL: root, dryRun: true)
        #expect(dry.pending.count == 2 && dry.issued == 0)
        #expect(try snapshot(root) == before, "dry run must leave the disk untouched")

        var rebuilds = 0
        var service = LegacySampleBackfillService()
        service.hooks.onIndexRebuild = { rebuilds += 1 }
        let report = try service.run(libraryStore: store, rootURL: root, dryRun: false)
        #expect(report.succeeded && report.issued == 2 && rebuilds == 1 && report.indexRebuilds == 1)
        #expect(report.backupDirectory.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        let index = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(Set(index.samples.map(\.id)) == ["LEG_01", "LEG_02"], "ids and folders do not change")
        for s in index.samples {
            #expect(SampleIdentityRule.isValidUID(s.sampleUID ?? ""))
            #expect(s.legacySampleKey == s.id)
        }
        #expect(try String(contentsOf: measurement, encoding: .utf8) == "1 2 3")

        let uids = Set(index.samples.compactMap(\.sampleUID))
        let again = try service.run(libraryStore: store, rootURL: root, dryRun: false)
        #expect(again.issued == 0 && again.skippedAlreadyIssued == 2)
        #expect(Set(try store.readOnlyCompleteIndex(rootURL: root).samples.compactMap(\.sampleUID)) == uids)
    }

    @Test("Backfill: a failed backup aborts before any sample is written")
    func backfillBackupFailureWritesNothing() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        try legacyDrawer(store, root: root, id: "LEG_01")
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        let before = try snapshot(root)
        var service = LegacySampleBackfillService()
        struct Boom: Error {}
        service.hooks.beforeBackup = { throw Boom() }
        #expect(throws: LegacySampleBackfillService.BackfillError.self) {
            try service.run(libraryStore: store, rootURL: root, dryRun: false)
        }
        #expect(try snapshot(root) == before)
    }

    @Test("Backfill: one failed sample write keeps that file intact, issues no ghost UID and the run reports failure")
    func backfillSingleWriteFailure() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        try legacyDrawer(store, root: root, id: "LEG_01")
        try legacyDrawer(store, root: root, id: "LEG_02")
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        let failingFile = store.sampleDirectoryURL(root, batchID: "OLD", sampleKey: "LEG_02").appending(path: "sample.json")
        let original = try Data(contentsOf: failingFile)

        var service = LegacySampleBackfillService()
        struct WriteBoom: Error {}
        service.hooks.beforeSampleWrite = { if $0.id == "LEG_02" { throw WriteBoom() } }
        var rebuilds = 0
        service.hooks.onIndexRebuild = { rebuilds += 1 }
        let report = try service.run(libraryStore: store, rootURL: root, dryRun: false)

        #expect(!report.succeeded && report.issued == 1 && report.failures.count == 1)
        #expect(report.missingAfterwards == ["LEG_02"], "completeness check must flag the sample without an ID")
        #expect(rebuilds == 1)
        #expect(try Data(contentsOf: failingFile) == original)
        let index = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(index.samples.first { $0.id == "LEG_02" }?.sampleUID == nil)
        #expect(SampleIdentityRule.isValidUID(index.samples.first { $0.id == "LEG_01" }?.sampleUID ?? ""))
    }

    @Test("Backfill is exclusive: a second run while one is in progress changes nothing, and the lock is released afterwards")
    func backfillIsExclusive() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        try legacyDrawer(store, root: root, id: "LEG_01")
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        let file = store.sampleDirectoryURL(root, batchID: "OLD", sampleKey: "LEG_01").appending(path: "sample.json")
        let original = try Data(contentsOf: file)

        var inner: Error?
        var service = LegacySampleBackfillService()
        // While the first run is in progress (before its first sample write), start a second real run.
        service.hooks.beforeSampleWrite = { _ in
            do { _ = try LegacySampleBackfillService().run(libraryStore: store, rootURL: root, dryRun: false) } catch { inner = error }
        }
        // The nested run must be refused; the outer run proceeds normally.
        _ = try service.run(libraryStore: store, rootURL: root, dryRun: false)
        #expect((inner as? LegacySampleBackfillService.BackfillError) == .alreadyRunning)
        #expect(try Data(contentsOf: file) != original, "the first run still issued its ID")

        // Lock released: a later run is allowed (nothing pending, so it is a no-op that succeeds).
        let again = try LegacySampleBackfillService().run(libraryStore: store, rootURL: root, dryRun: false)
        #expect(again.succeeded && again.issued == 0)
    }

    @Test("Backfill never overwrites a UID another run issued after the plan was read")
    func backfillKeepsConcurrentlyIssuedUID() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(); store.ensureRoot(at: root)
        try legacyDrawer(store, root: root, id: "LEG_01")
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        let file = store.sampleDirectoryURL(root, batchID: "OLD", sampleKey: "LEG_01").appending(path: "sample.json")
        let rival = "smp_aaaa-bbbb"
        var service = LegacySampleBackfillService()
        service.hooks.beforeSampleWrite = { _ in
            var other = try #require(store.decodeSample(from: file))
            other.sampleUID = rival
            try store.writeSampleChecked(other, to: file.deletingLastPathComponent())
        }
        let report = try service.run(libraryStore: store, rootURL: root, dryRun: false)
        #expect(report.issued == 0 && report.succeeded)
        #expect(try store.readOnlyCompleteIndex(rootURL: root).samples.first?.sampleUID == rival)
    }

    // MARK: AC-6 UI

    @Test("Library detail shows the permanent UID, never the old Sample Key")
    func detailShowsUID() {
        var sample = registrySample(cue: "OLD||KEY")
        sample.sampleUID = "smp_0000-1111"
        let sections = LibraryViewComputationService().makeDetailSections(for: sample)
        let labels = sections.allFields.map(\.label)
        #expect(!labels.contains("Sample Key"))
        #expect(sections.allFields.first { $0.label == "Sample UID" }?.value == "smp_0000-1111")
        #expect(!sections.allFields.contains { $0.value == "OLD||KEY" })
        sample.sampleUID = nil
        #expect(LibraryViewComputationService().makeDetailSections(for: sample).allFields
            .first { $0.label == "Sample UID" }?.value == "Not issued yet")
    }

    // MARK: AC-8 authority guard

    @Test("No code outside the creation service creates sample drawers or spells the smp_ rule")
    func creationAuthorityGuard() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/SpinLabApp", directoryHint: .isDirectory)
        let e = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var drawerOffenders: [String] = []
        var ruleOffenders: [String] = []
        while let url = e.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let name = url.lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            if code.contains(".createDrawer(for:"), !["NativeSampleCreationService.swift"].contains(name) {
                drawerOffenders.append(name)
            }
            if code.contains("\"smp_"), name != "SampleIdentityRule.swift" { ruleOffenders.append(name) }
        }
        #expect(drawerOffenders.isEmpty, "createDrawer outside the creation service: \(drawerOffenders)")
        #expect(ruleOffenders.isEmpty, "smp_ spelled outside SampleIdentityRule: \(ruleOffenders)")
    }
}
