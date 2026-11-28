import Foundation
import Testing
@testable import SpinLabApp

/// WP1 (Task 11 batch A): independent Source ingest, audited context amendment, schema 2→3.
/// Every library is an isolated temporary one.
@Suite("WP1 Source ingest")
struct WP1SourceIngestTests {
    typealias T = AssetTestSupport

    static func writeFile(_ bytes: Data, name: String = "run.dat") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "SpinLab_WP1_src_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try bytes.write(to: url)
        return url
    }

    static let sample = Data("[Header]\nTITLE,x\n[Data]\nTime,B1,B2,B3\n1,2,3,4\n".utf8)

    static func request(
        _ s: T.Scenario, file: URL, uid: String? = nil, op: String = UUID().uuidString,
        context: SourceContextInput = .unknown, channels: [EffectiveChannel]? = nil, reuse: String? = nil
    ) -> SourceIngestRequest {
        SourceIngestRequest(
            sourceFileURL: file, targetSampleUID: uid ?? s.uidA, operationID: op,
            context: context, effectiveChannels: channels, reuseSourceID: reuse
        )
    }

    private func rowCount(_ s: T.Scenario, _ table: String) throws -> Int {
        let db = try #require(try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false))
        return Int(try db.query("SELECT COUNT(*) AS n FROM \(table);").first?.int("n") ?? -1)
    }

    // MARK: AC1 — context round trip, unknown never guessed

    @Test("Context, channels, mtime and generic format round-trip through a reopened service")
    func contextRoundTrip() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try Self.writeFile(Self.sample, name: "AHE_sweep.dat")
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        let context = SourceContextInput(
            workflowID: "AHE", workflowOrigin: .rule,
            conditions: ["temperature": ContextConditionValue(value: "10K", origin: .manual)],
            measuredAt: "2026-11-01T10:00:00Z", measuredAtOrigin: .fallback,
            interpretation: ["rule": "filename"], legacyPath: "/old/place/AHE_sweep.dat"
        )
        let receipt = try s.service.ingestSource(
            Self.request(s, file: file, context: context, channels: [EffectiveChannel(id: "ch1", role: "Vxy")]), rootURL: s.root
        )
        #expect(receipt.sha256 == AssetHashing.sha256Hex(Self.sample) && receipt.byteSize == Self.sample.count && !receipt.reusedSource)

        let reopened = LibraryAssetService(libraryStore: s.store)
        let stored = try #require(try reopened.sourceContext(sourceID: receipt.sourceID, rootURL: s.root))
        #expect(stored.workflowID == "AHE" && stored.workflowOrigin == .rule)
        #expect(stored.conditions["temperature"] == ContextConditionValue(value: "10K", origin: .manual))
        #expect(stored.measuredAt == "2026-11-01T10:00:00Z" && stored.measuredAtOrigin == .fallback)
        #expect(stored.legacyPath == "/old/place/AHE_sweep.dat" && stored.interpretation["rule"] == "filename")
        #expect(stored.sourceMTime == ISO8601DateFormatter().string(from: modified))
        #expect(try reopened.effectiveChannels(sourceID: receipt.sourceID, rootURL: s.root) == [EffectiveChannel(id: "ch1", role: "Vxy")])
        let record = try #require(try reopened.listAssets(forSampleUID: s.uidA, rootURL: s.root).first)
        #expect(record.format == LibraryAssetService.genericSourceFormat && record.originalFilename == "AHE_sweep.dat")
        // The Library copy is byte-identical and there is no Dataset.
        #expect(try reopened.readSource(sourceID: receipt.sourceID, rootURL: s.root).bytes == Self.sample)
        #expect(try rowCount(s, "asset_dependencies") == 0)
    }

    @Test("Unknown stays unknown: no context, no channels means NULL, not 'all'; legacy Source without a row reads as unknown")
    func unknownIsNotGuessed() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try s.service.ingestSource(Self.request(s, file: try Self.writeFile(Self.sample)), rootURL: s.root)
        let stored = try #require(try s.service.sourceContext(sourceID: receipt.sourceID, rootURL: s.root))
        #expect(stored.workflowID == nil && stored.workflowOrigin == .unknown && stored.conditions.isEmpty && stored.measuredAtOrigin == .unknown)
        #expect(try s.service.effectiveChannels(sourceID: receipt.sourceID, rootURL: s.root) == nil)

        let db = try #require(try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false))
        try db.execute("DELETE FROM source_context WHERE source_id = ?;", [.text(receipt.sourceID)])
        #expect(try s.service.sourceContext(sourceID: receipt.sourceID, rootURL: s.root) == nil)
        let status = try #require(try s.service.sourceStatusSummaries(forSampleUID: s.uidA, rootURL: s.root).first)
        #expect(!status.hasContextRow && status.workflowID == nil && status.standardization == .pending)
    }

    // MARK: AC2 — multi-target

    @Test("One multi-channel file for two samples: two Sources with identical bytes and separate effective channels")
    func multiTarget() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try Self.writeFile(Self.sample)
        let a = try s.service.ingestSource(Self.request(s, file: file, uid: s.uidA, channels: [EffectiveChannel(id: "ch1")]), rootURL: s.root)
        let b = try s.service.ingestSource(Self.request(s, file: file, uid: s.uidB, channels: [EffectiveChannel(id: "ch3"), EffectiveChannel(id: "ch2")]), rootURL: s.root)
        #expect(a.sourceID != b.sourceID && a.sha256 == b.sha256)
        #expect(try s.service.effectiveChannels(sourceID: a.sourceID, rootURL: s.root)?.map(\.id) == ["ch1"])
        #expect(try s.service.effectiveChannels(sourceID: b.sourceID, rootURL: s.root)?.map(\.id) == ["ch2", "ch3"])
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).map(\.id) == [a.sourceID])
        #expect(try s.service.readSource(sourceID: a.sourceID, rootURL: s.root).bytes == s.service.readSource(sourceID: b.sourceID, rootURL: s.root).bytes)
    }

    // MARK: AC1++ — replay and reuse

    @Test("Replay of a committed operation returns the original receipt without reading the external file")
    func replayNeedsNoFile() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try Self.writeFile(Self.sample)
        let context = SourceContextInput(workflowID: "AHE", workflowOrigin: .manual)
        let first = try s.service.ingestSource(Self.request(s, file: file, op: "op-1", context: context), rootURL: s.root)
        try FileManager.default.removeItem(at: file)
        #expect(try s.service.ingestSource(Self.request(s, file: file, op: "op-1", context: context), rootURL: s.root) == first)
        // Different request under the same operation ID: refused. Other Sample: refused.
        #expect(throws: LibraryAssetError.operationRequestMismatch("op-1")) {
            try s.service.ingestSource(Self.request(s, file: file, op: "op-1", context: SourceContextInput(workflowID: "RT", workflowOrigin: .manual)), rootURL: s.root)
        }
        #expect(throws: LibraryAssetError.self) {
            try s.service.ingestSource(Self.request(s, file: file, uid: s.uidB, op: "op-1", context: context), rootURL: s.root)
        }
        #expect(try rowCount(s, "source_context") == 1)
    }

    @Test("Reuse: unknown values do not constrain, a different confirmed value is a contextConflict, new Source never duplicated")
    func reuseSemantics() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try Self.writeFile(Self.sample)
        let first = try s.service.ingestSource(Self.request(s, file: file, context: SourceContextInput(workflowID: "AHE", workflowOrigin: .rule)), rootURL: s.root)
        let reused = try s.service.ingestSource(Self.request(s, file: file, context: .unknown, reuse: first.sourceID), rootURL: s.root)
        #expect(reused.sourceID == first.sourceID && reused.reusedSource)
        #expect(throws: LibraryAssetError.self) {
            try s.service.ingestSource(Self.request(s, file: file, context: SourceContextInput(workflowID: "RT", workflowOrigin: .manual), reuse: first.sourceID), rootURL: s.root)
        }
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 1)
        // The same file for another Sample cannot reuse this Source.
        #expect(throws: LibraryAssetError.self) {
            try s.service.ingestSource(Self.request(s, file: file, uid: s.uidB, reuse: first.sourceID), rootURL: s.root)
        }
    }

    // MARK: Real ingest failures

    @Test("Only real failures reject ingest, and they leave no residue")
    func ingestFailures() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let empty = try Self.writeFile(Data())
        #expect(throws: LibraryAssetError.self) { try s.service.ingestSource(Self.request(s, file: empty), rootURL: s.root) }
        let missing = FileManager.default.temporaryDirectory.appending(path: "nope-\(UUID().uuidString).dat")
        #expect(throws: LibraryAssetError.self) { try s.service.ingestSource(Self.request(s, file: missing), rootURL: s.root) }
        let file = try Self.writeFile(Self.sample)
        #expect(throws: LibraryAssetError.self) { try s.service.ingestSource(Self.request(s, file: file, uid: "smp_missing"), rootURL: s.root) }
        let trashed = try s.store.moveSampleToTrash(sample: s.sampleB, rootURL: s.root)
        _ = trashed
        #expect(throws: LibraryAssetError.self) { try s.service.ingestSource(Self.request(s, file: file, uid: s.uidB), rootURL: s.root) }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage").path)) ?? []
        #expect(entries.filter { $0 != ".DS_Store" }.isEmpty)
        #expect(try rowCount(s, "assets") == 0)
    }

    // MARK: AC4 — crash points

    @Test("A crash before the commit rolls back completely and the retry stores exactly one Source")
    func crashBeforeCommit() throws {
        for point in [AssetFaultPoint.ingestAfterSourceWritten, .ingestBeforeCommit] {
            let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
            let file = try Self.writeFile(Self.sample)
            s.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) { try s.service.ingestSource(Self.request(s, file: file, op: "op-c"), rootURL: s.root) }
            let restarted = LibraryAssetService(libraryStore: s.store)
            let receipt = try restarted.ingestSource(Self.request(s, file: file, op: "op-c"), rootURL: s.root)
            #expect(try restarted.listAssets(forSampleUID: s.uidA, rootURL: s.root).map(\.id) == [receipt.sourceID])
            #expect(try rowCount(s, "source_context") == 1 && rowCount(s, "sample_asset_links") == 1)
            let dirs = try FileManager.default.contentsOfDirectory(atPath: s.root.appending(path: "storage").path).filter { $0 != ".DS_Store" }
            #expect(dirs == [receipt.sourceID])
        }
    }

    @Test("A crash right after the commit replays to the same receipt")
    func crashAfterCommit() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try Self.writeFile(Self.sample)
        s.service.faultHook = { if $0 == .ingestAfterCommit { throw T.Crash() } }
        #expect(throws: T.Crash.self) { try s.service.ingestSource(Self.request(s, file: file, op: "op-d"), rootURL: s.root) }
        s.service.faultHook = nil
        let receipt = try s.service.ingestSource(Self.request(s, file: file, op: "op-d"), rootURL: s.root)
        #expect(try s.service.listAssets(forSampleUID: s.uidA, rootURL: s.root).map(\.id) == [receipt.sourceID])
    }

    // MARK: AC1+ — audited amendment

    @Test("Amendment only turns unknown into manual-confirmed, is audited and idempotent, and never touches the Source")
    func amendment() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try Self.writeFile(Self.sample)
        let receipt = try s.service.ingestSource(Self.request(s, file: file, op: "ing"), rootURL: s.root)
        let changes = SourceContextAmendment(workflowID: "AHE", conditions: ["temperature": "10K"], effectiveChannels: [EffectiveChannel(id: "ch2")])
        let done = try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am-1", changes: changes, rootURL: s.root)
        #expect(Set(done.changedFields) == ["workflow", "condition:temperature", "effectiveChannels"])
        let stored = try #require(try s.service.sourceContext(sourceID: receipt.sourceID, rootURL: s.root))
        #expect(stored.workflowID == "AHE" && stored.workflowOrigin == .manual)
        #expect(stored.conditions["temperature"] == ContextConditionValue(value: "10K", origin: .manual))
        #expect(try s.service.effectiveChannels(sourceID: receipt.sourceID, rootURL: s.root)?.map(\.id) == ["ch2"])
        #expect(try s.service.contextAmendmentCount(sourceID: receipt.sourceID, rootURL: s.root) == 1)
        // Identity of the Source is untouched; the original ingest replays to its original receipt.
        #expect(try s.service.readSource(sourceID: receipt.sourceID, rootURL: s.root).sha256 == receipt.sha256)
        #expect(try s.service.ingestSource(Self.request(s, file: file, op: "ing"), rootURL: s.root) == receipt)
        // Replay: same result, no second audit row. Same ID with other content: mismatch.
        #expect(try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am-1", changes: changes, rootURL: s.root) == done)
        #expect(try s.service.contextAmendmentCount(sourceID: receipt.sourceID, rootURL: s.root) == 1)
        #expect(throws: LibraryAssetError.operationRequestMismatch("am-1")) {
            try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am-1", changes: SourceContextAmendment(workflowID: "RT"), rootURL: s.root)
        }
        // A confirmed value cannot be changed; an empty amendment is refused.
        #expect(throws: LibraryAssetError.self) {
            try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am-2", changes: SourceContextAmendment(workflowID: "RT"), rootURL: s.root)
        }
        #expect(throws: LibraryAssetError.self) {
            try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am-3", changes: SourceContextAmendment(effectiveChannels: [EffectiveChannel(id: "ch3")]), rootURL: s.root)
        }
        #expect(throws: LibraryAssetError.self) {
            try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am-4", changes: SourceContextAmendment(), rootURL: s.root)
        }
        // After amendment, reuse with an unknown value does not conflict; with a different confirmed value it does.
        #expect(try s.service.ingestSource(Self.request(s, file: file, context: .unknown, reuse: receipt.sourceID), rootURL: s.root).reusedSource)
        #expect(throws: LibraryAssetError.self) {
            try s.service.ingestSource(Self.request(s, file: file, context: SourceContextInput(workflowID: "RT", workflowOrigin: .manual), reuse: receipt.sourceID), rootURL: s.root)
        }
    }

    @Test("Amending a legacy Source without a context row creates the row")
    func amendLegacy() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try s.service.ingestSource(Self.request(s, file: try Self.writeFile(Self.sample)), rootURL: s.root)
        let db = try #require(try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false))
        try db.execute("DELETE FROM source_context WHERE source_id = ?;", [.text(receipt.sourceID)])
        _ = try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am", changes: SourceContextAmendment(workflowID: "RT"), rootURL: s.root)
        #expect(try s.service.sourceContext(sourceID: receipt.sourceID, rootURL: s.root)?.workflowID == "RT")
    }

    // MARK: AC4+ — deletion closure with foreign keys on

    @Test("Deleting a Source-only Source with context, outcome, amendment and follow-up rows leaves no row behind")
    func deletionClosure() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try s.service.ingestSource(Self.request(s, file: try Self.writeFile(Self.sample)), rootURL: s.root)
        _ = try s.service.amendSourceContext(sourceID: receipt.sourceID, operationID: "am", changes: SourceContextAmendment(workflowID: "RT"), rootURL: s.root)
        _ = try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: nil, operationID: "std", rootURL: s.root)
        try s.service.recordFollowup(standardizeOperationID: "std", sourceID: receipt.sourceID, kind: "auto_plot", requestJSON: "{}", rootURL: s.root)
        let plan = try s.service.planAssetDeletion(target: .source(receipt.sourceID), rootURL: s.root)
        _ = try s.service.commitAssetDeletion(target: .source(receipt.sourceID), plan: plan, operationID: "del", rootURL: s.root)
        for table in ["assets", "source_context", "standardization_outcome", "context_amendment", "coordinator_followup", "sample_asset_links"] {
            #expect(try rowCount(s, table) == 0, "\(table) must be empty")
        }
    }

    @Test("A Sample's permanent deletion plan treats a Source-only Source like any Source")
    func sourceOnlyFollowsSampleDeletion() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try s.service.ingestSource(Self.request(s, file: try Self.writeFile(Self.sample)), rootURL: s.root)
        let trashed = try s.store.moveSampleToTrash(sample: s.sampleA, rootURL: s.root)
        _ = trashed
        let plan = try s.service.planPermanentSampleDeletion(sampleUIDs: [s.uidA], rootURL: s.root)
        #expect(plan.assetsToDelete == [receipt.sourceID] && plan.deleteMeasurementCount == 1)
    }

    // MARK: Schema 2 → 3

    private func makeVersion2Library() throws -> (root: URL, store: LibraryStore) {
        let root = FileManager.default.temporaryDirectory.appending(path: "SpinLab_WP1_v2_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore()
        try store.initializeV2Library(at: root)
        let url = LibraryAssetDatabase.databaseURL(rootURL: root)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Build a genuine schema-2 database from the unchanged base statements.
        let db = try LibraryAssetDatabase.openForTesting(at: url)
        try db.transaction {
            for statement in LibraryAssetDatabase.schemaStatements { try db.execute(statement) }
            try db.execute("INSERT INTO schema_meta(key, value) VALUES ('schema_version', '2'), ('layout_version', '2');")
            try db.execute("INSERT INTO assets(asset_id, kind, format, status, storage_rel_path, current_revision, files_json, created_at, updated_at) VALUES ('src_old', 'source', 'ibw_v5', 'ready', 'storage/src_old', 1, '[]', 'x', 'x');")
        }
        return (root, store)
    }

    @Test("A schema 2 library is refused by read paths, upgraded by a writer in one step, and keeps its data")
    func upgradeFromVersion2() throws {
        let (root, store) = try makeVersion2Library(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: LibraryAssetError.databaseUpgradeRequired("2")) {
            _ = try LibraryAssetDatabase.open(rootURL: root, createIfMissing: false)
        }
        let db = try #require(try LibraryAssetDatabase.open(rootURL: root, createIfMissing: false, upgrade: true))
        #expect(try db.query("SELECT value FROM schema_meta WHERE key = 'schema_version';").first?.string("value") == "3")
        #expect(try db.query("SELECT asset_id FROM assets;").first?.string("asset_id") == "src_old")
        _ = try db.query("SELECT effective_channels_json FROM sample_asset_links;")
        for table in LibraryAssetDatabase.schema3Tables { _ = try db.query("SELECT * FROM \(table);") }
        _ = store
    }

    @Test("An interrupted upgrade rolls back entirely and can be retried; unknown newer versions stay refused")
    func upgradeAtomicity() throws {
        let (root, _) = try makeVersion2Library(); defer { try? FileManager.default.removeItem(at: root) }
        let blocker = try #require(try? LibraryAssetDatabase.openForTesting(at: LibraryAssetDatabase.databaseURL(rootURL: root)))
        try blocker.execute("CREATE TABLE standardization_outcome (x TEXT);")   // makes the upgrade fail midway
        #expect(throws: (any Error).self) { _ = try LibraryAssetDatabase.open(rootURL: root, createIfMissing: false, upgrade: true) }
        let check = try LibraryAssetDatabase.openForTesting(at: LibraryAssetDatabase.databaseURL(rootURL: root))
        #expect(try check.query("SELECT value FROM schema_meta WHERE key = 'schema_version';").first?.string("value") == "2")
        #expect(throws: (any Error).self) { _ = try check.query("SELECT effective_channels_json FROM sample_asset_links;") }
        try check.execute("DROP TABLE standardization_outcome;")
        #expect(try LibraryAssetDatabase.open(rootURL: root, createIfMissing: false, upgrade: true) != nil)

        try check.execute("UPDATE schema_meta SET value = '4' WHERE key = 'schema_version';")
        #expect(throws: LibraryAssetError.databaseUnknownVersion("4")) {
            _ = try LibraryAssetDatabase.open(rootURL: root, createIfMissing: false, upgrade: true)
        }
    }

    // MARK: Structure (AC3): ingest knows nothing about the other steps

    @Test("The ingest module does not reference adapters, Datasets, Workbench or plotting; standardize does not write ingest data")
    func structure() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/SpinLabApp/Library/Assets")
        func code(_ name: String) throws -> String {
            try String(contentsOf: dir.appending(path: name), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        // `StandardizedFile` is the shared name+bytes container used by every writer, not a Dataset notion.
        let ingest = try code("LibraryAssetService+SourceIngest.swift").replacingOccurrences(of: "StandardizedFile", with: "")
        for token in ["AssetStandardizationAdapter", "StandardizedDataset", "Dataset", "dataset", "Workbench", "AutoPlot", "Plot", "tandardiz"] {
            #expect(!ingest.contains(token), "the ingest module must not mention \(token)")
        }
        let standardize = try code("LibraryAssetService+Standardize.swift")
        for token in ["ingestSource(", "amendSourceContext(", "INSERT INTO sample_asset_links", "INSERT INTO source_context", "UPDATE source_context", "effective_channels_json"] {
            #expect(!standardize.contains(token), "standardize must not use \(token)")
        }
    }
}
