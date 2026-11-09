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

        guard case let .success(sample, batch, _) = outcome else {
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

        let faultingFM = TestFaultingFileManager()
        let store = LibraryStore(fileManager: faultingFM)
        store.ensureRoot(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let draft = CreateNativeSampleDraft(
            batchId: "FAIL_BATCH",
            substrateIdentity: "S1"
        )

        // Inject fault: Fail directory creation when creating measurements subfolder inside sample drawer
        faultingFM.shouldFailCreateDirectory = true
        faultingFM.failCreateDirectorySubstring = "measurements"

        // Attempt creation -> must fail cleanly with .writeFailed
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
        #expect(!faultingFM.fileExists(atPath: batchDir.appending(path: "batch.json").path))

        // Clear fault
        faultingFM.shouldFailCreateDirectory = false
        faultingFM.failCreateDirectorySubstring = nil

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

        let faultingFM = TestFaultingFileManager()
        let store = LibraryStore(fileManager: faultingFM)
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

        // 3. Inject write failure during createDrawer for new sample S2
        faultingFM.shouldFailCreateDirectory = true
        faultingFM.failCreateDirectorySubstring = "measurements"

        let draft = CreateNativeSampleDraft(
            batchId: "B1",
            substrateIdentity: "S2",
            substrateDescription: "LAO"
        )

        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = outcome else {
            Issue.record("Expected failure when sample directory cannot be created")
            return
        }
        guard case .writeFailed = error else {
            Issue.record("Expected writeFailed error from createDrawer, got \(error)")
            return
        }

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
    }

    @Test("Legacy Batch normal sample creation succeeds, preserves layout without migration, and readback after restart is intact")
    func legacyBatchNormalCreationAndRestartPreservesOldData() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Establish an existing legacy batch at <root>/batches/LEGACY_01
        let legacyBatchDir = store.legacyBatchDirectoryURL(root, batchID: "LEGACY_01")
        try FileManager.default.createDirectory(at: legacyBatchDir, withIntermediateDirectories: true)
        let legacyBatch = LibraryBatch(
            id: "LEGACY_01",
            displayName: "Legacy Batch 01",
            sheetName: "Sheet1",
            metadata: ["GrowthDate": "2024-01-01"],
            numericTags: ["Temp": 750],
            numericDisplay: ["Temp": "750"],
            sampleKeys: ["LEGACY_01_S1"],
            updatedAt: Date()
        )
        try store.writeBatchChecked(legacyBatch, to: legacyBatchDir)

        // Add S1 sample in legacy batch
        let s1Dir = store.sampleDirectoryURL(root, batchID: "LEGACY_01", sampleKey: "LEGACY_01_S1")
        try FileManager.default.createDirectory(at: s1Dir, withIntermediateDirectories: true)
        let s1 = LibrarySample(
            id: "LEGACY_01_S1",
            displayName: "LEGACY_01 - S1",
            batchId: "LEGACY_01",
            substrateRaw: "STO (001)",
            substrateDisplay: "STO (001)",
            substrateTokens: ["sto"],
            substrateTags: ["S1"],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: Date(),
            sampleUID: "smp_legacy_s1",
            legacySampleKey: "LEGACY_01_S1",
            substrateIdentity: "S1",
            origin: "xlsx"
        )
        try store.writeSampleChecked(s1, to: s1Dir)

        // Add real measurement and plot files
        let measDir = s1Dir.appending(path: "measurements", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: measDir, withIntermediateDirectories: true)
        let measFile = measDir.appending(path: "iv_curve.dat")
        let rawMeasContent = "voltage,current\n0.1,0.002\n0.2,0.005\n"
        try rawMeasContent.write(to: measFile, atomically: true, encoding: .utf8)

        let plotsDir = s1Dir.appending(path: "plots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plotsDir, withIntermediateDirectories: true)
        let plotFile = plotsDir.appending(path: "iv_plot.png")
        let rawPlotBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        try Data(rawPlotBytes).write(to: plotFile)

        // Save initial index
        let initialScan = store.scanIndexFromFilesystem(rootURL: root)
        #expect(store.saveIndex(initialScan.index, to: root))

        // Preferred batch dir must NOT exist yet
        let preferredBatchDir = store.preferredBatchDirectoryURL(root, batchID: "LEGACY_01")
        #expect(!FileManager.default.fileExists(atPath: preferredBatchDir.path))

        // 2. Create native sample S2 in this legacy batch
        let draft = CreateNativeSampleDraft(
            batchId: "LEGACY_01",
            substrateIdentity: "S2",
            substrateDescription: "LAO substrate"
        )
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)

        guard case let .success(createdSample, updatedBatch, index) = outcome else {
            Issue.record("Expected successful native sample creation in legacy batch, got \(outcome)")
            return
        }

        #expect(createdSample.id == "LEGACY_01_S2")
        #expect(createdSample.batchId == "LEGACY_01")
        #expect(createdSample.substrateIdentity == "S2")
        #expect(updatedBatch.sampleKeys.sorted() == ["LEGACY_01_S1", "LEGACY_01_S2"])
        #expect(index.samples.count == 2)

        // 3. Verify no accidental migration:
        // Batch remains at legacyBatchDir! Preferred path was NOT created!
        #expect(FileManager.default.fileExists(atPath: legacyBatchDir.path))
        #expect(!FileManager.default.fileExists(atPath: preferredBatchDir.path))

        // S1 measurement and plot files are 100% untouched
        let currentMeas = try String(contentsOf: measFile, encoding: .utf8)
        #expect(currentMeas == rawMeasContent)
        let currentPlot = try Data(contentsOf: plotFile)
        #expect(Array(currentPlot) == rawPlotBytes)

        // 4. Simulate App Restart: fresh store and fresh service instance
        let restartStore = LibraryStore()
        let restartIndex = try restartStore.readOnlyCompleteIndex(rootURL: root)
        #expect(restartIndex.batches.count == 1)
        #expect(restartIndex.batches.first?.id == "LEGACY_01")
        #expect(restartIndex.batches.first?.sampleKeys.sorted() == ["LEGACY_01_S1", "LEGACY_01_S2"])
        #expect(restartIndex.samples.count == 2)

        let reloadedS1 = restartIndex.samples.first(where: { $0.id == "LEGACY_01_S1" })
        #expect(reloadedS1 != nil)
        #expect(reloadedS1?.batchId == "LEGACY_01")

        let reloadedS2 = restartIndex.samples.first(where: { $0.id == "LEGACY_01_S2" })
        #expect(reloadedS2 != nil)
        #expect(reloadedS2?.batchId == "LEGACY_01")
        #expect(reloadedS2?.substrateIdentity == "S2")

        // Measurement and plot files remain intact after restart
        #expect(FileManager.default.fileExists(atPath: measFile.path))
        #expect(FileManager.default.fileExists(atPath: plotFile.path))
        #expect((try? String(contentsOf: measFile, encoding: .utf8)) == rawMeasContent)
        #expect((try? Data(contentsOf: plotFile)) == Data(rawPlotBytes))
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
        guard case let .failure(error) = failOutcome else {
            Issue.record("Expected failure")
            return
        }
        guard case .indexSyncFailed = error else {
            Issue.record("Expected .indexSyncFailed error, got \(error)")
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
        guard case let .failure(error) = failOutcome else {
            Issue.record("Expected failure")
            return
        }
        guard case .indexSyncFailed = error else {
            Issue.record("Expected .indexSyncFailed error, got \(error)")
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

    // MARK: - Post-Review Final Safety Tests (Batch/Sample Collisions & Rollback Visibility)

    @Test("Batch ID filesystem collision with existing indexed batch is rejected without overwriting")
    func batchIdFilesystemCollisionWithExistingIndexedBatchRejected() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Create a legitimate batch "PN110-A" with sample "S1"
        let draft1 = CreateNativeSampleDraft(
            batchId: "PN110-A",
            substrateIdentity: "S1",
            substrateDescription: "STO"
        )
        guard case let .success(sample1, batch1, _) = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings) else {
            Issue.record("Initial batch creation failed")
            return
        }
        #expect(batch1.id == "PN110-A")
        #expect(sample1.id == "PN110-A_S1")

        let batchDir = store.resolvedBatchDirectoryURL(root, batchID: "PN110-A")
        let batchFile = batchDir.appending(path: "batch.json")
        let originalBatchData = try Data(contentsOf: batchFile)

        // 2. Attempt creating with colliding Batch ID "PN110/A" (or "PN110\\A")
        let draftColliding = CreateNativeSampleDraft(
            batchId: "PN110/A",
            substrateIdentity: "S2",
            substrateDescription: "LAO"
        )
        let outcome = service.createSample(draft: draftColliding, rootURL: root, libraryStore: store, settings: settings)

        // Must reject explicitly as directoryCollision
        guard case let .failure(error) = outcome else {
            Issue.record("Expected directory collision error, got \(outcome)")
            return
        }
        guard case .directoryCollision = error else {
            Issue.record("Expected .directoryCollision, got \(error)")
            return
        }

        // 3. Verify original batch.json and S1 sample are 100% intact
        let currentBatchData = try Data(contentsOf: batchFile)
        #expect(currentBatchData == originalBatchData)
        let decodedBatch = store.decodeBatch(from: batchFile)
        #expect(decodedBatch?.id == "PN110-A")
        #expect(decodedBatch?.sampleKeys == ["PN110-A_S1"])

        // S1 sample file must still exist
        let s1File = store.sampleDirectoryURL(root, batchID: "PN110-A", sampleKey: "PN110-A_S1").appending(path: "sample.json")
        #expect(FileManager.default.fileExists(atPath: s1File.path))

        // Index must still have exactly 1 batch "PN110-A" and 1 sample "PN110-A_S1"
        let reloadedIndex = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(reloadedIndex.batches.count == 1)
        #expect(reloadedIndex.batches.first?.id == "PN110-A")
        #expect(reloadedIndex.samples.count == 1)
        #expect(reloadedIndex.samples.first?.id == "PN110-A_S1")
    }

    @Test("Batch ID filesystem collision on disk with unindexed batch is rejected")
    func batchIdFilesystemCollisionOnDiskRejected() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Create an existing batch on disk whose ID is "PN110-A"
        let batchDir = store.preferredBatchDirectoryURL(root, batchID: "PN110-A")
        try FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
        let diskBatch = LibraryBatch(
            id: "PN110-A",
            displayName: "Batch PN110-A",
            sheetName: "Sheet",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [],
            updatedAt: Date()
        )
        try store.writeBatchChecked(diskBatch, to: batchDir)
        let originalBatchData = try Data(contentsOf: batchDir.appending(path: "batch.json"))

        // Save index with that batch
        let scan = store.scanIndexFromFilesystem(rootURL: root)
        #expect(store.saveIndex(scan.index, to: root))

        // Try creating with "PN110\\A" which sanitizes to "PN110-A"
        let draft = CreateNativeSampleDraft(
            batchId: "PN110\\A",
            substrateIdentity: "S1"
        )
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = outcome else {
            Issue.record("Expected directory collision error")
            return
        }
        guard case .directoryCollision = error else {
            Issue.record("Expected .directoryCollision, got \(error)")
            return
        }

        // Verify disk batch.json was not overwritten
        let currentBatchData = try Data(contentsOf: batchDir.appending(path: "batch.json"))
        #expect(currentBatchData == originalBatchData)
    }

    @Test("Sample substrate identity filesystem collision within same batch is rejected")
    func sampleSubstrateIdentityFilesystemCollisionRejected() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Create first sample with substrateIdentity "Piece-1"
        let draft1 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "Piece-1",
            substrateDescription: "STO"
        )
        guard case let .success(sample1, _, _) = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings) else {
            Issue.record("Initial sample creation failed")
            return
        }
        #expect(sample1.id == "PN110_Piece-1")

        // 2. Attempt creating another sample in PN110 with substrateIdentity "Piece/1" (which sanitizes to "Piece-1")
        let draft2 = CreateNativeSampleDraft(
            batchId: "PN110",
            substrateIdentity: "Piece/1",
            substrateDescription: "LAO"
        )
        let outcome = service.createSample(draft: draft2, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = outcome else {
            Issue.record("Expected directory collision error for colliding substrate identity")
            return
        }
        guard case .directoryCollision = error else {
            Issue.record("Expected .directoryCollision, got \(error)")
            return
        }

        // Verify sample 1 is still the only sample in PN110
        let reloadedIndex = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(reloadedIndex.samples.count == 1)
        #expect(reloadedIndex.samples.first?.substrateIdentity == "Piece-1")
    }

    @Test("Sample directory collision with on-disk sample belonging to another sample ID is rejected")
    func sampleDirectoryCollisionWithDiskSampleRejected() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Create batch PN110 directory on disk
        let batchDir = store.preferredBatchDirectoryURL(root, batchID: "PN110")
        try FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
        let batch = LibraryBatch(id: "PN110", displayName: "PN110", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["PN110_Existing"], updatedAt: Date())
        try store.writeBatchChecked(batch, to: batchDir)

        // Put an existing sample drawer at path for "PN110_Colliding", but with sample.id == "PN110_Existing"
        let sampleDir = store.sampleDirectoryURL(root, batchID: "PN110", sampleKey: "PN110_Colliding")
        try FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let existingSample = LibrarySample(
            id: "PN110_Existing", displayName: "PN110 - Existing", batchId: "PN110",
            substrateRaw: "", substrateDisplay: "Existing", substrateTokens: [], substrateTags: [],
            metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:],
            sourceSheetName: nil, sourceRowNumber: nil, updatedAt: Date(),
            sampleUID: "smp_existing", legacySampleKey: "PN110_Existing", substrateIdentity: "Existing", origin: "native"
        )
        try store.writeSampleChecked(existingSample, to: sampleDir)

        let scan = store.scanIndexFromFilesystem(rootURL: root)
        #expect(store.saveIndex(scan.index, to: root))

        // Attempt creating sample with substrateIdentity "Colliding" (maps to PN110_Colliding directory)
        let draft = CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: "Colliding")
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = outcome else {
            Issue.record("Expected directory collision error")
            return
        }
        guard case .directoryCollision = error else {
            Issue.record("Expected .directoryCollision, got \(error)")
            return
        }

        // Verify existing sample was not overwritten
        let reloadedSample = store.decodeSample(from: sampleDir.appending(path: "sample.json"))
        #expect(reloadedSample?.id == "PN110_Existing")
    }

    @Test("Rollback failure visibility: if rollback itself fails, error surfaces failure details")
    func rollbackFailureVisibilitySurfacesErrors() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let faultingFM = TestFaultingFileManager()
        let store = LibraryStore(fileManager: faultingFM)
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Pre-create index so it exists
        let initialIndex = LibraryIndex(createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil, batches: [], samples: [])
        #expect(store.saveIndex(initialIndex, to: root))

        let indexFile = store.indexFileURL(root)

        // 1. Make index file immutable so saveIndex fails
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexFile.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexFile.path)
        }

        // 2. Configure faultingFM so that when rollback tries to removeItem(at: sampleURL), it fails!
        faultingFM.shouldFailRemoveItem = true

        let draft = CreateNativeSampleDraft(batchId: "PN700", substrateIdentity: "S1")
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)

        // Reset failure flag so cleanup can succeed
        faultingFM.shouldFailRemoveItem = false
        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexFile.path)

        guard case let .failure(error) = outcome else {
            Issue.record("Expected failure when index save and rollback fail")
            return
        }

        // Must report .rollbackFailed with descriptive errors
        guard case let .rollbackFailed(primaryError, rollbackErrors) = error else {
            Issue.record("Expected .rollbackFailed, got \(error)")
            return
        }

        #expect(!primaryError.isEmpty)
        #expect(!rollbackErrors.isEmpty)
        #expect(rollbackErrors.contains(where: { $0.contains("Failed to remove created sample drawer") }))
    }

    // MARK: - Path Containment, Traversal & Symbolic Link Tests

    @Test("Path containment rejects '.' and '..' and multi-level traversal without touching external sentinels")
    func pathContainmentRejectsTraversalWithoutTouchingSentinels() throws {
        // Setup isolated sandbox containing the library AND external sentinel files outside the library
        let sandbox = FileManager.default.temporaryDirectory.appending(path: "spinlab-containment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let libraryRoot = sandbox.appending(path: "library")
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let externalSentinelFile = sandbox.appending(path: "sentinel.txt")
        let sentinelContent = "CRITICAL_EXTERNAL_DATA_\(UUID().uuidString)"
        try sentinelContent.write(to: externalSentinelFile, atomically: true, encoding: .utf8)

        let externalDir = sandbox.appending(path: "sentinel_dir")
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let externalDirFile = externalDir.appending(path: "do_not_touch.json")
        let dirFileContent = "{\"protected\": true}"
        try dirFileContent.write(to: externalDirFile, atomically: true, encoding: .utf8)

        let store = LibraryStore()
        try store.ensureRootDirectories(at: libraryRoot)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        let dangerousDrafts: [(name: String, draft: CreateNativeSampleDraft)] = [
            ("dot batch", CreateNativeSampleDraft(batchId: ".", substrateIdentity: "S1")),
            ("dot-dot batch", CreateNativeSampleDraft(batchId: "..", substrateIdentity: "S1")),
            ("multi-level traversal batch", CreateNativeSampleDraft(batchId: "../..", substrateIdentity: "S1")),
            ("traversal targeting sentinel file", CreateNativeSampleDraft(batchId: "../../sentinel.txt", substrateIdentity: "S1")),
            ("traversal targeting sentinel dir", CreateNativeSampleDraft(batchId: "../../sentinel_dir", substrateIdentity: "S1")),
            ("embedded traversal in batch", CreateNativeSampleDraft(batchId: "PN110/../..", substrateIdentity: "S1")),
            ("dot substrate", CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: ".")),
            ("dot-dot substrate", CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: "..")),
            ("multi-level substrate traversal", CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: "../..")),
            ("substrate targeting sentinel file", CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: "../../sentinel.txt")),
            ("substrate targeting sentinel dir", CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: "../../sentinel_dir")),
            ("embedded substrate traversal", CreateNativeSampleDraft(batchId: "PN110", substrateIdentity: "Piece/../.."))
        ]

        for (scenario, dangerousDraft) in dangerousDrafts {
            let outcome = service.createSample(draft: dangerousDraft, rootURL: libraryRoot, libraryStore: store, settings: settings)
            switch outcome {
            case .success:
                Issue.record("Dangerous draft '\(scenario)' should have been rejected but succeeded!")
            case let .failure(error):
                switch error {
                case .invalidInput, .pathContainmentViolation, .directoryCollision:
                    // Expected containment or validation failure
                    break
                default:
                    Issue.record("Dangerous draft '\(scenario)' failed with unexpected error: \(error)")
                }
            }

            // Verify external sentinel file was NEVER overwritten or deleted
            #expect(FileManager.default.fileExists(atPath: externalSentinelFile.path), "Sentinel file missing after '\(scenario)'")
            let currentSentinel = try? String(contentsOf: externalSentinelFile, encoding: .utf8)
            #expect(currentSentinel == sentinelContent, "Sentinel file corrupted after '\(scenario)'")

            // Verify external dir file was NEVER overwritten or deleted
            #expect(FileManager.default.fileExists(atPath: externalDirFile.path), "External dir file missing after '\(scenario)'")
            let currentDirFile = try? String(contentsOf: externalDirFile, encoding: .utf8)
            #expect(currentDirFile == dirFileContent, "External dir file corrupted after '\(scenario)'")
        }

        // Verify no stray files were created in sandbox outside of libraryRoot
        let sandboxEntries = try FileManager.default.contentsOfDirectory(atPath: sandbox.path)
        let nonLibraryEntries = Set(sandboxEntries).subtracting(["library", "sentinel.txt", "sentinel_dir"])
        #expect(nonLibraryEntries.isEmpty, "Found unexpected files outside library root: \(nonLibraryEntries)")
    }

    @Test("Symbolic link traversal or escape is detected and rejected without modifying external target")
    func symbolicLinkEscapeOrAliasingDetectedAndRejected() throws {
        let sandbox = FileManager.default.temporaryDirectory.appending(path: "spinlab-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let libraryRoot = sandbox.appending(path: "library")
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let externalTarget = sandbox.appending(path: "external_target")
        try FileManager.default.createDirectory(at: externalTarget, withIntermediateDirectories: true)
        let protectedFile = externalTarget.appending(path: "protected.txt")
        let originalContent = "IMMUTABLE_OUTSIDE_DATA"
        try originalContent.write(to: protectedFile, atomically: true, encoding: .utf8)

        let store = LibraryStore()
        try store.ensureRootDirectories(at: libraryRoot)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Case A: Legacy layout symlink directly in batches directory (<root>/batches/SYMLINK_LEGACY)
        let symlinkBatchURL = store.batchesDirectoryURL(libraryRoot).appending(path: "SYMLINK_LEGACY")
        try FileManager.default.createSymbolicLink(at: symlinkBatchURL, withDestinationURL: externalTarget)

        let draft1 = CreateNativeSampleDraft(batchId: "SYMLINK_LEGACY", substrateIdentity: "S1")
        let outcome1 = service.createSample(draft: draft1, rootURL: libraryRoot, libraryStore: store, settings: settings)

        guard case let .failure(error1) = outcome1 else {
            Issue.record("Expected legacy symlink batch creation to fail, got \(outcome1)")
            return
        }

        guard case let .pathContainmentViolation(reason1) = error1 else {
            Issue.record("Expected .pathContainmentViolation, got \(error1)")
            return
        }
        #expect(reason1.contains("symbolic link"), "Failure must specifically identify symbolic link traversal, got: \(reason1)")

        // Case B: Preferred layout symlink in prefix directory (<root>/batches/PR/PREF_SYMLINK)
        let prefSymlinkURL = store.preferredBatchDirectoryURL(libraryRoot, batchID: "PREF_SYMLINK")
        try FileManager.default.createDirectory(at: prefSymlinkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: prefSymlinkURL, withDestinationURL: externalTarget)

        let draft2 = CreateNativeSampleDraft(batchId: "PREF_SYMLINK", substrateIdentity: "S1")
        let outcome2 = service.createSample(draft: draft2, rootURL: libraryRoot, libraryStore: store, settings: settings)

        guard case let .failure(error2) = outcome2 else {
            Issue.record("Expected preferred symlink batch creation to fail, got \(outcome2)")
            return
        }

        guard case let .pathContainmentViolation(reason2) = error2 else {
            Issue.record("Expected .pathContainmentViolation, got \(error2)")
            return
        }
        #expect(reason2.contains("symbolic link"), "Failure must specifically identify symbolic link traversal, got: \(reason2)")

        // External target must remain completely untouched
        #expect(FileManager.default.fileExists(atPath: protectedFile.path))
        let currentProtected = try? String(contentsOf: protectedFile, encoding: .utf8)
        #expect(currentProtected == originalContent)

        // No sample drawer should have been created in external_target
        let externalEntries = try FileManager.default.contentsOfDirectory(atPath: externalTarget.path)
        #expect(externalEntries == ["protected.txt"])
    }

    @Test("LibraryStore batch prefix and path sanitization prevents directory escape on '.' and '..'")
    func libraryStoreBatchPrefixPreventsEscape() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()

        // Test prefix resolution
        #expect(store.batchPrefix(for: "..") == "UNKNOWN")
        #expect(store.batchPrefix(for: ".") == "UNKNOWN")
        #expect(store.batchPrefix(for: "../escape") == "UNKNOWN")
        #expect(store.batchPrefix(for: "...") == "UNKNOWN")

        // Test path sanitization
        #expect(store.sanitizedPathComponent("..") == "_dots_")
        #expect(store.sanitizedPathComponent(".") == "_dots_")
        #expect(store.sanitizedPathComponent("...") == "_dots_")
        #expect(store.sanitizedPathComponent("PN110/A") == "PN110-A")

        // Preferred batch directory must stay inside batches directory
        let dotBatchURL = store.preferredBatchDirectoryURL(root, batchID: "..")
        #expect(store.isPathContained(dotBatchURL, within: store.batchesDirectoryURL(root)))
        #expect(store.isPathContained(dotBatchURL, within: root))
    }

    // MARK: - Post-Review Consolidated Findings (Findings 1 & 2)

    @Test("Finding 1: Duplicate Batch ID across physical layouts is rejected fail-closed without modifying files")
    func duplicateBatchIdAcrossPhysicalLayoutsIsRejectedFailClosed() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Manually set up duplicate batch "DUP1" in BOTH Legacy and Preferred layouts.
        // Legacy layout: <root>/batches/DUP1
        let legacyBatchURL = store.legacyBatchDirectoryURL(root, batchID: "DUP1")
        let legacySampleURL = legacyBatchURL.appending(path: "samples/DUP1_S_LEG", directoryHint: .isDirectory)
        let legacyMeasurementsDir = legacySampleURL.appending(path: "measurements", directoryHint: .isDirectory)
        let legacyPlotsDir = legacySampleURL.appending(path: "plots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyMeasurementsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyPlotsDir, withIntermediateDirectories: true)

        let legacyBatch = LibraryBatch(id: "DUP1", displayName: "Legacy DUP1", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["DUP1_S_LEG"], updatedAt: Date())
        let legacySample = LibrarySample(id: "DUP1_S_LEG", displayName: "DUP1 Legacy Sample", batchId: "DUP1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: Date(), appliedMeasurements: [], measurementSets: [], sampleUID: "smp_legacy_001", legacySampleKey: "DUP1_S_LEG", substrateIdentity: "S_LEG", origin: "native")
        try store.writeBatchChecked(legacyBatch, to: legacyBatchURL)
        try store.writeSampleChecked(legacySample, to: legacySampleURL)

        let legacyDataFile = legacyMeasurementsDir.appending(path: "run_legacy.dat")
        let legacyPlotFile = legacyPlotsDir.appending(path: "plot_legacy.png")
        try "LEGACY_DATA_CONTENT".write(to: legacyDataFile, atomically: true, encoding: .utf8)
        try "LEGACY_PLOT_CONTENT".write(to: legacyPlotFile, atomically: true, encoding: .utf8)

        // Preferred layout: <root>/batches/DU/DUP1
        let prefBatchURL = store.preferredBatchDirectoryURL(root, batchID: "DUP1")
        let prefSampleURL = prefBatchURL.appending(path: "samples/DUP1_S_PREF", directoryHint: .isDirectory)
        let prefMeasurementsDir = prefSampleURL.appending(path: "measurements", directoryHint: .isDirectory)
        let prefPlotsDir = prefSampleURL.appending(path: "plots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: prefMeasurementsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefPlotsDir, withIntermediateDirectories: true)

        let prefBatch = LibraryBatch(id: "DUP1", displayName: "Preferred DUP1", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["DUP1_S_PREF"], updatedAt: Date())
        let prefSample = LibrarySample(id: "DUP1_S_PREF", displayName: "DUP1 Preferred Sample", batchId: "DUP1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: Date(), appliedMeasurements: [], measurementSets: [], sampleUID: "smp_pref_002", legacySampleKey: "DUP1_S_PREF", substrateIdentity: "S_PREF", origin: "native")
        try store.writeBatchChecked(prefBatch, to: prefBatchURL)
        try store.writeSampleChecked(prefSample, to: prefSampleURL)

        let prefDataFile = prefMeasurementsDir.appending(path: "run_pref.dat")
        let prefPlotFile = prefPlotsDir.appending(path: "plot_pref.png")
        try "PREF_DATA_CONTENT".write(to: prefDataFile, atomically: true, encoding: .utf8)
        try "PREF_PLOT_CONTENT".write(to: prefPlotFile, atomically: true, encoding: .utf8)

        // 2. Scan index: must detect the duplicate Batch ID and report collision issue
        let scan = store.scanIndexFromFilesystem(rootURL: root)
        #expect(!scan.issues.isEmpty)
        let collisionIssue = scan.issues.first { $0.contains("Batch ID collision") && $0.contains("DUP1") }
        #expect(collisionIssue != nil, "Expected duplicate batch collision issue, got: \(scan.issues)")

        // Neither directory must be picked as the sole truth in the scan index
        #expect(!scan.index.batches.contains(where: { $0.id == "DUP1" }))
        #expect(!scan.index.samples.contains(where: { $0.id == "DUP1_S_LEG" }))
        #expect(!scan.index.samples.contains(where: { $0.id == "DUP1_S_PREF" }))

        // readOnlyCompleteIndex must fail-closed
        #expect(throws: LibraryIndexSyncError.self) {
            try store.readOnlyCompleteIndex(rootURL: root)
        }

        // 3. Attempting to create a sample in "DUP1" must fail-closed
        let draft = CreateNativeSampleDraft(batchId: "DUP1", substrateIdentity: "NEW_SAMP")
        let outcome = service.createSample(draft: draft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .failure(error) = outcome else {
            Issue.record("Expected creation to fail due to layout collision, got: \(outcome)")
            return
        }
        switch error {
        case .unreadableLibrary, .directoryCollision:
            break
        default:
            Issue.record("Unexpected error for duplicate batch layout: \(error)")
        }

        // 4. Verify all files and directories in BOTH layouts remain 100% intact
        #expect(FileManager.default.fileExists(atPath: legacyBatchURL.appending(path: "batch.json").path))
        #expect(FileManager.default.fileExists(atPath: legacySampleURL.appending(path: "sample.json").path))
        #expect(try String(contentsOf: legacyDataFile, encoding: .utf8) == "LEGACY_DATA_CONTENT")
        #expect(try String(contentsOf: legacyPlotFile, encoding: .utf8) == "LEGACY_PLOT_CONTENT")

        #expect(FileManager.default.fileExists(atPath: prefBatchURL.appending(path: "batch.json").path))
        #expect(FileManager.default.fileExists(atPath: prefSampleURL.appending(path: "sample.json").path))
        #expect(try String(contentsOf: prefDataFile, encoding: .utf8) == "PREF_DATA_CONTENT")
        #expect(try String(contentsOf: prefPlotFile, encoding: .utf8) == "PREF_PLOT_CONTENT")
    }

    @Test("Finding 1 regression: Single Legacy and single Preferred batches allow native sample creation normally")
    func singleLegacyAndSinglePreferredBatchesWorkNormally() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // Set up single legacy batch LEG1
        let legacyBatchURL = store.legacyBatchDirectoryURL(root, batchID: "LEG1")
        let legacySampleURL = legacyBatchURL.appending(path: "samples/LEG1_OLD", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacySampleURL, withIntermediateDirectories: true)
        let legBatch = LibraryBatch(id: "LEG1", displayName: "LEG1", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["LEG1_OLD"], updatedAt: Date())
        let legSample = LibrarySample(id: "LEG1_OLD", displayName: "LEG1 Old", batchId: "LEG1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: Date(), appliedMeasurements: [], measurementSets: [], sampleUID: "smp_leg_old", legacySampleKey: "LEG1_OLD", substrateIdentity: "OLD", origin: "native")
        try store.writeBatchChecked(legBatch, to: legacyBatchURL)
        try store.writeSampleChecked(legSample, to: legacySampleURL)

        // Set up single preferred batch PREF1
        let prefBatchURL = store.preferredBatchDirectoryURL(root, batchID: "PREF1")
        let prefSampleURL = prefBatchURL.appending(path: "samples/PREF1_OLD", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: prefSampleURL, withIntermediateDirectories: true)
        let prBatch = LibraryBatch(id: "PREF1", displayName: "PREF1", sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: ["PREF1_OLD"], updatedAt: Date())
        let prSample = LibrarySample(id: "PREF1_OLD", displayName: "PREF1 Old", batchId: "PREF1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: Date(), appliedMeasurements: [], measurementSets: [], sampleUID: "smp_pref_old", legacySampleKey: "PREF1_OLD", substrateIdentity: "OLD", origin: "native")
        try store.writeBatchChecked(prBatch, to: prefBatchURL)
        try store.writeSampleChecked(prSample, to: prefSampleURL)

        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // Native sample creation in legacy batch succeeds
        let legDraft = CreateNativeSampleDraft(batchId: "LEG1", substrateIdentity: "NEW1")
        let legOutcome = service.createSample(draft: legDraft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(sampleLeg, batchLeg, _) = legOutcome else {
            Issue.record("Expected creation in single legacy batch to succeed, got \(legOutcome)")
            return
        }
        #expect(sampleLeg.id == "LEG1_NEW1")
        #expect(batchLeg.sampleKeys.contains("LEG1_OLD"))
        #expect(batchLeg.sampleKeys.contains("LEG1_NEW1"))

        // Native sample creation in preferred batch succeeds
        let prefDraft = CreateNativeSampleDraft(batchId: "PREF1", substrateIdentity: "NEW2")
        let prefOutcome = service.createSample(draft: prefDraft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(samplePref, batchPref, _) = prefOutcome else {
            Issue.record("Expected creation in single preferred batch to succeed, got \(prefOutcome)")
            return
        }
        #expect(samplePref.id == "PREF1_NEW2")
        #expect(batchPref.sampleKeys.contains("PREF1_OLD"))
        #expect(batchPref.sampleKeys.contains("PREF1_NEW2"))
    }

    @Test("Finding 2: Native-first batch retains origin == 'native' and associations through Registry sync")
    func nativeFirstBatchPreservesOriginAndAssociationsDuringRegistrySync() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default

        // 1. Create native sample S1 in batch NATIVE_BATCH
        let draft1 = CreateNativeSampleDraft(batchId: "NATIVE_BATCH", substrateIdentity: "S1", substrateDescription: "STO(001)")
        let outcome1 = service.createSample(draft: draft1, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(nativeSample1, nativeBatch1, _) = outcome1 else {
            Issue.record("Expected native sample creation to succeed")
            return
        }
        #expect(nativeBatch1.origin == "native")
        #expect(nativeSample1.origin == "native")

        // Write a measurement file in native sample's drawer
        let s1DrawerURL = store.sampleDirectoryURL(root, batchID: "NATIVE_BATCH", sampleKey: nativeSample1.id)
        let measurementFile = s1DrawerURL.appending(path: "measurements/raw_data.csv")
        try "VOLT,CURR\n1,0.5\n2,1.0".write(to: measurementFile, atomically: true, encoding: .utf8)

        // 2. Perform Registry sync with a preview where NATIVE_BATCH also has sample S2 (origin is nil in Registry)
        let regSample = LibrarySample(
            id: "NATIVE_BATCH_S2",
            displayName: "NATIVE_BATCH - S2 from Registry",
            batchId: "NATIVE_BATCH",
            substrateRaw: "Al2O3",
            substrateDisplay: "Al2O3",
            substrateTokens: ["al2o3"],
            substrateTags: ["S2"],
            metadata: ["Grower": "Alice"],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 10,
            updatedAt: Date()
        )
        let regBatch = LibraryBatch(
            id: "NATIVE_BATCH",
            displayName: "NATIVE_BATCH",
            sheetName: "Sheet1",
            metadata: ["Grower": "Alice"],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["NATIVE_BATCH_S2"],
            updatedAt: Date(),
            origin: nil // Registry has nil origin
        )
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [regBatch],
            samples: [regSample]
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)

        // Apply Registry sync
        let syncResult = try syncService.applyBatch(batchId: "NATIVE_BATCH", preview: preview, rootURL: root, settings: settings)
        #expect(syncResult != nil)
        #expect(syncResult?.failedSamples == 0)

        // 3. Verify disk batch.json preserves origin == "native" and sampleKeys has both S1 and S2
        let batchJSONURL = store.resolvedBatchDirectoryURL(root, batchID: "NATIVE_BATCH").appending(path: "batch.json")
        let diskBatch = store.decodeBatch(from: batchJSONURL)
        #expect(diskBatch != nil)
        #expect(diskBatch?.origin == "native", "Disk batch origin must remain 'native', got: \(String(describing: diskBatch?.origin))")
        #expect(diskBatch?.sampleKeys.contains(nativeSample1.id) == true)
        #expect(diskBatch?.sampleKeys.contains(regSample.id) == true)
        #expect(diskBatch?.metadata["Grower"] == "Alice", "Registry managed metadata should be updated")

        // 4. Verify rebuilt LibraryIndex preserves batch origin, sample UID, and associations
        let rebuiltIndex = try store.syncIndexFromFilesystem(rootURL: root)
        let indexedBatch = rebuiltIndex.batches.first { $0.id == "NATIVE_BATCH" }
        #expect(indexedBatch?.origin == "native")
        #expect(indexedBatch?.sampleKeys.contains(nativeSample1.id) == true)
        #expect(indexedBatch?.sampleKeys.contains(regSample.id) == true)

        let indexedNativeSample = rebuiltIndex.samples.first { $0.id == nativeSample1.id }
        #expect(indexedNativeSample != nil)
        #expect(indexedNativeSample?.sampleUID == nativeSample1.sampleUID)
        #expect(indexedNativeSample?.origin == "native")

        // 5. Verify native sample data files remain untouched
        #expect(FileManager.default.fileExists(atPath: measurementFile.path))
        let measurementContent = try String(contentsOf: measurementFile, encoding: .utf8)
        #expect(measurementContent == "VOLT,CURR\n1,0.5\n2,1.0")
    }

    @Test("Finding 2: Registry-first batch preserves associations when native sample is added and Registry is subsequently synced")
    func registryFirstBatchPreservesAssociationsWhenNativeSampleAddedAndRegistryUpdated() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)

        // 1. Establish batch REG_B with sample S1 via Registry
        let regSample1 = LibrarySample(
            id: "REG_B_S1",
            displayName: "REG_B S1",
            batchId: "REG_B",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: ["sto"],
            substrateTags: ["S1"],
            metadata: ["Temperature": "800C"],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 2,
            updatedAt: Date()
        )
        let regBatch = LibraryBatch(
            id: "REG_B",
            displayName: "REG_B",
            sheetName: "Sheet1",
            metadata: ["Temperature": "800C"],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["REG_B_S1"],
            updatedAt: Date()
        )
        try store.createDrawer(for: regSample1, batch: regBatch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // 2. Add native sample S2 to REG_B
        let nativeDraft = CreateNativeSampleDraft(batchId: "REG_B", substrateIdentity: "S2", substrateDescription: "LAO(110)")
        let outcome2 = service.createSample(draft: nativeDraft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(nativeSample2, batchAfterNative, indexAfterNative) = outcome2 else {
            Issue.record("Expected native sample creation in registry batch to succeed")
            return
        }
        #expect(nativeSample2.origin == "native")
        #expect(batchAfterNative.sampleKeys.contains("REG_B_S1"))
        #expect(batchAfterNative.sampleKeys.contains(nativeSample2.id))
        #expect(indexAfterNative.samples.count == 2)

        // Write measurement file for native sample
        let nativeDrawerURL = store.sampleDirectoryURL(root, batchID: "REG_B", sampleKey: nativeSample2.id)
        let nativeData = nativeDrawerURL.appending(path: "measurements/native_scan.dat")
        try "RAW_SCAN_BINARY_FIXTURE".write(to: nativeData, atomically: true, encoding: .utf8)

        // 3. Subsequent Registry update: changes metadata in REG_B and adds a new Registry sample S3
        let regSample3 = LibrarySample(
            id: "REG_B_S3",
            displayName: "REG_B S3",
            batchId: "REG_B",
            substrateRaw: "LSAT",
            substrateDisplay: "LSAT",
            substrateTokens: ["lsat"],
            substrateTags: ["S3"],
            metadata: ["Temperature": "850C"],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 4,
            updatedAt: Date()
        )
        var updatedRegBatch = regBatch
        updatedRegBatch.metadata["Temperature"] = "850C"
        updatedRegBatch.sampleKeys = ["REG_B_S1", "REG_B_S3"]

        let preview2Index = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [updatedRegBatch],
            samples: [regSample1, regSample3]
        )
        let preview2 = LibraryPreview(index: preview2Index, warnings: [])

        let applyResult = try syncService.applyAll(preview: preview2, rootURL: root, settings: settings)
        #expect(applyResult.failures.isEmpty)

        // 4. Verify disk batch.json contains ALL THREE samples (S1, S2 native, S3)
        let batchJSONURL = store.resolvedBatchDirectoryURL(root, batchID: "REG_B").appending(path: "batch.json")
        let diskBatch = store.decodeBatch(from: batchJSONURL)
        #expect(diskBatch != nil)
        #expect(diskBatch?.sampleKeys.contains("REG_B_S1") == true)
        #expect(diskBatch?.sampleKeys.contains(nativeSample2.id) == true, "Native sample must NOT be dropped from batch sampleKeys")
        #expect(diskBatch?.sampleKeys.contains("REG_B_S3") == true)
        #expect(diskBatch?.metadata["Temperature"] == "850C")

        // 5. Verify native sample on disk and in rebuilt index
        let reloadedIndex = try store.syncIndexFromFilesystem(rootURL: root)
        let reloadedNative = reloadedIndex.samples.first { $0.id == nativeSample2.id }
        #expect(reloadedNative != nil)
        #expect(reloadedNative?.sampleUID == nativeSample2.sampleUID)
        #expect(reloadedNative?.origin == "native")

        #expect(FileManager.default.fileExists(atPath: nativeData.path))
        let readNativeData = try String(contentsOf: nativeData, encoding: .utf8)
        #expect(readNativeData == "RAW_SCAN_BINARY_FIXTURE")
    }

    // MARK: - Post-Review Final Integrity Repair (Findings 1 & 2)

    @Test("Finding 1: Mixed Batch deletes Registry sample, removes stale key from batch.json, and preserves Native sample")
    func mixedBatchRegistrySampleDeletionRemovesStaleKeyWhilePreservingNativeSample() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default
        let diffEngine = LibraryDiffEngine()
        let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)

        // 1. Set up mixed batch "MIX1" with Registry sample REG1 and REG2
        let regSample1 = LibrarySample(
            id: "MIX1_REG1",
            displayName: "MIX1 REG1",
            batchId: "MIX1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: ["sto"],
            substrateTags: ["REG1"],
            metadata: ["Material": "SrTiO3"],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 2,
            updatedAt: Date()
        )
        let regSample2 = LibrarySample(
            id: "MIX1_REG2",
            displayName: "MIX1 REG2",
            batchId: "MIX1",
            substrateRaw: "LAO",
            substrateDisplay: "LAO",
            substrateTokens: ["lao"],
            substrateTags: ["REG2"],
            metadata: ["Material": "LaAlO3"],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 3,
            updatedAt: Date()
        )
        let initialBatch = LibraryBatch(
            id: "MIX1",
            displayName: "MIX1",
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: ["MIX1_REG1", "MIX1_REG2"],
            updatedAt: Date()
        )
        try store.createDrawer(for: regSample1, batch: initialBatch, rootURL: root)
        try store.createDrawer(for: regSample2, batch: initialBatch, rootURL: root)
        _ = try store.syncIndexFromFilesystem(rootURL: root)

        // 2. Add Native sample NAT1 to MIX1
        let nativeDraft = CreateNativeSampleDraft(
            batchId: "MIX1",
            substrateIdentity: "NAT1",
            substrateDescription: "LSAT(001)",
            displayName: "MIX1 Native #1",
            metadata: ["Target": "LCMO"]
        )
        let nativeOutcome = service.createSample(draft: nativeDraft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(nativeSample, batchAfterNative, indexAfterNative) = nativeOutcome else {
            Issue.record("Expected native sample creation in mixed batch to succeed")
            return
        }
        #expect(nativeSample.origin == "native")
        #expect(batchAfterNative.sampleKeys.contains("MIX1_REG1"))
        #expect(batchAfterNative.sampleKeys.contains("MIX1_REG2"))
        #expect(batchAfterNative.sampleKeys.contains(nativeSample.id))
        #expect(indexAfterNative.samples.count == 3)

        // Add real measurement and plot files in native sample's drawer
        let natDrawerURL = store.sampleDirectoryURL(root, batchID: "MIX1", sampleKey: nativeSample.id)
        let natDataFile = natDrawerURL.appending(path: "measurements/raw_curve.dat")
        let natPlotFile = natDrawerURL.appending(path: "plots/figure1.png")
        try "NATIVE_CURVE_BYTES".write(to: natDataFile, atomically: true, encoding: .utf8)
        try "NATIVE_PNG_BYTES".write(to: natPlotFile, atomically: true, encoding: .utf8)

        // 3. Prepare updated Registry preview where REG2 is DELETED (only REG1 remains in Registry)
        var updatedBatchInRegistry = initialBatch
        updatedBatchInRegistry.sampleKeys = ["MIX1_REG1"]
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [updatedBatchInRegistry],
            samples: [regSample1] // REG2 is omitted
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        // 4. Apply Registry sync: REG2 must be deleted
        let syncResult = try syncService.applyBatch(batchId: "MIX1", preview: preview, rootURL: root, settings: settings)
        #expect(syncResult != nil)
        #expect(syncResult?.failedSamples == 0)

        // 5. Verify physical deletion: REG2 drawer is ACTUALLY deleted from disk
        let reg2DrawerURL = store.sampleDirectoryURL(root, batchID: "MIX1", sampleKey: "MIX1_REG2")
        #expect(!FileManager.default.fileExists(atPath: reg2DrawerURL.path), "REG2 drawer must be physically deleted from disk")

        // 6. Verify disk batch.json: does NOT contain stale key "MIX1_REG2", but CONTAINS "MIX1_REG1" and native sample
        let batchJSONURL = store.resolvedBatchDirectoryURL(root, batchID: "MIX1").appending(path: "batch.json")
        let diskBatch = store.decodeBatch(from: batchJSONURL)
        #expect(diskBatch != nil)
        #expect(diskBatch?.sampleKeys.contains("MIX1_REG2") == false, "batch.json must NOT contain stale key of deleted sample")
        #expect(diskBatch?.sampleKeys.contains("MIX1_REG1") == true)
        #expect(diskBatch?.sampleKeys.contains(nativeSample.id) == true, "batch.json must keep existing native sample key")

        // 7. Verify Native Sample UID, files, and relationships are 100% intact
        let natSampleJSON = natDrawerURL.appending(path: "sample.json")
        #expect(FileManager.default.fileExists(atPath: natSampleJSON.path))
        let reloadedNatSample = store.decodeSample(from: natSampleJSON)
        #expect(reloadedNatSample?.sampleUID == nativeSample.sampleUID)
        #expect(reloadedNatSample?.origin == "native")
        #expect(reloadedNatSample?.displayName == "MIX1 Native #1")
        #expect(try String(contentsOf: natDataFile, encoding: .utf8) == "NATIVE_CURVE_BYTES")
        #expect(try String(contentsOf: natPlotFile, encoding: .utf8) == "NATIVE_PNG_BYTES")

        // 8. Rescan and restart consistency: Rebuilding LibraryIndex from disk matches batch.json exactly
        let reloadedIndex = try store.syncIndexFromFilesystem(rootURL: root)
        let indexedBatch = reloadedIndex.batches.first { $0.id == "MIX1" }
        #expect(indexedBatch != nil)
        #expect(indexedBatch?.sampleKeys == diskBatch?.sampleKeys)
        #expect(!reloadedIndex.samples.contains(where: { $0.id == "MIX1_REG2" }))
        #expect(reloadedIndex.samples.contains(where: { $0.id == nativeSample.id }))
        #expect(reloadedIndex.samples.contains(where: { $0.id == "MIX1_REG1" }))
    }

    @Test("Finding 2: Existing Native Sample is protected from overwrite across preview and selection drawer creation paths")
    func existingNativeSampleProtectedFromRegistryOverwriteAcrossCreationPaths() throws {
        let root = try makeTempLibrary()
        defer { cleanup(root) }

        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let service = NativeSampleCreationService()
        let settings = LibrarySettings.default
        let mutationService = LibraryMutationService()

        // 1. Create a native sample "PROT_S1" in batch "PROT_BATCH" with specific scientific fields
        let nativeDraft = CreateNativeSampleDraft(
            batchId: "PROT_BATCH",
            substrateIdentity: "S1",
            substrateDescription: "STO(001) Special anneal",
            displayName: "PROT_BATCH - Annealed STO",
            metadata: ["GrowthTemp": "850C", "Target": "SrRuO3"],
            numericTags: ["thickness_nm": 45.0],
            numericDisplay: ["thickness_nm": "45 nm"]
        )
        let outcome = service.createSample(draft: nativeDraft, rootURL: root, libraryStore: store, settings: settings)
        guard case let .success(createdNativeSample, _, _) = outcome else {
            Issue.record("Expected native sample creation to succeed")
            return
        }
        let nativeUID = createdNativeSample.sampleUID
        #expect(createdNativeSample.origin == "native")

        // Write measurement and plot files in native sample drawer
        let drawerURL = store.sampleDirectoryURL(root, batchID: "PROT_BATCH", sampleKey: createdNativeSample.id)
        let measurementFile = drawerURL.appending(path: "measurements/hall_effect.dat")
        let plotFile = drawerURL.appending(path: "plots/hall_curve.png")
        try "RAW_HALL_DATA_12345".write(to: measurementFile, atomically: true, encoding: .utf8)
        try "PLOT_IMAGE_PIXELS_ABCDE".write(to: plotFile, atomically: true, encoding: .utf8)

        // 2. Prepare Registry input with the SAME sample ID "PROT_BATCH_S1", but completely different scientific fields
        let collidingRegistrySample = LibrarySample(
            id: createdNativeSample.id,
            displayName: "MALICIOUS_OVERWRITE_DISPLAY_NAME",
            batchId: "PROT_BATCH",
            substrateRaw: "DIFFERENT_SUBSTRATE",
            substrateDisplay: "DIFFERENT_SUBSTRATE",
            substrateTokens: ["diff"],
            substrateTags: ["S1"],
            metadata: ["GrowthTemp": "20C", "Target": "WRONG_TARGET"],
            orderedMetadata: [],
            numericTags: ["thickness_nm": 1.0],
            numericDisplay: ["thickness_nm": "1 nm"],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 99,
            updatedAt: Date()
        )
        let registryBatch = LibraryBatch(
            id: "PROT_BATCH",
            displayName: "PROT_BATCH from Registry",
            sheetName: "Sheet1",
            metadata: ["Grower": "Bob"],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [createdNativeSample.id],
            updatedAt: Date()
        )
        let previewIndex = LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [registryBatch],
            samples: [collidingRegistrySample]
        )
        let preview = LibraryPreview(index: previewIndex, warnings: [])

        // Helper to verify native sample's scientific data on disk and in index is completely uncorrupted
        func verifyNativeSampleUncorrupted(context: String) throws {
            let sampleJSONURL = drawerURL.appending(path: "sample.json")
            let diskSample = store.decodeSample(from: sampleJSONURL)
            #expect(diskSample != nil, "\(context): disk sample.json must exist")
            #expect(diskSample?.sampleUID == nativeUID, "\(context): sampleUID must not change")
            #expect(diskSample?.origin == "native", "\(context): origin must remain native")
            #expect(diskSample?.displayName == "PROT_BATCH - Annealed STO", "\(context): displayName must not be overwritten")
            #expect(diskSample?.metadata["Target"] == "SrRuO3", "\(context): metadata must not be overwritten")
            #expect(diskSample?.numericTags["thickness_nm"] == 45.0, "\(context): numericTags must not be overwritten")
            #expect(diskSample?.substrateRaw == "STO(001) Special anneal", "\(context): substrateRaw must not be overwritten")

            // Measurement & plot files must remain untouched
            #expect(try String(contentsOf: measurementFile, encoding: .utf8) == "RAW_HALL_DATA_12345", "\(context): measurement file altered!")
            #expect(try String(contentsOf: plotFile, encoding: .utf8) == "PLOT_IMAGE_PIXELS_ABCDE", "\(context): plot file altered!")

            // LibraryIndex from disk must also reflect the uncorrupted native sample
            let reloadedIndex = try store.readOnlyCompleteIndex(rootURL: root)
            let indexedSample = reloadedIndex.samples.first { $0.id == createdNativeSample.id }
            #expect(indexedSample?.displayName == "PROT_BATCH - Annealed STO", "\(context): indexed sample displayName altered")
            #expect(indexedSample?.origin == "native")
            #expect(indexedSample?.metadata["Target"] == "SrRuO3")
        }

        // --- Path 1: createDrawersFromPreview must refuse to overwrite ---
        let outcomePreview = mutationService.createDrawersFromPreview(
            preview: preview,
            rootPath: root.path,
            libraryStore: store,
            settings: settings
        )
        guard case let .failure(previewError) = outcomePreview else {
            Issue.record("Expected createDrawersFromPreview to fail on native sample conflict, got \(outcomePreview)")
            return
        }
        #expect(previewError.contains("Cannot overwrite existing native sample"), "Error message should identify native conflict: \(previewError)")
        try verifyNativeSampleUncorrupted(context: "After createDrawersFromPreview")

        // --- Path 2: createDrawersForSelection must refuse to overwrite ---
        let outcomeSelection = mutationService.createDrawersForSelection(
            preview: preview,
            rootPath: root.path,
            batchId: "PROT_BATCH",
            sampleId: createdNativeSample.id,
            libraryStore: store,
            settings: settings
        )
        guard case let .failure(selectionError) = outcomeSelection else {
            Issue.record("Expected createDrawersForSelection to fail on native sample conflict, got \(outcomeSelection)")
            return
        }
        #expect(selectionError.contains("Cannot overwrite existing native sample"), "Error message should identify native conflict: \(selectionError)")
        try verifyNativeSampleUncorrupted(context: "After createDrawersForSelection")

        // --- Direct Path 3: LibraryStore.createDrawer throws LibraryDrawerError.nativeSampleConflict ---
        #expect(throws: LibraryDrawerError.self) {
            try store.createDrawer(for: collidingRegistrySample, batch: registryBatch, rootURL: root)
        }
        try verifyNativeSampleUncorrupted(context: "After direct createDrawer call")
    }
}

// MARK: - Test Helpers

private final class TestFaultingFileManager: FileManager {
    var shouldFailCreateDirectory: Bool = false
    var failCreateDirectorySubstring: String? = nil
    var shouldFailRemoveItem: Bool = false

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        if shouldFailCreateDirectory {
            if let sub = failCreateDirectorySubstring {
                if url.path.contains(sub) {
                    throw CocoaError(.fileWriteUnknown)
                }
            } else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    override func removeItem(at URL: URL) throws {
        if shouldFailRemoveItem {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}
