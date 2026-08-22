import CoreXLSX
import Foundation

/// Builds a `RegistryGrowthImportPlan` by comparing Obsidian-observed
/// growth batches (`ObsidianVaultIndex`) against the Registry's *current
/// row-level* state. Never writes anything — see `RegistryGrowthMutationService`
/// for the only place that mutates the workbook.
///
/// Deliberately does not consume `LibraryIndex`/`LibraryRegistryParser`'s
/// batch-merge output for row identity: that parser dictionary-merges by
/// batch id and does not preserve per-row numbers or detect duplicate rows
/// for the same id (two rows with the same 编号 silently collapse into one
/// dictionary entry there). Row-level fidelity is required here — the
/// planner scans the routed target sheets directly via CoreXLSX instead.
struct RegistryGrowthImportPlanner {
    /// The only sheets this phase is allowed to route into (spec §5/§15) —
    /// never auto-created, never a sheet this list doesn't already name.
    static let routableSheetNames: [String] = ["LNO", "NCO", "NNO", "LSMO", "PLD-N样品"]

    /// Reuses `LibraryRegistryParser`'s own canonical substrate/sample
    /// identity primitive (`LibrarySubstrateParser.sampleKey`) to compute
    /// `expectedSampleKeys` — deliberately not a Registry-growth-specific
    /// identity parser (Phase 5A review blocker #3).
    private let substrateParser: LibrarySubstrateParser

    init(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) {
        guard ruleProvider.substrateConfig() != nil else {
            substrateParser = LibrarySubstrateParser(
                classifier: SubstrateSemanticClassifier(materials: [], treatments: [], orientations: [])
            )
            return
        }
        substrateParser = LibrarySubstrateParser(
            classifier: SubstrateSemanticClassifier(compiled: ruleProvider.ruleSet().compiled)
        )
    }

    func build(vault: ObsidianVaultIndex, dossier: SampleDossierIndex, registryURL: URL) throws -> RegistryGrowthImportPlan {
        let fingerprint = try XLSXWorkbookKit.contentFingerprint(of: registryURL)
        let snapshots = try Self.scanRoutableSheets(registryURL: registryURL)
        // Profiles are derived once from this single scan (spec: XLSX scan
        // → RegistrySheetSnapshot → RegistrySheetProfile → routing) — never
        // a second workbook open, and routing below never rescans
        // `snapshot.rows` per incoming batch.
        let profiles = RegistrySheetProfile.buildProfiles(from: snapshots)

        var items: [RegistryGrowthImportItem] = []
        var diagnostics: [RegistryGrowthPlanDiagnostic] = []
        var existingCount = 0

        for batchRecord in vault.batches.sorted(by: { $0.batchId < $1.batchId }) {
            let item = buildItem(batchId: batchRecord.batchId, vault: vault, dossier: dossier, snapshots: snapshots, profiles: profiles)
            if Self.isCleanExisting(item) {
                // Clean, populated, exact-existing Registry row: Button A
                // would do nothing for this batch. It is synchronization
                // history, not an actionable preview item — counted, never
                // materialized into `items` (spec: "compact clean Existing
                // items out of Obsidian → Registry preview"). A `.skipExisting`
                // item carrying warnings (Obsidian disagrees with the
                // existing row) is deliberately excluded from this check —
                // it still requires user attention, so it stays in `items`.
                existingCount += 1
                continue
            }
            items.append(item)
        }

        for diagnostic in vault.diagnostics where diagnostic.kind == .unresolvedBatchIdentity || diagnostic.kind == .ambiguousBatchIdentity {
            diagnostics.append(RegistryGrowthPlanDiagnostic(message: diagnostic.message, notePath: diagnostic.notePath))
        }

        return RegistryGrowthImportPlan(
            registryFingerprint: fingerprint,
            registrySourcePath: registryURL.path,
            builtAt: .now,
            items: items,
            diagnostics: diagnostics,
            existingCount: existingCount
        )
    }

    /// True only for a batch the planner unambiguously concluded is a clean,
    /// populated, exact-existing Registry row: `.skipExisting` with no
    /// conflict warnings. Never true for `.blocked` (duplicate rows,
    /// ambiguous identity, malformed sheet state, etc. always stay visible)
    /// and never true for a `.skipExisting` item that carries a warning
    /// (Obsidian/Registry disagreement on an existing batch's fields).
    private static func isCleanExisting(_ item: RegistryGrowthImportItem) -> Bool {
        guard case .skipExisting = item.action else { return false }
        return item.warnings.isEmpty
    }

