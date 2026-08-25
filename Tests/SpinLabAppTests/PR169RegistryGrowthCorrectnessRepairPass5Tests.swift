import Foundation
import Testing
@testable import SpinLabApp

/// PR #169 repair pass 5 — Existing reconciliation completeness. Covers the
/// two Registry correctness gaps closed in this pass:
///
/// 1. Existing-row comparison must include target-material identity (Registry
///    靶 vs Obsidian material claim) — previously excluded entirely, so a
///    fundamental experiment-target mismatch could compact into a clean
///    Existing row or even reach ENRICH undetected.
/// 2. A blank Registry cell for an eligible field must be treated as missing
///    evidence, not silently skipped — a deterministic Obsidian value for
///    that field is now a compatible-enrichment candidate instead of making
///    the row look synchronized.
@Suite("PR169 RegistryGrowthImportPlanner correctness repair — pass 5")
struct PR169RegistryGrowthCorrectnessRepairPass5Tests {
    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    private func makeVault(notes: [ObsidianNoteRecord]) -> ObsidianVaultIndex {
        var batchesById: [String: ObsidianVaultIndex.BatchRecord] = [:]
        for note in notes {
            guard let batchId = note.batchId else { continue }
            var record = batchesById[batchId] ?? ObsidianVaultIndex.BatchRecord(batchId: batchId, growthClaims: [:], notePaths: [])
            for (field, claim) in note.growthClaims { record.growthClaims[field, default: []].append(claim) }
            record.notePaths.append(note.notePath)
            batchesById[batchId] = record
        }
        return ObsidianVaultIndex(sourceRootPath: "/tmp/vault", noteCount: notes.count, batches: Array(batchesById.values), samples: [], diagnostics: [], notes: notes)
    }

    private func buildPlan(fixtureURL: URL, notes: [ObsidianNoteRecord]) throws -> RegistryGrowthImportPlan {
        let vault = makeVault(notes: notes)
        let settings = LibrarySettings(rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil, registrySourcePath: fixtureURL.path, backupPath: nil, backupLastSyncedAt: nil, allowedBatchPrefixes: [], lastRefreshAt: nil)
        return try withBundledRules { provider in
            let library = try LibraryRegistryParser(ruleProvider: provider).parse(xlsxURL: fixtureURL, settings: settings).index
            let dossier = SampleDossierBuilder.build(library: library, obsidian: vault)
            return try RegistryGrowthImportPlanner(ruleProvider: provider).build(vault: vault, dossier: dossier, registryURL: fixtureURL)
        }
    }

    // MARK: - Item 1: material identity

