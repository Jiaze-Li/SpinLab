import CryptoKit
import Foundation
import Testing
@testable import SpinLabApp

/// P0 Library data safety, Phase 1: startup, browse and selection never write
/// the physical Library. Every test snapshots the whole Library tree (paths,
/// kinds, SHA-256, mtimes) before and after and requires zero differences.
@MainActor
@Suite("P0 read-only startup")
struct P0ReadOnlyStartupTests {

    // MARK: - Tree snapshot (detects any create / modify / delete / touch)

    private struct TreeEntry: Equatable {
        var kind: String
        var sha256: String
        var mtime: TimeInterval
    }

    private static func snapshot(_ root: URL) -> [String: TreeEntry] {
        let fm = FileManager.default
        var result: [String: TreeEntry] = [:]
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: []) else {
            return result
        }
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isDir = values?.isDirectory == true
            let rel = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
            let digest: String
            if isDir {
                digest = "-"
            } else if let data = try? Data(contentsOf: url) {
                digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            } else {
                digest = "unreadable"
            }
            result[rel] = TreeEntry(
                kind: isDir ? "dir" : "file",
                sha256: digest,
                mtime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            )
        }
        return result
    }

    // MARK: - Fixtures

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "p0-readonly-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAppState() -> SpinLabAppState {
        SpinLabAppState(
            persistence: LocalPersistenceStub(),
            libraryArchiveScan: LibraryArchiveScanService(
                rootURL: FileManager.default.temporaryDirectory
                    .appending(path: "p0-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
            )
        )
    }

    private func batch(_ id: String, keys: [String]) -> LibraryBatch {
        LibraryBatch(
            id: id, displayName: id, sheetName: "STO",
            metadata: [:], numericTags: [:], numericDisplay: [:],
            sampleKeys: keys, updatedAt: Date()
        )
    }

    private func sample(_ id: String, name: String, batchId: String) -> LibrarySample {
        LibrarySample(
            id: id, displayName: name, batchId: batchId,
            substrateRaw: "", substrateDisplay: "", substrateTokens: [],
            substrateTags: [], metadata: [:], orderedMetadata: [],
            numericTags: [:], numericDisplay: [:],
            sourceSheetName: nil, sourceRowNumber: nil, updatedAt: Date()
        )
    }

    /// Library with a persisted index that is STALE relative to the files:
    /// the index says sample "A" is named "Old Name"; the file says "New Name",
    /// and the batches folder is newer than the index.
    private func makeStaleLibrary() throws -> (root: URL, appState: SpinLabAppState) {
        let root = try makeRoot()
        let appState = makeAppState()
        let store = appState.library.libraryStore
        try store.createDrawer(for: sample("A", name: "Old Name", batchId: "B1"), batch: batch("B1", keys: ["A"]), rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root) // explicit: persist the "old" index
        // Age the persisted index, then change the source file afterwards.
        var stale = try #require(store.loadIndex(from: root))
        stale.updatedAt = Date(timeIntervalSinceNow: -3600)
        store.saveIndex(stale, to: root)
        Thread.sleep(forTimeInterval: 1.1)
        let sampleDir = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A")
        store.writeSample(sample("A", name: "New Name", batchId: "B1"), to: sampleDir)
        appState.library.librarySettings.rootPath = root.path
        return (root, appState)
    }

    // MARK: - AC1 / AC3

    @Test("Stale index: startup shows current file data and writes nothing")
    func staleIndexStartupIsReadOnlyAndCurrent() throws {
        let (root, appState) = try makeStaleLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(appState.library.libraryStore.needsIndexRefresh(rootURL: root), "fixture must be stale")
        let before = Self.snapshot(root)

        appState.loadExistingDrawers()
        appState.validateLibraryCacheOnAppear()
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.librarySelectedSampleId = "A"
        _ = appState.library.selectExistingDrawer(prefix: "B", batchId: "B1", sampleId: "A")
        appState.library.loadWorkbenchResultsForCurrentSelection()
        appState.library.loadMeasurementDataForCurrentSelection()

        let names = appState.library.libraryExistingGroups.values.flatMap { $0 }.flatMap(\.samples).map(\.displayName)
        #expect(names == ["New Name"], "current file state must be visible, got \(names)")
        #expect(Self.snapshot(root) == before, "startup/browse must not mutate the Library tree")
    }

    // MARK: - AC2: legacy layout is not migrated by a read

    @Test("Legacy batch layout is neither migrated nor created over by reads")
    func legacyLayoutNotMigratedOnRead() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let appState = makeAppState()
        let store = appState.library.libraryStore
        try store.createDrawer(for: sample("A", name: "A", batchId: "B1"), batch: batch("B1", keys: ["A"]), rootURL: root)
        // Move to the legacy flat layout: batches/B1 (no prefix folder).
        let batchesURL = store.batchesDirectoryURL(root)
        let nested = store.preferredBatchDirectoryURL(root, batchID: "B1")
        let legacy = batchesURL.appending(path: "B1", directoryHint: .isDirectory)
        if nested.standardizedFileURL != legacy.standardizedFileURL {
            try FileManager.default.moveItem(at: nested, to: legacy)
            try? FileManager.default.removeItem(at: nested.deletingLastPathComponent())
        }
        appState.library.librarySettings.rootPath = root.path
        let before = Self.snapshot(root)

        appState.loadExistingDrawers()
        appState.validateLibraryCacheOnAppear()
        _ = store.snapshotIndexFromFilesystem(rootURL: root)

        let names = appState.library.libraryExistingGroups.values.flatMap { $0 }.flatMap(\.samples).map(\.id)
        #expect(names == ["A"], "legacy layout must still be readable")
        #expect(Self.snapshot(root) == before)
        #expect(FileManager.default.fileExists(atPath: legacy.appending(path: "batch.json").path))
    }

    // MARK: - AC2: missing root is not created

    @Test("Missing Library Root is reported, not created")
    func missingRootNotCreated() throws {
        let parent = try makeRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let missing = parent.appending(path: "NoSuchLibrary", directoryHint: .isDirectory)
        let appState = makeAppState()
        appState.library.librarySettings.rootPath = missing.path
        let before = Self.snapshot(parent)

        appState.loadExistingDrawers()
        appState.validateLibraryCacheOnAppear()
        _ = appState.library.libraryStore.snapshotIndexFromFilesystem(rootURL: missing)

        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(appState.library.libraryExistingGroups.isEmpty)
        #expect(appState.library.libraryRootVerificationMessage?.contains("not found") == true)
        #expect(Self.snapshot(parent) == before)
    }

    // MARK: - AC5: unreadable source files are surfaced, nothing is repaired

    @Test("Unreadable sample file is surfaced and the Library is left untouched")
    func unreadableFilesSurfacedWithoutRepair() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let appState = makeAppState()
        let store = appState.library.libraryStore
        try store.createDrawer(for: sample("A", name: "A", batchId: "B1"), batch: batch("B1", keys: ["A", "Z"]), rootURL: root)
        try store.createDrawer(for: sample("Z", name: "Z", batchId: "B1"), batch: batch("B1", keys: ["A", "Z"]), rootURL: root)
        let zDir = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "Z")
        try Data("{ not json".utf8).write(to: zDir.appending(path: "sample.json"))
        appState.library.librarySettings.rootPath = root.path
        let before = Self.snapshot(root)

        appState.loadExistingDrawers()

        #expect(appState.library.libraryReadIssues.count == 1)
        #expect(appState.library.libraryReadIssues.first?.contains("Z") == true)
        #expect(appState.library.libraryRootVerificationMessage?.contains("unreadable") == true)
        let ids = appState.library.libraryExistingGroups.values.flatMap { $0 }.flatMap(\.samples).map(\.id)
        #expect(ids == ["A"])
        #expect(Self.snapshot(root) == before, "failed reads must not trigger any repair write")
    }

    // MARK: - AC1: selecting a sample must not backfill sidecar indexes on disk

    @Test("Selection with a missing plot index computes it in memory only")
    func selectionDoesNotBackfillPlotIndex() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let appState = makeAppState()
        let store = appState.library.libraryStore
        try store.createDrawer(for: sample("A", name: "A", batchId: "B1"), batch: batch("B1", keys: ["A"]), rootURL: root)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifest = WorkbenchRunManifest(
            manifestID: "m1", runID: "r1", workflowID: "threeOmega",
            inputFiles: ["run1.lvm"], filters: [:],
            axisMapping: WorkbenchAxisMapping(xField: "T", yField: "R"),
            semanticParams: [:], outputImagePath: "samples/A/charts/c.png",
            generatedAt: Date(), appVersion: "test")
        let resolver = LibraryPathResolver(libraryRootURL: root)
        let manifestURL = try resolver.absoluteURL(for: "samples/A/charts/c.manifest.json")
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: manifestURL)
        let ref = WorkbenchResultReference(
            chartIdentityKey: "k1", chartImagePath: "samples/A/charts/c.png",
            manifestPath: "samples/A/charts/c.manifest.json", workflowID: "threeOmega",
            generatedAt: Date(), tabKey: nil)
        let results = WorkbenchResultsIndex(sampleKey: "A", updatedAt: Date(), references: [ref])
        let resultsURL = try resolver.absoluteURL(for: "samples/A/_spinlab/results_index.json")
        try FileManager.default.createDirectory(at: resultsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(results).write(to: resultsURL)

        appState.library.librarySettings.rootPath = root.path
        appState.loadExistingDrawers()
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.librarySelectedSampleId = "A"
        let before = Self.snapshot(root)

        _ = appState.library.selectExistingDrawer(prefix: "B", batchId: "B1", sampleId: "A")

        #expect(appState.library.measurementPlotIndex?.entries["run1.lvm"] == ["k1"], "in-memory index must still be available")
        #expect(Self.snapshot(root) == before, "selection must not write measurement_plot_index.json")
    }

    // MARK: - AC4: explicit operations keep their authorized behavior

    @Test("Explicit Sync Files still rebuilds and persists the index")
    func explicitSyncStillPersists() throws {
        let (root, appState) = try makeStaleLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let beforeNames = store.loadIndex(from: root)?.samples.map(\.displayName)
        #expect(beforeNames == ["Old Name"])

        let outcome = appState.library.syncLibraryFromFilesForCurrentRoot()

        #expect(outcome != nil)
        #expect(store.loadIndex(from: root)?.samples.map(\.displayName) == ["New Name"])
        #expect(!store.needsIndexRefresh(rootURL: root))
    }

    @Test("Explicit ensureRoot still creates folders and migrates legacy layout")
    func explicitEnsureRootStillMigrates() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        let legacy = store.batchesDirectoryURL(root).appending(path: "B1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(batch("B1", keys: [])).write(to: legacy.appending(path: "batch.json"))

        store.ensureRoot(at: root)

        #expect(!FileManager.default.fileExists(atPath: legacy.appending(path: "batch.json").path))
        #expect(FileManager.default.fileExists(atPath: store.indexDirectoryURL(root).path))
    }

    // MARK: - Explicit Sync fails closed on incomplete reads (F001)

    private struct IndexFingerprint: Equatable { var bytes: Data; var mtime: Date? }

    private func fingerprint(_ root: URL, _ appState: SpinLabAppState) throws -> IndexFingerprint {
        let url = appState.library.libraryStore.indexFileURL(root)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return IndexFingerprint(bytes: try Data(contentsOf: url), mtime: attrs[.modificationDate] as? Date)
    }

    /// Healthy two-sample library with a persisted index.
    private func makeSyncedLibrary() throws -> (root: URL, appState: SpinLabAppState) {
        let root = try makeRoot()
        let appState = makeAppState()
        let store = appState.library.libraryStore
        try store.createDrawer(for: sample("A", name: "Alpha", batchId: "B1"), batch: batch("B1", keys: ["A", "C"]), rootURL: root)
        try store.createDrawer(for: sample("C", name: "Gamma", batchId: "B1"), batch: batch("B1", keys: ["A", "C"]), rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        appState.library.librarySettings.rootPath = root.path
        return (root, appState)
    }

    private func expectSyncRefused(_ root: URL, _ original: SpinLabAppState, sourceLocation: SourceLocation = #_sourceLocation) throws {
        // Fresh state = fresh directory-listing cache, like a new app session.
        let appState = makeAppState()
        appState.library.librarySettings.rootPath = root.path
        _ = original
        let before = try fingerprint(root, appState)
        Thread.sleep(forTimeInterval: 1.1)
        let outcome = appState.library.syncLibraryFromFilesForCurrentRoot()
        #expect(outcome == nil, "sync must not report success", sourceLocation: sourceLocation)
        #expect(appState.library.libraryRootVerificationMessage?.contains("File sync stopped") == true,
                "a visible error is required", sourceLocation: sourceLocation)
        #expect(!appState.library.libraryReadIssues.isEmpty, sourceLocation: sourceLocation)
        #expect(try fingerprint(root, appState) == before, "saved index must be byte- and mtime-identical", sourceLocation: sourceLocation)
    }

    @Test("Sync with a corrupt sample file refuses and leaves the index untouched")
    func syncRefusesCorruptSample() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let dir = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "C")
        try "{ broken".write(to: dir.appending(path: "sample.json"), atomically: true, encoding: .utf8)
        try expectSyncRefused(root, appState)
    }

    @Test("Sync with a corrupt batch file refuses and leaves the index untouched")
    func syncRefusesCorruptBatch() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let batchJSON = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A")
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "batch.json")
        try "{ broken".write(to: batchJSON, atomically: true, encoding: .utf8)
        try expectSyncRefused(root, appState)
    }

    @Test("Sync with a corrupt existing index refuses instead of rewriting it")
    func syncRefusesCorruptIndex() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let indexURL = appState.library.libraryStore.indexFileURL(root)
        try "{ not an index".write(to: indexURL, atomically: true, encoding: .utf8)
        try expectSyncRefused(root, appState)
    }

    @Test("Sync when a sample folder cannot be listed refuses and leaves the index untouched")
    func syncRefusesUnlistableSamplesFolder() throws {
        let (root, appState) = try makeSyncedLibrary()
        let store = appState.library.libraryStore
        let samples = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A").deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: samples.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: samples.path)
        try expectSyncRefused(root, appState)
    }

    @Test("Sync when the batches folder cannot be listed refuses and leaves the index untouched")
    func syncRefusesUnlistableBatchesFolder() throws {
        let (root, appState) = try makeSyncedLibrary()
        let batches = appState.library.libraryStore.batchesDirectoryURL(root)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: batches.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: batches.path)
        try expectSyncRefused(root, appState)
    }

    @Test("Control: a healthy library still syncs and persists")
    func syncHealthyStillPersists() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try fingerprint(root, appState)
        Thread.sleep(forTimeInterval: 1.1)
        let outcome = appState.library.syncLibraryFromFilesForCurrentRoot()
        #expect(outcome?.syncedIndex.samples.count == 2)
        #expect(try fingerprint(root, appState) != before, "explicit sync of a healthy library must still write")
        #expect(appState.library.libraryReadIssues.isEmpty)
    }

    @Test("Sync whose index write fails is reported as stopped, never complete, and keeps the old index")
    func syncWriteFailureNotReportedAsSuccess() throws {
        let (root, appState) = try makeSyncedLibrary()
        let indexDir = appState.library.libraryStore.indexFileURL(root).deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: indexDir.path)
            try? FileManager.default.removeItem(at: root)
        }
        let before = try fingerprint(root, appState)
        // Controlled write failure: the index folder becomes read-only, so the atomic write fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: indexDir.path)
        let fresh = makeAppState()
        fresh.library.librarySettings.rootPath = root.path
        let checked = fresh.library.libraryStore.syncIndexFromFilesystemChecked(rootURL: root)
        #expect(checked.persisted == false)
        #expect(!checked.issues.isEmpty)
        let outcome = fresh.library.syncLibraryFromFilesForCurrentRoot()
        #expect(outcome == nil, "failed write must not produce a success outcome")
        let message = fresh.library.libraryRootVerificationMessage ?? ""
        #expect(message.contains("File sync stopped"))
        #expect(!message.contains("File sync complete"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: indexDir.path)
        #expect(try fingerprint(root, appState) == before, "old index must be untouched")
    }

    // MARK: - Write callers fail closed on an incomplete read (review F001/P2)

    private enum Damage: CaseIterable { case corruptSample, corruptBatch, unlistableSamples }

    /// Healthy library, then damaged. Returns what a mutation must NOT change.
    private func makeDamagedLibrary(_ damage: Damage) throws -> (root: URL, keep: [URL], restore: () -> Void) {
        let (root, appState) = try makeSyncedLibrary()
        let store = appState.library.libraryStore
        let dirA = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A")
        let dirC = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "C")
        let samplesDir = dirA.deletingLastPathComponent()
        let batchJSON = samplesDir.deletingLastPathComponent().appending(path: "batch.json")
        var restore: () -> Void = {}
        switch damage {
        case .corruptSample:
            try "{ broken".write(to: dirC.appending(path: "sample.json"), atomically: true, encoding: .utf8)
        case .corruptBatch:
            try "{ broken".write(to: batchJSON, atomically: true, encoding: .utf8)
        case .unlistableSamples:
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: samplesDir.path)
            restore = { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: samplesDir.path) }
        }
        return (root, [dirA.appending(path: "sample.json"), dirC.appending(path: "sample.json"), batchJSON, store.indexFileURL(root)], restore)
    }

    private func bytes(_ urls: [URL]) -> [String: Data?] {
        Dictionary(uniqueKeysWithValues: urls.map { ($0.path, try? Data(contentsOf: $0)) })
    }

    /// Preview that would require real work: a changed A and a new sample Z in B1.
    private func previewWithWork() -> LibraryPreview {
        let b = batch("B1", keys: ["A", "C", "Z"])
        let index = LibraryIndex(
            version: 1, createdAt: Date(), updatedAt: Date(),
            registryInternalPath: nil, registrySourcePath: nil, metadataColumnOrder: [],
            batches: [b],
            samples: [sample("A", name: "Alpha EDITED", batchId: "B1"), sample("C", name: "Gamma", batchId: "B1"), sample("Z", name: "Zeta", batchId: "B1")]
        )
        return LibraryPreview(index: index, warnings: [])
    }

    @Test("Apply, refresh, delete and commit all stop before changing anything when the Library read is incomplete")
    func writeCallersFailClosed() throws {
        for damage in Damage.allCases {
            let (root, keep, restore) = try makeDamagedLibrary(damage)
            defer { restore(); try? FileManager.default.removeItem(at: root) }
            let appState = makeAppState()               // fresh listing cache
            appState.library.librarySettings.rootPath = root.path
            let library = appState.library
            let sync = library.librarySyncService
            let mutation = appState.libraryMutationService
            let preview = previewWithWork()
            let before = bytes(keep)
            let treeBefore = damage == .unlistableSamples ? [:] : Self.snapshot(root)
            var settings = library.librarySettings
            settings.registryInternalPath = nil

            // legacy/base API
            #expect(throws: LibraryIndexSyncError.self) { _ = try library.libraryStore.syncIndexFromFilesystem(rootURL: root) }
            // Apply selected batch
            #expect(throws: LibraryIndexSyncError.self) {
                _ = try sync.applyBatch(batchId: "B1", preview: preview, rootURL: root, settings: settings)
            }
            // Apply all
            #expect(throws: LibraryIndexSyncError.self) {
                try sync.applyAll(preview: preview, rootURL: root, settings: settings)
            }
            // Refresh (plan + apply) reports a failure, not success
            if case .success = mutation.refreshIncremental(librarySyncService: sync, preview: preview, rootPath: root.path, settings: settings) {
                Issue.record("refresh must fail for \(damage)")
            }
            // Delete drawer reports failure and removes nothing
            let deleted = mutation.deleteExistingDrawer(batchId: "B1", rootPath: root.path, previewIndex: nil, libraryStore: library.libraryStore)
            if case .success = deleted { Issue.record("delete must fail for \(damage)") }
            // Commit after a mutation throws instead of adopting a partial index
            #expect(throws: LibraryIndexSyncError.self) {
                _ = try mutation.commitMutation(rootURL: root, previewIndex: nil, precomputedDiff: nil, precomputedReview: nil, librarySyncService: sync)
            }
            library.libraryPreview = preview
            // Facade: selected-batch apply surfaces a visible error
            if case .success = library.applySelectedRegistryDiff(batchId: "B1") { Issue.record("facade apply must fail for \(damage)") }
            #expect(library.libraryDrawerError?.contains("stopped") == true)

            #expect(bytes(keep) == before, "sample, batch and index files must be byte-identical for \(damage)")
            if damage != .unlistableSamples {
                #expect(Self.snapshot(root) == treeBefore, "no file may be created, changed or deleted for \(damage)")
            }
        }
    }

    @Test("Control: on a healthy Library apply and delete still work")
    func writeCallersHealthyStillWork() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let fresh = makeAppState()
        fresh.library.librarySettings.rootPath = root.path
        let sync = fresh.library.librarySyncService
        let applied = try sync.applyBatch(batchId: "B1", preview: previewWithWork(), rootURL: root, settings: fresh.library.librarySettings)
        #expect(applied != nil)
        let reread = try #require(fresh.library.libraryStore.loadIndex(from: root))
        #expect(Set(reread.samples.map(\.id)) == ["A", "C", "Z"])
        let deleted = fresh.libraryMutationService.deleteExistingDrawer(
            batchId: "B1", rootPath: root.path, previewIndex: nil, libraryStore: fresh.library.libraryStore)
        guard case .success = deleted else { Issue.record("healthy delete must succeed"); return }
        #expect(try #require(fresh.library.libraryStore.loadIndex(from: root)).samples.isEmpty)
        _ = appState
    }
}
