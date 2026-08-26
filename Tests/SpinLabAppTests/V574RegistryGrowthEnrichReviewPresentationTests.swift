import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5.4.6 — ENRICH detail pane restored as a full review/confirmation
/// surface (Registry / Obsidian / Final per field, plus a full post-Apply
/// Registry Preview). Presentation-only: proves the values
/// `RegistryGrowthImportPresentation` exposes for `.enrichExisting` are
/// exactly what the planner/mutation service already computed, never a
/// UI-side reconciliation.
@Suite("V5.4.6 ENRICH review presentation")
struct V574RegistryGrowthEnrichReviewPresentationTests {
    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    private func makeNote(batchId: String, path: String, date: String, energy: String) -> ObsidianNoteRecord {
        ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: [
                .growthDate: claim(date, notePath: path, rawKey: "date"),
                .growthTemperature: claim("650", notePath: path, rawKey: "temperature"),
                .targetSubstrateDistance: claim("45", notePath: path, rawKey: "sample height"),
                .oxygenPressure: claim("100", notePath: path, rawKey: "pressure"),
                .laserEnergy: claim(energy, notePath: path, rawKey: "energy"),
                .pulseCount: claim("1000/3000", notePath: path, rawKey: "pulse")
            ],
            rawFields: [claim("LNO", notePath: path, rawKey: "material")],
            testStatus: [:], sampleObservations: [],
            substrateEntries: [ObsidianSubstrateEntry(raw: "STO(001)", provenance: ObsidianProvenance(notePath: path, rawKey: "substrate", rawValue: "STO(001)"), material: nil, orientation: nil)]
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

    // MARK: A. Date ENRICH — Registry / Obsidian / Final all preserved distinctly

    @Test("A. Date ENRICH exposes Registry, Obsidian, and Final as three distinct values")
    func dateEnrichExposesAllThreeValues() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V574-date-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForProductionYearlessSharedStringDate(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-08-02", energy: "1.2")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let edits = RegistryGrowthImportPresentation.plannedFieldEdits(for: item)
        let dateEdit = try #require(edits.first { $0.field == .date })

        #expect(dateEdit.originalRegistryValue == "8月2日")
        #expect(dateEdit.obsidianValue == "2026.8.2")
        #expect(dateEdit.finalValue == "2026.8.2")
        // Obsidian is preserved as its own distinct value from Registry —
        // it happens to equal Final here because a yearless Registry date
        // merges to exactly the Obsidian date, not because the presentation
        // collapsed the two.
        #expect(dateEdit.obsidianValue != dateEdit.originalRegistryValue)
    }

    // MARK: B. Energy ENRICH — Registry / Obsidian / Final all preserved distinctly

    @Test("B. Energy ENRICH exposes Registry, Obsidian, and Final as three distinct values")
    func energyEnrichExposesAllThreeValues() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V574-energy-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForEnergyReconciliation(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-01-01", energy: "100 mJ 26.3 kV 280 mJ")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let edits = RegistryGrowthImportPresentation.plannedFieldEdits(for: item)
        let energyEdit = try #require(edits.first { $0.field == .laserEnergy })

        #expect(energyEdit.originalRegistryValue == "100mJ")
        #expect(energyEdit.obsidianValue == "100 mJ 26.3 kV 280 mJ")
        #expect(energyEdit.finalValue == "镜前100mJ，激光280mJ (26.3kV)")
        #expect(Set([energyEdit.originalRegistryValue, energyEdit.obsidianValue, energyEdit.finalValue]).count == 3)
    }

    // MARK: C. Final Registry Preview overlays planned edits onto the current row

    @Test("C. finalRegistryPreviewRows overlays planned edit values, leaves untouched columns unchanged")
    func finalRegistryPreviewOverlaysPlannedEdits() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "V574-preview-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try RegistryGrowthXLSXFixture.buildForEnergyReconciliation(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-01-01", energy: "100 mJ 26.3 kV 280 mJ")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        guard case .enrichExisting = item.action else {
            Issue.record("expected .enrichExisting, got \(item.action)")
            return
        }

        let rows = RegistryGrowthImportPresentation.finalRegistryPreviewRows(for: item)
        let byHeader = Dictionary(uniqueKeysWithValues: rows.map { ($0.header, $0.value) })

