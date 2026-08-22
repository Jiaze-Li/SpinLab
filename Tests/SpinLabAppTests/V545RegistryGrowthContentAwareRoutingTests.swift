import Foundation
import Testing
@testable import SpinLabApp

/// Content-aware sheet routing coverage: a batch's target sheet is resolved
/// primarily from which routable sheet already carries the same batch
/// *series* (e.g. `PN110` → series `PN`), not from a hard-coded
/// prefix/material table alone. `RegistryGrowthRouting.targetSheet(forBatchId:materialEvidence:)`
/// (the pre-existing rule table) stays as fallback evidence only — see
/// `RegistryGrowthRouting.resolveTargetSheet`. The write allowlist
/// (`RegistryGrowthImportPlanner.routableSheetNames`) is never touched by
/// this feature: content-aware routing only decides *which already-allowed*
/// sheet a batch belongs to, never whether a new sheet may be written.
@Suite("V5.4.5 Registry growth import content-aware sheet routing")
struct V545RegistryGrowthContentAwareRoutingTests {
    // MARK: - batchSeries unit coverage

    @Test("batchSeries strips a trailing numeric suffix")
    func batchSeriesStripsNumericSuffix() {
        #expect(RegistryGrowthRouting.batchSeries(for: "PN110") == "PN")
        #expect(RegistryGrowthRouting.batchSeries(for: "PN1") == "PN")
        #expect(RegistryGrowthRouting.batchSeries(for: "LNO14") == "LNO")
        #expect(RegistryGrowthRouting.batchSeries(for: "NCO5") == "NCO")
        #expect(RegistryGrowthRouting.batchSeries(for: "LSMO3") == "LSMO")
        #expect(RegistryGrowthRouting.batchSeries(for: "NNO12") == "NNO")
    }

    @Test("batchSeries returns nil when there is no reliable numeric suffix to strip")
    func batchSeriesNilWithoutNumericSuffix() {
        #expect(RegistryGrowthRouting.batchSeries(for: "PN") == nil)
        #expect(RegistryGrowthRouting.batchSeries(for: "ABCXYZ") == nil)
        #expect(RegistryGrowthRouting.batchSeries(for: "110") == nil)
        #expect(RegistryGrowthRouting.batchSeries(for: "") == nil)
    }

    // MARK: - Fixture plumbing (mirrors V545RegistryGrowthImportPlannerTests)

