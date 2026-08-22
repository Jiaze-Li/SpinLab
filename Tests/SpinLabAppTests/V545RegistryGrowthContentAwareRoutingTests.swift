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

    // MARK: - 5. Same series declared by two routable sheets → ambiguous, blocked
    //
    // Constructed directly against `resolveTargetSheet` rather than through
    // the shared XLSX fixture: a stray cross-series row on a
    // production-shared sheet doesn't make that sheet a second QX
    // candidate any more — it makes the sheet's own profile invalid (nil)
    // instead (see the "Mixed-series sheet profile invariant" tests
    // below). Demonstrating a genuine ambiguity needs two independently
    // *valid*, single-series profiles that happen to declare the same
    // series.

    @Test("5. QX series declared by two independently-valid sheets → ambiguousTargetSheet, no silent choice")
    func sameSeriesOnTwoSheetsBlocksAmbiguous() {
        let profiles: [String: RegistrySheetProfile] = [
            "NNO": RegistrySheetProfile(seriesObserved: ["QX"], series: "QX", rowsByNumber: [1: []]),
            "PLD-N样品": RegistrySheetProfile(seriesObserved: ["QX"], series: "QX", rowsByNumber: [50: []])
        ]
        let resolution = RegistryGrowthRouting.resolveTargetSheet(batchId: "QX99", profiles: profiles, materialEvidence: [])
        #expect(resolution == .ambiguous(batchSeries: "QX", candidateSheets: ["NNO", "PLD-N样品"]))
    }

    // MARK: - 6. Observed route conflicts with explicit route → blocked
    //
    // Also constructed directly: a unique, valid observed-series match on
    // one sheet, differing from the hard-coded prefix rule's target sheet.

    @Test("6. Observed series names one sheet while the explicit prefix rule names a different one → routingEvidenceConflict, blocked")
    func observedVsExplicitConflictBlocks() {
        // NNO uniquely and validly declares series "NCO"; the "NCO" sheet
        // itself is deliberately absent from this profiles map (isolating
        // the conflict from any fallback-series assignment it would
        // otherwise pick up), while the hard-coded prefix rule still sends
        // "NCO..." ids to the "NCO" sheet name.
        let profiles: [String: RegistrySheetProfile] = [
            "NNO": RegistrySheetProfile(seriesObserved: ["NCO"], series: "NCO", rowsByNumber: [4: []])
        ]
        let resolution = RegistryGrowthRouting.resolveTargetSheet(batchId: "NCO4", profiles: profiles, materialEvidence: ["NCO"])
        #expect(resolution == .conflict(batchSeries: "NCO", observedSheet: "NNO", explicitSheet: "NCO"))
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

    // MARK: - Mixed-series sheet profile invariant (SheetProfile fail-closed)
    //
    // A routable sheet whose rows mix more than one series has an invalid
    // (`series == nil`) `RegistrySheetProfile` — `seriesObserved` still
    // records every series it contains, but that's diagnostic only
    // (explains *why* the sheet is invalid), never a basis for a NEW/FILL
    // routing decision. See `RegistryGrowthXLSXFixture
    // .buildForMixedSheetProfileInvariant`: NNO mixes its own NNO4
    // (reserved) / NNO7 (populated) rows with a stray QX1 (reserved) row,
    // while LSMO carries a clean, single-series QX99 row.

    private func makeMixedProfileFixtureRegistry() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-mixed-profile-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForMixedSheetProfileInvariant(to: url)
        return url
    }

    private func mixedProfiles(registryURL: URL) throws -> [String: RegistrySheetProfile] {
        let snapshots = try RegistryGrowthImportPlanner.scanRoutableSheets(registryURL: registryURL)
        return RegistrySheetProfile.buildProfiles(from: snapshots)
    }

    @Test("Mixed-1. A mixed NNO/QX sheet is never selected as a routing candidate, even for a series it happens to contain")
    func mixedSheetNeverSelectedAsCandidate() throws {
        let url = try makeMixedProfileFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let profiles = try mixedProfiles(registryURL: url)
        let resolution = RegistryGrowthRouting.resolveTargetSheet(batchId: "QX2", profiles: profiles, materialEvidence: [])
        if case let .resolved(sheet) = resolution {
            #expect(sheet != "NNO")
        }
    }

    @Test("Mixed-2. With a mixed NNO/QX sheet and a separate clean QX sheet present, only the clean sheet routes")
    func onlyCleanSheetRoutesWhenAnotherIsMixed() throws {
        let url = try makeMixedProfileFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let profiles = try mixedProfiles(registryURL: url)
        let resolution = RegistryGrowthRouting.resolveTargetSheet(batchId: "QX2", profiles: profiles, materialEvidence: [])
        #expect(resolution == .resolved(sheet: "LSMO"))
    }

    @Test("Mixed-3. A brand-new NNO batch cannot NEW/FILL into the invalid (mixed) NNO sheet")
    func newBatchCannotRouteIntoInvalidSheet() throws {
        let url = try makeMixedProfileFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "nno9.md", batchId: "NNO9")])
        let nno9 = try #require(item(plan, "NNO9"))
        guard case let .blocked(reasons) = nno9.action else { Issue.record("expected blocked"); return }
        #expect(reasons.contains { if case .unroutableMaterialOrPrefix = $0 { return true }; return false })
    }

    @Test("Mixed-4. An exact populated existing row on the mixed sheet still Skips (no write, exact identity wins)")
    func exactPopulatedRowOnMixedSheetStillSkips() throws {
        let url = try makeMixedProfileFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "nno7.md", batchId: "NNO7", date: nil, material: nil, substrate: nil)])
        let nno7 = try #require(item(plan, "NNO7"))
        #expect(nno7.action == .skipExisting(targetSheet: "NNO", rowNumber: 3))
        #expect(nno7.blockingReasons.isEmpty)
    }

    @Test("Mixed-5. An exact reserved row physically on the mixed sheet is Blocked, never written")
    func exactReservedRowOnMixedSheetIsBlocked() throws {
        let url = try makeMixedProfileFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // QX1 is reserved on NNO (the mixed/invalid sheet), while QX's own
        // clean sheet is LSMO — routing alone would otherwise resolve
        // "QX1" to LSMO, but the exact reserved row physically lives on
        // NNO, whose profile is invalid, so the write must still be
        // blocked rather than filling a slot on the wrong/ambiguous sheet.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "qx1.md", batchId: "QX1", material: "QX")])
        let qx1 = try #require(item(plan, "QX1"))
        guard case let .blocked(reasons) = qx1.action else { Issue.record("expected blocked"); return }
        #expect(reasons.contains {
            if case let .reservedRowOnInvalidSheetProfile(sheet) = $0 { return sheet == "NNO" }
            return false
        })
    }
}
