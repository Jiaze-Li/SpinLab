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

    @Test("15. duplicate Obsidian notes conflicting on the same batch surface an explicit internal conflict, not first-wins")
    func duplicateNotesConflicting() {
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN207",
            growthClaims: [.growthTemperature: [claim("700 C", notePath: "a.md"), claim("720 C", notePath: "b.md")]],
            notePaths: ["a.md", "b.md"]
        )
        let dossier = SampleDossierBuilder.build(library: emptyLibrary(), obsidian: emptyObsidian(batches: [obsidianBatch]))
        guard case .obsidianInternalConflict(let claims, let libraryValue) = dossier.batches.first?.growthFields[.growthTemperature] else {
            Issue.record("expected obsidianInternalConflict, got \(String(describing: dossier.batches.first?.growthFields[.growthTemperature]))")
            return
        }
        #expect(libraryValue == nil)
        #expect(Set(claims.map(\.value)) == Set(["700 C", "720 C"]))
        #expect(Set(claims.map(\.provenance.notePath)) == Set(["a.md", "b.md"]))
    }

    @Test("15b. Obsidian-internal conflict still carries the Library value alongside, not forced into .conflict/.agreement")
    func duplicateNotesConflictingWithLibraryValue() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN208", numericDisplay: ["温度": "700"])])
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN208",
            growthClaims: [.growthTemperature: [claim("700 C", notePath: "a.md"), claim("720 C", notePath: "b.md")]],
            notePaths: ["a.md", "b.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(batches: [obsidianBatch]))
        guard case .obsidianInternalConflict(let claims, let libraryValue) = dossier.batches.first?.growthFields[.growthTemperature] else {
            Issue.record("expected obsidianInternalConflict")
            return
        }
        #expect(libraryValue == "700")
        #expect(claims.count == 2)
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

    @Test("field-specific normalization: dates differing only past the year-month-day must not agree")
    func dateMismatchIsNotAgreement() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN400", metadata: ["日期": "2026-08-10"])])
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN400",
            growthClaims: [.growthDate: [claim("2026-08-20")]],
            notePaths: ["pn400.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(batches: [obsidianBatch]))
        #expect(dossier.batches.first?.growthFields[.growthDate] == .conflict(library: "2026-08-10", obsidian: "2026-08-20"))
    }

    @Test("field-specific normalization: pulse recipes differing past the first number must not agree")
    func pulseMismatchIsNotAgreement() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN401", metadata: ["预打": "500/600"])])
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN401",
            growthClaims: [.pulseCount: [claim("500/3000")]],
            notePaths: ["pn401.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(batches: [obsidianBatch]))
        #expect(dossier.batches.first?.growthFields[.pulseCount] == .conflict(library: "500/600", obsidian: "500/3000"))
    }

    @Test("field-specific normalization: numeric value agrees across unit spelling ('700 C' == '700 °C')")
    func numericFieldAgreesAcrossUnitSpelling() {
        let library = emptyLibrary(batches: [makeBatch(id: "PN402", numericDisplay: ["温度": "700 C"])])
        let obsidianBatch = ObsidianVaultIndex.BatchRecord(
            batchId: "PN402",
            growthClaims: [.growthTemperature: [claim("700 °C")]],
            notePaths: ["pn402.md"]
        )
        let dossier = SampleDossierBuilder.build(library: library, obsidian: emptyObsidian(batches: [obsidianBatch]))
        #expect(dossier.batches.first?.growthFields[.growthTemperature] == .agreement("700 °C"))
    }
}
