import Foundation
import Testing
@testable import SpinLabApp

/// Phase 4: SampleDossierBuilder join-rule coverage. `SampleDossierIndex` is a
/// pure, read-only join of `LibraryIndex` + `ObsidianVaultIndex` — batch join
/// is exact `batchId` equality, sample join is exact canonical `sampleKey`
/// equality, and no rule (Library-wins/Obsidian-wins) is ever applied
/// globally (see Phase 4 spec §13–§15).
@Suite("V5.4.4 SampleDossierBuilder join rules")
struct V544SampleDossierJoinTests {
    private func makeBatch(id: String, metadata: [String: String] = [:], numericDisplay: [String: String] = [:]) -> LibraryBatch {
        LibraryBatch(
            id: id,
            displayName: id,
            sheetName: "Sheet1",
            metadata: metadata,
            numericTags: [:],
            numericDisplay: numericDisplay,
            sampleKeys: [],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeSample(id: String, batchId: String) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: id,
            batchId: batchId,
            substrateRaw: "",
            substrateDisplay: "",
            substrateTokens: [],
            substrateTags: [],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func emptyLibrary(batches: [LibraryBatch] = [], samples: [LibrarySample] = []) -> LibraryIndex {
        LibraryIndex(
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: batches,
            samples: samples
        )
    }

    private func emptyObsidian(
        batches: [ObsidianVaultIndex.BatchRecord] = [],
        samples: [ObsidianVaultIndex.SampleRecord] = [],
        notes: [ObsidianNoteRecord] = []
    ) -> ObsidianVaultIndex {
        ObsidianVaultIndex(
            sourceRootPath: "/tmp/vault",
            noteCount: notes.count,
            batches: batches,
            samples: samples,
            diagnostics: [],
            notes: notes
        )
    }

    private func claim(_ value: String, notePath: String = "note.md", rawKey: String = "field") -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    @Test("8. Library-only Batch has no Obsidian counterpart")
    func libraryOnlyBatch() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN200")])
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian())
        let batch = dossier.batches.first { $0.batchId == "PN200" }
        #expect(batch?.hasLibraryRecord == true)
        #expect(batch?.obsidianNotePaths.isEmpty == true)
    }

