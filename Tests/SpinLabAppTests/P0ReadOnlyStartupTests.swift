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

    fileprivate struct TreeEntry: Equatable {
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

    /// Deterministic read fault (identical for root and non-root users): listing these
    /// directories throws, exactly like an I/O or permission error would.
    private final class FaultingFileManager: FileManager, @unchecked Sendable {
        var failListing: Set<String> = []
        override func contentsOfDirectory(
            at url: URL,
            includingPropertiesForKeys keys: [URLResourceKey]?,
            options mask: FileManager.DirectoryEnumerationOptions = []
        ) throws -> [URL] {
            if failListing.contains(url.standardizedFileURL.path) || failListing.contains(url.path) {
                throw CocoaError(.fileReadNoPermission)
            }
            return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
        }
    }

    /// A fresh Library feature store (fresh listing caches) on `root`, optionally with
    /// directory-listing faults.
    private func freshLibrary(_ root: URL, failListing: [URL] = []) -> LibraryFeatureStore {
        let manager = FaultingFileManager()
        manager.failListing = Set(failListing.map(\.path))
        let library = LibraryFeatureStore(libraryStore: LibraryStore(fileManager: manager))
        library.librarySettings.rootPath = root.path
        return library
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

    private func expectSyncRefused(_ root: URL, indexURL: URL, failListing: [URL] = [], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let library = freshLibrary(root, failListing: failListing)
        let before = try fingerprintOf(indexURL)
        Thread.sleep(forTimeInterval: 1.1)
        let outcome = library.syncLibraryFromFilesForCurrentRoot()
        #expect(outcome == nil, "sync must not report success", sourceLocation: sourceLocation)
        #expect(library.libraryRootVerificationMessage?.contains("File sync stopped") == true,
                "a visible error is required", sourceLocation: sourceLocation)
        #expect(!library.libraryReadIssues.isEmpty, sourceLocation: sourceLocation)
        #expect(try fingerprintOf(indexURL) == before, "saved index must be byte- and mtime-identical", sourceLocation: sourceLocation)
    }

    private func fingerprintOf(_ url: URL) throws -> IndexFingerprint {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return IndexFingerprint(bytes: try Data(contentsOf: url), mtime: attrs[.modificationDate] as? Date)
    }

    @Test("Sync with a corrupt sample file refuses and leaves the index untouched")
    func syncRefusesCorruptSample() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let dir = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "C")
        try "{ broken".write(to: dir.appending(path: "sample.json"), atomically: true, encoding: .utf8)
        try expectSyncRefused(root, indexURL: appState.library.libraryStore.indexFileURL(root))
    }

    @Test("Sync with a corrupt batch file refuses and leaves the index untouched")
    func syncRefusesCorruptBatch() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let batchJSON = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A")
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "batch.json")
        try "{ broken".write(to: batchJSON, atomically: true, encoding: .utf8)
        try expectSyncRefused(root, indexURL: appState.library.libraryStore.indexFileURL(root))
    }

    @Test("Sync with a corrupt existing index refuses instead of rewriting it")
    func syncRefusesCorruptIndex() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let indexURL = appState.library.libraryStore.indexFileURL(root)
        try "{ not an index".write(to: indexURL, atomically: true, encoding: .utf8)
        try expectSyncRefused(root, indexURL: appState.library.libraryStore.indexFileURL(root))
    }

    @Test("Sync when a sample folder cannot be listed refuses and leaves the index untouched")
    func syncRefusesUnlistableSamplesFolder() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let samples = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A").deletingLastPathComponent()
        try expectSyncRefused(root, indexURL: store.indexFileURL(root), failListing: [samples])
    }

    @Test("Sync when the batches folder cannot be listed refuses and leaves the index untouched")
    func syncRefusesUnlistableBatchesFolder() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        try expectSyncRefused(root, indexURL: store.indexFileURL(root), failListing: [store.batchesDirectoryURL(root)])
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
        let indexURL = appState.library.libraryStore.indexFileURL(root)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
            try? FileManager.default.removeItem(at: root)
        }
        let before = try fingerprintOf(indexURL)
        // Deterministic write failure for any user, root included: the index file is immutable,
        // so the atomic replace is refused by the filesystem.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexURL.path)
        let fresh = freshLibrary(root)
        let checked = fresh.libraryStore.syncIndexFromFilesystemChecked(rootURL: root)
        #expect(checked.persisted == false)
        #expect(!checked.issues.isEmpty)
        let outcome = fresh.syncLibraryFromFilesForCurrentRoot()
        #expect(outcome == nil, "failed write must not produce a success outcome")
        let message = fresh.libraryRootVerificationMessage ?? ""
        #expect(message.contains("File sync stopped"))
        #expect(!message.contains("File sync complete"))
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
        #expect(try fingerprintOf(indexURL) == before, "old index must be untouched")
    }

    @Test("Sample edit write that the filesystem refuses throws and leaves the file untouched; healthy write persists")
    func sampleUpdateWriteFailureThrows() throws {
        let (root, appState) = try makeSyncedLibrary()
        let store = appState.library.libraryStore
        let sample = try #require(try store.readOnlyCompleteIndex(rootURL: root).samples.first)
        let sampleFile = store.sampleDirectoryURL(root, batchID: sample.batchId, sampleKey: sample.id)
            .appending(path: "sample.json")
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: sampleFile.path)
            try? FileManager.default.removeItem(at: root)
        }
        var edited = sample
        edited.substrateTags = ["edited-tag"]
        let before = try Data(contentsOf: sampleFile)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: sampleFile.path)
        #expect(throws: (any Error).self) { try store.updateSample(edited, rootURL: root) }
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: sampleFile.path)
        #expect(try Data(contentsOf: sampleFile) == before, "refused write must not change the file")
        // Control: once writable, the same update persists.
        try store.updateSample(edited, rootURL: root)
        #expect(try String(contentsOf: sampleFile, encoding: .utf8).contains("edited-tag"))
    }

    // MARK: - Write callers fail closed on an incomplete read (review F001/P2)

    private enum Damage: CaseIterable { case corruptSample, corruptBatch, corruptIndex, unlistableSamples }

    /// Healthy library, then damaged. Returns what a mutation must NOT change, plus any
    /// directories whose listing must fail (deterministic fault, same for root and non-root).
    private func makeDamagedLibrary(_ damage: Damage) throws -> (root: URL, keep: [URL], failListing: [URL]) {
        let (root, appState) = try makeSyncedLibrary()
        let store = appState.library.libraryStore
        let dirA = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "A")
        let dirC = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "C")
        let samplesDir = dirA.deletingLastPathComponent()
        let batchJSON = samplesDir.deletingLastPathComponent().appending(path: "batch.json")
        var failListing: [URL] = []
        switch damage {
        case .corruptSample:
            try "{ broken".write(to: dirC.appending(path: "sample.json"), atomically: true, encoding: .utf8)
        case .corruptBatch:
            try "{ broken".write(to: batchJSON, atomically: true, encoding: .utf8)
        case .corruptIndex:
            try "{ not an index".write(to: store.indexFileURL(root), atomically: true, encoding: .utf8)
        case .unlistableSamples:
            failListing = [samplesDir]
        }
        return (root, [dirA.appending(path: "sample.json"), dirC.appending(path: "sample.json"), batchJSON, store.indexFileURL(root)], failListing)
    }

    private func bytes(_ urls: [URL]) -> [String: Data?] {
        Dictionary(uniqueKeysWithValues: urls.map { ($0.path, try? Data(contentsOf: $0)) })
    }

    private func editedA() -> LibrarySample {
        var a = sample("A", name: "Alpha EDITED", batchId: "B1")
        a.metadata = ["Note": "edited"]
        return a
    }

    /// Preview that would require real work: a changed A and a new sample Z in B1.
    private func previewWithWork() -> LibraryPreview {
        let b = batch("B1", keys: ["A", "C", "Z"])
        let index = LibraryIndex(
            version: 1, createdAt: Date(), updatedAt: Date(),
            registryInternalPath: nil, registrySourcePath: nil, metadataColumnOrder: [],
            batches: [b],
            samples: [editedA(), sample("C", name: "Gamma", batchId: "B1"), sample("Z", name: "Zeta", batchId: "B1")]
        )
        return LibraryPreview(index: index, warnings: [])
    }

    @Test("Apply, refresh, delete, create and commit all stop before changing anything when the Library read is incomplete")
    func writeCallersFailClosed() throws {
        for damage in Damage.allCases {
            let (root, keep, failListing) = try makeDamagedLibrary(damage)
            defer { try? FileManager.default.removeItem(at: root) }
            let library = freshLibrary(root, failListing: failListing)
            let sync = library.librarySyncService
            let mutation = LibraryMutationService()
            let preview = previewWithWork()
            let before = bytes(keep)
            let treeBefore = Self.snapshot(root)
            let settings = library.librarySettings

            #expect(throws: LibraryIndexSyncError.self) { _ = try library.libraryStore.syncIndexFromFilesystem(rootURL: root) }
            #expect(throws: LibraryIndexSyncError.self) {
                _ = try sync.applyBatch(batchId: "B1", preview: preview, rootURL: root, settings: settings)
            }
            #expect(throws: LibraryIndexSyncError.self) {
                try sync.applyAll(preview: preview, rootURL: root, settings: settings)
            }
            if case .success = mutation.refreshIncremental(librarySyncService: sync, preview: preview, rootPath: root.path, settings: settings) {
                Issue.record("refresh must fail for \(damage)")
            }
            if case .success = mutation.deleteExistingDrawer(batchId: "B1", rootPath: root.path, previewIndex: nil, libraryStore: library.libraryStore) {
                Issue.record("delete must fail for \(damage)")
            }
            // F005: create paths must not treat an unreadable Library as empty
            if case .success = mutation.createDrawersFromPreview(preview: preview, rootPath: root.path, libraryStore: library.libraryStore, settings: settings) {
                Issue.record("create-from-preview must fail for \(damage)")
            }
            if case .success = mutation.createDrawersForSelection(preview: preview, rootPath: root.path, batchId: "B1", sampleId: "Z", libraryStore: library.libraryStore, settings: settings) {
                Issue.record("create-for-selection must fail for \(damage)")
            }
            #expect(throws: LibraryIndexSyncError.self) {
                _ = try mutation.commitMutation(rootURL: root, previewIndex: nil, precomputedDiff: nil, precomputedReview: nil, librarySyncService: sync)
            }
            library.libraryPreview = preview
            if case .success = library.applySelectedRegistryDiff(batchId: "B1") { Issue.record("facade apply must fail for \(damage)") }
            #expect(library.libraryDrawerError?.contains("stopped") == true)

            #expect(bytes(keep) == before, "sample, batch and index files must be byte-identical for \(damage)")
            #expect(Self.snapshot(root) == treeBefore, "no file may be created, changed or deleted for \(damage)")
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

    // MARK: - F002: display-only paths are truly read-only

    @Test("Display diff, sync review and registry browsing never write, create or migrate")
    func displayPathsAreReadOnly() throws {
        let (root, _) = try makeStaleLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = freshLibrary(root)
        let sync = library.librarySyncService
        let preview = previewWithWork()
        let before = Self.snapshot(root)

        let diff = sync.diffAgainstExisting(previewIndex: preview.index, baselineIndex: nil, rootPath: root.path)
        #expect(diff != nil, "a complete, readable Library still yields a diff")
        _ = try sync.diff(rootURL: root, previewIndex: preview.index)
        if case .failure = sync.prepareLibrarySyncReview(preview: preview, rootPath: root.path, precomputedDiff: nil) {
            Issue.record("healthy sync review must still work")
        }
        let state = sync.buildActionablePreviewState(
            preview: preview, precomputedDiff: nil, baselineIndex: nil, rootPath: root.path,
            previewComputationService: LibraryPreviewComputationService())
        #expect(!state.message.isEmpty)
        #expect(Self.snapshot(root) == before, "hashes, mtimes and the directory tree must not change")
    }

    @Test("Display diff on a missing root creates nothing and shows no diff; incomplete reads show no partial diff")
    func displayPathsFailClosedWithoutWriting() throws {
        let parent = try makeRoot()
        defer { try? FileManager.default.removeItem(at: parent) }
        let missing = parent.appending(path: "NoSuchLibrary", directoryHint: .isDirectory)
        let library = freshLibrary(missing)
        let sync = library.librarySyncService
        let preview = previewWithWork()
        let before = Self.snapshot(parent)

        #expect(sync.diffAgainstExisting(previewIndex: preview.index, baselineIndex: nil, rootPath: missing.path) == nil)
        #expect(throws: LibraryIndexSyncError.self) { _ = try sync.diff(rootURL: missing, previewIndex: preview.index) }
        if case .success = sync.prepareLibrarySyncReview(preview: preview, rootPath: missing.path, precomputedDiff: nil) {
            Issue.record("sync review of a missing root must not succeed")
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path), "the root must not be created")
        #expect(Self.snapshot(parent) == before)

        // Incomplete read: no diff is shown and nothing is written.
        let (root, keep, failListing) = try makeDamagedLibrary(.corruptSample)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = keep; _ = failListing
        let damaged = freshLibrary(root).librarySyncService
        let treeBefore = Self.snapshot(root)
        #expect(damaged.diffAgainstExisting(previewIndex: preview.index, baselineIndex: nil, rootPath: root.path) == nil)
        if case .success = damaged.prepareLibrarySyncReview(preview: preview, rootPath: root.path, precomputedDiff: nil) {
            Issue.record("sync review of an incomplete read must not succeed")
        }
        #expect(Self.snapshot(root) == treeBefore)
    }

    // MARK: - F003: controlled recovery of a damaged index

    private func backups(in root: URL, _ store: LibraryStore) -> [URL] {
        let dir = store.indexFileURL(root).deletingLastPathComponent()
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.contains(".corrupt-") }
    }

    @Test("Damaged index: normal Sync refuses, the Sync button only OFFERS recovery, nothing is written yet")
    func damagedIndexOffersButDoesNotWrite() throws {
        let (root, keep, _) = try makeDamagedLibrary(.corruptIndex)
        defer { try? FileManager.default.removeItem(at: root) }
        let indexURL = keep.last!
        let before = try fingerprintOf(indexURL)

        let plain = freshLibrary(root)
        #expect(plain.syncLibraryFromFilesForCurrentRoot() == nil)
        #expect(plain.libraryIndexRecoveryRootPath == nil, "no prompt outside the explicit Sync button")

        let offered = freshLibrary(root)
        #expect(offered.syncLibraryFromFilesForCurrentRoot(offerRecovery: true) == nil)
        #expect(offered.libraryIndexRecoveryRootPath == root.path)
        #expect(offered.libraryRootVerificationMessage?.contains("damaged") == true)
        #expect(try fingerprintOf(indexURL) == before)
        #expect(backups(in: root, offered.libraryStore).isEmpty, "no backup or rebuild before confirmation")
    }

    @Test("Confirmed recovery backs up the exact damaged bytes under a unique name, then rebuilds")
    func recoveryBacksUpThenRebuilds() throws {
        let (root, keep, _) = try makeDamagedLibrary(.corruptIndex)
        defer { try? FileManager.default.removeItem(at: root) }
        let indexURL = keep.last!
        let damaged = try Data(contentsOf: indexURL)
        let library = freshLibrary(root)

        let outcome = try #require(library.recoverLibraryIndexForCurrentRoot())
        #expect(outcome.syncedIndex.samples.count == 2)
        #expect(outcome.summaryMessage.contains(".bak"))
        let first = backups(in: root, library.libraryStore)
        #expect(first.count == 1)
        #expect(try Data(contentsOf: first[0]) == damaged, "backup must hold the original damaged bytes")
        let rebuilt = try #require(library.libraryStore.loadIndex(from: root))
        #expect(Set(rebuilt.samples.map(\.id)) == ["A", "C"])

        // A second damage + recovery creates a second, distinct backup; the first is untouched.
        try "{ damaged again".write(to: indexURL, atomically: true, encoding: .utf8)
        _ = try #require(freshLibrary(root).recoverLibraryIndexForCurrentRoot())
        let both = backups(in: root, library.libraryStore)
        #expect(both.count == 2 && Set(both.map(\.lastPathComponent)).count == 2)
        #expect(try Data(contentsOf: first[0]) == damaged)
    }

    @Test("Recovery is refused, with no backup and no change, when any source file is unreadable")
    func recoveryRefusedOnIncompleteSources() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let indexURL = store.indexFileURL(root)
        try "{ not an index".write(to: indexURL, atomically: true, encoding: .utf8)
        try "{ broken".write(to: store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "C").appending(path: "sample.json"), atomically: true, encoding: .utf8)
        let before = try fingerprintOf(indexURL)
        let library = freshLibrary(root)
        #expect(library.recoverLibraryIndexForCurrentRoot() == nil)
        #expect(library.libraryRootVerificationMessage?.contains("Recovery stopped") == true)
        #expect(try fingerprintOf(indexURL) == before)
        #expect(backups(in: root, store).isEmpty)
    }

    @Test("Recovery does not replace the damaged index when the backup cannot be made")
    func recoveryStopsWhenBackupFails() throws {
        let (root, keep, _) = try makeDamagedLibrary(.corruptIndex)
        let indexURL = keep.last!
        let indexDir = indexURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexDir.path)
            try? FileManager.default.removeItem(at: root)
        }
        let before = try fingerprintOf(indexURL)
        // Deterministic for any user: an immutable folder refuses the new backup file.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexDir.path)
        let library = freshLibrary(root)
        #expect(library.recoverLibraryIndexForCurrentRoot() == nil)
        #expect(library.libraryRootVerificationMessage?.contains("Recovery stopped") == true)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexDir.path)
        #expect(try fingerprintOf(indexURL) == before, "damaged index stays exactly as it was")
        #expect(backups(in: root, library.libraryStore).isEmpty)
    }

    @Test("Recovery keeps the backup and the damaged index when the rebuilt index cannot be written")
    func recoveryStopsWhenWriteFails() throws {
        let (root, keep, _) = try makeDamagedLibrary(.corruptIndex)
        let indexURL = keep.last!
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
            try? FileManager.default.removeItem(at: root)
        }
        let before = try fingerprintOf(indexURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexURL.path)
        let library = freshLibrary(root)
        #expect(library.recoverLibraryIndexForCurrentRoot() == nil)
        #expect(library.libraryRootVerificationMessage?.contains("Recovery stopped") == true)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
        #expect(try fingerprintOf(indexURL) == before)
        let kept = backups(in: root, library.libraryStore)
        #expect(kept.count == 1)
        #expect(try Data(contentsOf: kept[0]) == before.bytes)
    }

    // MARK: - F004: Apply All reports what really happened

    /// Makes creating sample `key` in batch B1 fail deterministically: a regular file sits where its folder must go.
    private func blockSampleFolder(_ key: String, root: URL, store: LibraryStore) throws {
        let dir = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: key)
        try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "block".write(to: dir, atomically: true, encoding: .utf8)
    }

    @Test("Apply All with one failed create is PARTIAL and the saved index matches the disk, not the plan")
    func applyAllPartialIsHonest() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        try blockSampleFolder("Z", root: root, store: appState.library.libraryStore)
        let library = freshLibrary(root)
        let result = try library.librarySyncService.applyAll(preview: previewWithWork(), rootURL: root, settings: library.librarySettings)
        #expect(result.isPartial)
        #expect(result.failures.count == 1 && result.failures[0].contains("Z"))
        #expect(result.succeeded >= 1, "the edit to A really was applied")
        let saved = try #require(library.libraryStore.loadIndex(from: root))
        #expect(Set(saved.samples.map(\.id)) == ["A", "C"], "failed sample must not be listed")
        #expect(saved.samples.first { $0.id == "A" }?.metadata["Note"] == "edited")

        let again = freshLibrary(root)
        let outcome = LibraryMutationService().refreshIncremental(
            librarySyncService: again.librarySyncService, preview: previewWithWork(), rootPath: root.path, settings: again.librarySettings)
        guard case let .partial(_, _, message) = outcome else {
            Issue.record("refresh must report .partial, got \(outcome)"); return
        }
        #expect(message.hasPrefix("PARTIAL"))
    }

    @Test("Apply All stops before changing anything when even the baseline index cannot be written")
    func applyAllStopsOnBaselineWriteFailure() throws {
        let (root, appState) = try makeSyncedLibrary()
        let indexURL = appState.library.libraryStore.indexFileURL(root)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
            try? FileManager.default.removeItem(at: root)
        }
        // Files only: a refused atomic write may touch folder timestamps, but no file may change.
        func files() -> [String: TreeEntry] { Self.snapshot(root).filter { $0.value.kind == "file" } }
        let before = files()
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexURL.path)
        let library = freshLibrary(root)
        #expect(throws: LibraryIndexSyncError.self) {
            try library.librarySyncService.applyAll(preview: previewWithWork(), rootURL: root, settings: library.librarySettings)
        }
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
        #expect(files() == before, "no file may be created, changed or deleted")
    }

    @Test("Control: Apply All on a healthy Library is complete and the index equals the disk")
    func applyAllHealthyIsComplete() throws {
        let (root, _) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = freshLibrary(root)
        let result = try library.librarySyncService.applyAll(preview: previewWithWork(), rootURL: root, settings: library.librarySettings)
        #expect(!result.isPartial)
        let saved = try #require(library.libraryStore.loadIndex(from: root))
        #expect(Set(saved.samples.map(\.id)) == ["A", "C", "Z"])
    }

    // MARK: - F005: Create Drawers

    private func previewOnlyB2(_ keys: [String]) -> LibraryPreview {
        let b = LibraryBatch(id: "B2", displayName: "B2", sheetName: "STO", metadata: [:], numericTags: [:], numericDisplay: [:],
                             sampleKeys: keys, updatedAt: Date())
        let index = LibraryIndex(
            version: 1, createdAt: Date(), updatedAt: Date(),
            registryInternalPath: nil, registrySourcePath: nil, metadataColumnOrder: [],
            batches: [b], samples: keys.map { sample($0, name: "S-\($0)", batchId: "B2") })
        return LibraryPreview(index: index, warnings: [])
    }

    @Test("Create from a partial preview keeps existing Library content in the saved index")
    func createFromPreviewKeepsExistingContent() throws {
        let (root, _) = try makeSyncedLibrary()   // A, C in B1
        defer { try? FileManager.default.removeItem(at: root) }
        let library = freshLibrary(root)
        let outcome = LibraryMutationService().createDrawersFromPreview(
            preview: previewOnlyB2(["Q"]), rootPath: root.path, libraryStore: library.libraryStore, settings: library.librarySettings)
        guard case .success = outcome else { Issue.record("healthy create must succeed: \(outcome)"); return }
        let saved = try #require(library.libraryStore.loadIndex(from: root))
        #expect(Set(saved.samples.map(\.id)) == ["A", "C", "Q"], "existing samples must not be dropped")
    }

    @Test("Create that partly fails reports PARTIAL with real counts and lists only what exists")
    func createPartialIsHonest() throws {
        let (root, appState) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = appState.library.libraryStore
        let blocked = store.sampleDirectoryURL(root, batchID: "B2", sampleKey: "Q2")
        try FileManager.default.createDirectory(at: blocked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "block".write(to: blocked, atomically: true, encoding: .utf8)
        let library = freshLibrary(root)
        let outcome = LibraryMutationService().createDrawersFromPreview(
            preview: previewOnlyB2(["Q1", "Q2"]), rootPath: root.path, libraryStore: library.libraryStore, settings: library.librarySettings)
        guard case let .partial(_, _, created, message) = outcome else { Issue.record("expected .partial, got \(outcome)"); return }
        #expect(created == 1)
        #expect(message.hasPrefix("PARTIAL: created 1 of 2"))
        let saved = try #require(library.libraryStore.loadIndex(from: root))
        #expect(Set(saved.samples.map(\.id)) == ["A", "C", "Q1"])
    }

    @Test("Create is never reported as success when the index could not be saved")
    func createWithIndexWriteFailureIsPartial() throws {
        let (root, appState) = try makeSyncedLibrary()
        let indexURL = appState.library.libraryStore.indexFileURL(root)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
            try? FileManager.default.removeItem(at: root)
        }
        let before = try fingerprintOf(indexURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexURL.path)
        let library = freshLibrary(root)
        let service = LibraryMutationService()
        let a = service.createDrawersFromPreview(
            preview: previewOnlyB2(["Q"]), rootPath: root.path, libraryStore: library.libraryStore, settings: library.librarySettings)
        guard case let .partial(_, _, _, m1) = a else { Issue.record("from-preview must be .partial, got \(a)"); return }
        #expect(m1.contains("index"))
        let b = service.createDrawersForSelection(
            preview: previewOnlyB2(["R"]), rootPath: root.path, batchId: "B2", sampleId: "R",
            libraryStore: freshLibrary(root).libraryStore, settings: library.librarySettings)
        guard case let .partial(_, _, _, m2) = b else { Issue.record("for-selection must be .partial, got \(b)"); return }
        #expect(m2.contains("index"))
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path)
        #expect(try fingerprintOf(indexURL) == before, "old index must not be overwritten")
    }

    @Test("Control: Create for a selection on a healthy Library merges and keeps existing content")
    func createForSelectionHealthy() throws {
        let (root, _) = try makeSyncedLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = freshLibrary(root)
        let outcome = LibraryMutationService().createDrawersForSelection(
            preview: previewOnlyB2(["Q"]), rootPath: root.path, batchId: "B2", sampleId: "Q",
            libraryStore: library.libraryStore, settings: library.librarySettings)
        guard case .success = outcome else { Issue.record("healthy create must succeed: \(outcome)"); return }
        #expect(Set(try #require(library.libraryStore.loadIndex(from: root)).samples.map(\.id)) == ["A", "C", "Q"])
    }
}
