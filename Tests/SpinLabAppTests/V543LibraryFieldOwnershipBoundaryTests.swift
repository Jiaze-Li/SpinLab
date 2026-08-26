import Foundation
import Testing
@testable import SpinLabApp

/// Phase 3A: Batch / Sample Field Ownership Boundary.
///
/// Regression coverage for the confirmed integrity bug in
/// `docs/library-architecture-audit.md` §13.6/F1: editing a metadata field
/// on one `LibrarySample` (e.g. `PN109|o|STO|110`) used to write directly
/// into the Registry row shared by every sibling Sample of the same Batch
/// (e.g. `PN109|o|STO|111`), with zero ownership guard. Both enforcement
/// layers are fail-closed for Sample→Registry mutation: only a field
/// confirmed Sample-owned may be written; Batch-owned AND Unknown fields
/// are both rejected — including the raw Registry substrate/衬底 cell,
/// which describes the whole Batch's sample composition (e.g.
/// `STO(110), STO(111)`), not one Sample.
///
/// - Layer 1 (`LibrarySampleEditService.apply`): rejects before any sample
///   mutation is produced.
/// - Layer 2 (`LibraryXLSXSyncService.syncEditedSample`): independently
///   re-derives the changed-key set from oldSample/updatedSample.metadata
///   (not the caller's write list) and rejects before any workbook I/O.
@Suite("V5.4.3 Library Field Ownership Boundary")
struct V543LibraryFieldOwnershipBoundaryTests {

    // MARK: - Fixtures