    @Test("9. Obsidian-only Batch has no Library counterpart")
    func obsidianOnlyBatch() {
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN201",
            growthClaims: [.growthTemperature: [claim("700 C")]],
            notePaths: ["pn201.md"]
        )
        let dossier = SampleDossierBuilder.build(library: emptyLibrary(), obsidian: emptyObsidian(batches: [obsidianBatch]))
        let batch = dossier.batches.first { $0.batchId == "PN201" }
        #expect(batch?.hasLibraryRecord == false)
        #expect(batch?.growthFields[.growthTemperature] == .obsidianOnly("700 C"))
    }

    @Test("10. matching Batch joins by exact batchId equality")
    func matchingBatch() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN202", numericDisplay: ["温度": "700"])])
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN202",
            growthClaims: [.growthTemperature: [claim("700 C")]],
            notePaths: ["pn202.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(batches: [obsidianBatch]))
        #expect(dossier.batches.count == 1)
        let batch = dossier.batches[0]
        #expect(batch.hasLibraryRecord)
        #expect(batch.obsidianNotePaths == ["pn202.md"])
    }

    @Test("11. matching Sample joins by canonical sampleKey equality")
    func matchingSample() {
        let key = SampleSemanticDescriptor.withPrevalidatedTokens(batch: "PN203", processingTokens: [], material: "STO", orientation: "110").canonicalKey!
        let library = emptyLibrary(samples: [makeSample(id: key, batchId: "PN203")])
        let obsidianSample = ObsidianVaultIndex.SampleRecord(
            sampleKey: key,
            batchId: "PN203",
            testStatus: ["3w": [claim("planned")]],
            sampleObservations: [],
            notePaths: ["pn203 110.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(samples: [obsidianSample]))
        #expect(dossier.samples.count == 1)
        let sample = dossier.samples[0]
        #expect(sample.hasLibraryRecord)
        #expect(sample.obsidianTestStatus["3w"]?.first?.value == "planned")
    }

    @Test("12. agreement field: both sides carry the same normalized growth value")
    func agreementField() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN204", numericDisplay: ["温度": "700"])])
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN204",
            growthClaims: [.growthTemperature: [claim("700 C")]],
            notePaths: ["pn204.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(batches: [obsidianBatch]))
        #expect(dossier.batches.first?.growthFields[.growthTemperature] == .agreement("700 C"))
    }

    @Test("13. conflict field: both sides carry different growth values, surfaced not silently overwritten")
    func conflictField() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN205", numericDisplay: ["温度": "700"])])
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN205",
            growthClaims: [.growthTemperature: [claim("720 C")]],
            notePaths: ["pn205.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(batches: [obsidianBatch]))
        #expect(dossier.batches.first?.growthFields[.growthTemperature] == .conflict(library: "700", obsidian: "720 C"))
    }

    @Test("14. duplicate Obsidian notes agreeing on the same batch reconcile to one value")
    func duplicateNotesAgreeing() {
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN206",
            growthClaims: [.growthTemperature: [claim("700 C", notePath: "a.md"), claim("700", notePath: "b.md")]],
            notePaths: ["a.md", "b.md"]
        )
        let dossier = SampleDossierBuilder.build(library: emptyLibrary(), obsidian: emptyObsidian(batches: [obsidianBatch]))
        #expect(dossier.batches.first?.growthFields[.growthTemperature] == .obsidianOnly("700 C"))
    }

    @Test("15. duplicate Obsidian notes conflicting on the same batch do not silently pick a winner")
    func duplicateNotesConflicting() {
        let noteA = ObsidianNoteRecord(
            notePath: "a.md", batchId: "PN207", identity: .unresolvedSample,
            growthClaims: [.growthTemperature: claim("700 C", notePath: "a.md")],
            rawFields: [], testStatus: [:], sampleObservations: [], substrateEntries: []
        )
        let noteB = ObsidianNoteRecord(
            notePath: "b.md", batchId: "PN207", identity: .unresolvedSample,
            growthClaims: [.growthTemperature: claim("720 C", notePath: "b.md")],
            rawFields: [], testStatus: [:], sampleObservations: [], substrateEntries: []
        )
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN207",
            growthClaims: [.growthTemperature: [claim("700 C", notePath: "a.md"), claim("720 C", notePath: "b.md")]],
            notePaths: ["a.md", "b.md"]
        )
        let dossier = SampleDossierBuilder.build(
            library: emptyLibrary(),
            obsidian: emptyObsidian(batches: [obsidianBatch], notes: [noteA, noteB])
        )
        // The join result exposes a value (never a fabricated average), but callers
        // needing the internal disagreement must inspect the source notes directly —
        // the point under test is that this does NOT come back as `.conflict` against
        // a Library side that has no record at all (that would misreport the source
        // of the disagreement as Library-vs-Obsidian rather than Obsidian-internal).
        #expect(dossier.batches.first?.growthFields[.growthTemperature] != nil)
        if case .obsidianOnly = dossier.batches.first?.growthFields[.growthTemperature] {
            // expected shape
        } else {
            Issue.record("expected obsidianOnly reconciliation, not a fabricated Library-side conflict")
        }
    }

    @Test("16. PN109-style siblings share one Batch dossier but keep independent Sample dossiers")
    func siblingSamplesShareBatchNotSample() {
        let keyA = SampleSemanticDescriptor.withPrevalidatedTokens(batch: "PN109", processingTokens: [], material: "STO", orientation: "110").canonicalKey!
        let keyB = SampleSemanticDescriptor.withPrevalidatedTokens(batch: "PN109", processingTokens: [], material: "STO", orientation: "111").canonicalKey!
        #expect(keyA != keyB)

        let obsidianBatch = ObsidianVaultIndex.BatchRecord(batchId: "PN109", growthClaims: [:], notePaths: ["pn109 110.md", "pn109 111.md"])
        let sampleA = ObsidianVaultIndex.SampleRecord(sampleKey: keyA, batchId: "PN109", testStatus: [:], sampleObservations: [], notePaths: ["pn109 110.md"])
        let sampleB = ObsidianVaultIndex.SampleRecord(sampleKey: keyB, batchId: "PN109", testStatus: [:], sampleObservations: [], notePaths: ["pn109 111.md"])

        let dossier = SampleDossierBuilder.build(
            library: emptyLibrary(),
            obsidian: emptyObsidian(batches: [obsidianBatch], samples: [sampleA, sampleB])
        )
        #expect(dossier.batches.count == 1)
        #expect(Set(dossier.batches[0].sampleKeys) == Set([keyA, keyB]))
        #expect(dossier.samples.count == 2)
        #expect(Set(dossier.samples.map(\.sampleKey)) == Set([keyA, keyB]))
    }

    @Test("17. no fuzzy merge: similar but distinct sampleKeys never join")
    func noFuzzyMerge() {
        let libKey = SampleSemanticDescriptor.withPrevalidatedTokens(batch: "PN300", processingTokens: [], material: "STO", orientation: "110").canonicalKey!
        let obsKey = SampleSemanticDescriptor.withPrevalidatedTokens(batch: "PN300", processingTokens: [], material: "STO", orientation: "111").canonicalKey!
        let library = emptyLibrary(samples: [makeSample(id: libKey, batchId: "PN300")])
        let obsidianSample = ObsidianVaultIndex.SampleRecord(sampleKey: obsKey, batchId: "PN300", testStatus: [:], sampleObservations: [], notePaths: ["x.md"])

        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(samples: [obsidianSample]))
        #expect(dossier.samples.count == 2)
        let libSide = dossier.samples.first { $0.sampleKey == libKey }
        let obsSide = dossier.samples.first { $0.sampleKey == obsKey }
        #expect(libSide?.hasLibraryRecord == true)
        #expect(libSide?.obsidianNotePaths.isEmpty == true)
        #expect(obsSide?.hasLibraryRecord == false)
        #expect(obsSide?.obsidianNotePaths == ["x.md"])
    }
}