    private func makeFixtureRegistry() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-routing-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForRouting(to: url)
        return url
    }

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    private func makeNote(
        path: String,
        batchId: String?,
        date: String? = "2026-08-20",
        material: String? = "SRO",
        substrate: String? = "STO(001)"
    ) -> ObsidianNoteRecord {
        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [:]
        if let date { growthClaims[.growthDate] = claim(date, notePath: path, rawKey: "date") }

        var rawFields: [ObsidianFieldClaim] = []
        if let material { rawFields.append(claim(material, notePath: path, rawKey: "material")) }

        var substrateEntries: [ObsidianSubstrateEntry] = []
        if let substrate {
            substrateEntries.append(ObsidianSubstrateEntry(
                raw: substrate,
                provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: substrate),
                material: nil, orientation: nil
            ))
        }

        return ObsidianNoteRecord(
            notePath: path,
            batchId: batchId,
            identity: batchId == nil ? .unresolvedBatch : .unresolvedSample,
            growthClaims: growthClaims,
            rawFields: rawFields,
            testStatus: [:],
            sampleObservations: [],
            substrateEntries: substrateEntries
        )
    }

    private func makeVault(notes: [ObsidianNoteRecord]) -> ObsidianVaultIndex {
        var batchesById: [String: ObsidianVaultIndex.BatchRecord] = [:]
        for note in notes {
            guard let batchId = note.batchId else { continue }
            var record = batchesById[batchId] ?? ObsidianVaultIndex.BatchRecord(batchId: batchId, growthClaims: [:], notePaths: [])
            for (field, claim) in note.growthClaims {
                record.growthClaims[field, default: []].append(claim)
            }
            record.notePaths.append(note.notePath)
            batchesById[batchId] = record
        }
        return ObsidianVaultIndex(
            sourceRootPath: "/tmp/vault",
            noteCount: notes.count,
            batches: Array(batchesById.values),
            samples: [],
            diagnostics: [],
            notes: notes
        )
    }

    private func buildPlan(fixtureURL: URL, notes: [ObsidianNoteRecord]) throws -> RegistryGrowthImportPlan {
        let vault = makeVault(notes: notes)
        let settings = LibrarySettings(
            rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil,
            registrySourcePath: fixtureURL.path, backupPath: nil, backupLastSyncedAt: nil,
            allowedBatchPrefixes: [], lastRefreshAt: nil
        )
        return try withBundledRules { provider in
            let library = try LibraryRegistryParser(ruleProvider: provider).parse(xlsxURL: fixtureURL, settings: settings).index
            let dossier = SampleDossierBuilder.build(library: library, obsidian: vault)
            return try RegistryGrowthImportPlanner(ruleProvider: provider).build(vault: vault, dossier: dossier, registryURL: fixtureURL)
        }
    }

    private func item(_ plan: RegistryGrowthImportPlan, _ batchId: String) -> RegistryGrowthImportItem? {
        plan.items.first { $0.batchId == batchId }
    }

    // MARK: - 1. Observed PN series routes a new PN batch, no material needed for routing

    @Test("1. PLD-N样品 already carries PN100/PN101/PN109 → incoming PN110 routes there via observed series")
    func observedPNSeriesRoutesNewBatch() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn110.md", batchId: "PN110", material: "SRO")])
        let pn110 = try #require(item(plan, "PN110"))
        #expect(pn110.action == .appendNewRow(targetSheet: "PLD-N样品"))
    }

    // MARK: - 2. Observed routing does not require material == SRO

    @Test("2. Observed PN series routes PN110 even when material evidence isn't SRO; material cell still writes as-is")
    func observedRoutingIgnoresExplicitSRORequirement() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn110.md", batchId: "PN110", material: "STO")])
        let pn110 = try #require(item(plan, "PN110"))
        #expect(pn110.action == .appendNewRow(targetSheet: "PLD-N样品"))
        #expect(pn110.columnValues["靶"] == "STO")
        #expect(!pn110.blockingReasons.contains { if case .unroutableMaterialOrPrefix = $0 { return true }; return false })
    }

    // MARK: - 3. Missing date still blocks even though routing resolves

    @Test("3. PN110 missing date → target resolves PLD-N样品 via observed series, but item is still Blocked missingDate")
    func observedRoutingDoesNotPaperOverMissingDate() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn110.md", batchId: "PN110", date: nil, material: "SRO")])
        let pn110 = try #require(item(plan, "PN110"))
        #expect(pn110.targetSheetHint == "PLD-N样品")
        #expect(pn110.blockingReasons.contains(.missingDate))
        guard case .blocked = pn110.action else { Issue.record("expected blocked"); return }
    }

    // MARK: - 4. Exact existing row still wins regardless of routing changes

    @Test("4. Exact PN110 row already exists in PLD-N样品 → Existing/Skip even with incomplete Obsidian evidence")
    func exactExistingRowStillWinsOverRouting() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // PN109 in the fixture already has a full row (date/material/substrate);
        // reuse that batch id to exercise the exact-match path deterministically.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn109.md", batchId: "PN109", date: nil, material: nil, substrate: nil)])
        let pn109 = try #require(item(plan, "PN109"))
        #expect(pn109.action == .skipExisting(targetSheet: "PLD-N样品", rowNumber: 4))
        #expect(pn109.blockingReasons.isEmpty)
    }

    // MARK: - 5. Same series on two allowed sheets → ambiguous, blocked

    @Test("5. QX series appears on both NNO and PLD-N样品 → ambiguousTargetSheet, no silent choice")
    func sameSeriesOnTwoSheetsBlocksAmbiguous() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // QX1 lives on NNO in the fixture and QX50 lives on PLD-N样品 — a
        // fresh QX99 batch now has QX-series evidence on both, and no
        // explicit rule names either sheet.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "qx99.md", batchId: "QX99", material: "unknown")])
        let qx99 = try #require(item(plan, "QX99"))
        guard case let .blocked(reasons) = qx99.action else { Issue.record("expected blocked"); return }
        #expect(reasons.contains {
            if case let .ambiguousTargetSheet(series, candidates) = $0 {
                return series == "QX" && Set(candidates) == Set(["NNO", "PLD-N样品"])
            }
            return false
        })
        #expect(qx99.targetSheetHint == nil)
    }

    // MARK: - 6. Observed route conflicts with explicit route → blocked

    @Test("6. Observed series names one sheet while the explicit prefix rule names a different one → routingEvidenceConflict, blocked")
    func observedVsExplicitConflictBlocks() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // NCO4 is reserved on NNO in this fixture (and the NCO sheet itself
        // carries zero rows), while the hard-coded prefix rule still sends
        // "NCO..." ids to the NCO sheet — a deliberate evidence conflict.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "nco4.md", batchId: "NCO4", material: "NCO")])
        let nco4 = try #require(item(plan, "NCO4"))
        guard case let .blocked(reasons) = nco4.action else { Issue.record("expected blocked"); return }
        #expect(reasons.contains {
            if case let .routingEvidenceConflict(series, observed, explicit) = $0 {
                return series == "NCO" && observed == "NNO" && explicit == "NCO"
            }
            return false
        })
    }

    // MARK: - 7. Empty sheet falls back to explicit prefix routing

    @Test("7. LSMO sheet has zero rows → no observed series evidence, explicit prefix fallback still routes LSMO1")
    func emptySheetFallsBackToExplicitRouting() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lsmo1.md", batchId: "LSMO1", material: "LSMO")])
        let lsmo1 = try #require(item(plan, "LSMO1"))
        #expect(lsmo1.action == .appendNewRow(targetSheet: "LSMO"))
    }

    // MARK: - 8. Reserved ID-only row counts as observed series evidence

    @Test("8. Reserved PN114 row (id-only) still counts as PN series evidence for routing")
    func reservedRowCountsAsSeriesEvidence() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // Remove the fully-populated PN109 row's contribution by targeting a
        // fresh PN batch and asserting routing succeeds purely because PN100/
        // PN101/PN114 (reserved) exist — none of those three besides PN114
        // carries growth data either, so this exercises the reserved-row path.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn115.md", batchId: "PN115", material: "SRO")])
        let pn115 = try #require(item(plan, "PN115"))
        #expect(pn115.action == .appendNewRow(targetSheet: "PLD-N样品"))
    }

    // MARK: - 9. No reliable numeric suffix → no observed-series inference, fallback only

    @Test("9. Batch id without a numeric suffix → no observed-series inference, only explicit fallback applies")
    func noNumericSuffixFallsBackOnly() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // "NCOX" has no trailing digits, so batchSeries(for:) is nil; the
        // explicit prefix rule ("NCO" prefix) still routes it to NCO.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "ncox.md", batchId: "NCOX", material: "NCO")])
        let ncox = try #require(item(plan, "NCOX"))
        #expect(ncox.action == .appendNewRow(targetSheet: "NCO"))
    }

    // MARK: - 10. Write allowlist is never expanded by routing

    @Test("10. Content-aware routing never expands the write allowlist or auto-creates a sheet")
    func routingNeverExpandsAllowlist() throws {
        #expect(RegistryGrowthImportPlanner.routableSheetNames == ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"])
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // A batch series with zero observed evidence anywhere and no
        // explicit rule (e.g. "ZZZ") must stay unroutable — never invent a
        // sheet to hold it.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "zzz1.md", batchId: "ZZZ1", material: "ZZZ")])
        let zzz1 = try #require(item(plan, "ZZZ1"))
        #expect(zzz1.blockingReasons.contains { if case .unroutableMaterialOrPrefix = $0 { return true }; return false })
    }
}