    private func makeMaterialNote(batchId: String, path: String, material: String) -> ObsidianNoteRecord {
        ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: [:],
            rawFields: [claim(material, notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: "STO(001)", provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: "STO(001)"), material: nil, orientation: nil)]
        )
    }

    private func makeStandardFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PR169-pass5-std-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.build(to: url)
        return url
    }

    @Test("1A. Same material (Registry 靶=LNO, Obsidian material=LNO) → clean, no material difference")
    func sameMaterialIsClean() throws {
        let url = try makeStandardFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeMaterialNote(batchId: "LNO1", path: "lno1.md", material: "LNO")])

        #expect(plan.items.first { $0.batchId == "LNO1" } == nil, "matching material must compact into clean Existing")
        #expect(plan.existingCount == 1)
    }

    @Test("1B. Registry 靶=NCO vs Obsidian material=SRO → visible conflict, never ENRICH")
    func mismatchedMaterialIsVisibleConflict() throws {
        let url = try makeStandardFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeMaterialNote(batchId: "NCO1", path: "nco1.md", material: "SRO")])

        let item = try #require(plan.items.first { $0.batchId == "NCO1" })
        guard case .skipExisting = item.action else {
            Issue.record("expected .skipExisting (material conflict), got \(item.action)")
            return
        }
        let diff = try #require(item.existingDifferences.first { $0.field == .material })
        #expect(diff.registryValue == "NCO")
        #expect(diff.obsidianValue == "SRO")
        #expect(plan.existingCount == 0, "a row with a genuine material conflict is never counted as clean Existing")
    }

    @Test("1C. Equivalent material aliases (Registry 靶=SRO, Obsidian material=SrRuO3) → no false conflict")
    func equivalentMaterialAliasesDoNotConflict() throws {
        let url = try makeStandardFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeMaterialNote(batchId: "PN1", path: "pn1.md", material: "SrRuO3")])

        #expect(plan.items.first { $0.batchId == "PN1" } == nil, "an alias-equivalent material must never surface as a difference")
        #expect(plan.existingCount == 1)
    }

    // MARK: - Item 2: blank Registry fields participate in enrichment

    private func makeBlankFieldNote(
        path: String = "lno1.md",
        material: String = "LNO",
        oxygenPressure: String?,
        growthTemperature: String = "650",
        targetSubstrateDistance: String = "45",
        laserEnergy: String = "1.2",
        pulseCount: String = "200/3000"
    ) -> ObsidianNoteRecord {
        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [
            .growthTemperature: claim(growthTemperature, notePath: path, rawKey: "temperature"),
            .targetSubstrateDistance: claim(targetSubstrateDistance, notePath: path, rawKey: "sample height"),
            .laserEnergy: claim(laserEnergy, notePath: path, rawKey: "energy"),
            .pulseCount: claim(pulseCount, notePath: path, rawKey: "pulse")
        ]
        if let oxygenPressure { growthClaims[.oxygenPressure] = claim(oxygenPressure, notePath: path, rawKey: "pressure") }
        return ObsidianNoteRecord(
            notePath: path, batchId: "LNO1", identity: .unresolvedSample,
            growthClaims: growthClaims,
            rawFields: [claim(material, notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: "STO(001)", provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: "STO(001)"), material: nil, orientation: nil)]
        )
    }

    private func makeBlankFieldFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PR169-pass5-blank-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForBlankFieldEnrichment(to: url)
        return url
    }

    @Test("2A. Blank Registry 氧压 + deterministic Obsidian value → ENRICH, not silently synchronized")
    func blankRegistryFieldWithObsidianValueEnriches() throws {
        let url = try makeBlankFieldFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeBlankFieldNote(oxygenPressure: "200")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(item.existingDifferences.isEmpty)
        guard case let .enrichExisting(sheet, row, edits) = item.action else {
            Issue.record("expected .enrichExisting for a blank Registry field with a deterministic Obsidian value, got \(item.action)")
            return
        }
        #expect(sheet == "LNO")
        #expect(row == 2)
        let edit = try #require(edits.first { $0.field == .oxygenPressure })
        #expect(edit.originalRegistryValue == "")
        #expect(edit.finalValue == "200")
        #expect(plan.existingCount == 0, "a row carrying a planned enrichment is never counted as clean Existing")
    }

    @Test("2B. Blank Registry optional field with no Obsidian evidence → unchanged behavior")
    func blankRegistryFieldWithNoObsidianEvidenceIsUnchanged() throws {
        let url = try makeBlankFieldFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeBlankFieldNote(oxygenPressure: nil)])

        #expect(plan.items.first { $0.batchId == "LNO1" } == nil, "no Obsidian evidence for the blank field must leave the row clean, exactly as before")
        #expect(plan.existingCount == 1)
    }

    @Test("2C. Conflicting non-empty values on an already-populated field → Existing conflict, not ENRICH")
    func conflictingNonEmptyFieldStaysConflict() throws {
        let url = try makeBlankFieldFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeBlankFieldNote(oxygenPressure: "200", growthTemperature: "700")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        guard case .skipExisting = item.action else {
            Issue.record("expected .skipExisting — a genuine conflict on an already-populated field must never be masked by another field's enrichment, got \(item.action)")
            return
        }
        #expect(item.existingDifferences.contains { $0.field == .growthTemperature })
        #expect(plan.existingCount == 0)
    }
}
