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
        // A clean skipExisting batch (no Obsidian/Registry conflict warning)
        // never occupies plan.items — it's synchronization history, counted
        // in existingCount instead (see RegistryGrowthImportPlanner.isCleanExisting).
        #expect(item(plan, "PN109") == nil)
        #expect(plan.existingCount == 1)
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
            "NNO": RegistrySheetProfile(seriesObserved: ["QX"], rowsBySeries: ["QX": [1: []]]),
            "PLD-N样品": RegistrySheetProfile(seriesObserved: ["QX"], rowsBySeries: ["QX": [50: []]])
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
            "NNO": RegistrySheetProfile(seriesObserved: ["NCO"], rowsBySeries: ["NCO": [4: []]])
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

    // MARK: - Multi-series sheet profile invariant (Human Identifier layer)
    //
    // A Registry "编号" cell may name more than one human identifier
    // (`"PN110/SRO1"`), and a routable sheet legitimately observes more
    // than one series as a result — "one sheet = one series" is not an
    // invariant of this model. See
    // `RegistryGrowthXLSXFixture.buildForMultiSeriesSheet`: PLD-N样品
    // carries `PN110/SRO1` (populated) and `PN111/SRO2` (reserved), so its
    // profile validly observes both `PN` and `SRO`.

    private func makeMultiSeriesFixtureRegistry() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-multi-series-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForMultiSeriesSheet(to: url)
        return url
    }

    private func multiSeriesProfiles(registryURL: URL) throws -> [String: RegistrySheetProfile] {
        let snapshots = try RegistryGrowthImportPlanner.scanRoutableSheets(registryURL: registryURL)
        return RegistrySheetProfile.buildProfiles(from: snapshots)
    }

    @Test("Multi-1. A sheet observing both PN and SRO is a valid profile, not invalid/mixed")
    func multiSeriesSheetProfileIsValid() throws {
        let url = try makeMultiSeriesFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let profiles = try multiSeriesProfiles(registryURL: url)
        #expect(profiles["PLD-N样品"]?.seriesObserved == ["PN", "SRO"])
    }

    // MARK: - G. incoming PN114 + SRO routes to PLD-N样品, no Unroutable

    @Test("G. incoming PN114 (material SRO) routes to PLD-N样品 despite its multi-series profile")
    func newPNBatchRoutesOnMultiSeriesSheet() throws {
        let url = try makeMultiSeriesFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn114.md", batchId: "PN114", material: "SRO")])
        let pn114 = try #require(item(plan, "PN114"))
        #expect(pn114.action == .appendNewRow(targetSheet: "PLD-N样品"))
    }

    // MARK: - H. incoming PN110 matches the composite row exactly (Existing)

    @Test("H. incoming PN110 exact-matches the composite PN110/SRO1 row → Existing (skip)")
    func incomingPNMatchesCompositeRowExactly() throws {
        let url = try makeMultiSeriesFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn110.md", batchId: "PN110", date: nil, material: nil, substrate: nil)])
        #expect(item(plan, "PN110") == nil)
        #expect(plan.existingCount == 1)
    }

    // MARK: - I. incoming SRO1 matches the SAME composite row

    @Test("I. incoming SRO1 exact-matches the same composite PN110/SRO1 row → Existing (skip)")
    func incomingSROMatchesSameCompositeRow() throws {
        let url = try makeMultiSeriesFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "sro1.md", batchId: "SRO1", date: nil, material: nil, substrate: nil)])
        #expect(item(plan, "SRO1") == nil)
        #expect(plan.existingCount == 1)
    }

    // MARK: - J/K. Composite cell is not a duplicate; the same identifier on two rows is

    @Test("J. PN110/SRO1 in one row is NOT a duplicate")
    func compositeCellIsNotADuplicate() throws {
        let url = try makeMultiSeriesFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn110.md", batchId: "PN110")])
        #expect(!(item(plan, "PN110")?.blockingReasons.contains { if case .duplicateRegistryRow = $0 { return true }; return false } ?? false))
    }

    @Test("K. PN110 repeated on a second row (already used inside PN110/SRO1) is Blocked as a duplicate")
    func sameIdentifierOnTwoRowsIsBlockedAsDuplicate() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-dup-identifier-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForDuplicateHumanIdentifier(to: url)
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn110.md", batchId: "PN110")])
        let pn110 = try #require(item(plan, "PN110"))
        guard case let .blocked(reasons) = pn110.action else { Issue.record("expected blocked"); return }
        #expect(reasons.contains { if case .duplicateRegistryRow = $0 { return true }; return false })
    }

    // MARK: - L. Reserved composite row still fills

    @Test("L. A reserved composite row (PN111/SRO2, ID-only) still fills via fillReservedRow")
    func reservedCompositeRowStillFills() throws {
        let url = try makeMultiSeriesFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn111.md", batchId: "PN111", material: "SRO")])
        let pn111 = try #require(item(plan, "PN111"))
        guard case let .fillReservedRow(sheet, rowNumber) = pn111.action else {
            Issue.record("expected fillReservedRow, got \(pn111.action)")
            return
        }
        #expect(sheet == "PLD-N样品")
        #expect(rowNumber > 0)
    }

    // MARK: - N. A populated row with a malformed identifier fragment must
    // never silently disappear through Existing compaction.

    @Test("N. Populated \"PN110/???\" row + incoming PN110 → Blocked, not compacted away")
    func populatedRowWithMalformedFragmentStaysVisible() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-populated-malformed-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForPopulatedMalformedRow(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn110.md", batchId: "PN110", date: nil, material: nil, substrate: nil)])

        // Must NOT be silently compacted out of the preview.
        let pn110 = try #require(item(plan, "PN110"))
        #expect(plan.existingCount == 0)

        // Must be a Blocked diagnostic, never executable, never overwritten.
        guard case let .blocked(reasons) = pn110.action else {
            Issue.record("expected blocked, got \(pn110.action)")
            return
        }
        #expect(!pn110.isExecutable)
        #expect(reasons.contains { reason in
            if case let .populatedRowHasMalformedIdentifier(sheet, _, malformedTokens) = reason {
                return sheet == "PLD-N样品" && malformedTokens == ["???"]
            }
            return false
        })
    }
}
