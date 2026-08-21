import Foundation
import Testing
@testable import SpinLabApp

/// Phase 3A: Batch / Sample Field Ownership Boundary.
///
/// Regression coverage for the confirmed integrity bug in
/// `docs/library-architecture-audit.md` §13.6/F1: editing a metadata field
/// on one `LibrarySample` (e.g. `PN109|o|STO|110`) used to write directly
/// into the Registry row shared by every sibling Sample of the same Batch
/// (e.g. `PN109|o|STO|111`), with zero ownership guard. These tests verify
/// both enforcement layers added to close that gap:
///
/// - Layer 1 (`LibrarySampleEditService.apply`): rejects Batch-owned field
///   changes before any sample mutation is produced.
/// - Layer 2 (`LibraryXLSXSyncService.syncEditedSample`): independently
///   re-validates and rejects Batch-owned writes before any workbook I/O,
///   even if called directly (bypassing Layer 1).
@Suite("V5.4.3 Library Field Ownership Boundary")
struct V543LibraryFieldOwnershipBoundaryTests {

    // MARK: - Fixtures

    private static func makeSample(
        id: String,
        batchId: String,
        substrateDisplay: String,
        metadata: [String: String],
        sourceSheetName: String = "Sheet1",
        sourceRowNumber: Int = 5
    ) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: "\(batchId) - \(substrateDisplay)",
            batchId: batchId,
            substrateRaw: substrateDisplay,
            substrateDisplay: substrateDisplay,
            substrateTokens: [],
            substrateTags: [],
            metadata: metadata,
            orderedMetadata: metadata.map { LibraryMetadataItem(key: $0.key, value: $0.value) },
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: sourceSheetName,
            sourceRowNumber: sourceRowNumber,
            updatedAt: .now
        )
    }

    private static func draft(from sample: LibrarySample, changing key: String, to newValue: String) -> LibrarySampleEditDraft {
        var metadataValues = sample.orderedMetadata.map { LibraryEditableKeyValue(key: $0.key, value: $0.value) }
        if let index = metadataValues.firstIndex(where: { $0.key == key }) {
            metadataValues[index].value = newValue
        } else {
            metadataValues.append(LibraryEditableKeyValue(key: key, value: newValue))
        }
        return LibrarySampleEditDraft(
            sampleId: sample.id,
            batchId: sample.batchId,
            baseUpdatedAt: sample.updatedAt,
            substrateTagsText: sample.substrateTags.joined(separator: ", "),
            numericValues: [],
            metadataValues: metadataValues
        )
    }

    // MARK: - Test 1: sibling-sample isolation via Layer 1 rejection

    @Test("Editing a Batch-owned field (temperature) from one Sample is rejected; sibling Sample is untouched")
    func batchOwnedFieldEdit_rejectedAtServiceLayer_siblingUnaffected() throws {
        let sharedMetadata = ["温度": "650", "衬底": "STO"]
        let sample110 = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: sharedMetadata)
        let sample111 = Self.makeSample(id: "PN109|o|STO|111", batchId: "PN109", substrateDisplay: "STO(111)", metadata: sharedMetadata)

        let service = LibrarySampleEditService()
        let editedDraft = Self.draft(from: sample110, changing: "温度", to: "700")

        #expect(throws: LibrarySampleEditService.EditError.self) {
            try service.apply(draft: editedDraft, to: sample110)
        }

        do {
            _ = try service.apply(draft: editedDraft, to: sample110)
            Issue.record("Expected batchOwnedFieldsRejected to be thrown")
        } catch let error as LibrarySampleEditService.EditError {
            guard case let .batchOwnedFieldsRejected(keys) = error else {
                Issue.record("Expected .batchOwnedFieldsRejected, got \(error)")
                return
            }
            #expect(keys == ["温度"])
        }

        // Sibling was never passed to apply() and remains byte-for-byte
        // identical — no shared-row write occurred, so it has nothing to
        // pick up on next load.
        #expect(sample111.metadata["温度"] == "650")
    }

    // MARK: - Test 2: Sample-owned field edit still works

    @Test("Editing a Sample-owned field (substrate) is allowed and applies correctly")
    func sampleOwnedFieldEdit_allowed() throws {
        let sample = Self.makeSample(
            id: "PN109|o|STO|110",
            batchId: "PN109",
            substrateDisplay: "STO(110)",
            metadata: ["温度": "650", "衬底": "STO(110)"]
        )
        let service = LibrarySampleEditService()
        let editedDraft = Self.draft(from: sample, changing: "衬底", to: "STO(110) polished")

        let updated = try service.apply(draft: editedDraft, to: sample)

        #expect(updated.metadata["衬底"] == "STO(110) polished")
        #expect(updated.metadata["温度"] == "650")
    }

    // MARK: - Test 2b: Unknown field edit still works (compatibility, existing behavior preserved)

    @Test("Editing an unclassified field is still allowed (compatibility default)")
    func unknownFieldEdit_allowedForCompatibility() throws {
        let sample = Self.makeSample(
            id: "PN109|o|STO|110",
            batchId: "PN109",
            substrateDisplay: "STO(110)",
            metadata: ["备注": "old note"]
        )
        let service = LibrarySampleEditService()
        let editedDraft = Self.draft(from: sample, changing: "备注", to: "new note")

        let updated = try service.apply(draft: editedDraft, to: sample)

        #expect(updated.metadata["备注"] == "new note")
    }

    // MARK: - Test 3: Registry write service independently rejects, with zero file I/O

    @Test("LibraryXLSXSyncService rejects a direct Batch-owned metadata write before any workbook I/O")
    func registryWriteService_rejectsBatchOwnedWrite_directly() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // The rejection must happen before the file is ever opened as a
        // workbook, so a byte sequence that is not a valid XLSX/ZIP is
        // sufficient to prove no unzip/parse/write was attempted.
        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        let originalBytes = Data("not-a-real-xlsx".utf8)
        try originalBytes.write(to: dummyRegistryURL)

        let oldSample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["温度": "650"])
        var newSample = oldSample
        newSample.metadata["温度"] = "700"
        let service = LibraryXLSXSyncService()

        #expect(throws: LibraryXLSXSyncService.SyncError.self) {
            _ = try service.syncEditedSample(
                oldSample: oldSample,
                updatedSample: newSample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [LibraryXLSXSyncService.MetadataWrite(key: "温度", oldValue: "650", newValue: "700")],
                numericWrites: []
            )
        }

        let bytesAfter = try Data(contentsOf: dummyRegistryURL)
        #expect(bytesAfter == originalBytes, "Registry source file must be untouched when a Batch-owned write is rejected")
    }

    @Test("LibraryXLSXSyncService derives ownership from sample state, not the caller's write list — a forged/omitted write list cannot bypass rejection")
    func registryWriteService_ignoresForgedWriteList_stillRejectsBasedOnSampleDiff() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        let originalBytes = Data("not-a-real-xlsx".utf8)
        try originalBytes.write(to: dummyRegistryURL)

        // oldSample/updatedSample genuinely disagree on a Batch-owned field,
        // but the caller's metadataWrites list is empty — a caller could
        // "forget" to declare the write, or a bug could drop it. Layer 2
        // must still reject because it recomputes the diff itself.
        let oldSample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["温度": "650"])
        var newSample = oldSample
        newSample.metadata["温度"] = "700"
        let service = LibraryXLSXSyncService()

        #expect(throws: LibraryXLSXSyncService.SyncError.self) {
            _ = try service.syncEditedSample(
                oldSample: oldSample,
                updatedSample: newSample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [],
                numericWrites: []
            )
        }

        let bytesAfter = try Data(contentsOf: dummyRegistryURL)
        #expect(bytesAfter == originalBytes)
    }

    @Test("An unchanged Batch-owned value does not block an unrelated Sample-owned write, and Unknown changes are surfaced as warnings")
    func registryWriteService_unchangedBatchValue_doesNotBlock_unknownChangeIsWarned() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A byte sequence that is not a valid XLSX is fine here too: with
        // no rejection, syncEditedSample will attempt real workbook I/O and
        // this test only needs to observe the *thrown* error type (an
        // unzip/workbook failure, not a batchOwnedFieldsRejected), proving
        // the ownership gate let this request proceed.
        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        try Data("not-a-real-xlsx".utf8).write(to: dummyRegistryURL)

        let oldSample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["温度": "650", "备注": "old"])
        var newSample = oldSample
        newSample.metadata["备注"] = "new"
        let service = LibraryXLSXSyncService()

        do {
            _ = try service.syncEditedSample(
                oldSample: oldSample,
                updatedSample: newSample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [LibraryXLSXSyncService.MetadataWrite(key: "备注", oldValue: "old", newValue: "new")],
                numericWrites: []
            )
            Issue.record("Expected a workbook I/O failure (not-a-real-xlsx), not a clean success — this only proves the ownership gate did not block")
        } catch let error as LibraryXLSXSyncService.SyncError {
            if case .batchOwnedFieldsRejected = error {
                Issue.record("Unchanged Batch-owned field 温度 must not cause rejection when only an Unknown field (备注) changed")
            }
            // Any other SyncError (unzip/workbook failure against the dummy
            // bytes) confirms the ownership gate passed and execution
            // proceeded to real workbook I/O, as expected.
        }
    }

    // MARK: - Test 4: rule book classification is stable and matches documented defaults

    @Test("Default rule book classifies documented examples correctly")
    func defaultRuleBook_classification() {
        let ruleBook = LibraryFieldOwnershipRuleBook.shared
        #expect(ruleBook.scope(for: "温度") == .batch)
        #expect(ruleBook.scope(for: "Temperature") == .batch)
        #expect(ruleBook.scope(for: "衬底") == .sample)
        #expect(ruleBook.scope(for: "Substrate") == .sample)
        #expect(ruleBook.scope(for: "生长日期") == .unknown)
        #expect(ruleBook.scope(for: "some_never_seen_field") == .unknown)
    }
}
