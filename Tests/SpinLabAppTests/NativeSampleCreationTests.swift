import Foundation
import Testing
@testable import SpinLabApp

@Suite("Native Sample Creation & Stable Identity")
struct NativeSampleCreationTests {
    private func makeTempLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-native-sample-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - AC1 & AC2: Creation in New Batch, Persistence, Re-read, Index Rebuild

    @Test("Create native sample in new batch, persist, read back, and verify stable identity")
    func createSampleInNewBatchAndReadBack() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S1",
            substrateDescription: "STO(001)",
            displayName: "PN110 STO #1",
            metadata: ["Target": "SRO"]
        )

        let outcome = service.createSample(
            draft: draft,
            rootURL: root,
            libraryStore: store,
            settings: settings
        )

        guard case let .success(sample, batch, syncedIndex) = outcome else {
            Issue.record("Expected successful sample creation, got \(outcome)")
            return
        }

        #expect(sample.batchId == "PN110")
        #expect(sample.substrateIdentity == "S1")
        #expect(sample.origin == "native")
        #expect(sample.sourceSheetName == nil)
        #expect(sample.sourceRowNumber == nil)
        #expect(sample.sampleUID != nil && !sample.sampleUID!.isEmpty)
        #expect(sample.persistentIdentity == sample.sampleUID)
        #expect(batch.id == "PN110")
        #expect(batch.origin == "native")
        #expect(batch.sampleKeys.contains(sample.id))

        // Verify on-disk file contents
        let sampleDir = store.sampleDirectoryURL(root, batchID: "PN110", sampleKey: sample.id)
        let sampleFile = sampleDir.appending(path: "sample.json")
        #expect(FileManager.default.fileExists(atPath: sampleFile.path))

        let decodedSample = store.decodeSample(from: sampleFile)
        #expect(decodedSample != nil)
        #expect(decodedSample?.id == sample.id)
        #expect(decodedSample?.sampleUID == sample.sampleUID)
        #expect(decodedSample?.substrateIdentity == "S1")
        #expect(decodedSample?.origin == "native")
        #expect(decodedSample?.persistentIdentity == sample.sampleUID)

        // Verify index rebuild from filesystem
        let rebuiltIndex = try store.syncIndexFromFilesystem(rootURL: root)
        let indexedSample = rebuiltIndex.samples.first(where: { $0.id == sample.id })
        #expect(indexedSample != nil)
        #expect(indexedSample?.sampleUID == sample.sampleUID)
        #expect(indexedSample?.batchId == "PN110")
        #expect(indexedSample?.displayName == "PN110 STO #1")
        #expect(indexedSample?.persistentIdentity == sample.sampleUID)
    }

    // MARK: - AC2: Existing Batch reuse

    @Test("Create multiple native samples in the same batch")
    func createMultipleSamplesInSameBatch() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft1 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "Piece-A",
            substrateDescription: "STO(001)"
        )
        let draft2 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "Piece-B",
            substrateDescription: "LAO(001)"
        )

        let outcome1 = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample1, _, _) = outcome1 else {
            Issue.record("First creation failed")
            return
        }

        let outcome2 = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample2, batch2, index2) = outcome2 else {
            Issue.record("Second creation failed")
            return
        }

        #expect(sample1.id != sample2.id)
        #expect(sample1.sampleUID != sample2.sampleUID)
        #expect(batch2.sampleKeys.contains(sample1.id))
        #expect(batch2.sampleKeys.contains(sample2.id))
        #expect(index2.samples.count == 2)
    }

    // MARK: - AC4: Duplicate Established Identity Rejection & Ambiguity

    @Test("Duplicate sample identity in same batch is identified and rejected")
    func duplicateSampleIdentityRejected() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft1 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S1",
            substrateDescription: "STO(001)",
            displayName: "First Sample"
        )
        let outcome1 = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings)
        guard case .success = outcome1 else {
            Issue.record("First creation failed")
            return
        }

        // Attempt creation with exact same substrate identity in same batch, but different display name
        let duplicateDraft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S1",
            substrateDescription: "Different description",
            displayName: "Attempted Duplicate"
        )
        let duplicateOutcome = service.createSample(draft: duplicateDraft, rootURL: root, libraryStore: store, settings: settings)

        guard case let .failure(error) = duplicateOutcome else {
            Issue.record("Expected duplicate error, got success")
            return
        }

        guard case let .duplicateSample(sampleId, substrateIdentity, batchId) = error else {
            Issue.record("Expected .duplicateSample error, got \(error)")
            return
        }
        #expect(batchId == "PN110")
        #expect(substrateIdentity == "S1")
        #expect(!sampleId.isEmpty)

        // Verify only 1 sample exists on disk
        let rebuiltIndex = try store.syncIndexFromFilesystem(rootURL: root)
        #expect(rebuiltIndex.samples.count == 1)
    }

    @Test("Different substrate identities with the same display name are not merged")
    func differentSubstratesWithSameDisplayNameNotMerged() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft1 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S1",
            displayName: "Shared Display Name"
        )
        let draft2 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S2",
            displayName: "Shared Display Name"
        )

        let outcome1 = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings)
        let outcome2 = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)

        guard case let .success(sample1, _, _) = outcome1,
              case let .success(sample2, _, index) = outcome2 else {
            Issue.record("Expected both samples to be created successfully")
            return
        }

        #expect(sample1.id != sample2.id)
        #expect(sample1.sampleUID != sample2.sampleUID)
        #expect(sample1.displayName == sample2.displayName)
        #expect(index.samples.count == 2)
    }

    // MARK: - AC2: Unknown Material Not Guessed

    @Test("Unknown substrate material properties are not guessed")
    func unknownMaterialNotGuessed() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "Piece1",
            substrateDescription: "CustomSubstrateUnknownChemical"
        )

        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample, _, _) = outcome else {
            Issue.record("Expected successful creation")
            return
        }

        #expect(sample.substrateRaw == "CustomSubstrateUnknownChemical")
        #expect(sample.substrateDisplay == "CustomSubstrateUnknownChemical")
        #expect(sample.displayName == "PN110 - CustomSubstrateUnknownChemical (Piece1)")
    }

    // MARK: - AC5: Fail-Closed & Rollback

    @Test("Fail-closed on missing library root")
    func failClosedOnMissingRoot() {
        let store = LibraryStore()
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft = CreateNativeSampleDraft(batchId: "B1", substrateIdentity: "S1")
        let outcome = service.createSample(draft: draft, rootURL: nil, libraryStore: store, settings: settings)

        guard case let .failure(error) = outcome else {
            Issue.record("Expected failure")
            return
        }
        #expect(error == .missingLibraryRoot)
    }

    @Test("Fail-closed on corrupt unreadable library")
    func failClosedOnCorruptLibrary() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        // Corrupt the library index
        let indexFile = store.indexFileURL(root)
        try "CORRUPT NOT JSON".write(to: indexFile, atomically: true, encoding: .utf8)

        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default
        let draft = CreateNativeSampleDraft(batchId: "B1", substrateIdentity: "S1")
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)

        guard case let .failure(error) = outcome else {
            Issue.record("Expected failure on unreadable library")
            return
        }
        guard case .unreadableLibrary = error else {
            Issue.record("Expected unreadableLibrary error, got \(error)")
            return
        }
    }

    // MARK: - AC3: Registry Sync Protection

    @Test("Native sample is protected from Registry sync deletion and overwrite")
    func registrySyncProtectsNativeSample() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Create a native sample
        let nativeDraft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "Native1",
            substrateDescription: "STO(001)",
            displayName: "Native Sample 1"
        )
        guard case let .success(nativeSample, _, _) = service.createSample(draft: nativeDraft, rootURL: root, libraryStore: store, settings: settings) else {
            Issue.record("Native creation failed")
            return
        }

        // 2. Simulate an incoming Registry index that only contains a registry sample (and does NOT contain nativeSample)
        let registrySample = LibrarySample(
            id: "REG_SAMPLE",
            displayName: "PN104 - STO(001)",
            batchId: "PN104",
            substrateRaw: "STO(001)",
            substrateDisplay: "STO(001)",
            substrateTokens: ["sto", "001"],
            substrateTags: ["sto"],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 2,
            updatedAt: Date()
        )
        let registryBatch = LibraryBatch(
            id: "PN104",
            displayName: "PN104",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["REG_SAMPLE"],
            updatedAt: Date()
        )
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [registryBatch],
            samples: [registrySample]
        )

        // 3. Compute diff between on-disk library and Registry preview
        let currentOnDisk = try store.syncIndexFromFilesystem(rootURL: root)
        let diffEngine = LibraryDiffEngine()
        let diff = diffEngine.diff(current: currentOnDisk, updated: previewIndex)

        // Native sample MUST NOT be in removedSamples!
        #expect(!diff.removedSamples.contains(where: { $0.id == nativeSample.id }))
        #expect(!diff.removedBatches.contains(where: { $0.id == "PN110" }))
        #expect(diff.newSamples.contains(where: { $0.id == "REG_SAMPLE" }))

        // 4. Test protection against unauthorized overwrite if registry preview tries to reuse native key
        let conflictingRegistrySample = LibrarySample(
            id: nativeSample.id,
            displayName: "Hijacked Registry Sample",
            batchId: "PN110",
            substrateRaw: "LAO",
            substrateDisplay: "LAO",
            substrateTokens: ["lao"],
            substrateTags: ["lao"],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 10,
            updatedAt: Date()
        )
        let conflictingPreviewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [registryBatch],
            samples: [conflictingRegistrySample]
        )
        let conflictDiff = diffEngine.diff(current: currentOnDisk, updated: conflictingPreviewIndex)

        #expect(conflictDiff.changedSamples.isEmpty)
        #expect(conflictDiff.warnings.contains(where: { $0.affectedSampleKey == nativeSample.id }))
    }

    // MARK: - AC6: Local Native Edit without XLSX

    @Test("Editing native sample saves locally without requiring XLSX registry")
    func nativeSampleEditSavesLocallyWithoutXLSX() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "S1",
            displayName: "Initial Name"
        )
        guard case let .success(_, _, syncedIndex) = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings),
              let sample = syncedIndex.samples.first(where: { $0.batchId == "PN110" }) else {
            Issue.record("Creation failed")
            return
        }

        let editService = LibrarySampleEditService()
        var editDraft = editService.makeDraft(from: sample)
        editDraft.substrateTagsText = "annealed, high-purity"

        let useCase = SaveLibrarySampleEditsUseCase()
        let result = useCase.execute(
            input: SaveLibrarySampleEditsUseCase.Input(
                rootPath: root.path,
                draft: editDraft,
                baseSample: sample
            ),
            snapshotIndexFromFilesystem: { store.snapshotIndexFromFilesystem(rootURL: $0) },
            applyDraft: { try editService.apply(draft: $0, to: $1) },
            updateSample: { try store.updateSample($0, rootURL: $1, changeSource: "manual_edit") },
            resolveRegistrySourceURL: { nil }, // No XLSX registry file exists!
            syncRegistrySource: { _, _, _ in
                Issue.record("syncRegistrySource should NOT be called for native samples")
                throw AppError.sync("Should not be called")
            }
        )

        guard case let .success(output) = result else {
            Issue.record("Expected successful edit save, got \(result)")
            return
        }

        #expect(output.clearDraft == true)
        #expect(output.syncIssue == nil)
        #expect(output.nonFatalError == nil)

        // Verify edited sample on disk
        let sampleFile = store.sampleDirectoryURL(root, batchID: "PN110", sampleKey: sample.id).appending(path: "sample.json")
        let updatedOnDisk = store.decodeSample(from: sampleFile)
        #expect(updatedOnDisk?.substrateTags.contains("annealed") == true)
        #expect(updatedOnDisk?.sampleUID == sample.sampleUID)
        #expect(updatedOnDisk?.origin == "native")
    }

    // MARK: - AC3: Legacy Sample Fixture with Measurement Artifacts Coexists Intact

    @Test("Legacy sample with measurement and plot artifacts coexists with native samples")
    func legacySampleWithArtifactsCoexistsIntact() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        // 1. Set up a legacy sample drawer with measurement and results index
        let legacySample = LibrarySample(
            id: "LEGACY_01",
            displayName: "Legacy Sample 01",
            batchId: "LEGACY_BATCH",
            substrateRaw: "STO(110)",
            substrateDisplay: "STO(110)",
            substrateTokens: ["sto", "110"],
            substrateTags: ["sto"],
            metadata: ["GrowthDate": "2025-01-01"],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Historical",
            sourceRowNumber: 5,
            updatedAt: Date()
        )
        let legacyBatch = LibraryBatch(
            id: "LEGACY_BATCH",
            displayName: "LEGACY_BATCH",
            sheetName: "Historical",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["LEGACY_01"],
            updatedAt: Date()
        )
        try store.createDrawer(for: legacySample, batch: legacyBatch, rootURL: root)

        // Add dummy measurement and results index inside drawer
        let drawerURL = store.sampleDirectoryURL(root, batchID: "LEGACY_BATCH", sampleKey: "LEGACY_01")
        let measurementsURL = drawerURL.appending(path: "measurements")
        let dummyDataURL = measurementsURL.appending(path: "data_sample.dat")
        try "DATA 1 2 3".write(to: dummyDataURL, atomically: true, encoding: .utf8)

        // 2. Now create a native sample in the same library
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default
        let nativeDraft = CreateNativeSampleDraft(
            batchId: "NEW_BATCH",
            substrateIdentity: "P1",
            substrateDescription: "LAO(001)"
        )
        let outcome = service.createSample(draft: nativeDraft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(nativeSample, _, index) = outcome else {
            Issue.record("Native creation failed")
            return
        }

        // Verify both coexist in library
        #expect(index.samples.count == 2)
        #expect(index.samples.contains(where: { $0.id == "LEGACY_01" }))
        #expect(index.samples.contains(where: { $0.id == nativeSample.id }))

        // Legacy measurement file still exists untouched
        #expect(FileManager.default.fileExists(atPath: dummyDataURL.path))

        // Legacy sample persistentIdentity is deterministic mapping
        let reloadedLegacy = index.samples.first(where: { $0.id == "LEGACY_01" })
        #expect(reloadedLegacy?.persistentIdentity == "legacy:LEGACY_BATCH:LEGACY_01")
    }

    // MARK: - AC5: Fault Injection Rollback & Retry Recovery

    @Test("Write failure injection rolls back batch and sample, and retry succeeds")
    func writeFailureInjectionRollbackAndRetry() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft = CreateNativeSampleDraft(
            batchId: "FAIL_BATCH",
            substrateIdentity: "S1"
        )

        // Inject fault: Create a regular file where the sample directory would be, blocking folder creation
        let sampleURL = store.sampleDirectoryURL(root, batchID: "FAIL_BATCH", sampleKey: "FAIL_BATCH_S1")
        let parentDir = sampleURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try "BLOCKING FILE".write(to: sampleURL, atomically: true, encoding: .utf8)

        // Attempt creation -> must fail cleanly
        let failedOutcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = failedOutcome else {
            Issue.record("Expected write failure")
            return
        }
        guard case .writeFailed = error else {
            Issue.record("Expected writeFailed error, got \(error)")
            return
        }

        // Verify batch directory was rolled back (no orphan batch left on disk)
        let batchDir = store.preferredBatchDirectoryURL(root, batchID: "FAIL_BATCH")
        #expect(!FileManager.default.fileExists(atPath: batchDir.appending(path: "batch.json").path))

        // Clear fault
        try FileManager.default.removeItem(at: sampleURL)

        // Retry creation -> must succeed!
        let retryOutcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample, batch, index) = retryOutcome else {
            Issue.record("Expected retry to succeed after clearing fault")
            return
        }

        #expect(sample.id == "FAIL_BATCH_S1")
        #expect(batch.id == "FAIL_BATCH")
        #expect(index.samples.contains(where: { $0.id == sample.id }))
    }

    @Test("Case-insensitive batch matching adopts canonical casing without creating duplicate batch folders")
    func caseInsensitiveBatchMatchingAdoptsCanonicalCasing() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Create initial sample in batch "PN110"
        let draft1 = CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: "S1")
        _ = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings)

        // 2. Create second sample with lowercase batch "pn110"
        let draft2 = CreateNativeSampleDraft(batchId: "pn110", substrateIdentity: "S2")
        let outcome2 = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)

        guard case let .success(sample2, batch2, index) = outcome2 else {
            Issue.record("Expected creation to succeed")
            return
        }

        #expect(sample2.batchId == "PN110")
        #expect(sample2.id == "PN110_S2")
        #expect(batch2.id == "PN110")
        #expect(batch2.sampleKeys.contains("PN110_S1"))
        #expect(batch2.sampleKeys.contains("PN110_S2"))
        #expect(index.batches.count == 1)
    }

    @Test("Legacy sample lacking substrateIdentity triggers duplicate detection on substrateDisplay or id match")
    func legacySampleLackingSubstrateIdentityTriggersDuplicate() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)

        // Set up legacy sample
        let legacySample = LibrarySample(
            id: "PIECE_A",
            displayName: "B1 - STO(110)",
            batchId: "B1",
            substrateRaw: "STO(110)",
            substrateDisplay: "STO(110)",
            substrateTokens: ["sto", "110"],
            substrateTags: ["sto"],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Historical",
            sourceRowNumber: 1,
            updatedAt: Date()
        )
        let legacyBatch = LibraryBatch(
            id: "B1",
            displayName: "B1",
            sheetName: "Historical",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["PIECE_A"],
            updatedAt: Date()
        )
        try store.createDrawer(for: legacySample, batch: legacyBatch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Attempt 1: matching legacy sample id
        let draft1 = CreateNativeSampleDraft(batchId: "B1", substrateIdentity: "PIECE_A")
        let outcome1 = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error1) = outcome1 else {
            Issue.record("Expected duplicate error on matching ID")
            return
        }
        guard case .duplicateSample = error1 else {
            Issue.record("Expected duplicateSample error, got \(error1)")
            return
        }

        // Attempt 2: matching legacy substrateDisplay
        let draft2 = CreateNativeSampleDraft(batchId: "B1", substrateIdentity: "STO(110)")
        let outcome2 = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error2) = outcome2 else {
            Issue.record("Expected duplicate error on matching substrateDisplay")
            return
        }
        guard case .duplicateSample = error2 else {
            Issue.record("Expected duplicateSample error, got \(error2)")
            return
        }
    }

    @Test("Shared batch preserves native sample association during Registry sync apply")
    func sharedBatchPreservesNativeSampleDuringRegistrySync() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Existing Registry sample in PN104
        let regSample = LibrarySample(
            id: "PN104_REG1",
            displayName: "PN104 - Reg 1",
            batchId: "PN104",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: ["sto"],
            substrateTags: ["sto"],
            metadata: ["GrowthDate": "2025-01-01"],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 2,
            updatedAt: Date()
        )
        let regBatch = LibraryBatch(
            id: "PN104",
            displayName: "PN104",
            sheetName: "Sheet1",
            metadata: ["GrowthDate": "2025-01-01"],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["PN104_REG1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: regSample, batch: regBatch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // 2. Add native sample to the same batch "PN104"
        let nativeDraft = CreateNativeSampleDraft(
            batchId: "PN104",
            substrateIdentity: "Native1",
            substrateDescription: "LAO(001)"
        )
        guard case let .success(nativeSample, _, indexAfterNative) = service.createSample(draft: nativeDraft, rootURL: root, libraryStore: store, settings: settings) else {
            Issue.record("Native creation failed")
            return
        }
        #expect(indexAfterNative.samples.count == 2)

        // 3. Prepare an updated Registry preview that changes metadata for PN104, but only knows about PN104_REG1
        var updatedRegBatch = regBatch
        updatedRegBatch.displayName = "PN104 Renamed in Registry"
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [updatedRegBatch],
            samples: [regSample]
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        // 4. Run DiffEngine: batch change MUST preserve native sample key in batchChange
        let diffEngine = LibraryDiffEngine()
        let diff = diffEngine.diff(current: indexAfterNative, updated: previewIndex)
        let batchChange = diff.changedBatches.first { $0.batch.id == "PN104" }
        #expect(batchChange != nil)
        #expect(batchChange?.batch.sampleKeys.contains(nativeSample.id) == true)

        // 5. Apply Registry sync: batch.sampleKeys on disk must still contain native sample!
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
        _ = try syncService.applyAll(preview: preview, rootURL: root, settings: settings)

        let reloadedBatch = store.decodeBatch(from: store.preferredBatchDirectoryURL(root, batchID: "PN104").appending(path: "batch.json"))
        #expect(reloadedBatch?.sampleKeys.contains(nativeSample.id) == true)
        #expect(reloadedBatch?.sampleKeys.contains("PN104_REG1") == true)
        #expect(reloadedBatch?.displayName == "PN104 Renamed in Registry")

        // Native sample file must still be present and intact
        let nativeFile = store.sampleDirectoryURL(root, batchID: "PN104", sampleKey: nativeSample.id).appending(path: "sample.json")
        #expect(FileManager.default.fileExists(atPath: nativeFile.path))
    }

    // MARK: - Post-Review Regression Tests (Issues 1 & 2)

    @Test("Legacy Batch containing Sample, measurement, plot: failure in new Sample preserves all files and relationships")
    func legacyBatchPreservedOnNewSampleFailure() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Manually establish a legacy layout batch at <root>/batches/B1 (NOT <root>/batches/B/B1)
        let legacyBatchDir = store.legacyBatchDirectoryURL(root, batchID: "B1")
        try FileManager.default.createDirectory(at: legacyBatchDir, withIntermediateDirectories: true)
        let legacyBatch = LibraryBatch(
            id: "B1",
            displayName: "Batch B1",
            sheetName: "Sheet1",
            metadata: ["Original": "Value"],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["B1_S1"],
            updatedAt: Date()
        )
        try store.writeBatchChecked(legacyBatch, to: legacyBatchDir)

        // 2. Add an existing sample B1_S1 with measurements and plots in legacy batch
        let legacySampleDir = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "B1_S1")
        try FileManager.default.createDirectory(at: legacySampleDir, withIntermediateDirectories: true)
        let legacySample = LibrarySample(
            id: "B1_S1",
            displayName: "B1 Sample 1",
            batchId: "B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: ["sto"],
            substrateTags: ["S1"],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: Date(),
            sampleUID: "smp_legacy_1",
            legacySampleKey: "B1_S1",
            substrateIdentity: "S1"
        )
        try store.writeSampleChecked(legacySample, to: legacySampleDir)

        // Add real measurement and plot files
        let measDir = legacySampleDir.appending(path: "measurements", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: measDir, withIntermediateDirectories: true)
        let measFile = measDir.appending(path: "raw_sweep.dat")
        try "field,current,voltage\n1,2,3\n".write(to: measFile, atomically: true, encoding: .utf8)

        let plotsDir = legacySampleDir.appending(path: "plots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plotsDir, withIntermediateDirectories: true)
        let plotFile = plotsDir.appending(path: "curve.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: plotFile)

        // Save initial index
        let initialScan = store.scanIndexFromFilesystem(rootURL: root)
        #expect(store.saveIndex(initialScan.index, to: root))
        #expect(FileManager.default.fileExists(atPath: legacyBatchDir.path))
        #expect(!FileManager.default.fileExists(atPath: store.preferredBatchDirectoryURL(root, batchID: "B1").path))

        // 3. Inject write failure for new sample S2 by creating a blocking file where sample directory should go
        let s2Dir = store.sampleDirectoryURL(root, batchID: "B1", sampleKey: "B1_S2")
        let s2Parent = s2Dir.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: s2Parent, withIntermediateDirectories: true)
        try "blocker".write(to: s2Dir, atomically: true, encoding: .utf8)

        let draft = CreateNativeSampleDraft(
            batchId: "B1",
            substrateIdentity: "S2",
            substrateDescription: "LAO"
        )

        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case .failure = outcome else {
            Issue.record("Expected failure when sample directory cannot be created")
            return
        }

        // Clean up blocker
        try? FileManager.default.removeItem(at: s2Dir)

        // 4. VERIFY:
        // - Legacy batch directory is still at legacy path, NOT migrated, NOT deleted
        #expect(FileManager.default.fileExists(atPath: legacyBatchDir.path))
        #expect(!FileManager.default.fileExists(atPath: store.preferredBatchDirectoryURL(root, batchID: "B1").path))
        // - S1 and its measurements and plots are 100% intact
        #expect(FileManager.default.fileExists(atPath: measFile.path))
        #expect(FileManager.default.fileExists(atPath: plotFile.path))
        let readMeas = try String(contentsOf: measFile, encoding: .utf8)
        #expect(readMeas.contains("field,current,voltage"))
        // - Batch JSON was restored and only contains S1
        let reloadedBatch = store.decodeBatch(from: legacyBatchDir.appending(path: "batch.json"))
        #expect(reloadedBatch?.sampleKeys == ["B1_S1"])
        // - Index does not contain S2
        let currentIndex = store.loadIndex(from: root)
        #expect(currentIndex?.samples.contains(where: { $0.id == "B1_S2" }) == false)
        #expect(currentIndex?.samples.contains(where: { $0.id == "B1_S1" }) == true)
    }

    @Test("Index save failure: new Sample is not marked as formally existing, rollback restores disk and index")
    func indexSaveFailureRollback() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Create initial batch PN100 with S1
        let draft1 = CreateNativeSampleDraft(
            batchId: "PN100",
            substrateIdentity: "S1",
            substrateDescription: "STO"
        )
        guard case .success = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings) else {
            Issue.record("Initial sample creation failed")
            return
        }

        let indexFile = store.indexFileURL(root)
        let preIndexData = try Data(contentsOf: indexFile)

        // Inject failure on index save:
        // Making index file immutable causes atomic write to fail
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexFile.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexFile.path)
        }

        // Try creating S2
        let draft2 = CreateNativeSampleDraft(
            batchId: "PN100",
            substrateIdentity: "S2",
            substrateDescription: "LAO"
        )
        let outcome = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = outcome else {
            Issue.record("Expected failure when index save fails")
            return
        }
        guard case .indexSyncFailed = error else {
            Issue.record("Expected .indexSyncFailed, got \(error)")
            return
        }

        // Unlock index file to read
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexFile.path)

        // VERIFY:
        // - S2 directory does NOT exist on disk
        let s2Dir = store.sampleDirectoryURL(root, batchID: "PN100", sampleKey: "PN100_S2")
        #expect(!FileManager.default.fileExists(atPath: s2Dir.path))
        // - Batch JSON on disk has only S1
        let batchFile = store.preferredBatchDirectoryURL(root, batchID: "PN100").appending(path: "batch.json")
        let reloadedBatch = store.decodeBatch(from: batchFile)
        #expect(reloadedBatch?.sampleKeys == ["PN100_S1"])
        // - Index file on disk matches preIndexData (no S2)
        let currentIndexData = try Data(contentsOf: indexFile)
        #expect(currentIndexData == preIndexData)
        let reloadedIndex = store.loadIndex(from: root)
        #expect(reloadedIndex?.samples.contains(where: { $0.id == "PN100_S2" }) == false)
    }

    @Test("Existing Batch creation failure and retry: failure cleans up, retry succeeds idempotently")
    func existingBatchFailureAndRetry() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Create initial batch PN100 with S1
        let draft1 = CreateNativeSampleDraft(
            batchId: "PN100",
            substrateIdentity: "S1",
            substrateDescription: "STO"
        )
        guard case .success = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings) else {
            Issue.record("Initial sample creation failed")
            return
        }

        let indexFile = store.indexFileURL(root)

        // Inject failure on index write
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexFile.path)
        let draft2 = CreateNativeSampleDraft(
            batchId: "PN100",
            substrateIdentity: "S2",
            substrateDescription: "LAO"
        )
        let failOutcome = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)
        guard case .failure = failOutcome else {
            Issue.record("Expected failure")
            return
        }

        // Lift failure condition
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexFile.path)

        // Retry creating S2
        let retryOutcome = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample2, batch2, index2) = retryOutcome else {
            Issue.record("Retry must succeed")
            return
        }

        #expect(sample2.id == "PN100_S2")
        #expect(batch2.sampleKeys.sorted() == ["PN100_S1", "PN100_S2"])
        #expect(index2.samples.count == 2)
        #expect(index2.samples.contains(where: { $0.id == "PN100_S1" }))
        #expect(index2.samples.contains(where: { $0.id == "PN100_S2" }))
    }

    @Test("New Batch creation failure and retry: failure removes created batch directory, retry succeeds")
    func newBatchFailureAndRetry() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let indexFile = store.indexFileURL(root)
        let initialIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [],
            samples: []
        )
        #expect(store.saveIndex(initialIndex, to: root))

        // Inject failure on index write
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexFile.path)

        let draft = CreateNativeSampleDraft(
            batchId: "PN300",
            substrateIdentity: "S1",
            substrateDescription: "STO"
        )
        let failOutcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case .failure = failOutcome else {
            Issue.record("Expected failure")
            return
        }

        // VERIFY: Newly created batch directory was removed!
        let batchDir = store.preferredBatchDirectoryURL(root, batchID: "PN300")
        #expect(!FileManager.default.fileExists(atPath: batchDir.path))

        // Lift failure condition
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexFile.path)

        // Retry creating PN300 S1
        let retryOutcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sample, batch, index) = retryOutcome else {
            Issue.record("Retry must succeed")
            return
        }

        #expect(sample.id == "PN300_S1")
        #expect(batch.id == "PN300")
        #expect(FileManager.default.fileExists(atPath: batchDir.path))
        #expect(index.samples.contains(where: { $0.id == "PN300_S1" }))
        #expect(index.batches.contains(where: { $0.id == "PN300" }))
    }

    @Test("Rework Verification: Normal creation, restart readback, and Registry sync protection remain intact")
    func reworkVerificationNormalCreationRestartAndSyncProtection() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Normal creation
        let draft = CreateNativeSampleDraft(
            batchId: "PN500",
            substrateIdentity: "S1",
            substrateDescription: "STO(001)",
            displayName: "PN500 Primary"
        )
        guard case let .success(sample, batch, syncedIndex) = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings) else {
            Issue.record("Normal creation failed")
            return
        }
        #expect(sample.sampleUID != nil)
        #expect(batch.id == "PN500")
        #expect(syncedIndex.samples.contains(where: { $0.id == sample.id }))

        // 2. Restart readback from fresh store / fresh scan
        let freshStore = LibraryStore()
        let reloadedIndex = try freshStore.readOnlyCompleteIndex(rootURL: root)
        let reloadedSample = reloadedIndex.samples.first(where: { $0.id == sample.id })
        #expect(reloadedSample != nil)
        #expect(reloadedSample?.sampleUID == sample.sampleUID)
        #expect(reloadedSample?.persistentIdentity == sample.sampleUID)
        #expect(reloadedSample?.batchId == "PN500")

        // 3. Registry sync protection: preview that does not contain PN500
        let otherBatch = LibraryBatch(id: "PN999", displayName: "PN999", sheetName: "Sheet", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["PN999_A"], updatedAt: Date())
        let otherSample = LibrarySample(id: "PN999_A", displayName: "A", batchId: "PN999", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet", sourceRowNumber: 1, updatedAt: Date())
        let previewIndex = LibraryIndex(createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil, batches: [otherBatch], samples: [otherSample])

        let diff = LibraryDiffEngine().diff(current: reloadedIndex, updated: previewIndex)
        #expect(!diff.removedBatches.contains(where: { $0.id == "PN500" }))
        #expect(!diff.removedSamples.contains(where: { $0.id == sample.id }))
    }
}
