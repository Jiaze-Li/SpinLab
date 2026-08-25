import Foundation
import Testing
@testable import SpinLabApp

/// PR #169 repair pass 7 — identity and energy semantic completeness.
///
/// Item 1: substrate identity is part of Sample identity — an Existing
/// Registry row whose substrate cell semantically disagrees with Obsidian
/// (different orientation/material, not just different formatting) must
/// surface as a structured `.substrate` difference, never compact into
/// `existingCount` or ENRICH silently.
///
/// Item 2: laser energy carries three independent components (mirror/front
/// energy, laser output energy, voltage) — two Obsidian claims for the same
/// batch that agree on the leading magnitude but disagree on voltage/output
/// must surface as an Obsidian-internal conflict, not collapse into a single
/// clean value.
@Suite("PR169 repair pass 7 — substrate identity + energy component conflicts")
struct PR169RegistryGrowthCorrectnessRepairPass7Tests {
    private func makeFixtureRegistry() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PR169P7-registry-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForSemanticDateAndPulse(to: url)
        return url
    }

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    /// Every fixture row (LNO1..LNO6) carries 生长温度=650, 靶机距=45,
    /// 氧压=100, 能量=1.2, substrate=STO(001) — matching claims for those
    /// keeps only the field under test in `.existingDifferences`, exactly
    /// like `V544RegistryGrowthSemanticNormalizationTests`.
    private func makeNote(batchId: String, path: String, substrate: String) -> ObsidianNoteRecord {
        ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: [
                .growthTemperature: claim("650", notePath: path, rawKey: "temperature"),
                .targetSubstrateDistance: claim("45", notePath: path, rawKey: "sample height"),
                .oxygenPressure: claim("100", notePath: path, rawKey: "pressure"),
                .laserEnergy: claim("1.2", notePath: path, rawKey: "energy")
            ],
            rawFields: [claim("LNO", notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: substrate, provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: substrate), material: nil, orientation: nil)]
        )
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

    // MARK: - Item 1: substrate identity

    @Test("Substrate A. Registry STO(001) vs Obsidian STO(001) → clean, compacts into existingCount")
    func sameSubstrateIsClean() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", substrate: "STO(001)")])

        #expect(plan.items.first { $0.batchId == "LNO1" } == nil)
        #expect(plan.existingCount == 1)
    }

    @Test("Substrate B. Registry STO(001) vs Obsidian STO(111) → genuine orientation mismatch, structured conflict")
    func differentOrientationIsConflict() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO2", path: "lno2.md", substrate: "STO(111)")])

        let item = try #require(plan.items.first { $0.batchId == "LNO2" })
        let diff = try #require(item.existingDifferences.first { $0.field == .substrate })
        #expect(diff.registryValue == "STO(001)")
        #expect(diff.obsidianValue == "STO(111)")
        #expect(plan.existingCount == 0)
    }

    @Test("Substrate C. Registry STO(001) vs Obsidian same substrate, different formatting (STO001) → no false conflict")
    func differentFormattingSameSubstrateIsNotConflict() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO3", path: "lno3.md", substrate: "STO001")])

        #expect(plan.items.first { $0.batchId == "LNO3" } == nil, "equivalent substrate formatting must never false-flag as a conflict")
        #expect(plan.existingCount == 1)
    }

    // MARK: - Item 2: energy component internal conflict (new-batch path)
    //
    // Exercises `SampleDossierBuilder.reconcile`/`normalizedForCompare` via
    // `RegistryGrowthImportPlanner.hasInternalConflict` — the *new*-batch
    // append path (no existing Registry row for the batch), distinct from
    // the Existing-row dedup path pass 6 already fixed with its own
    // `RegistryGrowthEnergyMapper` bypass. A brand-new batch id (not any of
    // the fixture's LNO1..LNO6 rows) with otherwise-complete required
    // fields isolates this path.

    private func newBatchNote(batchId: String, path: String, energy: String, date: String = "2026-01-01") -> ObsidianNoteRecord {
        ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: [
                .growthDate: claim(date, notePath: path, rawKey: "date"),
                .laserEnergy: claim(energy, notePath: path, rawKey: "energy")
            ],
            rawFields: [claim("LNO", notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: "STO(001)", provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: "STO(001)"), material: nil, orientation: nil)]
        )
    }

    private func hasEnergyInternalConflictReason(_ item: RegistryGrowthImportItem) -> Bool {
        item.blockingReasons.contains { reason in
            if case let .obsidianInternalConflict(field) = reason { return field == "能量" }
            return false
        }
    }

    @Test("Energy A. Same components, different formatting → no internal conflict")
    func sameEnergyComponentsDifferentFormattingIsClean() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            newBatchNote(batchId: "LNO20", path: "lno20a.md", energy: "110 mJ 26.3 kV 280 mJ"),
            newBatchNote(batchId: "LNO20", path: "lno20b.md", energy: "110mJ 26.3kV 280mJ")
        ])

        let item = try #require(plan.items.first { $0.batchId == "LNO20" })
        #expect(!hasEnergyInternalConflictReason(item), "same energy components spelled differently must never read as an Obsidian-internal disagreement")
    }

    @Test("Energy B. Same primary mJ, different kV/output → genuine internal conflict")
    func sameLeadingMagnitudeDifferentComponentsIsConflict() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            newBatchNote(batchId: "LNO21", path: "lno21a.md", energy: "110 mJ 26.3 kV 280 mJ"),
            newBatchNote(batchId: "LNO21", path: "lno21b.md", energy: "110 mJ 25.0 kV 247 mJ")
        ])

        let item = try #require(plan.items.first { $0.batchId == "LNO21" })
        #expect(hasEnergyInternalConflictReason(item), "same leading magnitude with different voltage/output components must still be a genuine internal conflict")
    }

    @Test("Energy C. Different primary energy → genuine internal conflict")
    func differentPrimaryEnergyIsConflict() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            newBatchNote(batchId: "LNO22", path: "lno22a.md", energy: "110 mJ 26.3 kV 280 mJ"),
            newBatchNote(batchId: "LNO22", path: "lno22b.md", energy: "120 mJ 26.3 kV 280 mJ")
        ])

        let item = try #require(plan.items.first { $0.batchId == "LNO22" })
        #expect(hasEnergyInternalConflictReason(item))
    }
}