        // The touched field carries the merged Final value, not the raw
        // current Registry value.
        #expect(byHeader["能量"] == "镜前100mJ，激光280mJ (26.3kV)")
        // Untouched columns are unchanged from the current row snapshot.
        // (编号/生长 are never part of the confirmed field mapping, so —
        // same as append/fill's `columnValues` — they never appear here.)
        #expect(byHeader["日期"] == "2026.1.1")
        #expect(byHeader["substrate"] == "STO(001)")
        #expect(byHeader["靶"] == "LNO")
        #expect(byHeader["生长温度"] == "650")
        #expect(byHeader["靶机距"] == "45")
        #expect(byHeader["氧压"] == "100")
        #expect(byHeader["预打/生长次数"] == "1000/3000")
    }

    // MARK: D. Preview Final == actual mutation-written value

    @Test("D. finalRegistryPreviewRows' Final value equals the value RegistryGrowthMutationService actually writes")
    func finalPreviewValueMatchesActualAppliedCell() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "V574-apply-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForEnergyReconciliation(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-01-01", energy: "100 mJ 26.3 kV 280 mJ")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        let previewRows = RegistryGrowthImportPresentation.finalRegistryPreviewRows(for: item)
        let previewFinal = try #require(previewRows.first { $0.header == "能量" }?.value)

        let service = RegistryGrowthMutationService(ruleProvider: InlineRuleProvider(loadResult: RuleLoader().loadFromBundleOnly()))
        _ = try service.apply(plan: plan, selectedBatchIds: ["LNO1"], registryURL: url)

        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let workbook = try XLSXWorkbookKit.loadWorkbook(in: workDir)
        let path = try XLSXWorkbookKit.worksheetPath(named: "LNO", workbook: workbook)
        let doc = try XLSXWorkbookKit.loadXML(at: workDir.appending(path: path))
        guard let cell = try doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']/*[local-name()='c' and @r='H2']").first as? XMLElement else {
            Issue.record("H2 cell not found")
            return
        }
        let actualValue = XLSXWorkbookKit.readCellValue(cell: cell, sharedStrings: [])
        #expect(actualValue == previewFinal)
    }

    // MARK: E. Existing conflict behavior unchanged — obsidianValue mirrors the difference

    @Test("E. Manual Existing field edits still carry the same Registry/Obsidian values as before")
    func existingConflictObsidianValueUnchanged() {
        let diff = RegistryGrowthExistingDifference(field: .laserEnergy, header: "能量", registryValue: "100mJ", obsidianValue: "110 mJ")
        let plan = RegistryGrowthImportPlan(
            registryFingerprint: "fp", registrySourcePath: "/tmp/r.xlsx", builtAt: Date(),
            items: [RegistryGrowthImportItem(
                batchId: "LNO1", sourceNotePaths: [], targetSheetHint: "LNO",
                action: .skipExisting(targetSheet: "LNO", rowNumber: 2), columnValues: [:], provenance: [],
                blankColumns: [], expectedSampleKeys: [], warnings: [], existingDifferences: [diff], blockingReasons: []
            )],
            diagnostics: [], existingCount: 0
        )
        let edits = LibraryFeatureStore.buildExistingFieldEdits(plan: plan, pending: ["LNO1": ["能量": "110 mJ"]])
        let edit = edits.first
        #expect(edit?.originalRegistryValue == "100mJ")
        #expect(edit?.obsidianValue == "110 mJ")
        #expect(edit?.finalValue == "110 mJ")
    }

    // MARK: F. Append/fill Registry Preview unchanged (finalRegistryPreviewRows is ENRICH-only)

    @Test("F. finalRegistryPreviewRows is empty for non-ENRICH actions, leaving append/fill preview untouched")
    func finalPreviewEmptyForNonEnrichActions() {
        let appendItem = RegistryGrowthImportItem(
            batchId: "LNO9", sourceNotePaths: [], targetSheetHint: "LNO",
            action: .appendNewRow(targetSheet: "LNO"), columnValues: ["编号": "LNO9", "日期": "2026.1.1"],
            provenance: [], blankColumns: [], expectedSampleKeys: [], warnings: [], existingDifferences: [], blockingReasons: []
        )
        #expect(RegistryGrowthImportPresentation.finalRegistryPreviewRows(for: appendItem).isEmpty)
        #expect(RegistryGrowthImportPresentation.orderedRegistryPreviewRows(for: appendItem).count == 2)
    }
}
