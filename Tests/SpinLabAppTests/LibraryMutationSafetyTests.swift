import Foundation
import Testing
@testable import SpinLabApp

@Suite("Library Mutation Safety & Deletion Preflight Guard (SPINLAB-G1-01-SAFETY)")
struct LibraryMutationSafetyTests {

    private func makeTempLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-g1-01-safety-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        // Restore write permissions recursively before deleting in case any tests changed them
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: url.path)
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: item.path)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private struct FileSnapshot: Equatable {
        var size: Int
        var mtime: Date
        var data: Data
    }

    private func snapshotDirectoryTree(at rootURL: URL) throws -> [String: FileSnapshot] {
        var snapshot: [String: FileSnapshot] = [:]
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [])
        while let item = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue {
                let relPath = String(item.path.dropFirst(rootURL.path.count + 1))
                let data = try Data(contentsOf: item)
                let attrs = try fm.attributesOfItem(atPath: item.path)
                let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast
                snapshot[relPath] = FileSnapshot(size: data.count, mtime: mtime, data: data)
            }
        }
        return snapshot
    }

    // MARK: - AC1: Read-Only Audit / Preview Integrity

    @Test("AC1: Read-only audit and preview have zero file/mtime/content changes and no UID assignment")
    func readOnlyAuditPreviewZeroFileChanges() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)

        let sample = LibrarySample(
            id: "AC1_S1",
            displayName: "AC1 Sample 1",
            batchId: "AC1_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: ["Target": "SRO"],
            orderedMetadata: [LibraryMetadataItem(key: "Target", value: "SRO")],
            numericTags: ["Thickness": 50.0],
            numericDisplay: ["Thickness": "50 nm"],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date(),
            sampleUID: "smp_ac1_fixed_uid"
        )
        let batch = LibraryBatch(
            id: "AC1_B1",
            displayName: "AC1 Batch 1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["AC1_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Add real measurement and plot files
        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC1_B1", sampleKey: "AC1_S1")
        let measFile = sampleDir.appending(path: "measurements/curve.dat")
        try "meas_data_ac1".write(to: measFile, atomically: true, encoding: .utf8)

        let plotFile = sampleDir.appending(path: "plots/plot.png")
        try "png_data_ac1".write(to: plotFile, atomically: true, encoding: .utf8)

        // Snapshot initial disk state
        let beforeSnapshot = try snapshotDirectoryTree(at: root)

        // 1. Run read-only diff
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [batch],
            samples: [sample]
        )
        let (baseline, diff) = try syncService.diff(rootURL: root, previewIndex: previewIndex)
        #expect(baseline.samples.count == 1)
        #expect(diff.removedSamples.isEmpty)
        #expect(diff.newSamples.isEmpty)

        // 2. Run diffAgainstExisting
        let diffAgainst = syncService.diffAgainstExisting(previewIndex: previewIndex, baselineIndex: baseline, rootPath: root.path)
        #expect(diffAgainst != nil)

        // 3. Run prepareLibrarySyncReview
        let reviewPlan = syncService.prepareLibrarySyncReview(preview: LibraryPreview(index: previewIndex, warnings: []), rootPath: root.path, precomputedDiff: nil)
        guard case let .success(plan) = reviewPlan else {
            Issue.record("Expected successful review plan")
            return
        }
        #expect(plan.review.newSamples.isEmpty)

        // 4. Run ChartAssetAuditService.audit
        let auditReport = ChartAssetAuditService.audit(rootURL: root)
        #expect(auditReport.unreadableIndexSampleKeys.isEmpty)

        // Verify that exact filesystem remains 100% byte-for-byte and mtime identical
        let afterSnapshot = try snapshotDirectoryTree(at: root)
        #expect(beforeSnapshot.count == afterSnapshot.count)
        for (path, beforeEntry) in beforeSnapshot {
            guard let afterEntry = afterSnapshot[path] else {
                Issue.record("Missing file after read-only audit: \(path)")
                continue
            }
            #expect(beforeEntry.size == afterEntry.size, "File size changed for \(path)")
            #expect(beforeEntry.data == afterEntry.data, "File content changed for \(path)")
            #expect(beforeEntry.mtime == afterEntry.mtime, "File mtime changed for \(path)")
        }

        // Verify no UID backfill or mutation occurred in sample.json
        let diskSample = store.decodeSample(from: sampleDir.appending(path: "sample.json"))
        #expect(diskSample?.sampleUID == "smp_ac1_fixed_uid")
    }

    @Test("AC1: Corrupt sample.json, index, batch layout, and reference index independently assert targeted errors and leave filesystem unchanged")
    func readOnlyIndependentCorruptionZeroChanges() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let sample = LibrarySample(
            id: "AC1_CORRUPT_S1",
            displayName: "AC1 Corrupt S1",
            batchId: "AC1_CORRUPT_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date(),
            sampleUID: "smp_ac1_corrupt_uid"
        )
        let batch = LibraryBatch(
            id: "AC1_CORRUPT_B1",
            displayName: "AC1 Corrupt B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["AC1_CORRUPT_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC1_CORRUPT_B1", sampleKey: "AC1_CORRUPT_S1")
        let sampleJSON = sampleDir.appending(path: "sample.json")
        let indexJSON = store.indexFileURL(root)

        // --- Test A: Corrupt sample.json independently ---
        let originalSampleBytes = try Data(contentsOf: sampleJSON)
        try "INVALID_JSON_SAMPLE_CORRUPT".write(to: sampleJSON, atomically: true, encoding: .utf8)
        let snapshotSampleCorrupt = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryIndexSyncError.self) {
            _ = try store.readOnlyCompleteIndex(rootURL: root)
        }
        let afterSampleCorrupt = try snapshotDirectoryTree(at: root)
        #expect(snapshotSampleCorrupt == afterSampleCorrupt, "Filesystem modified after corrupt sample.json check")

        // Restore sample.json
        try originalSampleBytes.write(to: sampleJSON)

        // --- Test B: Corrupt library_index.json independently ---
        let originalIndexBytes = try Data(contentsOf: indexJSON)
        try "INVALID_JSON_INDEX_CORRUPT".write(to: indexJSON, atomically: true, encoding: .utf8)
        let snapshotIndexCorrupt = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryIndexSyncError.self) {
            _ = try store.readOnlyCompleteIndex(rootURL: root)
        }
        let afterIndexCorrupt = try snapshotDirectoryTree(at: root)
        #expect(snapshotIndexCorrupt == afterIndexCorrupt, "Filesystem modified after corrupt library_index.json check")

        // Restore index
        try originalIndexBytes.write(to: indexJSON)

        // --- Test C: Corrupt batch layout collision independently ---
        let legacyBatchURL = store.legacyBatchDirectoryURL(root, batchID: "AC1_CORRUPT_B1")
        let preferredBatchURL = store.preferredBatchDirectoryURL(root, batchID: "AC1_CORRUPT_B1")
        try FileManager.default.createDirectory(at: legacyBatchURL.appending(path: "samples"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preferredBatchURL.appending(path: "samples"), withIntermediateDirectories: true)
        try store.writeBatchChecked(batch, to: legacyBatchURL)
        try store.writeBatchChecked(batch, to: preferredBatchURL)
        let snapshotBatchCollision = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryIndexSyncError.self) {
            _ = try store.readOnlyCompleteIndex(rootURL: root)
        }
        let afterBatchCollision = try snapshotDirectoryTree(at: root)
        #expect(snapshotBatchCollision == afterBatchCollision, "Filesystem modified after batch layout collision check")

        // Cleanup duplicate legacy batch
        try FileManager.default.removeItem(at: legacyBatchURL)

        // --- Test D: Corrupt reference index independently (results_index.json) ---
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let resultsIndexURL = try layout.resultsIndexURL(sampleKey: "AC1_CORRUPT_S1")
        try FileManager.default.createDirectory(at: resultsIndexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ corrupt_results_index_syntax_error:".write(to: resultsIndexURL, atomically: true, encoding: .utf8)
        let snapshotRefCorrupt = try snapshotDirectoryTree(at: root)

        let report = ChartAssetAuditService.audit(rootURL: root)
        #expect(report.unreadableIndexSampleKeys.contains("AC1_CORRUPT_S1"))

        let afterRefCorrupt = try snapshotDirectoryTree(at: root)
        #expect(snapshotRefCorrupt == afterRefCorrupt, "Filesystem modified after corrupt reference index audit")
    }

    // MARK: - AC2: Registry Missing-Row and Key-Change Cases (S1, S2)

    @Test("AC2: Registry missing-row for sample with measurements and plots is rejected before any write or batch reconciliation")
    func registryMissingRowRejectedBeforeAnyWrite() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let settings = LibrarySettings.default

        // Create sample S1 in batch B1
        let sample = LibrarySample(
            id: "AC2_S1",
            displayName: "AC2 S1",
            batchId: "AC2_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let batch = LibraryBatch(
            id: "AC2_B1",
            displayName: "AC2 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["AC2_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Add real scientific measurements and plots
        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC2_B1", sampleKey: "AC2_S1")
        let measFile = sampleDir.appending(path: "measurements/curve.dat")
        try "meas_bytes_data".write(to: measFile, atomically: true, encoding: .utf8)
        let plotFile = sampleDir.appending(path: "plots/curve.png")
        try "plot_bytes_data".write(to: plotFile, atomically: true, encoding: .utf8)

        // Inject stale key into batch.json to detect whether reconcileBatchSampleKeys executes
        let batchDir = store.resolvedBatchDirectoryURL(root, batchID: "AC2_B1")
        let batchJSON = batchDir.appending(path: "batch.json")
        var diskBatch = store.decodeBatch(from: batchJSON)!
        diskBatch.sampleKeys.append("STALE_GHOST_KEY")
        try store.writeBatchChecked(diskBatch, to: batchDir)

        let initialSnapshot = try snapshotDirectoryTree(at: root)

        // Preview where row AC2_S1 is DROPPED from Registry
        let previewBatch = LibraryBatch(
            id: "AC2_B1",
            displayName: "AC2 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [],
            updatedAt: Date()
        )
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [previewBatch],
            samples: []
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        // 1. applyBatch MUST reject before any write
        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyBatch(batchId: "AC2_B1", preview: preview, rootURL: root, settings: settings)
        }
        // Assert: sample directory still exists with measurement and plot files
        #expect(FileManager.default.fileExists(atPath: measFile.path))
        #expect(FileManager.default.fileExists(atPath: plotFile.path))
        // Assert: batch.json STILL contains STALE_GHOST_KEY (proof reconcileBatchSampleKeys NEVER committed)
        let diskBatchAfterApplyBatch = store.decodeBatch(from: batchJSON)
        #expect(diskBatchAfterApplyBatch?.sampleKeys.contains("STALE_GHOST_KEY") == true)
        // Assert: filesystem is completely untouched
        let snapshotAfterApplyBatch = try snapshotDirectoryTree(at: root)
        #expect(initialSnapshot == snapshotAfterApplyBatch)

        // 2. applyAll MUST reject before any write
        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyAll(preview: preview, rootURL: root, settings: settings)
        }
        let diskBatchAfterApplyAll = store.decodeBatch(from: batchJSON)
        #expect(diskBatchAfterApplyAll?.sampleKeys.contains("STALE_GHOST_KEY") == true)
        let snapshotAfterApplyAll = try snapshotDirectoryTree(at: root)
        #expect(initialSnapshot == snapshotAfterApplyAll)
    }

    @Test("AC2: Registry key-change for sample with measurements and plots is rejected before create-new commits")
    func registryKeyChangeRejectedBeforeCreateNewCommitted() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let settings = LibrarySettings.default

        // Create sample S1 in batch B1
        let sample = LibrarySample(
            id: "AC2_KEY_OLD",
            displayName: "AC2 Old",
            batchId: "AC2_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let batch = LibraryBatch(
            id: "AC2_B1",
            displayName: "AC2 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["AC2_KEY_OLD"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Add measurement and plot
        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC2_B1", sampleKey: "AC2_KEY_OLD")
        let measFile = sampleDir.appending(path: "measurements/curve.dat")
        try "meas_data".write(to: measFile, atomically: true, encoding: .utf8)
        let plotFile = sampleDir.appending(path: "plots/curve.png")
        try "plot_data".write(to: plotFile, atomically: true, encoding: .utf8)

        // Inject stale key into batch.json
        let batchDir = store.resolvedBatchDirectoryURL(root, batchID: "AC2_B1")
        let batchJSON = batchDir.appending(path: "batch.json")
        var diskBatch = store.decodeBatch(from: batchJSON)!
        diskBatch.sampleKeys.append("STALE_GHOST_KEY")
        try store.writeBatchChecked(diskBatch, to: batchDir)

        let initialSnapshot = try snapshotDirectoryTree(at: root)

        // Registry preview renames AC2_KEY_OLD -> AC2_KEY_NEW
        let sampleNew = LibrarySample(
            id: "AC2_KEY_NEW",
            displayName: "AC2 New",
            batchId: "AC2_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let previewBatch = LibraryBatch(
            id: "AC2_B1",
            displayName: "AC2 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["AC2_KEY_NEW"],
            updatedAt: Date()
        )
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [previewBatch],
            samples: [sampleNew]
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        // 1. applyBatch must reject
        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyBatch(batchId: "AC2_B1", preview: preview, rootURL: root, settings: settings)
        }
        // Assert: AC2_KEY_NEW directory was NEVER created on disk! (Invariant S1)
        let newSampleDir = store.sampleDirectoryURL(root, batchID: "AC2_B1", sampleKey: "AC2_KEY_NEW")
        #expect(!FileManager.default.fileExists(atPath: newSampleDir.path))
        // Assert: AC2_KEY_OLD still exists with files intact
        #expect(FileManager.default.fileExists(atPath: measFile.path))
        #expect(FileManager.default.fileExists(atPath: plotFile.path))
        // Assert: batch.json still has STALE_GHOST_KEY
        #expect(store.decodeBatch(from: batchJSON)?.sampleKeys.contains("STALE_GHOST_KEY") == true)
        #expect(try snapshotDirectoryTree(at: root) == initialSnapshot)

        // 2. applyAll must reject
        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyAll(preview: preview, rootURL: root, settings: settings)
        }
        #expect(!FileManager.default.fileExists(atPath: newSampleDir.path))
        #expect(store.decodeBatch(from: batchJSON)?.sampleKeys.contains("STALE_GHOST_KEY") == true)
        #expect(try snapshotDirectoryTree(at: root) == initialSnapshot)
    }

    @Test("AC2: Ordinary safe updates on existing samples succeed normally")
    func ordinarySafeUpdatesSucceedNormally() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let settings = LibrarySettings.default

        let sample = LibrarySample(
            id: "AC2_SAFE_S1",
            displayName: "AC2 Safe S1",
            batchId: "AC2_SAFE_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: ["Target": "OldTarget"],
            orderedMetadata: [LibraryMetadataItem(key: "Target", value: "OldTarget")],
            numericTags: ["Thickness": 20.0],
            numericDisplay: ["Thickness": "20 nm"],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let batch = LibraryBatch(
            id: "AC2_SAFE_B1",
            displayName: "AC2 Safe B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["AC2_SAFE_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Add real measurement
        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC2_SAFE_B1", sampleKey: "AC2_SAFE_S1")
        let measFile = sampleDir.appending(path: "measurements/curve.dat")
        try "meas_data_safe".write(to: measFile, atomically: true, encoding: .utf8)

        // Safe update: metadata update
        var updatedSample = sample
        updatedSample.metadata["Target"] = "NewTarget"
        updatedSample.orderedMetadata = [LibraryMetadataItem(key: "Target", value: "NewTarget")]
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [batch],
            samples: [updatedSample]
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        let result = try syncService.applyBatch(batchId: "AC2_SAFE_B1", preview: preview, rootURL: root, settings: settings)
        #expect(result != nil)
        #expect(result?.failures.isEmpty == true)

        let reloadedSample = store.decodeSample(from: sampleDir.appending(path: "sample.json"))
        #expect(reloadedSample?.metadata["Target"] == "NewTarget")
        #expect(FileManager.default.fileExists(atPath: measFile.path))
    }

    // MARK: - AC3: Explicit Delete Entrypoints Reject Ambiguity, Shared Plots, Corrupt Dependencies

    @Test("AC3: Explicit delete rejects sample participating in shared plot references with zero file changes")
    func explicitDeleteRejectsSharedPlotReferences() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let mutationService = LibraryMutationService()

        // Create S1 and S2
        let s1 = LibrarySample(id: "AC3_S1", displayName: "AC3 S1", batchId: "AC3_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let s2 = LibrarySample(id: "AC3_S2", displayName: "AC3 S2", batchId: "AC3_B1", substrateRaw: "LAO", substrateDisplay: "LAO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 2, updatedAt: Date())
        let batch = LibraryBatch(id: "AC3_B1", displayName: "AC3 B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["AC3_S1", "AC3_S2"], updatedAt: Date())
        try store.createDrawer(for: s1, batch: batch, rootURL: root)
        try store.createDrawer(for: s2, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Set up shared chart reference in results_index.json for both S1 and S2
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let chartIndexStore = LibraryChartIndexStore(layout: layout)
        let sharedRef = WorkbenchResultReference(
            chartIdentityKey: "shared_chart_key_1",
            chartImagePath: "_spinlab/multi-sample/charts/shared_xy.png",
            manifestPath: "_spinlab/multi-sample/charts/shared_xy.manifest.json",
            workflowID: "XY",
            generatedAt: Date()
        )
        let s1Results = WorkbenchResultsIndex(sampleKey: "AC3_S1", updatedAt: Date(), references: [sharedRef])
        let s2Results = WorkbenchResultsIndex(sampleKey: "AC3_S2", updatedAt: Date(), references: [sharedRef])

        let s1ResultsURL = try layout.resultsIndexURL(sampleKey: "AC3_S1")
        let s2ResultsURL = try layout.resultsIndexURL(sampleKey: "AC3_S2")
        try FileManager.default.createDirectory(at: s1ResultsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: s2ResultsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try chartIndexStore.encodeResultsIndex(s1Results).write(to: s1ResultsURL)
        try chartIndexStore.encodeResultsIndex(s2Results).write(to: s2ResultsURL)

        // Create shared chart files
        let sharedImageURL = try layout.pathResolver.absoluteURL(for: sharedRef.chartImagePath)
        let sharedManifestURL = try layout.pathResolver.absoluteURL(for: sharedRef.manifestPath)
        try FileManager.default.createDirectory(at: sharedImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "png_bytes".write(to: sharedImageURL, atomically: true, encoding: .utf8)
        let sharedManifest = WorkbenchRunManifest(
            schemaVersion: 1,
            manifestID: "shared-manifest-1",
            runID: "run-1",
            workflowID: "XY",
            inputFiles: ["samples/AC3_S1/measurements/test.dat", "samples/AC3_S2/measurements/test.dat"],
            filters: [:],
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            semanticParams: [:],
            outputImagePath: sharedRef.chartImagePath,
            generatedAt: Date(),
            appVersion: "5.14.1"
        )
        let manifestEncoder = JSONEncoder()
        manifestEncoder.dateEncodingStrategy = .iso8601
        try manifestEncoder.encode(sharedManifest).write(to: sharedManifestURL)

        let initialSnapshot = try snapshotDirectoryTree(at: root)

        // 1. Calling store.deleteSampleDrawer on S1 must throw sharedPlotReferenceConflict
        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }
        #expect(try snapshotDirectoryTree(at: root) == initialSnapshot)

        // 2. Calling mutationService.deleteExistingDrawer must return failure
        let deleteOutcome = mutationService.deleteExistingDrawer(batchId: "AC3_B1", rootPath: root.path, previewIndex: nil, libraryStore: store)
        guard case let .failure(msg) = deleteOutcome else {
            Issue.record("Expected failure for drawer delete with shared plots, got \(deleteOutcome)")
            return
        }
        #expect(msg.contains("shared with other samples") || msg.contains("Shared plots cannot be deleted"))
        #expect(try snapshotDirectoryTree(at: root) == initialSnapshot)
    }

    @Test("AC3: Explicit delete rejects sample with corrupted dependency and leaves files untouched")
    func explicitDeleteRejectsCorruptedDependency() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let mutationService = LibraryMutationService()

        let s1 = LibrarySample(id: "AC3_CORRUPT_S1", displayName: "AC3 S1", batchId: "AC3_CORRUPT_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let batch = LibraryBatch(id: "AC3_CORRUPT_B1", displayName: "AC3 B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["AC3_CORRUPT_S1"], updatedAt: Date())
        try store.createDrawer(for: s1, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Create corrupted results_index.json for S1
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let resultsURL = try layout.resultsIndexURL(sampleKey: "AC3_CORRUPT_S1")
        try FileManager.default.createDirectory(at: resultsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "CORRUPTED_NOT_VALID_JSON".write(to: resultsURL, atomically: true, encoding: .utf8)

        let initialSnapshot = try snapshotDirectoryTree(at: root)

        // 1. Direct deleteSampleDrawer throws corruptDependency
        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }
        #expect(try snapshotDirectoryTree(at: root) == initialSnapshot)

        // 2. deleteExistingDrawer returns failure
        let deleteOutcome = mutationService.deleteExistingDrawer(batchId: "AC3_CORRUPT_B1", rootPath: root.path, previewIndex: nil, libraryStore: store)
        guard case let .failure(msg) = deleteOutcome else {
            Issue.record("Expected failure for drawer delete with corrupt dependency, got \(deleteOutcome)")
            return
        }
        #expect(msg.contains("Corrupted dependency") || msg.contains("Delete stopped"))
        #expect(try snapshotDirectoryTree(at: root) == initialSnapshot)
    }

    @Test("AC3: Explicit delete rejects sample with unrecognized cross-namespace asset and leaves files untouched")
    func explicitDeleteRejectsUnrecognizedCrossNamespaceAsset() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let s1 = LibrarySample(id: "AC3_XNAME_S1", displayName: "AC3 S1", batchId: "AC3_XNAME_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let batch = LibraryBatch(id: "AC3_XNAME_B1", displayName: "AC3 B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["AC3_XNAME_S1"], updatedAt: Date())
        try store.createDrawer(for: s1, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Inject foreign / cross-namespace directory into sample drawer
        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC3_XNAME_B1", sampleKey: "AC3_XNAME_S1")
        let foreignDir = sampleDir.appending(path: "external_foreign_dataset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: foreignDir, withIntermediateDirectories: true)
        try "foreign_bytes".write(to: foreignDir.appending(path: "payload.bin"), atomically: true, encoding: .utf8)

        let initialSnapshot = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }
        #expect(try snapshotDirectoryTree(at: root) == initialSnapshot)
    }

    // MARK: - AC4: Orphan Artifact Collision Blocks Re-creation (S3)

    @Test("AC4: Orphan samples/<sampleKey>/_spinlab artifact blocks re-creation without cleanup or attachment")
    func orphanArtifactBlocksRecreation() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Create an orphan artifact on disk at samples/ORPHAN_S1/_spinlab/results_index.json
        // Note: No active sample drawer exists in any batch!
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let orphanResultsURL = try layout.resultsIndexURL(sampleKey: "ORPHAN_S1")
        try FileManager.default.createDirectory(at: orphanResultsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let orphanRef = WorkbenchResultReference(
            chartIdentityKey: "orphan_old_chart_key",
            chartImagePath: "samples/ORPHAN_S1/charts/old_chart.png",
            manifestPath: "samples/ORPHAN_S1/charts/old_chart.manifest.json",
            workflowID: "AHE",
            generatedAt: Date()
        )
        let orphanResults = WorkbenchResultsIndex(sampleKey: "ORPHAN_S1", updatedAt: Date(), references: [orphanRef])
        try LibraryChartIndexStore(layout: layout).encodeResultsIndex(orphanResults).write(to: orphanResultsURL)
        let initialOrphanBytes = try Data(contentsOf: orphanResultsURL)

        // 1. NativeSampleCreationService.createSample must be blocked
        let draft = CreateNativeSampleDraft(
            batchId: "ORPHAN",
            substrateIdentity: "S1",
            substrateDescription: "STO",
            displayName: "New Sample Same Locator"
        )
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = outcome else {
            Issue.record("Expected failure on orphan artifact collision, got \(outcome)")
            return
        }
        guard case let .orphanArtifactCollision(msg) = error else {
            Issue.record("Expected .orphanArtifactCollision error, got \(error)")
            return
        }
        #expect(msg.contains("ORPHAN_S1"))

        // Assert: NO sample drawer created, orphan artifact untouched
        let expectedSampleDir = store.sampleDirectoryURL(root, batchID: "ORPHAN", sampleKey: "ORPHAN_S1")
        #expect(!FileManager.default.fileExists(atPath: expectedSampleDir.path))
        #expect(try Data(contentsOf: orphanResultsURL) == initialOrphanBytes)

        // 2. LibraryStore.createDrawer must also be blocked
        let sampleObj = LibrarySample(
            id: "ORPHAN_S1",
            displayName: "New Sample",
            batchId: "ORPHAN",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: Date()
        )
        let batchObj = LibraryBatch(id: "ORPHAN", displayName: "ORPHAN", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["ORPHAN_S1"], updatedAt: Date())
        #expect(throws: LibraryMutationSafetyError.self) {
            try store.createDrawer(for: sampleObj, batch: batchObj, rootURL: root)
        }
        #expect(!FileManager.default.fileExists(atPath: expectedSampleDir.path))
        #expect(try Data(contentsOf: orphanResultsURL) == initialOrphanBytes)

        // 3. Registry diff apply must also be blocked
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let previewIndex = LibraryIndex(createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil, batches: [batchObj], samples: [sampleObj])
        let preview = LibraryPreview(index: previewIndex, warnings: [])
        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyBatch(batchId: "ORPHAN", preview: preview, rootURL: root, settings: settings)
        }
        #expect(!FileManager.default.fileExists(atPath: expectedSampleDir.path))
        #expect(try Data(contentsOf: orphanResultsURL) == initialOrphanBytes)
    }

    // MARK: - AC5: Fault Injection at Post-Validation Write Phases with Restart Recovery (S5)

    @Test("AC5: Post-validation write fault in permitted mutation reports partial outcome and recovers on retry")
    func permittedMutationWriteFaultReportsPartialAndRecovers() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let settings = LibrarySettings.default

        // Existing sample S1 in batch B1
        let s1 = LibrarySample(id: "AC5_S1", displayName: "AC5 S1", batchId: "AC5_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: ["Field": "Val1"], orderedMetadata: [LibraryMetadataItem(key: "Field", value: "Val1")], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let batch = LibraryBatch(id: "AC5_B1", displayName: "AC5 B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["AC5_S1"], updatedAt: Date())
        try store.createDrawer(for: s1, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC5_B1", sampleKey: "AC5_S1")
        let sampleJSON = sampleDir.appending(path: "sample.json")

        // Prepare permitted update: update metadata
        var s1Updated = s1
        s1Updated.metadata["Field"] = "Val2"
        s1Updated.orderedMetadata = [LibraryMetadataItem(key: "Field", value: "Val2")]
        let previewIndex = LibraryIndex(createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil, batches: [batch], samples: [s1Updated])
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        // Inject write fault: make sample directory write-protected (0o555: read+execute, no write)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sampleDir.path)

        // Call applyBatch: preflight passes, but write phase fails
        let result = try syncService.applyBatch(batchId: "AC5_B1", preview: preview, rootURL: root, settings: settings)
        #expect(result != nil)
        #expect(result?.isPartial == true, "Expected isPartial == true on write failure")
        #expect(result?.failedSamples == 1)
        #expect(result?.failures.contains(where: { $0.contains("updateSample") }) == true)

        // Restore permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sampleDir.path)

        // Restart/Retry recovery: re-run applyBatch
        let retryResult = try syncService.applyBatch(batchId: "AC5_B1", preview: preview, rootURL: root, settings: settings)
        #expect(retryResult != nil)
        #expect(retryResult?.isPartial == false)
        #expect(retryResult?.failedSamples == 0)

        // Verify update succeeded and disk is consistent
        let diskSampleAfter = store.decodeSample(from: sampleJSON)
        #expect(diskSampleAfter?.metadata["Field"] == "Val2")
    }

    @Test("AC5: Explicit delete with post-deletion batch.json failure reports partial outcome and recovers on retry")
    func postDeletionBatchWriteFailureReportsPartialAndRecovers() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        // Explicit (user-initiated) deletion path; Registry apply no longer deletes (S2).
        let emptySample = LibrarySample(id: "AC5_EMPTY_S1", displayName: "AC5 Empty", batchId: "AC5_B2", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let batch = LibraryBatch(id: "AC5_B2", displayName: "AC5 B2", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["AC5_EMPTY_S1"], updatedAt: Date())
        try store.createDrawer(for: emptySample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        let batchDir = store.resolvedBatchDirectoryURL(root, batchID: "AC5_B2")
        let batchJSON = batchDir.appending(path: "batch.json")
        let sampleDir = store.sampleDirectoryURL(root, batchID: "AC5_B2", sampleKey: "AC5_EMPTY_S1")

        // Make batch directory read-only so sample deletion succeeds but batch.json update fails
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: batchDir.path)

        var reportedPartial = false
        do {
            try store.deleteSampleDrawer(for: emptySample, rootURL: root)
        } catch LibraryDrawerError.batchUpdateFailedAfterSampleDeletion {
            reportedPartial = true
        }
        #expect(reportedPartial, "Post-deletion batch.json failure must be reported as a partial outcome, not success")
        #expect(!FileManager.default.fileExists(atPath: sampleDir.path))

        // Restore batch directory permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: batchDir.path)

        // Reconcile (restart/retry recovery) removes the stale key
        let reconciled = try store.reconcileBatchSampleKeys(rootURL: root, batchID: "AC5_B2")
        #expect(reconciled["AC5_B2"]?.contains("AC5_EMPTY_S1") == true)
        let diskBatchAfter = store.decodeBatch(from: batchJSON)
        #expect(diskBatchAfter?.sampleKeys.contains("AC5_EMPTY_S1") == false)
    }

    // MARK: - AC6: Regression & Compatibility

    @Test("AC6: Native sample creation, edit, index rebuild, and safe updates function without regressions")
    func regressionAndCompatibilityVerification() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Create native sample
        let draft = CreateNativeSampleDraft(
            batchId: "PN900",
            substrateIdentity: "S1",
            substrateDescription: "STO(001)",
            displayName: "PN900 S1",
            metadata: ["Grower": "Jack"]
        )
        let createOutcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample, batch, syncedIndex) = createOutcome else {
            Issue.record("Expected successful native sample creation")
            return
        }
        #expect(sample.batchId == "PN900")
        #expect(sample.origin == "native")
        #expect(batch.origin == "native")
        #expect(syncedIndex.samples.count == 1)

        // 2. Restart and read back
        let reloadedIndex = store.loadIndex(from: root)
        #expect(reloadedIndex?.samples.first?.id == sample.id)
        #expect(reloadedIndex?.samples.first?.persistentIdentity == sample.sampleUID)

        // 3. Edit native sample substrate tags and tags
        let editService = LibrarySampleEditService(fieldOwnership: LibraryFieldOwnershipRuleBook(batchOwnedAliases: [], sampleOwnedAliases: ["Grower"]))
        var editDraft = editService.makeDraft(from: sample)
        editDraft.substrateTagsText = "S1, STO-001"
        let updatedSample = try editService.apply(draft: editDraft, to: sample)
        try store.updateSample(updatedSample, rootURL: root)

        let sampleDir = store.sampleDirectoryURL(root, batchID: "PN900", sampleKey: sample.id)
        let diskSample = store.decodeSample(from: sampleDir.appending(path: "sample.json"))
        #expect(diskSample?.substrateTags.contains("s1") == true || diskSample?.substrateTags.contains("S1") == true)
        #expect(diskSample?.sampleUID == sample.sampleUID)
    }

    // MARK: - F001 - F006 Data Integrity & Fail-Closed Tests

    @Test("F001: deleteBatchDrawer fails-closed when library index is unreadable, preserving files")
    func deleteBatchDrawerFailsClosedWhenIndexCorrupted() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let s1 = LibrarySample(
            id: "F1_S1",
            displayName: "F1 S1",
            batchId: "F1_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let b1 = LibraryBatch(
            id: "F1_B1",
            displayName: "F1 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["F1_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Corrupt library_index.json with unparseable data
        let indexURL = store.indexFileURL(root)
        try Data("invalid json content".utf8).write(to: indexURL)

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // deleteBatchDrawer must throw and refuse deletion
        #expect(throws: LibraryIndexSyncError.self) {
            try store.deleteBatchDrawer(batchID: "F1_B1", rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "All files and batch drawer must remain untouched when index is corrupted")
        let batchDir = store.resolvedBatchDirectoryURL(root, batchID: "F1_B1")
        #expect(FileManager.default.fileExists(atPath: batchDir.path), "Batch directory must not be deleted")
    }

    @Test("F002: deleteSampleDrawer fails-closed when library index is unreadable, preserving files")
    func deleteSampleDrawerFailsClosedWhenIndexCorrupted() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let s1 = LibrarySample(
            id: "F2_S1",
            displayName: "F2 S1",
            batchId: "F2_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let b1 = LibraryBatch(
            id: "F2_B1",
            displayName: "F2 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["F2_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Corrupt library_index.json
        let indexURL = store.indexFileURL(root)
        try Data("invalid json content".utf8).write(to: indexURL)

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // deleteSampleDrawer must throw and refuse deletion, never falling back to [sample]
        #expect(throws: LibraryIndexSyncError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Sample files must remain untouched when index is corrupted")
        let sampleDir = store.sampleDirectoryURL(root, batchID: "F2_B1", sampleKey: "F2_S1")
        #expect(FileManager.default.fileExists(atPath: sampleDir.path), "Sample directory must not be deleted")
    }

    @Test("F003: Parameter-only sample with tags, metadata, or revision log is protected from Registry deletion")
    func parameterOnlySampleProtectedFromRegistryDeletion() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let settings = LibrarySettings.default

        // Sample has NO measurements, NO plots, but HAS numeric tags and metadata
        let sample = LibrarySample(
            id: "F3_S1",
            displayName: "F3 S1",
            batchId: "F3_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: ["Recipe": "R42-Anneal", "Growth_Pressure": "1e-5"],
            orderedMetadata: [LibraryMetadataItem(key: "Recipe", value: "R42-Anneal")],
            numericTags: ["thickness_nm": 45.0, "hall_mobility": 120.5],
            numericDisplay: ["thickness_nm": "45 nm", "hall_mobility": "120.5 cm^2/Vs"],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let batch = LibraryBatch(
            id: "F3_B1",
            displayName: "F3 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["F3_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)

        // Write a manual change log to sample drawer as well
        let sampleDir = store.sampleDirectoryURL(root, batchID: "F3_B1", sampleKey: "F3_S1")
        let changeLogURL = sampleDir.appending(path: "sample_change_log.json")
        let changeEntry = LibrarySampleChangeLogEntry(
            id: UUID(),
            sampleId: "F3_S1",
            batchId: "F3_B1",
            changedAt: Date(),
            source: "manual",
            changes: [LibrarySampleChangeLogItem(key: "thickness_nm", oldValue: nil, newValue: "45.0")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let entryData = try encoder.encode([changeEntry])
        try entryData.write(to: changeLogURL)

        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Registry preview drops F3_S1 from batch F3_B1
        let previewBatch = LibraryBatch(
            id: "F3_B1",
            displayName: "F3 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [],
            updatedAt: Date()
        )
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [previewBatch],
            samples: []
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // applyBatch must refuse deletion due to scientific parameter data
        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyBatch(batchId: "F3_B1", preview: preview, rootURL: root, settings: settings)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "No files modified when Registry drops parameter-bearing sample")
        #expect(FileManager.default.fileExists(atPath: sampleDir.path))
        #expect(FileManager.default.fileExists(atPath: changeLogURL.path))
    }

    @Test("F004: Stale library_index does not mask orphan artifact collision during native creation")
    func staleIndexDoesNotMaskOrphanArtifactDuringCreation() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let targetSampleId = "B_NEW_S_ORPHAN"

        // 1. Create a library index that still records B_NEW_S_ORPHAN
        let staleIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [
                LibraryBatch(
                    id: "B_NEW",
                    displayName: "B New",
                    sheetName: "",
                    metadata: [:],
                    numericTags: [:],
                    numericDisplay: [:],
                    sampleKeys: [targetSampleId],
                    updatedAt: Date()
                )
            ],
            samples: [
                LibrarySample(
                    id: targetSampleId,
                    displayName: "S Orphan",
                    batchId: "B_NEW",
                    substrateRaw: "STO",
                    substrateDisplay: "STO",
                    substrateTokens: [],
                    substrateTags: [],
                    metadata: [:],
                    orderedMetadata: [],
                    numericTags: [:],
                    numericDisplay: [:],
                    sourceSheetName: nil,
                    sourceRowNumber: nil,
                    updatedAt: Date()
                )
            ]
        )
        _ = store.saveIndex(staleIndex, to: root)

        // Notice: Physical sample drawer for B_NEW_S_ORPHAN does NOT exist on disk!
        // But orphan artifact exists in samples/B_NEW_S_ORPHAN/_spinlab/
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let spinlabDir = root.appending(path: "samples/\(targetSampleId)/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: spinlabDir, withIntermediateDirectories: true)
        let resultsURL = try layout.resultsIndexURL(sampleKey: targetSampleId)
        let dummyIndex = WorkbenchResultsIndex(
            sampleKey: targetSampleId,
            updatedAt: Date(),
            references: [
                WorkbenchResultReference(
                    chartIdentityKey: "orphan-chart-id",
                    chartImagePath: "samples/\(targetSampleId)/charts/c1.png",
                    manifestPath: "samples/\(targetSampleId)/charts/c1.manifest.json",
                    workflowID: "transport",
                    generatedAt: Date()
                )
            ]
        )
        try JSONEncoder().encode(dummyIndex).write(to: resultsURL)

        // Verify detectOrphanArtifact directly detects the orphan despite stale index:
        let (isOrphan, orphanPath) = LibraryMutationSafetyGuard.detectOrphanArtifact(
            sampleKey: targetSampleId,
            rootURL: root,
            fileManager: store.fileManager
        )
        #expect(isOrphan == true, "Stale index must not mask orphan artifact")
        #expect(orphanPath?.contains(targetSampleId) == true)

        // 2. User attempts to create new sample with locator 'S_ORPHAN' in B_NEW
        let draft = CreateNativeSampleDraft(
            batchId: "B_NEW",
            substrateIdentity: "S_ORPHAN",
            substrateDescription: "STO",
            displayName: "New S Orphan"
        )

        let creationService = NativeSampleCreationService()
        let result = creationService.createSample(draft: draft, rootURL: root, libraryStore: store, settings: .default)
        guard case let .failure(error) = result else {
            Issue.record("createSample must fail when orphan artifact exists, even if stale index lists the sampleKey")
            return
        }
        guard case let .orphanArtifactCollision(msg) = error else {
            Issue.record("Expected .orphanArtifactCollision error, got \(error)")
            return
        }
        #expect(msg.contains(targetSampleId))

        // Verify the orphan artifact was not touched or attached
        let resultsData = try Data(contentsOf: resultsURL)
        let reloaded = try JSONDecoder().decode(WorkbenchResultsIndex.self, from: resultsData)
        #expect(reloaded.references.first?.chartIdentityKey == "orphan-chart-id")
    }

    @Test("F005: Unrecognized assets in independent Workbench namespace block explicit deletion")
    func unrecognizedWorkbenchAssetsBlockExplicitDeletion() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let sample = LibrarySample(
            id: "F5_S1",
            displayName: "F5 S1",
            batchId: "F5_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let batch = LibraryBatch(
            id: "F5_B1",
            displayName: "F5 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["F5_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Create an unrecognized foreign script in samples/F5_S1/_spinlab/
        let spinlabDir = root.appending(path: "samples/F5_S1/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: spinlabDir, withIntermediateDirectories: true)
        let foreignFile = spinlabDir.appending(path: "foreign_script.sh")
        try Data("#!/bin/sh\necho test\n".utf8).write(to: foreignFile)

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: sample, rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "No files must be deleted when unrecognized workbench assets exist")
    }

    @Test("F006: Other sample corrupted results index fails closed during deletion")
    func otherSampleCorruptedResultsIndexFailsClosedDuringDeletion() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let layout = LibraryArtifactLayout(libraryRootURL: root)

        let s1 = LibrarySample(
            id: "F6_S1",
            displayName: "F6 S1",
            batchId: "F6_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let s2 = LibrarySample(
            id: "F6_S2",
            displayName: "F6 S2",
            batchId: "F6_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 2,
            updatedAt: Date()
        )
        let b1 = LibraryBatch(
            id: "F6_B1",
            displayName: "F6 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["F6_S1", "F6_S2"],
            updatedAt: Date()
        )
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        try store.createDrawer(for: s2, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // S1 has a valid results index referencing a chart
        let s1SpinlabDir = root.appending(path: "samples/F6_S1/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: s1SpinlabDir, withIntermediateDirectories: true)
        let s1ResultsURL = try layout.resultsIndexURL(sampleKey: "F6_S1")
        let s1Results = WorkbenchResultsIndex(
            sampleKey: "F6_S1",
            updatedAt: Date(),
            references: [
                WorkbenchResultReference(
                    chartIdentityKey: "shared-key",
                    chartImagePath: "samples/F6_S1/charts/plot.png",
                    manifestPath: "samples/F6_S1/charts/plot.manifest.json",
                    workflowID: "wf",
                    generatedAt: Date()
                )
            ]
        )
        try JSONEncoder().encode(s1Results).write(to: s1ResultsURL)

        // S2 has a CORRUPT results index
        let s2SpinlabDir = root.appending(path: "samples/F6_S2/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: s2SpinlabDir, withIntermediateDirectories: true)
        let s2ResultsURL = try layout.resultsIndexURL(sampleKey: "F6_S2")
        try Data("corrupted broken json {".utf8).write(to: s2ResultsURL)

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // Deleting S1 must fail-closed because S2's results index is corrupt (unknown dependencies)
        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Files must remain intact when other sample's dependencies cannot be read")
    }

    @Test("F003: Native sample with parameters but NO change log is protected from deletion")
    func nativeSampleParametersWithoutChangeLogProtectedFromRegistryDeletion() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        // Native/manual sample with numericTags and metadata, but NO change log file on disk
        let sample = LibrarySample(
            id: "F3B_S1",
            displayName: "F3B S1",
            batchId: "F3B_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: ["Anneal_Temp_C": "850", "Dopant": "Mn"],
            orderedMetadata: [LibraryMetadataItem(key: "Anneal_Temp_C", value: "850")],
            numericTags: ["hall_mobility": 185.0, "resistivity_ohm_cm": 0.042],
            numericDisplay: ["hall_mobility": "185 cm^2/Vs", "resistivity_ohm_cm": "0.042 ohm-cm"],
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: Date(),
            origin: "native"
        )
        let batch = LibraryBatch(
            id: "F3B_B1",
            displayName: "F3B B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["F3B_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        let sampleDir = store.sampleDirectoryURL(root, batchID: "F3B_B1", sampleKey: "F3B_S1")
        #expect(!FileManager.default.fileExists(atPath: sampleDir.appending(path: "sample_change_log.json").path))
        #expect(!FileManager.default.fileExists(atPath: sampleDir.appending(path: "change_log.jsonl").path))
        #expect(!FileManager.default.fileExists(atPath: sampleDir.appending(path: "edit_log.json").path))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // 2. Direct validateRegistryDiffSafety with removedSamples must throw the S2 non-authorization error
        #expect(throws: LibraryMutationSafetyError.registrySampleRemovalNotAuthorized(sampleId: "F3B_S1", batchId: "F3B_B1")) {
            try LibraryMutationSafetyGuard.validateRegistryDiffSafety(
                removedSamples: [sample],
                newSamples: [],
                removedBatches: [],
                rootURL: root
            )
        }

        // 3. Batch removal must also throw the S2 non-authorization error
        #expect(throws: LibraryMutationSafetyError.registryBatchRemovalNotAuthorized(batchId: "F3B_B1")) {
            try LibraryMutationSafetyGuard.validateRegistryDiffSafety(
                removedSamples: [],
                newSamples: [],
                removedBatches: [batch],
                rootURL: root
            )
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "No files modified when Registry validation rejects deletion of parameter-bearing sample")
        #expect(FileManager.default.fileExists(atPath: sampleDir.path))
    }

    @Test("Entry point: LibraryMutationService.deleteExistingDrawer fails-closed when index is corrupt")
    func deleteExistingDrawerFailsClosedWhenIndexCorrupt() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let mutationService = LibraryMutationService()

        let s1 = LibrarySample(
            id: "CE_S1",
            displayName: "CE S1",
            batchId: "CE_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let b1 = LibraryBatch(
            id: "CE_B1",
            displayName: "CE B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["CE_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Corrupt library_index.json
        let indexURL = store.indexFileURL(root)
        try Data("corrupt json data".utf8).write(to: indexURL)

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        let outcome = mutationService.deleteExistingDrawer(
            batchId: "CE_B1",
            rootPath: root.path,
            previewIndex: nil,
            libraryStore: store
        )

        switch outcome {
        case .failure(let message):
            #expect(message.contains("Delete stopped:"), "Outcome should report delete stopped")
        default:
            Issue.record("Expected .failure but got \(outcome)")
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when deleteExistingDrawer encounters corrupt index")
        let batchDir = store.resolvedBatchDirectoryURL(root, batchID: "CE_B1")
        #expect(FileManager.default.fileExists(atPath: batchDir.path), "Batch directory must remain intact")
    }

    @Test("Entry point: LibrarySyncService applyBatch and applyAll fail-closed when index is corrupt")
    func syncServiceApplyFailsClosedWhenIndexCorrupt() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let settings = LibrarySettings.default

        let s1 = LibrarySample(
            id: "CS_S1",
            displayName: "CS S1",
            batchId: "CS_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let b1 = LibraryBatch(
            id: "CS_B1",
            displayName: "CS B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["CS_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Corrupt library_index.json
        let indexURL = store.indexFileURL(root)
        try Data("corrupt json data".utf8).write(to: indexURL)

        let previewBatch = LibraryBatch(
            id: "CS_B1",
            displayName: "CS B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [],
            updatedAt: Date()
        )
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [previewBatch],
            samples: []
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryIndexSyncError.self) {
            _ = try syncService.applyBatch(batchId: "CS_B1", preview: preview, rootURL: root, settings: settings)
        }

        #expect(throws: LibraryIndexSyncError.self) {
            _ = try syncService.applyAll(preview: preview, rootURL: root, settings: settings)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when applyBatch/applyAll encounter corrupt index")
        let batchDir = store.resolvedBatchDirectoryURL(root, batchID: "CS_B1")
        #expect(FileManager.default.fileExists(atPath: batchDir.path), "Batch directory must remain intact")
    }

    // MARK: - R01: Scientific Parameters (numericTags, numericDisplay, metadata) in XLSX Registry Samples

    @Test("R01: XLSX Registry sample with parameters (numeric tags/metadata) but no change log is protected from Registry diff deletion")
    func xlsxRegistrySampleWithParametersProtectedFromDiffDeletion() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        let settings = LibrarySettings.default

        // Existing XLSX sample that has parameters: numericTags, numericDisplay, and metadata
        let sample = LibrarySample(
            id: "R01_REG_S1",
            displayName: "R01 Sample",
            batchId: "R01_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: ["sto"],
            substrateTags: ["STO"],
            metadata: ["Growth Temperature": "750 C", "Oxygen Pressure": "100 mTorr"],
            orderedMetadata: [
                LibraryMetadataItem(key: "Growth Temperature", value: "750 C"),
                LibraryMetadataItem(key: "Oxygen Pressure", value: "100 mTorr")
            ],
            numericTags: ["temp": 750.0, "po2": 100.0],
            numericDisplay: ["temp": "750", "po2": "100"],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let batch = LibraryBatch(
            id: "R01_B1",
            displayName: "R01 Batch",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["R01_REG_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // Incoming Registry diff dropped R01_REG_S1
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [LibraryBatch(id: "R01_B1", displayName: "R01 Batch", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: [], updatedAt: Date())],
            samples: []
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyBatch(batchId: "R01_B1", preview: preview, rootURL: root, settings: settings)
        }

        #expect(throws: LibraryMutationSafetyError.self) {
            _ = try syncService.applyAll(preview: preview, rootURL: root, settings: settings)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when Registry diff attempts to drop sample with parameters")
        let sampleDir = store.sampleDirectoryURL(root, batchID: "R01_B1", sampleKey: "R01_REG_S1")
        #expect(FileManager.default.fileExists(atPath: sampleDir.path), "Sample drawer must remain intact")
    }

    // MARK: - R02: Unreadable Orphan Directory Fails Closed

    @Test("R02: Unreadable orphan Workbench directory fails closed during native sample creation")
    func unreadableOrphanWorkbenchDirectoryFailsClosedDuringCreation() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let creationService = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let targetKey = "R02_B1_ORPHAN_S1"

        // Create orphan Workbench _spinlab directory without an active sample drawer
        let spinlabDir = root.appending(path: "samples/\(targetKey)/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: spinlabDir, withIntermediateDirectories: true)
        let dummyFile = spinlabDir.appending(path: "results_index.json")
        try "{}".write(to: dummyFile, atomically: true, encoding: .utf8)

        // Make spinlab directory unreadable (permission 0o000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: spinlabDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: spinlabDir.path)
        }

        // 1. detectOrphanArtifact must return true fail-closed
        let (isOrphan, orphanPath) = LibraryMutationSafetyGuard.detectOrphanArtifact(sampleKey: targetKey, rootURL: root)
        #expect(isOrphan, "detectOrphanArtifact must fail-closed on unreadable directory")
        #expect(orphanPath != nil)

        // 2. Attempting to create native sample with this locator must fail-closed
        let draft = CreateNativeSampleDraft(
            batchId: "R02_B1",
            substrateIdentity: "ORPHAN_S1",
            substrateDescription: "STO",
            displayName: "Test R02"
        )
        let outcome = creationService.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        switch outcome {
        case .failure(let err):
            switch err {
            case .orphanArtifactCollision(let msg):
                #expect(msg.contains("R02_B1_ORPHAN_S1") || msg.contains("samples/"))
            default:
                #expect(err.localizedDescription.contains("Orphan artifact") || err.localizedDescription.contains("R02_B1_ORPHAN_S1"))
            }
        default:
            Issue.record("Expected .failure but got \(outcome)")
        }

        // Verify zero drawers created under batches/
        let sampleDir = store.sampleDirectoryURL(root, batchID: "R02_B1", sampleKey: targetKey)
        #expect(!FileManager.default.fileExists(atPath: sampleDir.path), "Sample drawer must not be created")
    }

    // MARK: - R03: Explicit Sample Deletion Refused When Active Workbench Artifacts Exist

    @Test("R03: Explicit sample deletion is refused when active Workbench artifacts exist")
    func explicitDeletionRefusedWhenActiveWorkbenchArtifactsExist() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let layout = LibraryArtifactLayout(libraryRootURL: root)
        let mutationService = LibraryMutationService()

        let sample = LibrarySample(
            id: "R03_S1",
            displayName: "R03 S1",
            batchId: "R03_B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let batch = LibraryBatch(
            id: "R03_B1",
            displayName: "R03 B1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["R03_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Write active Workbench results index and chart for R03_S1
        let spinlabDir = root.appending(path: "samples/R03_S1/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: spinlabDir, withIntermediateDirectories: true)
        let resultsURL = try layout.resultsIndexURL(sampleKey: "R03_S1")
        let results = WorkbenchResultsIndex(
            sampleKey: "R03_S1",
            updatedAt: Date(),
            references: [
                WorkbenchResultReference(
                    chartIdentityKey: "r03-chart-key",
                    chartImagePath: "samples/R03_S1/charts/plot.png",
                    manifestPath: "samples/R03_S1/charts/plot.manifest.json",
                    workflowID: "afm",
                    generatedAt: Date()
                )
            ]
        )
        let isoEncoder = JSONEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        try isoEncoder.encode(results).write(to: resultsURL)

        let chartsDir = root.appending(path: "samples/R03_S1/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chartsDir, withIntermediateDirectories: true)
        try Data("PNG_BYTES".utf8).write(to: chartsDir.appending(path: "plot.png"))
        try Data("MANIFEST_BYTES".utf8).write(to: chartsDir.appending(path: "plot.manifest.json"))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // 1. deleteSampleDrawer must throw attachedWorkbenchArtifact fail-closed
        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: sample, rootURL: root)
        }

        // 2. deleteExistingDrawer must return failure
        let outcome = mutationService.deleteExistingDrawer(
            batchId: "R03_B1",
            rootPath: root.path,
            previewIndex: nil,
            libraryStore: store
        )
        switch outcome {
        case .failure(let msg):
            #expect(msg.contains("active Workbench artifacts") || msg.contains("Delete stopped"), "Outcome must state deletion refused due to active artifacts, got: \(msg)")
        default:
            Issue.record("Expected failure but got \(outcome)")
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when explicit deletion is refused due to active Workbench artifacts")
        let sampleDir = store.sampleDirectoryURL(root, batchID: "R03_B1", sampleKey: "R03_S1")
        #expect(FileManager.default.fileExists(atPath: sampleDir.path), "Sample drawer must remain intact")
        #expect(FileManager.default.fileExists(atPath: resultsURL.path), "Results index must remain intact")
    }

    @Test("R03: Explicit deletion refused when only chart files exist without results index (attachedWorkbenchArtifact, not corruptDependency)")
    func explicitDeletionRefusedWhenOnlyChartFilesExist() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let sample = LibrarySample(id: "R03_CHART_S1", displayName: "R03 Chart S1", batchId: "R03_CHART_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let batch = LibraryBatch(id: "R03_CHART_B1", displayName: "R03 Chart B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["R03_CHART_S1"], updatedAt: Date())
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Only create charts directory with a file; NO results_index.json exists!
        let chartsDir = root.appending(path: "samples/R03_CHART_S1/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chartsDir, withIntermediateDirectories: true)
        try Data("PNG_IMAGE".utf8).write(to: chartsDir.appending(path: "lone_plot.png"))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // Must throw attachedWorkbenchArtifact, NOT corruptDependency
        var caughtError: LibraryMutationSafetyError?
        do {
            try store.deleteSampleDrawer(for: sample, rootURL: root)
            Issue.record("Expected deleteSampleDrawer to throw")
        } catch let err as LibraryMutationSafetyError {
            caughtError = err
        } catch {
            Issue.record("Expected LibraryMutationSafetyError but got: \(error)")
        }

        switch caughtError {
        case .attachedWorkbenchArtifact(let sId, let path, let reason):
            #expect(sId == "R03_CHART_S1")
            #expect(path.contains("charts"))
            #expect(reason.contains("chart file(s)"))
        default:
            Issue.record("Expected .attachedWorkbenchArtifact but got: \(String(describing: caughtError))")
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Files must remain intact")
    }

    @Test("R03: Explicit deletion refused when empty results index exists in _spinlab")
    func explicitDeletionRefusedWhenEmptyResultsIndexExists() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let layout = LibraryArtifactLayout(libraryRootURL: root)

        let sample = LibrarySample(id: "R03_EMPTY_S1", displayName: "R03 Empty S1", batchId: "R03_EMPTY_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let batch = LibraryBatch(id: "R03_EMPTY_B1", displayName: "R03 Empty B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["R03_EMPTY_S1"], updatedAt: Date())
        try store.createDrawer(for: sample, batch: batch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Write results_index.json with 0 references
        let emptyResults = WorkbenchResultsIndex(sampleKey: "R03_EMPTY_S1", updatedAt: Date(), references: [])
        let isoEncoder = JSONEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: root.appending(path: "samples/R03_EMPTY_S1/_spinlab"), withIntermediateDirectories: true)
        try isoEncoder.encode(emptyResults).write(to: layout.resultsIndexURL(sampleKey: "R03_EMPTY_S1"))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // Must throw attachedWorkbenchArtifact because _spinlab contains a file
        var caughtError: LibraryMutationSafetyError?
        do {
            try store.deleteSampleDrawer(for: sample, rootURL: root)
            Issue.record("Expected deleteSampleDrawer to throw")
        } catch let err as LibraryMutationSafetyError {
            caughtError = err
        } catch {
            Issue.record("Expected LibraryMutationSafetyError but got: \(error)")
        }

        switch caughtError {
        case .attachedWorkbenchArtifact(let sId, _, let reason):
            #expect(sId == "R03_EMPTY_S1")
            #expect(reason.contains("file(s)"))
        default:
            Issue.record("Expected .attachedWorkbenchArtifact but got: \(String(describing: caughtError))")
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Files must remain intact")
    }

    // MARK: - R04: Cross-Sample Reverse Reference, Multi-Sample Manifests, and Unindexed Samples

    @Test("R04: Other sample reverse reference blocks deletion even when target sample has no results index")
    func otherSampleReverseReferenceBlocksDeletionWhenTargetHasNoResultsIndex() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let layout = LibraryArtifactLayout(libraryRootURL: root)

        // S1 has NO results index
        let s1 = LibrarySample(id: "R04_S1", displayName: "R04 S1", batchId: "R04_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        // S2 has results index referencing S1's chart
        let s2 = LibrarySample(id: "R04_S2", displayName: "R04 S2", batchId: "R04_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 2, updatedAt: Date())
        let b1 = LibraryBatch(id: "R04_B1", displayName: "R04 B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["R04_S1", "R04_S2"], updatedAt: Date())

        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        try store.createDrawer(for: s2, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // S2 references S1's chart path in its results index
        let s2Spinlab = root.appending(path: "samples/R04_S2/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: s2Spinlab, withIntermediateDirectories: true)
        let s2Results = WorkbenchResultsIndex(
            sampleKey: "R04_S2",
            updatedAt: Date(),
            references: [
                WorkbenchResultReference(
                    chartIdentityKey: "rev-ref-key",
                    chartImagePath: "samples/R04_S1/charts/reverse_plot.png",
                    manifestPath: "samples/R04_S1/charts/reverse_plot.manifest.json",
                    workflowID: "wf",
                    generatedAt: Date()
                )
            ]
        )
        let isoEncoder = JSONEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        try isoEncoder.encode(s2Results).write(to: layout.resultsIndexURL(sampleKey: "R04_S2"))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // Deleting S1 must fail-closed because S2 holds a reverse reference to S1's assets
        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when deleting sample with reverse reference")
    }

    @Test("R04: Other sample corrupted results index blocks deletion even when target sample has no results index")
    func otherSampleCorruptIndexBlocksDeletionWhenTargetHasNoResultsIndex() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let layout = LibraryArtifactLayout(libraryRootURL: root)

        // S1 has NO results index
        let s1 = LibrarySample(id: "R04B_S1", displayName: "R04B S1", batchId: "R04B_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        // S3 has CORRUPTED results index
        let s3 = LibrarySample(id: "R04B_S3", displayName: "R04B S3", batchId: "R04B_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 3, updatedAt: Date())
        let b1 = LibraryBatch(id: "R04B_B1", displayName: "R04B B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["R04B_S1", "R04B_S3"], updatedAt: Date())

        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        try store.createDrawer(for: s3, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Write broken corrupt results index for S3
        let s3Spinlab = root.appending(path: "samples/R04B_S3/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: s3Spinlab, withIntermediateDirectories: true)
        try Data("broken corrupt json {{".utf8).write(to: layout.resultsIndexURL(sampleKey: "R04B_S3"))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        // Deleting S1 must fail-closed because S3's index is corrupt and unknown dependencies exist
        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when deleting sample while other sample index is corrupt")
    }

    @Test("R04: Multi-sample manifest in _spinlab/multi-sample/charts blocks deletion even when target has no results index")
    func multiSampleManifestBlocksDeletionWhenTargetHasNoResultsIndex() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let s1 = LibrarySample(id: "R04_MS_S1", displayName: "MS S1", batchId: "R04_MS_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let b1 = LibraryBatch(id: "R04_MS_B1", displayName: "MS B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["R04_MS_S1"], updatedAt: Date())
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Create multi-sample chart manifest mentioning R04_MS_S1 in inputFiles
        let msDir = root.appending(path: "_spinlab/multi-sample/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: msDir, withIntermediateDirectories: true)
        let manifest = WorkbenchRunManifest(
            schemaVersion: 1,
            manifestID: "ms-manifest-1",
            runID: "run-1",
            workflowID: "afm",
            inputFiles: ["samples/R04_MS_S1/measurements/test.dat", "samples/OTHER/measurements/test.dat"],
            filters: [:],
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            semanticParams: [:],
            outputImagePath: "_spinlab/multi-sample/charts/comp.png",
            generatedAt: Date(),
            appVersion: "5.14.1"
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(manifest).write(to: msDir.appending(path: "comp.manifest.json"))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when deleting sample participating in multi-sample manifest")
    }

    @Test("R04: Unindexed sample directory on disk referencing target sample blocks deletion fail-closed")
    func unindexedSampleOnDiskBlocksDeletionFailClosed() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let layout = LibraryArtifactLayout(libraryRootURL: root)

        let s1 = LibrarySample(id: "R04_UNIDX_S1", displayName: "Target S1", batchId: "R04_UNIDX_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let b1 = LibraryBatch(id: "R04_UNIDX_B1", displayName: "Target B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["R04_UNIDX_S1"], updatedAt: Date())
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Create unindexed sample on disk under samples/UNINDEXED_GHOST/_spinlab/results_index.json
        // referencing R04_UNIDX_S1
        let ghostKey = "UNINDEXED_GHOST"
        let ghostDir = root.appending(path: "samples/\(ghostKey)/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ghostDir, withIntermediateDirectories: true)
        let ghostResults = WorkbenchResultsIndex(
            sampleKey: ghostKey,
            updatedAt: Date(),
            references: [
                WorkbenchResultReference(
                    chartIdentityKey: "ghost-key",
                    chartImagePath: "samples/R04_UNIDX_S1/charts/plot.png",
                    manifestPath: "samples/R04_UNIDX_S1/charts/plot.manifest.json",
                    workflowID: "afm",
                    generatedAt: Date()
                )
            ]
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(ghostResults).write(to: layout.resultsIndexURL(sampleKey: ghostKey))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        #expect(throws: LibraryMutationSafetyError.self) {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when unindexed sample holds reverse reference")
    }

    @Test("R04: Corrupted multi-sample manifest in _spinlab/multi-sample/charts fails closed with corruptDependency")
    func corruptMultiSampleManifestFailsClosedWithCorruptDependency() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)

        let s1 = LibrarySample(id: "R04_CORRUPT_MS_S1", displayName: "Target S1", batchId: "R04_CORRUPT_MS_B1", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date())
        let b1 = LibraryBatch(id: "R04_CORRUPT_MS_B1", displayName: "Target B1", sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["R04_CORRUPT_MS_S1"], updatedAt: Date())
        try store.createDrawer(for: s1, batch: b1, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Write corrupt JSON to _spinlab/multi-sample/charts/broken.manifest.json
        let msDir = root.appending(path: "_spinlab/multi-sample/charts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: msDir, withIntermediateDirectories: true)
        try Data("broken corrupt manifest json {{".utf8).write(to: msDir.appending(path: "broken.manifest.json"))

        let snapshotBefore = try snapshotDirectoryTree(at: root)

        var caughtError: LibraryMutationSafetyError?
        do {
            try store.deleteSampleDrawer(for: s1, rootURL: root)
            Issue.record("Expected deleteSampleDrawer to throw")
        } catch let err as LibraryMutationSafetyError {
            caughtError = err
        } catch {
            Issue.record("Expected LibraryMutationSafetyError but got: \(error)")
        }

        switch caughtError {
        case .corruptDependency(let sampleId, let path, let reason):
            #expect(sampleId == "R04_CORRUPT_MS_S1")
            #expect(path.contains("broken.manifest.json"))
            #expect(reason.contains("Corrupted or invalid multi-sample manifest"))
        default:
            Issue.record("Expected .corruptDependency but got: \(String(describing: caughtError))")
        }

        let snapshotAfter = try snapshotDirectoryTree(at: root)
        #expect(snapshotBefore == snapshotAfter, "Zero files changed when corrupt multi-sample manifest is encountered")
    }

    // MARK: - F004 / S2: Registry removal is never deletion authorization

    private func makeRegistrySample(
        id: String, batch: String, metadata: [String: String], numericTags: [String: Double] = [:]
    ) -> LibrarySample {
        LibrarySample(
            id: id, displayName: id, batchId: batch, substrateRaw: "STO", substrateDisplay: "STO",
            substrateTokens: [], substrateTags: [], metadata: metadata,
            orderedMetadata: metadata.keys.sorted().map { LibraryMetadataItem(key: $0, value: metadata[$0] ?? "") },
            numericTags: numericTags, numericDisplay: [:],
            sourceSheetName: "Sheet1", sourceRowNumber: 1, updatedAt: Date()
        )
    }

    private func makeRegistryBatch(id: String, keys: [String]) -> LibraryBatch {
        LibraryBatch(id: id, displayName: id, sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: keys, updatedAt: Date())
    }

    private func makePreview(batches: [LibraryBatch], samples: [LibrarySample]) -> LibraryPreview {
        LibraryPreview(
            index: LibraryIndex(createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil, batches: batches, samples: samples),
            warnings: []
        )
    }

    @Test("F004/S2: Registry missing row is rejected for samples WITH and WITHOUT metadata (metadata emptiness is not authorization)")
    func registryMissingRowRejectedRegardlessOfMetadata() throws {
        let variants: [(String, [String: String], [String: Double])] = [
            ("EMPTY", [:], [:]),
            ("META", ["Growth_Temp_C": "700"], [:]),
            ("TAGS", ["Growth_Temp_C": "700"], ["thickness_nm": 42.0])
        ]
        for (tag, metadata, tags) in variants {
            let root = try makeTempLibrary()
            defer { cleanup(root) }
            let store = LibraryStore()
            try store.ensureRootDirectories(at: root)
            let sync = LibrarySyncService(libraryStore: store, libraryDiffEngine: LibraryDiffEngine())
            let settings = LibrarySettings.default

            let sample = makeRegistrySample(id: "F4_\(tag)_S1", batch: "F4_\(tag)_B1", metadata: metadata, numericTags: tags)
            let batch = makeRegistryBatch(id: "F4_\(tag)_B1", keys: [sample.id])
            try store.createDrawer(for: sample, batch: batch, rootURL: root)
            _ = try store.syncIndexFromFilesystem(rootURL: root)
            let before = try snapshotDirectoryTree(at: root)

            let preview = makePreview(batches: [makeRegistryBatch(id: batch.id, keys: [])], samples: [])
            let expected = LibraryMutationSafetyError.registrySampleRemovalNotAuthorized(sampleId: sample.id, batchId: batch.id)

            #expect(throws: expected) { _ = try sync.applyBatch(batchId: batch.id, preview: preview, rootURL: root, settings: settings) }
            #expect(throws: expected) { _ = try sync.applyAll(preview: preview, rootURL: root, settings: settings) }

            #expect(try snapshotDirectoryTree(at: root) == before, "\(tag): files, mtimes and index must be unchanged")
            let message = expected.errorDescription ?? ""
            #expect(!message.contains("scientific data"), "Registry fields must not be described as confirmed research data")
            #expect(message.contains("not authorization"))
        }
    }

    @Test("F004/S2: Registry batch missing (empty batch) is rejected without separate authorization")
    func registryEmptyBatchMissingRejected() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }
        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let sync = LibrarySyncService(libraryStore: store, libraryDiffEngine: LibraryDiffEngine())
        let settings = LibrarySettings.default

        // Keep one unrelated batch in preview so the diff only drops the empty batch.
        let keepSample = makeRegistrySample(id: "KEEP_S1", batch: "KEEP_B1", metadata: [:])
        let keepBatch = makeRegistryBatch(id: "KEEP_B1", keys: [keepSample.id])
        try store.createDrawer(for: keepSample, batch: keepBatch, rootURL: root)
        let emptyBatch = makeRegistryBatch(id: "EMPTY_B1", keys: [])
        let emptyBatchDir = store.resolvedBatchDirectoryURL(root, batchID: emptyBatch.id)
        try FileManager.default.createDirectory(at: emptyBatchDir, withIntermediateDirectories: true)
        try store.writeBatchChecked(emptyBatch, to: emptyBatchDir)
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        let before = try snapshotDirectoryTree(at: root)

        let preview = makePreview(batches: [keepBatch], samples: [keepSample])
        let expected = LibraryMutationSafetyError.registryBatchRemovalNotAuthorized(batchId: "EMPTY_B1")
        #expect(throws: expected) { _ = try sync.applyBatch(batchId: "EMPTY_B1", preview: preview, rootURL: root, settings: settings) }
        #expect(throws: expected) { _ = try sync.applyAll(preview: preview, rootURL: root, settings: settings) }
        #expect(try snapshotDirectoryTree(at: root) == before)
    }

    @Test("F004/S2: Registry rekey (old key gone, new key present) is rejected before creating the new drawer")
    func registryRekeyRejectedBeforeFirstWrite() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }
        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let sync = LibrarySyncService(libraryStore: store, libraryDiffEngine: LibraryDiffEngine())
        let settings = LibrarySettings.default

        let old = makeRegistrySample(id: "RK_OLD", batch: "RK_B1", metadata: [:])
        try store.createDrawer(for: old, batch: makeRegistryBatch(id: "RK_B1", keys: [old.id]), rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        let before = try snapshotDirectoryTree(at: root)

        let renamed = makeRegistrySample(id: "RK_NEW", batch: "RK_B1", metadata: [:])
        let preview = makePreview(batches: [makeRegistryBatch(id: "RK_B1", keys: [renamed.id])], samples: [renamed])
        let expected = LibraryMutationSafetyError.registrySampleRemovalNotAuthorized(sampleId: "RK_OLD", batchId: "RK_B1")
        #expect(throws: expected) { _ = try sync.applyBatch(batchId: "RK_B1", preview: preview, rootURL: root, settings: settings) }
        #expect(throws: expected) { _ = try sync.applyAll(preview: preview, rootURL: root, settings: settings) }
        #expect(try snapshotDirectoryTree(at: root) == before)
        #expect(!FileManager.default.fileExists(atPath: store.sampleDirectoryURL(root, batchID: "RK_B1", sampleKey: "RK_NEW").path))
    }

    @Test("F004/S1: Plan mixing a dangerous removal with legitimate update and new sample is rejected as a whole with no partial write")
    func mixedDangerousAndLegitimatePlanRejectedAtomically() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }
        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let sync = LibrarySyncService(libraryStore: store, libraryDiffEngine: LibraryDiffEngine())
        let settings = LibrarySettings.default

        let keep = makeRegistrySample(id: "MX_KEEP", batch: "MX_B1", metadata: ["Field": "v1"])
        let drop = makeRegistrySample(id: "MX_DROP", batch: "MX_B1", metadata: [:])
        try store.createDrawer(for: keep, batch: makeRegistryBatch(id: "MX_B1", keys: [keep.id, drop.id]), rootURL: root)
        try store.createDrawer(for: drop, batch: makeRegistryBatch(id: "MX_B1", keys: [keep.id, drop.id]), rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)
        let before = try snapshotDirectoryTree(at: root)

        var keepUpdated = keep
        keepUpdated.metadata["Field"] = "v2"
        keepUpdated.orderedMetadata = [LibraryMetadataItem(key: "Field", value: "v2")]
        let added = makeRegistrySample(id: "MX_ADDED", batch: "MX_B1", metadata: [:])
        let preview = makePreview(batches: [makeRegistryBatch(id: "MX_B1", keys: [keep.id, added.id])], samples: [keepUpdated, added])

        #expect(throws: LibraryMutationSafetyError.registrySampleRemovalNotAuthorized(sampleId: "MX_DROP", batchId: "MX_B1")) {
            _ = try sync.applyAll(preview: preview, rootURL: root, settings: settings)
        }
        #expect(throws: LibraryMutationSafetyError.registrySampleRemovalNotAuthorized(sampleId: "MX_DROP", batchId: "MX_B1")) {
            _ = try sync.applyBatch(batchId: "MX_B1", preview: preview, rootURL: root, settings: settings)
        }
        #expect(try snapshotDirectoryTree(at: root) == before, "Update and create must not be applied when the plan contains a removal")
    }

    @Test("F004/AC6: Legitimate-only Registry update and new sample still apply, and retry is a clean no-op")
    func legitimateOnlyRegistryUpdateStillSucceeds() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }
        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let sync = LibrarySyncService(libraryStore: store, libraryDiffEngine: LibraryDiffEngine())
        let settings = LibrarySettings.default

        let s1 = makeRegistrySample(id: "OK_S1", batch: "OK_B1", metadata: ["Field": "v1"])
        try store.createDrawer(for: s1, batch: makeRegistryBatch(id: "OK_B1", keys: [s1.id]), rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        var s1Updated = s1
        s1Updated.metadata["Field"] = "v2"
        s1Updated.orderedMetadata = [LibraryMetadataItem(key: "Field", value: "v2")]
        let s2 = makeRegistrySample(id: "OK_S2", batch: "OK_B1", metadata: [:])
        let preview = makePreview(batches: [makeRegistryBatch(id: "OK_B1", keys: [s1.id, s2.id])], samples: [s1Updated, s2])

        let result = try sync.applyAll(preview: preview, rootURL: root, settings: settings)
        #expect(result.isPartial == false)
        #expect(store.decodeSample(from: store.sampleDirectoryURL(root, batchID: "OK_B1", sampleKey: "OK_S1").appending(path: "sample.json"))?.metadata["Field"] == "v2")
        #expect(FileManager.default.fileExists(atPath: store.sampleDirectoryURL(root, batchID: "OK_B1", sampleKey: "OK_S2").path))

        // Retry: no pending changes, no throw
        let retry = try sync.applyBatch(batchId: "OK_B1", preview: preview, rootURL: root, settings: settings)
        #expect(retry == nil || retry?.isPartial == false)
    }
}
