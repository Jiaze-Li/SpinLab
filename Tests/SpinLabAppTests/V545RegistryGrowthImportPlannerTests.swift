import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5A: `RegistryGrowthImportPlanner` coverage. The planner never
/// writes anything — every test here reads a fresh fixture copy and only
/// asserts on the returned `RegistryGrowthImportPlan`. Registry mutation
/// coverage lives in `V545RegistryGrowthMutationServiceTests`.
@Suite("V5.4.5 RegistryGrowthImportPlanner")
struct V545RegistryGrowthImportPlannerTests {
    // MARK: - Fixture plumbing

    private func makeFixtureRegistry(includeLSMO: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-registry-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.build(includeLSMO: includeLSMO, to: url)
        return url
    }

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    private func makeNote(
        path: String,
        batchId: String?,
        date: String? = "2026-08-20",
        material: String? = "LNO",
        substrate: String? = "STO(001)",
        temperature: String? = "650",
        distance: String? = "45",
        pressure: String? = "100",
        energy: String? = "1.2",
        pulse: String? = "200/3000"
    ) -> ObsidianNoteRecord {
        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [:]
        if let date { growthClaims[.growthDate] = claim(date, notePath: path, rawKey: "date") }
        if let temperature { growthClaims[.growthTemperature] = claim(temperature, notePath: path, rawKey: "temperature") }
        if let distance { growthClaims[.targetSubstrateDistance] = claim(distance, notePath: path, rawKey: "sample height") }
        if let pressure { growthClaims[.oxygenPressure] = claim(pressure, notePath: path, rawKey: "pressure") }
        if let energy { growthClaims[.laserEnergy] = claim(energy, notePath: path, rawKey: "energy") }
        if let pulse { growthClaims[.pulseCount] = claim(pulse, notePath: path, rawKey: "pulse") }

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

    private func makeVault(notes: [ObsidianNoteRecord], diagnostics: [ObsidianDiagnostic] = []) -> ObsidianVaultIndex {
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
            diagnostics: diagnostics,
            notes: notes
        )
    }

    private func buildPlan(fixtureURL: URL, notes: [ObsidianNoteRecord], diagnostics: [ObsidianDiagnostic] = []) throws -> RegistryGrowthImportPlan {
        let vault = makeVault(notes: notes, diagnostics: diagnostics)
        let settings = LibrarySettings(
            rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil,
            registrySourcePath: fixtureURL.path, backupPath: nil, backupLastSyncedAt: nil,
            allowedBatchPrefixes: [], lastRefreshAt: nil
        )
        // Inject an isolated bundled-rules provider rather than the mutable
        // `SpinLabRuleProvider.shared` singleton — other concurrently
        // running Rules tests reconfigure that global, and this parse would
        // otherwise intermittently race it (docs/architecture/TESTING_STRATEGY.md).
        // The planner now also needs the same provider (its own
        // `LibrarySubstrateParser` for `expectedSampleKeys`), so both must
        // share one `withBundledRules` call rather than the planner
        // defaulting to the shared singleton.
        return try withBundledRules { provider in
            let library = try LibraryRegistryParser(ruleProvider: provider).parse(xlsxURL: fixtureURL, settings: settings).index
            let dossier = SampleDossierBuilder.build(library: library, obsidian: vault)
            return try RegistryGrowthImportPlanner(ruleProvider: provider).build(vault: vault, dossier: dossier, registryURL: fixtureURL)
        }
    }

    private func item(_ plan: RegistryGrowthImportPlan, _ batchId: String) -> RegistryGrowthImportItem? {
        plan.items.first { $0.batchId == batchId }
    }

    // MARK: - 1. New LNO row append