    // MARK: - Per-batch item construction

    private func buildItem(batchId: String, vault: ObsidianVaultIndex, dossier: SampleDossierIndex, snapshots: [String: RegistrySheetSnapshot], profiles: [String: RegistrySheetProfile]) -> RegistryGrowthImportItem {
        let notes = vault.notes.filter { $0.batchId == batchId }
        let notePaths = notes.map(\.notePath).sorted()
        // `BatchRecord.growthClaims` is the same per-field claim aggregation
        // `SampleDossierBuilder` already reconciles against Library — reuse
        // both rather than re-deriving conflict detection here (spec §9:
        // "使用 Phase 4 已有 reconciliation"). Only material/substrate have no
        // Phase 4 reconciliation (deliberately excluded from
        // `ObsidianGrowthField` — see `ObsidianVaultModels.swift`), so those
        // two still fall back to a direct claim comparison below.
        let obsidianBatch = vault.batches.first { $0.batchId == batchId }
        let batchDossier = dossier.batches.first { $0.batchId == batchId }

        let dateClaims = obsidianBatch?.growthClaims[.growthDate] ?? []
        let materialClaims = notes.flatMap { note in
            note.rawFields.filter { $0.provenance.rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "material" }
        }
        let substrateClaims: [(raw: String, provenance: ObsidianProvenance)] = notes.flatMap { note in
            note.substrateEntries.map { ($0.raw, $0.provenance) }
        }
        // Canonical substrate parse, computed once up front so both the
        // required-field check and `expectedSampleKeys` see the same
        // result — never re-derived or re-classified independently.
        let substrateJoined = Self.dedupOrderPreserving(substrateClaims.map(\.raw)).joined(separator: ", ")
        let parsedSubstrates = substrateClaims.isEmpty ? [] : substrateParser.parse(substrateJoined)

        // Row-level Registry state takes precedence over Obsidian
        // completeness (Phase 5A review blocker #1): identify any existing
        // row(s) for this batch id across every routed sheet *before*
        // requiring Obsidian evidence to be complete. Whether an existing
        // row counts as "found" must never depend on how much Obsidian has
        // to say about it.
        let allMatches: [(sheet: String, row: RegistryRowSnapshot)] = snapshots.flatMap { sheetName, snapshot in
            snapshot.rows.filter { $0.batchId == batchId }.map { (sheetName, $0) }
        }

        func existingRowConflictWarnings() -> [String] {
            guard let batchDossier else { return [] }
            var warnings: [String] = []
            for (field, reconciliation) in batchDossier.growthFields {
                if case .conflict = reconciliation {
                    warnings.append("Obsidian and the existing Registry row disagree on \(RegistryGrowthFieldMapping.humanLabel(for: field)); the existing row is kept unchanged.")
                }
            }
            return warnings
        }

        if allMatches.count > 1 {
            let sheetName = allMatches.map(\.sheet).sorted().first!
            let rowNumbers = allMatches.map(\.row.rowNumber).sorted()
            let reason = RegistryGrowthBlockingReason.duplicateRegistryRow(sheet: sheetName, rowNumbers: rowNumbers)
            return RegistryGrowthImportItem(
                batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: sheetName,
                action: .blocked(reasons: [reason]), columnValues: [:], provenance: [],
                blankColumns: [], expectedSampleKeys: [], warnings: [], blockingReasons: [reason]
            )
        }

        if let (existingSheet, existingRow) = allMatches.first, !existingRow.isReserved {
            // Exactly one existing *normal* row: never overwritten, and its
            // identification never requires Obsidian date/material/
            // substrate to be complete (spec: skipExisting regardless of
            // Obsidian completeness).
            return RegistryGrowthImportItem(
                batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: existingSheet,
                action: .skipExisting(targetSheet: existingSheet, rowNumber: existingRow.rowNumber),
                columnValues: [:], provenance: [], blankColumns: [], expectedSampleKeys: [],
                warnings: existingRowConflictWarnings(), blockingReasons: []
            )
        }

        // Remaining cases: exactly one reserved-ID-only existing row, or no
        // existing row at all — both require Obsidian required fields/
        // routing to be complete before writing anything.
        var reasons: [RegistryGrowthBlockingReason] = []
        var warnings: [String] = []

        func hasInternalConflict(_ field: ObsidianGrowthField) -> Bool {
            if case .obsidianInternalConflict = batchDossier?.growthFields[field] { return true }
            return false
        }

        // Required fields (spec §8): batchId (given), date, material/target,
        // substrate, target sheet.
        var registryDate: String?
        if dateClaims.isEmpty {
            reasons.append(.missingDate)
        } else if hasInternalConflict(.growthDate) {
            reasons.append(.obsidianInternalConflict(field: RegistryGrowthFieldMapping.humanLabel(for: .growthDate)))
        } else if let mapped = RegistryGrowthDateMapper.registryDisplayString(fromISODate: dateClaims[0].value) {
            registryDate = mapped
        } else {
            reasons.append(.missingDate)
        }

        if materialClaims.isEmpty {
            reasons.append(.missingMaterialEvidence)
        } else if Set(materialClaims.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }).count > 1 {
            reasons.append(.obsidianInternalConflict(field: RegistryGrowthFieldMapping.materialHumanLabel))
        }

