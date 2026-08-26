import Foundation
import Testing
@testable import SpinLabApp

/// Phase 5.4.5: compatible-completion / information-refinement
/// reconciliation at the Registry Existing-row boundary. Replaces the
/// binary agreement/conflict idea with `RegistryGrowthFieldReconciliation`
/// (equal / compatible / conflict / unresolved) for date and energy —
/// `RegistryGrowthFieldReconciler`, `RegistryGrowthEnergyMapper`,
/// `RegistryGrowthDateMapper`'s partial-component parsing, and the
/// `.enrichExisting` plan action / mutation write path.
@Suite("V5.4.5 Registry compatible-completion reconciliation")
struct V573RegistryGrowthCompatibleCompletionTests {
    // MARK: - §10 Generic relation (pure, field-agnostic via energy as the vehicle)

    @Test("Generic 1. Identical fact sets → equal")
    func genericIdenticalIsEqual() {
        let a = RegistryGrowthEnergyMapper.EnergyComponents(primary: 100, voltage: 24, output: 238)
        let b = RegistryGrowthEnergyMapper.EnergyComponents(primary: 100, voltage: 24, output: 238)
        #expect(a == b)
    }

    @Test("Generic 2. One strict subset → compatible + richer merge")
    func genericSubsetIsCompatible() {
        let result = RegistryGrowthFieldReconciler.reconcileEnergy(registryValue: "100mJ", obsidianRaw: "100 mJ 24 kV 238 mJ")
        guard case let .compatible(merged) = result else {
            Issue.record("expected .compatible, got \(result)")
            return
        }
        #expect(merged == "镜前100mJ，激光238mJ (24kV)")
    }

    @Test("Generic 3. Complementary non-conflicting sets → compatible union")
    func genericComplementaryIsCompatibleUnion() {
        let result = RegistryGrowthFieldReconciler.reconcileEnergy(registryValue: "100mJ (24kV)", obsidianRaw: "100 mJ 24 kV 238 mJ")
        guard case let .compatible(merged) = result else {
            Issue.record("expected .compatible, got \(result)")
            return
        }
        #expect(merged == "镜前100mJ，激光238mJ (24kV)")
    }

    @Test("Generic 4. One overlapping component differs → conflict")
    func genericOverlapDifferingIsConflict() {
        let result = RegistryGrowthFieldReconciler.reconcileEnergy(registryValue: "100mJ", obsidianRaw: "110 mJ 24 kV 238 mJ")
        guard case .conflict = result else {
            Issue.record("expected .conflict, got \(result)")
            return
        }
    }

    @Test("Generic 5. Unparseable unequal values → unresolved, never auto-merged")
    func genericUnparseableIsUnresolved() {
        let result = RegistryGrowthFieldReconciler.reconcileEnergy(registryValue: "衰减镜220mJ (25.1kV) 镜前57mJ", obsidianRaw: "50 mJ 20 kV 100 mJ")
        guard case .unresolved = result else {
            Issue.record("expected .unresolved, got \(result)")
            return
        }
    }

    // MARK: - §12 Energy parser — real production syntax

    @Test("Energy parse. Bare primary-only Registry form")
    func parsesBarePrimary() {
        let c = RegistryGrowthEnergyMapper.parseRegistry("160mJ")
        #expect(c == .init(primary: 160, voltage: nil, output: nil))
    }

    @Test("Energy parse. Primary + voltage, no laser reading")
    func parsesPrimaryAndVoltage() {
        let c = RegistryGrowthEnergyMapper.parseRegistry("110mJ (20.2kV) ")
        #expect(c == .init(primary: 110, voltage: 20.2, output: nil))
    }

    @Test("Energy parse. Full canonical triple")
    func parsesFullTriple() {
        let c = RegistryGrowthEnergyMapper.parseRegistry("镜前100mJ，激光238 mJ (24kV)")
        #expect(c == .init(primary: 100, voltage: 24, output: 238))
    }

    @Test("Energy parse. 衰减镜-labeled primary (attenuator stands in for mirror-front)")
    func parsesAttenuatorLabeledPrimary() {
        let c = RegistryGrowthEnergyMapper.parseRegistry("衰减镜220mJ (25.1kV)")
        #expect(c == .init(primary: 220, voltage: 25.1, output: nil))
    }

    @Test("Energy parse. Bare 衰减镜 flag (no number) between primary and laser is ignored, not a 4th component")
    func parsesBareAttenuatorFlag() {
        let c = RegistryGrowthEnergyMapper.parseRegistry("镜前48mJ，衰减镜，激光197 mJ (21.8kV)")
        #expect(c == .init(primary: 48, voltage: 21.8, output: 197))
    }