    @Test("1. New batch with no existing Registry row → appendNewRow")
    func appendNewLNORow() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        let lno2 = try #require(item(plan, "LNO2"))
        #expect(lno2.action == .appendNewRow(targetSheet: "LNO"))
        #expect(lno2.columnValues["编号"] == "LNO2")
        #expect(lno2.columnValues["日期"] == "2026.8.20")
        #expect(lno2.columnValues["靶"] == "LNO")
        #expect(lno2.columnValues["substrate"] == "STO(001)")
        #expect(lno2.columnValues["生长温度"] == "650")
    }

    @Test("1b. A recognizable substrate produces a non-empty expectedSampleKeys for an executable item")
    func appendNewLNORowHasExpectedSampleKeys() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno2.md", batchId: "LNO2")])
        let lno2 = try #require(item(plan, "LNO2"))
        #expect(lno2.isExecutable)
        #expect(!lno2.expectedSampleKeys.isEmpty)
        #expect(lno2.expectedSampleKeys.contains { $0.hasPrefix("LNO2|") && $0.contains("STO") })
    }

    // MARK: - 2. New NCO row append

    @Test("2. New NCO batch → appendNewRow(NCO)")
    func appendNewNCORow() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "nco2.md", batchId: "NCO2", material: "NCO")])
        let nco2 = try #require(item(plan, "NCO2"))
        #expect(nco2.action == .appendNewRow(targetSheet: "NCO"))
    }

    // MARK: - 3. PN + SRO → PLD-N样品 (header-driven mapping)

    @Test("3. PN batch with Obsidian material=SRO routes to PLD-N样品, header-driven")
    func pnSRORoutesToPLDN() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn2.md", batchId: "PN2", material: "SRO")])
        let pn2 = try #require(item(plan, "PN2"))
        #expect(pn2.action == .appendNewRow(targetSheet: "PLD-N样品"))
        // PLD-N样品's schema puts 靶/日期 in different columns than the
        // material sheets and has an unrelated "其他备注" column at the
        // position 生长 occupies elsewhere — mapping must be header-driven.
        #expect(pn2.columnValues["靶"] == "SRO")
        #expect(pn2.columnValues["日期"] == "2026.8.20")
        #expect(pn2.columnValues["其他备注"] == nil)
        #expect(pn2.columnValues["生长"] == nil)
    }

    // MARK: - 4. NNO reserved-ID row fill

    @Test("4. Reserved NNO4 row (id-only) → fillReservedRow, not append")
    func fillsReservedRow() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "nno4.md", batchId: "NNO4", material: "NNO")])
        let nno4 = try #require(item(plan, "NNO4"))
        #expect(nno4.action == .fillReservedRow(targetSheet: "NNO", rowNumber: 2))
    }

    @Test("4b. Reserved row with only some growth evidence leaves the rest blank, not guessed")
    func reservedRowPartialEvidenceLeavesBlanks() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "nno4.md", batchId: "NNO4", material: "NNO", temperature: "600", distance: nil, pressure: nil, energy: nil, pulse: nil)
        ])
        let nno4 = try #require(item(plan, "NNO4"))
        #expect(nno4.columnValues["生长温度"] == "600")
        #expect(nno4.columnValues["靶机距"] == nil)
        let blankHeaders = Set(nno4.blankColumns.map(\.columnHeader))
        #expect(blankHeaders.contains("靶机距"))
        #expect(blankHeaders.contains("氧压"))
        #expect(blankHeaders.contains("能量"))
        #expect(blankHeaders.contains("预打/生长次数"))
        // No-evidence warnings must name the humanized Registry header, never
        // the internal ObsidianGrowthField.rawValue.
        let warningsText = nno4.warnings.joined(separator: "\n")
        #expect(warningsText.contains("靶机距"))
        #expect(warningsText.contains("氧压"))
        #expect(warningsText.contains("能量"))
        #expect(warningsText.contains("预打/生长次数"))
        #expect(!warningsText.contains("targetSubstrateDistance"))
        #expect(!warningsText.contains("oxygenPressure"))
        #expect(!warningsText.contains("laserEnergy"))
        #expect(!warningsText.contains("pulseCount"))
    }

    // MARK: - 5. Existing normal ID → skip

    @Test("5. Existing fully-populated NCO1 row → skipExisting, never overwritten")
    func skipsExistingNormalRow() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "nco1.md", batchId: "NCO1", date: "2099-01-01", material: "NCO")])
        let nco1 = try #require(item(plan, "NCO1"))
        #expect(nco1.action == .skipExisting(targetSheet: "NCO", rowNumber: 2))
        #expect(nco1.columnValues.isEmpty)
        #expect(!nco1.isExecutable)
    }

    @Test("5b. Existing PN1(SRO) row → skipExisting on PLD-N样品")
    func skipsExistingPN1() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn1.md", batchId: "PN1", material: "SRO")])
        let pn1 = try #require(item(plan, "PN1"))
        #expect(pn1.action == .skipExisting(targetSheet: "PLD-N样品", rowNumber: 2))
    }

    // MARK: - 5c/5d. Existing normal row identification never depends on
    // Obsidian completeness (Phase 5A review blocker #1)

    @Test("5c. Existing PN1(SRO) row + Obsidian note missing date → skipExisting, not blocked(missingDate)")
    func skipsExistingPN1EvenWithMissingObsidianDate() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn1.md", batchId: "PN1", date: nil, material: "SRO")])
        let pn1 = try #require(item(plan, "PN1"))
        #expect(pn1.action == .skipExisting(targetSheet: "PLD-N样品", rowNumber: 2))
        #expect(pn1.blockingReasons.isEmpty)
    }

    @Test("5d. Existing PN1(SRO) row + Obsidian stub missing material/substrate → still skipExisting")
    func skipsExistingPN1EvenWithStubObsidianNote() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn1.md", batchId: "PN1", material: nil, substrate: nil)])
        let pn1 = try #require(item(plan, "PN1"))
        #expect(pn1.action == .skipExisting(targetSheet: "PLD-N样品", rowNumber: 2))
        #expect(pn1.blockingReasons.isEmpty)
    }

    // MARK: - 6. Duplicate Registry ID → blocked

    @Test("6. Duplicate LNO9 rows in Registry → blocked, no winner guessed")
    func duplicateRegistryRowsBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno9.md", batchId: "LNO9", material: "LNO")])
        let lno9 = try #require(item(plan, "LNO9"))
        guard case let .blocked(reasons) = lno9.action else { Issue.record("expected blocked"); return }
        #expect(reasons.contains { if case .duplicateRegistryRow(let sheet, let rows) = $0 { return sheet == "LNO" && rows == [4, 5] }; return false })
    }

    // MARK: - 7. Missing date → blocked

    @Test("7. Missing Obsidian date → blocked, never mtime/today/guessed")
    func missingDateBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno6.md", batchId: "LNO6", date: nil, material: "LNO")])
        let lno6 = try #require(item(plan, "LNO6"))
        #expect(lno6.blockingReasons.contains(.missingDate))
    }

    // MARK: - 8. Missing target sheet → blocked

    @Test("8. Routed sheet absent from workbook → blocked, never auto-created")
    func missingTargetSheetBlocked() throws {
        let url = try makeFixtureRegistry(includeLSMO: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lsmo1.md", batchId: "LSMO1", material: "LSMO")])
        let lsmo1 = try #require(item(plan, "LSMO1"))
        #expect(lsmo1.blockingReasons.contains(.targetSheetNotFound(sheetName: "LSMO")))
    }

    // MARK: - 9. Obsidian internal conflict → blocked

    @Test("9. Two notes disagreeing on growth date → obsidianInternalConflict, blocked")
    func internalDateConflictBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno8a.md", batchId: "LNO8", date: "2026-08-01", material: "LNO"),
            makeNote(path: "lno8b.md", batchId: "LNO8", date: "2026-08-02", material: "LNO")
        ])
        let lno8 = try #require(item(plan, "LNO8"))
        #expect(lno8.blockingReasons.contains(.obsidianInternalConflict(field: "日期")))
        let text = RegistryGrowthImportPresentation.blockingReasonsText(for: lno8)
        #expect(text.contains("日期"))
        #expect(!text.contains("growthDate"))
    }

    @Test("9b. Two notes disagreeing on a secondary growth field → blocked, no winner picked")
    func internalSecondaryFieldConflictBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno7a.md", batchId: "LNO7", material: "LNO", temperature: "600"),
            makeNote(path: "lno7b.md", batchId: "LNO7", material: "LNO", temperature: "650")
        ])
        let lno7 = try #require(item(plan, "LNO7"))
        #expect(lno7.blockingReasons.contains(.obsidianInternalConflict(field: "生长温度")))
        let text = RegistryGrowthImportPresentation.blockingReasonsText(for: lno7)
        #expect(text.contains("生长温度"))
        #expect(!text.contains("growthTemperature"))
    }

    // MARK: - 10. Unsupported material/prefix → blocked

    @Test("10. Unroutable batch prefix → blocked, never guessed into a sheet")
    func unroutablePrefixBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "xyz1.md", batchId: "XYZ1", material: "XYZ")])
        let xyz1 = try #require(item(plan, "XYZ1"))
        #expect(xyz1.blockingReasons.contains { if case .unroutableMaterialOrPrefix = $0 { return true }; return false })
    }

    @Test("10b. PN prefix without confirmed SRO evidence still routes via observed PN series (content-aware routing) — content-aware routing tests own the SRO-vs-observed-series distinction in detail")
    func pnWithoutSROEvidenceStillRoutesViaObservedSeries() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // The fixture's PLD-N样品 sheet already carries PN1, so the PN
        // series is observed there — content-aware routing (see
        // V545RegistryGrowthContentAwareRoutingTests) no longer requires
        // material == SRO once Registry history already says where the PN
        // series belongs. The old prefix/material rule stays as fallback
        // evidence only, exercised in isolation by that suite's
        // empty-sheet-fallback test.
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "pn9.md", batchId: "PN9", material: "STO")])
        let pn9 = try #require(item(plan, "PN9"))
        #expect(pn9.action == .appendNewRow(targetSheet: "PLD-N样品"))
        #expect(pn9.columnValues["靶"] == "STO")
    }

    @Test("10c. Missing material evidence entirely → blocked")
    func missingMaterialEvidenceBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno10.md", batchId: "LNO10", material: nil)])
        let lno10 = try #require(item(plan, "LNO10"))
        #expect(lno10.blockingReasons.contains(.missingMaterialEvidence))
    }

    @Test("10d. Substrate evidence present but unrecognizable by the canonical parser → blocked, not merely a blank column")
    func unresolvedSubstrateIdentityBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // Date and material are complete; only the substrate text is
        // something the real (bundled) classifier has no material/
        // orientation/treatment signal for at all.
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno11.md", batchId: "LNO11", material: "LNO", substrate: "abcdefg")
        ])
        let lno11 = try #require(item(plan, "LNO11"))
        #expect(lno11.blockingReasons.contains { if case .unresolvedSubstrateIdentity = $0 { return true }; return false })
        #expect(lno11.expectedSampleKeys.isEmpty)
        #expect(!lno11.isExecutable)
    }

    // MARK: - 11. Composite Registry 编号 must not hide Existing conflicts
    // (PR #169 cumulative-review repair item 1)

    @Test("11. Composite 编号 (PN110/SRO1): matched via the PN110 peer, every genuine secondary-field disagreement surfaces, never compacted")
    func compositeIdentifierExistingConflictsSurfacedViaPN() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-registry-composite-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForCompositeIdentifierExistingRow(to: url)

        // Registry row (PN110/SRO1): temp=800, distance=40, pressure=80,
        // pulse=50/1000. Obsidian (batchId "PN110", which never exact-joins
        // the composite "PN110/SRO1" Library batch id) claims different
        // values for all four.
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(
                path: "pn110.md", batchId: "PN110", date: "2026-08-10", material: "SRO", substrate: "STO(001)",
                temperature: "900", distance: "60", pressure: "120", energy: "2.0", pulse: "70/1200"
            )
        ])
        let pn110 = try #require(item(plan, "PN110"))
        #expect(pn110.action == .skipExisting(targetSheet: "PLD-N样品", rowNumber: 2))
        let fields = Set(pn110.existingDifferences.map(\.field))
        #expect(fields.contains(.growthTemperature))
        #expect(fields.contains(.targetSubstrateDistance))
        #expect(fields.contains(.oxygenPressure))
        #expect(fields.contains(.pulseCount))
        #expect(pn110.existingDifferences.count == 4)
        // Never compacted into clean existingCount — item stays visible.
        #expect(plan.items.contains { $0.batchId == "PN110" })
        #expect(!pn110.isExecutable)
        // No Registry mutation occurs merely because a conflict was
        // detected — the planner never writes; skipExisting carries no
        // column values to write.
        #expect(pn110.columnValues.isEmpty)
    }

    @Test("11b. Same physical composite row reached via the other peer identifier (SRO1)")
    func compositeIdentifierExistingConflictsSurfacedViaSRO() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-registry-composite-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForCompositeIdentifierExistingRow(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(
                path: "sro1.md", batchId: "SRO1", date: "2026-08-10", material: "SRO", substrate: "STO(001)",
                temperature: "900", distance: nil, pressure: nil, energy: "2.0", pulse: nil
            )
        ])
        let sro1 = try #require(item(plan, "SRO1"))
        #expect(sro1.action == .skipExisting(targetSheet: "PLD-N样品", rowNumber: 2))
        #expect(sro1.existingDifferences.contains { $0.field == .growthTemperature })
    }

    @Test("11c. Semantically-equal formatting variants remain clean — no textual false conflict from unit-format differences")
    func compositeIdentifierExistingRowFormatVariantsStayClean() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-registry-composite-clean-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForCompositeIdentifierExistingRow(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(
                path: "pn110-clean.md", batchId: "PN110", date: "2026-08-10", material: "SRO", substrate: "STO(001)",
                temperature: "800 °C", distance: "40 mm", pressure: "80 Pa", energy: "2.0", pulse: "50 (2Hz) /1000 (2Hz)"
            )
        ])
        // Compacted out of the preview entirely — a genuinely clean
        // Existing row, not merely "no differences we happened to check".
        #expect(item(plan, "PN110") == nil)
    }

    // MARK: - 12. New append/fill must not create UNKNOWN substrate identity
    // (PR #169 cumulative-review repair item 2)

    @Test("12a. substrate='111' (orientation-only signal) → BLOCKED, never produces an executable UNKNOWN-material sampleKey")
    func incompleteSubstrateOrientationOnlyBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno20.md", batchId: "LNO20", material: "LNO", substrate: "111")
        ])
        let lno20 = try #require(item(plan, "LNO20"))
        #expect(lno20.blockingReasons.contains {
            if case let .incompleteSubstrateIdentity(_, missingMaterial, missingOrientation) = $0 {
                return missingMaterial && !missingOrientation
            }
            return false
        })
        #expect(!lno20.isExecutable)
        #expect(!lno20.expectedSampleKeys.contains { $0.contains("UNKNOWN") })
    }

    @Test("12b. substrate='HF' (treatment-only signal) → BLOCKED")
    func incompleteSubstrateTreatmentOnlyBlocked() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno21.md", batchId: "LNO21", material: "LNO", substrate: "HF")
        ])
        let lno21 = try #require(item(plan, "LNO21"))
        #expect(lno21.blockingReasons.contains {
            if case let .incompleteSubstrateIdentity(_, missingMaterial, missingOrientation) = $0 {
                return missingMaterial && missingOrientation
            }
            return false
        })
        #expect(!lno21.isExecutable)
    }

    @Test("12c. substrate='STO(111)' (material + orientation both resolve) → remains eligible")
    func completeSubstrateMaterialAndOrientationEligible() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno22.md", batchId: "LNO22", material: "LNO", substrate: "STO(111)")
        ])
        let lno22 = try #require(item(plan, "LNO22"))
        #expect(!lno22.blockingReasons.contains { if case .incompleteSubstrateIdentity = $0 { return true }; return false })
        #expect(lno22.isExecutable)
    }

    @Test("12d. substrate='HF STO(001)' (processing + material + orientation) → remains eligible")
    func completeSubstrateWithProcessingEligible() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "lno23.md", batchId: "LNO23", material: "LNO", substrate: "HF STO(001)")
        ])
        let lno23 = try #require(item(plan, "LNO23"))
        #expect(!lno23.blockingReasons.contains { if case .incompleteSubstrateIdentity = $0 { return true }; return false })
        #expect(lno23.isExecutable)
    }

    @Test("12e. Pre-existing historical row behavior is unchanged — this check only applies to a NEW append/fill item")
    func incompleteSubstrateCheckDoesNotAffectExistingRows() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        // NCO1 already exists (fixture row), fully populated — this stays
        // skipExisting regardless of what Obsidian's substrate text is,
        // since the incomplete-substrate-identity check is scoped to the
        // no-existing-row / reserved-row branch only.
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(path: "nco1.md", batchId: "NCO1", material: "NCO", substrate: "111")
        ])
        let nco1 = try #require(item(plan, "NCO1"))
        #expect(nco1.action == .skipExisting(targetSheet: "NCO", rowNumber: 2))
        #expect(!nco1.blockingReasons.contains { if case .incompleteSubstrateIdentity = $0 { return true }; return false })
    }

    // MARK: - 13. Required Registry headers must exist before an item is
    // executable (PR #169 cumulative-review repair item 3)

    private func headerVariantFixture(excluding excludedHeader: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-registry-header-\(UUID().uuidString).xlsx")
        let headers = RegistryGrowthXLSXFixture.materialSheetHeaders.filter { $0 != excludedHeader }
        try RegistryGrowthXLSXFixture.buildForHeaderVariant(lnoHeaders: headers, to: url)
        return url
    }

    @Test("13a. Target sheet lacks 日期 → BLOCKED")
    func missingDateHeaderBlocks() throws {
        let url = try headerVariantFixture(excluding: "日期")
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno30.md", batchId: "LNO30", material: "LNO")])
        let lno30 = try #require(item(plan, "LNO30"))
        #expect(lno30.blockingReasons.contains {
            if case let .missingRequiredRegistryHeader(sheet, field, _) = $0 { return sheet == "LNO" && field == .date }
            return false
        })
        #expect(!lno30.isExecutable)
    }

    @Test("13b. Target sheet lacks 靶 → BLOCKED")
    func missingMaterialHeaderBlocks() throws {
        let url = try headerVariantFixture(excluding: "靶")
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno31.md", batchId: "LNO31", material: "LNO")])
        let lno31 = try #require(item(plan, "LNO31"))
        #expect(lno31.blockingReasons.contains {
            if case let .missingRequiredRegistryHeader(sheet, field, _) = $0 { return sheet == "LNO" && field == .material }
            return false
        })
        #expect(!lno31.isExecutable)
    }

    @Test("13c. Target sheet lacks substrate/衬底 → BLOCKED")
    func missingSubstrateHeaderBlocks() throws {
        let url = try headerVariantFixture(excluding: "substrate")
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno32.md", batchId: "LNO32", material: "LNO")])
        let lno32 = try #require(item(plan, "LNO32"))
        #expect(lno32.blockingReasons.contains {
            if case let .missingRequiredRegistryHeader(sheet, field, _) = $0 { return sheet == "LNO" && field == .substrate }
            return false
        })
        #expect(!lno32.isExecutable)
    }

    @Test("13d. Target sheet lacks 编号 → BLOCKED")
    func missingBatchIdHeaderBlocks() throws {
        let url = try headerVariantFixture(excluding: "编号")
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno33.md", batchId: "LNO33", material: "LNO")])
        let lno33 = try #require(item(plan, "LNO33"))
        #expect(lno33.blockingReasons.contains {
            if case let .missingRequiredRegistryHeader(sheet, field, _) = $0 { return sheet == "LNO" && field == .batchId }
            return false
        })
        #expect(!lno33.isExecutable)
    }

    @Test("13e. Alternate confirmed substrate alias (衬底 instead of substrate) still works — not blocked")
    func alternateSubstrateAliasHeaderWorks() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V545-registry-header-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        let headers = RegistryGrowthXLSXFixture.materialSheetHeaders.map { $0 == "substrate" ? "衬底" : $0 }
        try RegistryGrowthXLSXFixture.buildForHeaderVariant(lnoHeaders: headers, to: url)
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno34.md", batchId: "LNO34", material: "LNO")])
        let lno34 = try #require(item(plan, "LNO34"))
        #expect(!lno34.blockingReasons.contains { if case .missingRequiredRegistryHeader = $0 { return true }; return false })
        #expect(lno34.isExecutable)
        #expect(lno34.columnValues["衬底"] != nil)
    }

    @Test("13f. Missing optional secondary header (氧压) alone does not newly block the item")
    func missingOptionalSecondaryHeaderDoesNotBlock() throws {
        let url = try headerVariantFixture(excluding: "氧压")
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(path: "lno35.md", batchId: "LNO35", material: "LNO")])
        let lno35 = try #require(item(plan, "LNO35"))
        #expect(!lno35.blockingReasons.contains { if case .missingRequiredRegistryHeader = $0 { return true }; return false })
        #expect(lno35.isExecutable)
        #expect(lno35.columnValues["氧压"] == nil)
    }

    // MARK: - Unattached diagnostics

    @Test("Notes with no resolvable batch identity surface as plan diagnostics, not phantom items")
    func unresolvedBatchDiagnosticSurfaced() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(
            fixtureURL: url,
            notes: [],
            diagnostics: [ObsidianDiagnostic(kind: .unresolvedBatchIdentity, notePath: "orphan.md", message: "No batch token found.")]
        )
        #expect(plan.items.isEmpty)
        #expect(plan.diagnostics.contains { $0.notePath == "orphan.md" })
    }

    // MARK: - Fingerprint

    @Test("Plan fingerprint matches the fixture's actual content hash")
    func fingerprintMatchesContentHash() throws {
        let url = try makeFixtureRegistry()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [])
        let expected = try XLSXWorkbookKit.contentFingerprint(of: url)
        #expect(plan.registryFingerprint == expected)
    }
}
