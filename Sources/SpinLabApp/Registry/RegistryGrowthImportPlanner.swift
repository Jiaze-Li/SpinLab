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

    func build(vault: ObsidianVaultIndex, dossier: SampleDossierIndex, registryURL: URL) throws -> RegistryGrowthImportPlan {
        let fingerprint = try XLSXWorkbookKit.contentFingerprint(of: registryURL)

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

        var items: [RegistryGrowthImportItem] = []
        var diagnostics: [RegistryGrowthPlanDiagnostic] = []

        for batchRecord in vault.batches.sorted(by: { $0.batchId < $1.batchId }) {
            items.append(buildItem(batchId: batchRecord.batchId, vault: vault, dossier: dossier, snapshots: snapshots))
        }

        for diagnostic in vault.diagnostics where diagnostic.kind == .unresolvedBatchIdentity || diagnostic.kind == .ambiguousBatchIdentity {
            diagnostics.append(RegistryGrowthPlanDiagnostic(message: diagnostic.message, notePath: diagnostic.notePath))
        }

        return RegistryGrowthImportPlan(
            registryFingerprint: fingerprint,
            registrySourcePath: registryURL.path,
            builtAt: .now,
            items: items,
            diagnostics: diagnostics
        )
    }

    // MARK: - Per-batch item construction

    private func buildItem(batchId: String, vault: ObsidianVaultIndex, dossier: SampleDossierIndex, snapshots: [String: RegistrySheetSnapshot]) -> RegistryGrowthImportItem {
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
            reasons.append(.obsidianInternalConflict(field: "growthDate"))
        } else if let mapped = RegistryGrowthDateMapper.registryDisplayString(fromISODate: dateClaims[0].value) {
            registryDate = mapped
        } else {
            reasons.append(.missingDate)
        }

        if materialClaims.isEmpty {
            reasons.append(.missingMaterialEvidence)
        } else if Set(materialClaims.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }).count > 1 {
            reasons.append(.obsidianInternalConflict(field: "material"))
        }

        if substrateClaims.isEmpty {
            reasons.append(.missingSubstrateEvidence)
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
                warnings.append("No Obsidian evidence for \(obsidianField.rawValue); column will be left blank.")
                continue
            }
            if hasInternalConflict(obsidianField) {
                reasons.append(.obsidianInternalConflict(field: obsidianField.rawValue))
                continue
            }
            secondaryValues[mappingField] = claims[0]
        }

        let materialEvidenceSet = Set(materialClaims.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) })
        let targetSheet = RegistryGrowthRouting.targetSheet(forBatchId: batchId, materialEvidence: materialEvidenceSet)
        if targetSheet == nil {
            reasons.append(.unroutableMaterialOrPrefix(rawHint: materialClaims.first?.value))
        }

        if let targetSheet, snapshots[targetSheet] == nil {
            reasons.append(.targetSheetNotFound(sheetName: targetSheet))
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
                warnings: warnings,
                blockingReasons: reasons
            )
        }

        guard let targetSheet, let snapshot = snapshots[targetSheet] else {
            // Unreachable given the checks above, but fail closed rather
            // than force-unwrap.
            let reason = RegistryGrowthBlockingReason.other("Internal: routed sheet snapshot missing after routing succeeded.")
            return RegistryGrowthImportItem(
                batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: targetSheet,
                action: .blocked(reasons: [reason]), columnValues: [:], provenance: [],
                blankColumns: [], warnings: warnings, blockingReasons: [reason]
            )
        }

        let matchingRows = snapshot.rows.filter { $0.batchId == batchId }
        if matchingRows.count > 1 {
            let reason = RegistryGrowthBlockingReason.duplicateRegistryRow(sheet: targetSheet, rowNumbers: matchingRows.map(\.rowNumber).sorted())
            return RegistryGrowthImportItem(
                batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: targetSheet,
                action: .blocked(reasons: [reason]), columnValues: [:], provenance: [],
                blankColumns: [], warnings: warnings, blockingReasons: [reason]
            )
        }

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

        let substrateJoined = Self.dedupOrderPreserving(substrateClaims.map(\.raw)).joined(separator: ", ")
        setValue(.substrate, substrateJoined, notePath: substrateClaims.first?.provenance.notePath, rawKey: substrateClaims.first?.provenance.rawKey, rawValue: substrateClaims.first?.provenance.rawValue)

        for (_, mappingField) in secondaryFields {
            let claim = secondaryValues[mappingField]
            setValue(mappingField, claim?.value, notePath: claim?.provenance.notePath, rawKey: claim?.provenance.rawKey, rawValue: claim?.provenance.rawValue)
        }

        let action: RegistryGrowthImportAction
        if let existingRow = matchingRows.first {
            if existingRow.isReserved {
                action = .fillReservedRow(targetSheet: targetSheet, rowNumber: existingRow.rowNumber)
            } else {
                action = .skipExisting(targetSheet: targetSheet, rowNumber: existingRow.rowNumber)
                columnValues = [:]
                provenance = []
                blankColumns = []
                // Spec §9/§19: an existing row is never overwritten, even
                // when Obsidian disagrees with it — but the disagreement is
                // still worth surfacing to whoever reviews the preview.
                if let batchDossier {
                    for (field, reconciliation) in batchDossier.growthFields {
                        if case .conflict = reconciliation {
                            warnings.append("Obsidian and the existing Registry row disagree on \(field.rawValue); the existing row is kept unchanged.")
                        }
                    }
                }
            }
        } else {
            action = .appendNewRow(targetSheet: targetSheet)
        }

        return RegistryGrowthImportItem(
            batchId: batchId,
            sourceNotePaths: notePaths,
            targetSheetHint: targetSheet,
            action: action,
            columnValues: columnValues,
            provenance: provenance,
            blankColumns: blankColumns,
            warnings: warnings,
            blockingReasons: []
        )
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