        if substrateClaims.isEmpty {
            reasons.append(.missingSubstrateEvidence)
        } else if parsedSubstrates.isEmpty {
            // Evidence exists but none of it resolves to a canonical
            // substrate/sample identity (Phase 5A review follow-up) — never
            // append/fill with evidence that cannot produce a Sample the
            // Library will actually recognize.
            reasons.append(.unresolvedSubstrateIdentity(rawHint: substrateClaims.first?.raw))
        }

        // Secondary growth fields: internal conflict across notes still
        // blocks (never silently pick a winner); a field with zero claims
        // is only a warning + blank cell.
        let secondaryFields: [(ObsidianGrowthField, RegistryGrowthFieldMapping.Field)] = [
            (.growthTemperature, .growthTemperature),
            (.targetSubstrateDistance, .targetSubstrateDistance),
            (.oxygenPressure, .oxygenPressure),
            (.laserEnergy, .laserEnergy),
            (.pulseCount, .pulseCount)
        ]
        var secondaryValues: [RegistryGrowthFieldMapping.Field: ObsidianFieldClaim] = [:]
        for (obsidianField, mappingField) in secondaryFields {
            let claims = obsidianBatch?.growthClaims[obsidianField] ?? []
            if claims.isEmpty {
                warnings.append("No Obsidian evidence for \(RegistryGrowthFieldMapping.humanLabel(for: obsidianField)); column will be left blank.")
                continue
            }
            if hasInternalConflict(obsidianField) {
                reasons.append(.obsidianInternalConflict(field: RegistryGrowthFieldMapping.humanLabel(for: obsidianField)))
                continue
            }
            secondaryValues[mappingField] = claims[0]
        }