    private static func makeSample(
        id: String,
        batchId: String,
        substrateDisplay: String,
        metadata: [String: String],
        substrateTags: [String] = [],
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
            substrateTags: substrateTags,
            metadata: metadata,
            orderedMetadata: metadata.map { LibraryMetadataItem(key: $0.key, value: $0.value) },
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: sourceSheetName,
            sourceRowNumber: sourceRowNumber,
            updatedAt: .now
        )
    }

    private static func draft(from sample: LibrarySample, changingMetadata key: String, to newValue: String) -> LibrarySampleEditDraft {
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

    private static func rejectedKeys(from error: Error) -> [String]? {
        guard let editError = error as? LibrarySampleEditService.EditError,
              case let .registryFieldsRejected(keys) = editError else {
            return nil
        }
        return keys
    }

    // MARK: - Layer 1 (LibrarySampleEditService.apply): confirmed Batch-owned growth fields, rejected

    @Test(
        "Layer 1 rejects Batch-owned growth-condition fields edited from a Sample; sibling Sample is unaffected",
        arguments: ["生长温度", "日期", "靶机距", "预打", "生长次数", "靶", "生长", "编号"]
    )
    func batchOwnedGrowthField_rejectedAtServiceLayer(fieldKey: String) throws {
        let sharedMetadata = [fieldKey: "original-value"]
        let sample110 = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: sharedMetadata)
        let sample111 = Self.makeSample(id: "PN109|o|STO|111", batchId: "PN109", substrateDisplay: "STO(111)", metadata: sharedMetadata)

        let service = LibrarySampleEditService()
        let editedDraft = Self.draft(from: sample110, changingMetadata: fieldKey, to: "changed-value")

        do {
            _ = try service.apply(draft: editedDraft, to: sample110)
            Issue.record("Expected .registryFieldsRejected for field \(fieldKey)")
        } catch {
            #expect(Self.rejectedKeys(from: error) == [fieldKey])
        }

        // Sibling was never passed to apply() and remains untouched — no
        // shared-row write occurred, so it has nothing to pick up.
        #expect(sample111.metadata[fieldKey] == "original-value")
    }

    // MARK: - Layer 1: raw Registry substrate cell is Batch composition, not Sample-owned — rejected

    @Test("Editing the raw Registry substrate/衬底 cell from one Sample (PN109 row = STO(110), STO(111)) is rejected; sibling Sample's identity/existence is unaffected")
    func rawSubstrateCellEdit_rejectedAtServiceLayer_siblingIdentityUnaffected() throws {
        // One Registry row, one raw substrate cell, describing the whole
        // Batch's composition — the case from the acceptance report.
        let sharedMetadata = ["衬底": "STO(110), STO(111)"]
        let sample110 = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: sharedMetadata, sourceRowNumber: 5)
        let sample111 = Self.makeSample(id: "PN109|o|STO|111", batchId: "PN109", substrateDisplay: "STO(111)", metadata: sharedMetadata, sourceRowNumber: 5)

        let service = LibrarySampleEditService()
        let editedDraft = Self.draft(from: sample110, changingMetadata: "衬底", to: "STO(110)")

        do {
            _ = try service.apply(draft: editedDraft, to: sample110)
            Issue.record("Expected raw substrate cell edit to be rejected")
        } catch {
            #expect(Self.rejectedKeys(from: error) == ["衬底"])
        }

        // STO(111)'s row mapping and raw composition cell are untouched —
        // its identity/existence in the Batch is unaffected.
        #expect(sample111.metadata["衬底"] == "STO(110), STO(111)")
        #expect(sample111.sourceSheetName == sample110.sourceSheetName)
        #expect(sample111.sourceRowNumber == sample110.sourceRowNumber)
    }

    @Test("English/alternate-spelling substrate header aliases are also rejected")
    func substrateAliasVariants_rejected() throws {
        for key in ["substrate", "Substrate"] {
            let sample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: [key: "STO(110), STO(111)"])
            let service = LibrarySampleEditService()
            let editedDraft = Self.draft(from: sample, changingMetadata: key, to: "STO(110)")
            #expect(throws: LibrarySampleEditService.EditError.self) {
                try service.apply(draft: editedDraft, to: sample)
            }
        }
    }

    // MARK: - Layer 1: Unknown Registry metadata is now fail-closed (rejected), not warned-and-allowed

    @Test("Editing an unclassified Registry field (remark/备注) from a Sample is rejected, not silently written")
    func unknownRegistryField_rejectedAtServiceLayer() throws {
        let sample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["备注": "old note"])
        let service = LibrarySampleEditService()
        let editedDraft = Self.draft(from: sample, changingMetadata: "备注", to: "new note")

        do {
            _ = try service.apply(draft: editedDraft, to: sample)
            Issue.record("Expected unclassified field 备注 to be rejected")
        } catch {
            #expect(Self.rejectedKeys(from: error) == ["备注"])
        }
    }

    // MARK: - Sample-local properties outside the Registry metadata dict remain editable

    @Test("Sample-local substrateTags (not a Registry metadata cell) can still be edited normally")
    func sampleLocalSubstrateTags_stillEditable() throws {
        let sample = Self.makeSample(
            id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)",
            metadata: [:], substrateTags: ["old-tag"]
        )
        let service = LibrarySampleEditService()
        var draft = service.makeDraft(from: sample)
        draft.substrateTagsText = "new-tag, another-tag"

        let updated = try service.apply(draft: draft, to: sample)

        #expect(updated.substrateTags == ["new-tag", "another-tag"])
    }

    // MARK: - Layer 2 (LibraryXLSXSyncService): independent re-derivation, zero file I/O on rejection

    @Test("LibraryXLSXSyncService rejects a direct Batch-owned metadata write (生长温度) before any workbook I/O")
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

        let oldSample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["生长温度": "650"])
        var newSample = oldSample
        newSample.metadata["生长温度"] = "700"
        let service = LibraryXLSXSyncService()

        #expect(throws: LibraryXLSXSyncService.SyncError.self) {
            _ = try service.syncEditedSample(
                oldSample: oldSample,
                updatedSample: newSample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [LibraryXLSXSyncService.MetadataWrite(key: "生长温度", oldValue: "650", newValue: "700")],
                numericWrites: []
            )
        }

        let bytesAfter = try Data(contentsOf: dummyRegistryURL)
        #expect(bytesAfter == originalBytes, "Registry source file must be untouched when a rejected write is attempted")
    }

    @Test("LibraryXLSXSyncService rejects a direct raw-substrate-cell write before any workbook I/O")
    func registryWriteService_rejectsRawSubstrateCellWrite_directly() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        let originalBytes = Data("not-a-real-xlsx".utf8)
        try originalBytes.write(to: dummyRegistryURL)

        let oldSample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["衬底": "STO(110), STO(111)"])
        var newSample = oldSample
        newSample.metadata["衬底"] = "STO(110)"
        let service = LibraryXLSXSyncService()

        #expect(throws: LibraryXLSXSyncService.SyncError.self) {
            _ = try service.syncEditedSample(
                oldSample: oldSample,
                updatedSample: newSample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [LibraryXLSXSyncService.MetadataWrite(key: "衬底", oldValue: "STO(110), STO(111)", newValue: "STO(110)")],
                numericWrites: []
            )
        }

        let bytesAfter = try Data(contentsOf: dummyRegistryURL)
        #expect(bytesAfter == originalBytes)
    }

    @Test("LibraryXLSXSyncService rejects a direct Unknown-field write (fail-closed, not warn-and-allow)")
    func registryWriteService_rejectsUnknownFieldWrite_directly() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        let originalBytes = Data("not-a-real-xlsx".utf8)
        try originalBytes.write(to: dummyRegistryURL)

        let oldSample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["备注": "old"])
        var newSample = oldSample
        newSample.metadata["备注"] = "new"
        let service = LibraryXLSXSyncService()

        #expect(throws: LibraryXLSXSyncService.SyncError.self) {
            _ = try service.syncEditedSample(
                oldSample: oldSample,
                updatedSample: newSample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [LibraryXLSXSyncService.MetadataWrite(key: "备注", oldValue: "old", newValue: "new")],
                numericWrites: []
            )
        }

        let bytesAfter = try Data(contentsOf: dummyRegistryURL)
        #expect(bytesAfter == originalBytes, "Unknown fields must fail-closed: rejected, not written-with-warning")
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
        // must still reject because it recomputes the diff itself, not
        // trusting metadataWrites.
        let oldSample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["生长温度": "650"])
        var newSample = oldSample
        newSample.metadata["生长温度"] = "700"
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

    @Test("LibraryXLSXSyncService rejects a forged metadataWrites entry even when oldSample == updatedSample (empty diff) — the write-list itself is independently checked")
    func registryWriteService_rejectsForgedWriteList_withEmptyDiff_batchOwnedKey() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        let originalBytes = Data("not-a-real-xlsx".utf8)
        try originalBytes.write(to: dummyRegistryURL)

        // oldSample and updatedSample are identical (no metadata diff at
        // all), but the caller's metadataWrites list — constructed
        // directly, bypassing LibrarySampleEditService.apply — asks to
        // write a Batch-owned key. The diff-based check alone would see
        // nothing wrong and let this through; the write-list must be
        // checked independently.
        let sample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["生长温度": "650"])
        let service = LibraryXLSXSyncService()

        #expect(throws: LibraryXLSXSyncService.SyncError.self) {
            _ = try service.syncEditedSample(
                oldSample: sample,
                updatedSample: sample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [LibraryXLSXSyncService.MetadataWrite(key: "生长温度", oldValue: "650", newValue: "700")],
                numericWrites: []
            )
        }

        let bytesAfter = try Data(contentsOf: dummyRegistryURL)
        #expect(bytesAfter == originalBytes, "A forged write-list entry for a Batch-owned key must be rejected even with an empty sample diff")
    }

    @Test("LibraryXLSXSyncService rejects a forged metadataWrites entry for an Unknown key even when oldSample == updatedSample (empty diff)")
    func registryWriteService_rejectsForgedWriteList_withEmptyDiff_unknownKey() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        let originalBytes = Data("not-a-real-xlsx".utf8)
        try originalBytes.write(to: dummyRegistryURL)

        let sample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["备注": "old"])
        let service = LibraryXLSXSyncService()

        #expect(throws: LibraryXLSXSyncService.SyncError.self) {
            _ = try service.syncEditedSample(
                oldSample: sample,
                updatedSample: sample,
                registrySourceURL: dummyRegistryURL,
                metadataWrites: [LibraryXLSXSyncService.MetadataWrite(key: "备注", oldValue: "old", newValue: "new")],
                numericWrites: []
            )
        }

        let bytesAfter = try Data(contentsOf: dummyRegistryURL)
        #expect(bytesAfter == originalBytes, "A forged write-list entry for an Unknown key must be rejected even with an empty sample diff")
    }

    @Test("No changed metadata keys: sync proceeds without any ownership rejection")
    func registryWriteService_noChangedKeys_noRejection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "V543-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummyRegistryURL = tempDir.appending(path: "registry.xlsx")
        try Data("not-a-real-xlsx".utf8).write(to: dummyRegistryURL)

        let sample = Self.makeSample(id: "PN109|o|STO|110", batchId: "PN109", substrateDisplay: "STO(110)", metadata: ["生长温度": "650"])
        let service = LibraryXLSXSyncService()

        // metadataWrites/numericWrites both empty and oldSample == updatedSample:
        // this must take the early-return "nothing to sync" path, not throw
        // an ownership rejection and not attempt workbook I/O either.
        let result = try service.syncEditedSample(
            oldSample: sample,
            updatedSample: sample,
            registrySourceURL: dummyRegistryURL,
            metadataWrites: [],
            numericWrites: []
        )

        #expect(result.metadataWrittenCount == 0)
        #expect(result.metadataFailedCount == 0)
    }

    // MARK: - Rule book classification

    @Test("Default rule book classifies the confirmed real Registry schema correctly")
    func defaultRuleBook_classification() {
        let ruleBook = LibraryFieldOwnershipRuleBook.shared

        let confirmedBatchOwned = ["编号", "日期", "生长温度", "靶机距", "氧压", "能量", "预打", "生长次数", "靶", "生长", "substrate", "衬底", "Substrate"]
        for key in confirmedBatchOwned {
            #expect(ruleBook.scope(for: key) == .batch, "\(key) should be classified .batch")
        }

        #expect(ruleBook.scope(for: "remark") == .unknown)
        #expect(ruleBook.scope(for: "备注") == .unknown)
        #expect(ruleBook.scope(for: "生长日期") == .unknown)
        #expect(ruleBook.scope(for: "some_never_seen_field") == .unknown)

        // No Registry metadata column has confirmed Sample-owned evidence today.
        #expect(ruleBook.nonSampleOwnedKeys(among: confirmedBatchOwned + ["remark", "备注"]).sorted() == (confirmedBatchOwned + ["remark", "备注"]).sorted())
    }
}