    @Test("Energy parse. Laser number without its own mJ unit")
    func parsesLaserNumberWithoutUnit() {
        let c = RegistryGrowthEnergyMapper.parseRegistry("镜前45mJ，激光90 (20.1kV)")
        #expect(c == .init(primary: 45, voltage: 20.1, output: 90))
    }

    @Test("Energy parse. Decorative trailing remark text does not block parsing")
    func parsesWithTrailingRemark() {
        let c = RegistryGrowthEnergyMapper.parseRegistry("镜前68mJ，激光150mJ，无衰减，")
        #expect(c == .init(primary: 68, voltage: nil, output: 150))
    }

    @Test("Energy parse. Two independent unattributed numbers fail closed, never guessed")
    func parsesTwoIndependentNumbersAsUnparseable() {
        #expect(RegistryGrowthEnergyMapper.parseRegistry("衰减镜220mJ (25.1kV) 镜前57mJ") == nil)
    }

    @Test("Energy parse. Obsidian's strict positional triple")
    func parsesObsidianTriple() {
        let c = RegistryGrowthEnergyMapper.parseObsidian("110 mJ 26.3 kV 280 mJ")
        #expect(c == .init(primary: 110, voltage: 26.3, output: 280))
    }

    @Test("Energy parse. Obsidian 衰减镜-labeled triple parses identically to unlabeled")
    func parsesObsidianAttenuatorLabeledTriple() {
        let c = RegistryGrowthEnergyMapper.parseObsidian("衰减镜 53 mJ 23.7 kV 247 mJ")
        #expect(c == .init(primary: 53, voltage: 23.7, output: 247))
    }

    // MARK: - Date partial components

    @Test("Date parse. Registry yearless '8月2日' → (year: nil, month: 8, day: 2)")
    func parsesYearlessRegistryDate() {
        let c = RegistryGrowthDateMapper.partialComponents(fromRegistryRawText: "8月2日")
        #expect(c == .init(year: nil, month: 8, day: 2))
    }

    @Test("Date parse. Registry full 'yyyy.M.d' → year known")
    func parsesFullRegistryDate() {
        let c = RegistryGrowthDateMapper.partialComponents(fromRegistryRawText: "2026.8.2")
        #expect(c == .init(year: 2026, month: 8, day: 2))
    }

    @Test("Date reconcile. Yearless Registry + full Obsidian, same month/day → compatible")
    func reconcileYearlessCompatible() {
        let result = RegistryGrowthFieldReconciler.reconcileDate(registryRawText: "8月2日", registrySemanticISODate: nil, obsidianRawISO: "2026-08-02")
        guard case let .compatible(merged) = result else {
            Issue.record("expected .compatible, got \(result)")
            return
        }
        #expect(merged == "2026.8.2")
    }

    @Test("Date reconcile. Yearless Registry, differing day → conflict")
    func reconcileYearlessDayConflict() {
        let result = RegistryGrowthFieldReconciler.reconcileDate(registryRawText: "8月3日", registrySemanticISODate: nil, obsidianRawISO: "2026-08-02")
        guard case .conflict = result else {
            Issue.record("expected .conflict, got \(result)")
            return
        }
    }

    @Test("Date reconcile. Full Registry year differs from Obsidian → conflict on year")
    func reconcileFullYearConflict() {
        let result = RegistryGrowthFieldReconciler.reconcileDate(registryRawText: "2025.8.2", registrySemanticISODate: "2025-08-02", obsidianRawISO: "2026-08-02")
        guard case .conflict = result else {
            Issue.record("expected .conflict, got \(result)")
            return
        }
    }

    // MARK: - Planner integration: §12 A–F, energy fixture