        let materialEvidenceSet = Set(materialClaims.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) })
        let routingResolution = RegistryGrowthRouting.resolveTargetSheet(
            batchId: batchId, profiles: profiles, materialEvidence: materialEvidenceSet
        )
        var targetSheet: String?
        switch routingResolution {
        case let .resolved(sheet):
            targetSheet = sheet
        case .unroutable:
            reasons.append(.unroutableMaterialOrPrefix(rawHint: materialClaims.first?.value))
        case let .ambiguous(batchSeries, candidateSheets):
            reasons.append(.ambiguousTargetSheet(batchSeries: batchSeries, candidateSheets: candidateSheets))
        case let .conflict(batchSeries, observedSheet, explicitSheet):
            reasons.append(.routingEvidenceConflict(batchSeries: batchSeries, observedSheet: observedSheet, explicitSheet: explicitSheet))
        }

        if let targetSheet, snapshots[targetSheet] == nil {
            reasons.append(.targetSheetNotFound(sheetName: targetSheet))
        }

        // A reserved-ID-only row would be *written into* below (unlike the
        // populated-row `skipExisting` path above, which never writes and
        // already returned before reaching here). Exact row identity is a
        // stronger fact than routing, but it does not override the
        // requirement that the sheet actually being written into has a
        // valid ("one sheet = one series") profile — a mixed sheet stays
        // Blocked even for its own exact reserved row.
        if let (existingSheet, existingRow) = allMatches.first, existingRow.isReserved,
           profiles[existingSheet]?.series == nil {
            reasons.append(.reservedRowOnInvalidSheetProfile(sheet: existingSheet))
        }

        if !reasons.isEmpty {
            return RegistryGrowthImportItem(
                batchId: batchId,
                sourceNotePaths: notePaths,
                targetSheetHint: targetSheet,
                action: .blocked(reasons: reasons),
                columnValues: [:],
                provenance: [],
                blankColumns: [],
                expectedSampleKeys: [],
                warnings: warnings,
                blockingReasons: reasons
            )
        }

        guard let targetSheet, let routedSnapshot = snapshots[targetSheet] else {
            // Unreachable given the checks above, but fail closed rather
            // than force-unwrap.
            let reason = RegistryGrowthBlockingReason.other("Internal: routed sheet snapshot missing after routing succeeded.")
            return RegistryGrowthImportItem(
                batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: targetSheet,
                action: .blocked(reasons: [reason]), columnValues: [:], provenance: [],
                blankColumns: [], expectedSampleKeys: [], warnings: warnings, blockingReasons: [reason]
            )
        }

        // The only remaining row-level possibility here is the reserved-ID-
        // only row already found above (`allMatches.first`) — a fresh
        // duplicate check against `routedSnapshot` would be redundant with
        // the global `allMatches` check earlier in this function. A
        // reserved row always lives on its own routed sheet in practice,
        // but fall back to the sheet it was actually found on (rather than
        // the freshly-routed one) so header resolution can never target the
        // wrong sheet if the two ever disagree.
        let effectiveSheet = allMatches.first?.sheet ?? targetSheet
        let snapshot = snapshots[effectiveSheet] ?? routedSnapshot
        var columnValues: [String: String] = [:]
        var provenance: [RegistryGrowthValueProvenance] = []
        var blankColumns: [RegistryGrowthBlankColumn] = []

        func setValue(_ field: RegistryGrowthFieldMapping.Field, _ value: String?, notePath: String?, rawKey: String?, rawValue: String?) {
            guard let header = RegistryGrowthFieldMapping.header(for: field, availableHeaders: snapshot.availableHeaders) else { return }
            guard let value, !value.isEmpty else {
                blankColumns.append(RegistryGrowthBlankColumn(columnHeader: header, reason: "No Obsidian evidence."))
                return
            }
            columnValues[header] = value
            if let notePath, let rawKey, let rawValue {
                provenance.append(RegistryGrowthValueProvenance(columnHeader: header, notePath: notePath, rawKey: rawKey, rawValue: rawValue))
            }
        }

        setValue(.batchId, batchId, notePath: notePaths.first, rawKey: "batchId", rawValue: batchId)
        setValue(.date, registryDate, notePath: dateClaims.first?.provenance.notePath, rawKey: dateClaims.first?.provenance.rawKey, rawValue: dateClaims.first?.provenance.rawValue)
        setValue(.material, materialClaims.first?.value, notePath: materialClaims.first?.provenance.notePath, rawKey: materialClaims.first?.provenance.rawKey, rawValue: materialClaims.first?.provenance.rawValue)

        setValue(.substrate, substrateJoined, notePath: substrateClaims.first?.provenance.notePath, rawKey: substrateClaims.first?.provenance.rawKey, rawValue: substrateClaims.first?.provenance.rawValue)

        for (_, mappingField) in secondaryFields {
            let claim = secondaryValues[mappingField]
            setValue(mappingField, claim?.value, notePath: claim?.provenance.notePath, rawKey: claim?.provenance.rawKey, rawValue: claim?.provenance.rawValue)
        }

        // Reaching here means either a reserved-ID-only row was already
        // found (`allMatches.first`) — filled, never appended — or there was
        // no existing row at all, so a new row is appended.
        let action: RegistryGrowthImportAction
        if let (existingSheet, existingRow) = allMatches.first {
            action = .fillReservedRow(targetSheet: existingSheet, rowNumber: existingRow.rowNumber)
        } else {
            action = .appendNewRow(targetSheet: effectiveSheet)
        }

        // Expected canonical sample identity after apply (Phase 5A review
        // blocker #3) — reuses `LibrarySubstrateParser`'s own classifier
        // rather than re-deriving substrate/material/orientation parsing.
        // `parsedSubstrates` is guaranteed non-empty here: the
        // `unresolvedSubstrateIdentity` check above already returned
        // `.blocked` for any item that would otherwise reach this point
        // with nothing parseable.
        let expectedSampleKeys = Self.dedupOrderPreserving(
            parsedSubstrates.map { substrateParser.sampleKey(batchId: batchId, substrate: $0) }
        )

        let result = RegistryGrowthImportItem(
            batchId: batchId,
            sourceNotePaths: notePaths,
            targetSheetHint: targetSheet,
            action: action,
            columnValues: columnValues,
            provenance: provenance,
            blankColumns: blankColumns,
            expectedSampleKeys: expectedSampleKeys,
            warnings: warnings,
            blockingReasons: []
        )
        // Invariant (Phase 5A review follow-up): every executable item must
        // carry at least one expected sample key, or post-apply validation
        // would vacuously pass without ever having checked anything.
        assert(!result.isExecutable || !result.expectedSampleKeys.isEmpty, "executable RegistryGrowthImportItem must have non-empty expectedSampleKeys")
        return result
    }

    // MARK: - Registry sheet scanning

    struct RegistrySheetSnapshot {
        var sheetName: String
        var availableHeaders: Set<String>
        var rows: [RegistryRowSnapshot]
    }

    struct RegistryRowSnapshot {
        var rowNumber: Int
        var batchId: String
        var isReserved: Bool
    }

    /// Scans every `routableSheetNames` sheet present in `registryURL` into a
    /// `RegistrySheetSnapshot`. Extracted from `build` so routing (which
    /// needs snapshots to read observed batch-series evidence) and any
    /// read-only preview/report code share one scan path rather than each
    /// re-opening the workbook independently. Read-only: never writes.
    static func scanRoutableSheets(registryURL: URL) throws -> [String: RegistrySheetSnapshot] {
        guard let file = XLSXFile(filepath: registryURL.path) else {
            throw AppError.io("Unable to open XLSX at \(registryURL.path)")
        }
        guard let workbook = try file.parseWorkbooks().first else {
            throw AppError.io("No workbook found in XLSX.")
        }
        let sharedStrings = try? file.parseSharedStrings()
        let worksheetPathsAndNames = try file.parseWorksheetPathsAndNames(workbook: workbook)

        var snapshots: [String: RegistrySheetSnapshot] = [:]
        for sheetName in Self.routableSheetNames {
            guard let entry = worksheetPathsAndNames.first(where: { $0.0 == sheetName }) else { continue }
            guard let worksheet = try? file.parseWorksheet(at: entry.1),
                  let rows = worksheet.data?.rows, !rows.isEmpty else { continue }
            snapshots[sheetName] = Self.scan(sheetName: sheetName, rows: rows, sharedStrings: sharedStrings)
        }
        return snapshots
    }

    private static func scan(sheetName: String, rows: [Row], sharedStrings: SharedStrings?) -> RegistrySheetSnapshot {
        let headerByColumn = XLSXSheetValueReader.headerValueByColumnIndex(row: rows[0], sharedStrings: sharedStrings)
        let availableHeaders = Set(headerByColumn.values)

        guard let batchColumn = headerByColumn.first(where: { $0.value == "编号" })?.key else {
            return RegistrySheetSnapshot(sheetName: sheetName, availableHeaders: availableHeaders, rows: [])
        }

        let reservedCheckFields: [RegistryGrowthFieldMapping.Field] = [
            .date, .substrate, .material, .growthTemperature, .targetSubstrateDistance, .oxygenPressure, .laserEnergy, .pulseCount
        ]
        let reservedCheckColumns: [Int] = reservedCheckFields.compactMap { field in
            guard let header = RegistryGrowthFieldMapping.header(for: field, availableHeaders: availableHeaders) else { return nil }
            return headerByColumn.first(where: { $0.value == header })?.key
        }

        var snapshotRows: [RegistryRowSnapshot] = []
        for row in rows.dropFirst() {
            guard let batchId = XLSXSheetValueReader.rowValue(row: row, atColumn: batchColumn, sharedStrings: sharedStrings) else { continue }
            let rowNumber = Int(row.reference)
            let isReserved = reservedCheckColumns.allSatisfy { column in
                XLSXSheetValueReader.rowValue(row: row, atColumn: column, sharedStrings: sharedStrings) == nil
            }
            snapshotRows.append(RegistryRowSnapshot(rowNumber: rowNumber, batchId: batchId, isReserved: isReserved))
        }

        return RegistrySheetSnapshot(sheetName: sheetName, availableHeaders: availableHeaders, rows: snapshotRows)
    }

    // MARK: - Helpers

    private static func dedupOrderPreserving(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}