    private func claim(_ value: String, notePath: String, rawKey: String) -> ObsidianFieldClaim {
        ObsidianFieldClaim(value: value, provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: value))
    }

    private func makeNote(batchId: String, path: String, energy: String) -> ObsidianNoteRecord {
        ObsidianNoteRecord(
            notePath: path, batchId: batchId, identity: .unresolvedSample,
            growthClaims: [
                .growthDate: claim("2026-01-01", notePath: path, rawKey: "date"),
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

    private func makeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V573-energy-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForEnergyReconciliation(to: url)
        return url
    }

    @Test("A. Base same, Obsidian richer (voltage + output new) → enrichExisting")
    func aObsidianRicherEnriches() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", energy: "100 mJ 20.2 kV 249 mJ")])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        #expect(item.existingDifferences.isEmpty)
        guard case let .enrichExisting(sheet, row, edits) = item.action else {
            Issue.record("expected .enrichExisting, got \(item.action)")
            return
        }
        #expect(sheet == "LNO")
        #expect(row == 2)
        let energyEdit = try #require(edits.first { $0.field == .laserEnergy })
        #expect(energyEdit.originalRegistryValue == "100mJ")
        #expect(energyEdit.finalValue == "镜前100mJ，激光249mJ (20.2kV)")
    }

    @Test("B. Base same, Registry already fully complete → equal, no write, clean Existing")
    func bRegistryRicherIsCleanExisting() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO3", path: "lno3.md", energy: "100 mJ 24 kV 238 mJ")])

        #expect(plan.items.first { $0.batchId == "LNO3" } == nil, "already-equal energy must compact into existingCount")
        #expect(plan.existingCount == 1)
    }

    @Test("C. Complementary non-conflicting optional facts → enrichExisting with union")
    func cComplementaryFactsUnion() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO2", path: "lno2.md", energy: "100 mJ 20.2 kV 249 mJ")])

        let item = try #require(plan.items.first { $0.batchId == "LNO2" })
        guard case let .enrichExisting(_, _, edits) = item.action else {
            Issue.record("expected .enrichExisting, got \(item.action)")
            return
        }
        let energyEdit = try #require(edits.first { $0.field == .laserEnergy })
        #expect(energyEdit.originalRegistryValue == "100mJ (20.2kV)")
        #expect(energyEdit.finalValue == "镜前100mJ，激光249mJ (20.2kV)")
    }

    @Test("D. Base (primary) differs → Existing conflict")
    func dBaseDiffersIsConflict() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO4", path: "lno4.md", energy: "110 mJ 24 kV 238 mJ")])

        let item = try #require(plan.items.first { $0.batchId == "LNO4" })
        guard case .skipExisting = item.action else {
            Issue.record("expected .skipExisting (conflict), got \(item.action)")
            return
        }
        let diff = try #require(item.existingDifferences.first { $0.field == .laserEnergy })
        #expect(diff.registryValue == "镜前100mJ")
    }

    @Test("E. Same base/output but explicit voltage differs → Existing conflict")
    func eVoltageDiffersIsConflict() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO5", path: "lno5.md", energy: "100 mJ 25 kV 238 mJ")])

        let item = try #require(plan.items.first { $0.batchId == "LNO5" })
        guard case .skipExisting = item.action else {
            Issue.record("expected .skipExisting (conflict), got \(item.action)")
            return
        }
        #expect(item.existingDifferences.contains { $0.field == .laserEnergy })
    }

    @Test("F. Unknown/unparseable Registry energy syntax never auto-enriched")
    func fUnknownSyntaxNeverEnriched() throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO6", path: "lno6.md", energy: "50 mJ 20 kV 100 mJ")])

        let item = try #require(plan.items.first { $0.batchId == "LNO6" })
        guard case .skipExisting = item.action else {
            Issue.record("expected .skipExisting (unresolved fallback), got \(item.action)")
            return
        }
        #expect(item.existingDifferences.isEmpty, "an unparseable value is never materialized as a structured conflict")
        #expect(!item.warnings.isEmpty, "an unparseable value keeps the non-editable fallback-warning path")
        #expect(plan.existingCount == 0, "a row carrying a warning is not clean Existing")
    }

    // MARK: - §12 G / mutation: Registry Preview final == actual workbook value after Apply

    @Test("G. enrichExisting's planned final value matches the actual workbook cell after Apply")
    func mutationWritesExactPlannedEnrichmentValue() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "V573-mut-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForEnergyReconciliation(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", energy: "100 mJ 20.2 kV 249 mJ")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        guard case .enrichExisting = item.action else {
            Issue.record("expected .enrichExisting, got \(item.action)")
            return
        }

        let service = RegistryGrowthMutationService(ruleProvider: InlineRuleProvider(loadResult: RuleLoader().loadFromBundleOnly()))
        let result = try service.apply(plan: plan, selectedBatchIds: ["LNO1"], registryURL: url)

        #expect(result.enrichedBatchIds == ["LNO1"])
        #expect(result.appliedBatchIds.isEmpty)
        #expect(result.existingFieldEditBatchIds.isEmpty)

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
        #expect(actualValue == "镜前100mJ，激光249mJ (20.2kV)")

        // 编号 untouched, no duplicate/extra row for LNO1.
        let reparsed = try withBundledRules { provider in
            try LibraryRegistryParser(ruleProvider: provider).parse(
                xlsxURL: url,
                settings: LibrarySettings(rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil, registrySourcePath: url.path, backupPath: nil, backupLastSyncedAt: nil, allowedBatchPrefixes: [], lastRefreshAt: nil)
            ).index
        }
        #expect(reparsed.batches.filter { $0.id == "LNO1" }.count == 1)
        #expect(reparsed.batches.first { $0.id == "LNO1" }?.metadata["能量"] == "镜前100mJ，激光249mJ (20.2kV)")
    }

    // MARK: - §13 Conservative ENRICH gate: fallbackWarnings must block promotion
    // even when a real, compatible plannedEdit exists on another field.

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

    private func makeGateFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "V573-gate-\(UUID().uuidString).xlsx")
        try RegistryGrowthXLSXFixture.buildForConservativeEnrichmentGate(to: url)
        return url
    }

    @Test("H. Compatible date + unresolvable-syntax energy fallback → stays non-executable, never enrichExisting")
    func hFallbackWarningBlocksEnrichEvenWithCompatibleDate() throws {
        let url = try makeGateFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-08-02", energy: "50 mJ 20 kV 100 mJ")
        ])

        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        guard case .skipExisting = item.action else {
            Issue.record("expected .skipExisting — an unresolved energy fallback must block ENRICH even though the date reconciled as compatible, got \(item.action)")
            return
        }
        #expect(!item.isExecutable)
        #expect(item.existingDifferences.isEmpty, "the date field must not be misreported as a conflict")
        #expect(!item.warnings.isEmpty, "the unresolved-energy fallback warning must remain visible")
    }

    @Test("I. Compatible date + Obsidian internal energy disagreement → stays non-executable, never enrichExisting")
    func iObsidianInternalEnergyConflictBlocksEnrich() throws {
        let url = try makeGateFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let plan = try buildPlan(fixtureURL: url, notes: [
            makeNote(batchId: "LNO2", path: "lno2a.md", date: "2026-08-02", energy: "100 mJ 20 kV 200 mJ"),
            makeNote(batchId: "LNO2", path: "lno2b.md", date: "2026-08-02", energy: "110 mJ 20 kV 210 mJ")
        ])

        let item = try #require(plan.items.first { $0.batchId == "LNO2" })
        guard case .skipExisting = item.action else {
            Issue.record("expected .skipExisting — Obsidian notes disagreeing with each other on energy must block ENRICH even though the date reconciled as compatible, got \(item.action)")
            return
        }
        #expect(!item.isExecutable)
        #expect(item.existingDifferences.isEmpty, "the date field must not be misreported as a conflict")
        #expect(!item.warnings.isEmpty, "the Obsidian-disagreement fallback warning must remain visible")
    }

    // MARK: - §14 Production shared-string yearless date, full Apply E2E

    @Test("J. Real shared-string '8月2日' Registry cell + full Obsidian date → enrichExisting, applies through the real mutation/backup/read-contract path, and re-reads back as the completed date")
    func jSharedStringYearlessDateAppliesAndReadsBackCanonical() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "V573-sharedstring-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "registry.xlsx")
        try RegistryGrowthXLSXFixture.buildForProductionYearlessSharedStringDate(to: url)

        let plan = try buildPlan(fixtureURL: url, notes: [makeNote(batchId: "LNO1", path: "lno1.md", date: "2026-08-02", energy: "1.2")])
        let item = try #require(plan.items.first { $0.batchId == "LNO1" })
        guard case let .enrichExisting(sheet, row, edits) = item.action else {
            Issue.record("expected .enrichExisting for a genuinely compatible shared-string yearless date, got \(item.action)")
            return
        }
        #expect(sheet == "LNO")
        #expect(row == 2)
        let dateEdit = try #require(edits.first { $0.field == .date })
        #expect(dateEdit.originalRegistryValue == "8月2日")
        #expect(dateEdit.finalValue == "2026.8.2")

        let service = RegistryGrowthMutationService(ruleProvider: InlineRuleProvider(loadResult: RuleLoader().loadFromBundleOnly()))
        let result = try service.apply(plan: plan, selectedBatchIds: ["LNO1"], registryURL: url)
        #expect(result.enrichedBatchIds == ["LNO1"])

        let workDir = try XLSXWorkbookKit.prepareWorkingDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let workbook = try XLSXWorkbookKit.loadWorkbook(in: workDir)
        let path = try XLSXWorkbookKit.worksheetPath(named: "LNO", workbook: workbook)
        let doc = try XLSXWorkbookKit.loadXML(at: workDir.appending(path: path))
        guard let cell = try doc.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']/*[local-name()='c' and @r='B2']").first as? XMLElement else {
            Issue.record("B2 cell not found")
            return
        }
        let actualValue = XLSXWorkbookKit.readCellValue(cell: cell, sharedStrings: workbook.sharedStrings)
        #expect(actualValue == "2026.8.2")

        let reparsed = try withBundledRules { provider in
            try LibraryRegistryParser(ruleProvider: provider).parse(
                xlsxURL: url,
                settings: LibrarySettings(rootPath: nil, rootBookmarkData: nil, registryInternalPath: nil, registrySourcePath: url.path, backupPath: nil, backupLastSyncedAt: nil, allowedBatchPrefixes: [], lastRefreshAt: nil)
            ).index
        }
        #expect(reparsed.batches.filter { $0.id == "LNO1" }.count == 1)
        #expect(reparsed.batches.first { $0.id == "LNO1" }?.metadata["日期"] == "2026.8.2")
    }
}
