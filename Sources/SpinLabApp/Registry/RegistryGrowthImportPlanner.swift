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
        return item.warnings.isEmpty && item.existingDifferences.isEmpty
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
        // Exact-match identity is the incoming batch id's own human
        // identifier (series + number), not a raw string compare — this is
        // what lets a composite Registry cell like `"PN110/SRO1"` be found
        // by either `PN110` or `SRO1` (spec: both point to the same row).
        // An incoming batch id that itself doesn't parse under
        // `RegistryBatchIdentity` (rare — Obsidian batch ids are expected to
        // be single tokens) falls back to the previous raw-string compare
        // rather than matching nothing.
        let allMatches: [(sheet: String, row: RegistryRowSnapshot)] = snapshots.flatMap { sheetName, snapshot -> [(sheet: String, row: RegistryRowSnapshot)] in
            if let incoming = RegistryBatchIdentity.parse(batchId) {
                return snapshot.rows.filter { $0.matchesIdentifier(series: incoming.series, number: incoming.number) }.map { (sheetName, $0) }
            }
            return snapshot.rows.filter { $0.batchId == batchId }.map { (sheetName, $0) }
        }

        // Growth fields that have a Phase 4 reconciliation to reuse for
        // Existing conflicts — same mapping `secondaryFields` below uses.
        // Deliberately the ONE place that decides "is this an Existing
        // conflict" for a given field: reuses `batchDossier.growthFields`'s
        // existing `.conflict` verdict (spec §9/Phase 5C §2) rather than a
        // second comparison. `.growthEnvironment` has no Registry column and
        // is never in this table.
        let existingDiffFieldMap: [(ObsidianGrowthField, RegistryGrowthFieldMapping.Field)] = [
            (.growthDate, .date),
            (.growthTemperature, .growthTemperature),
            (.targetSubstrateDistance, .targetSubstrateDistance),
            (.oxygenPressure, .oxygenPressure),
            (.laserEnergy, .laserEnergy),
            (.pulseCount, .pulseCount)
        ]

        /// Structured field-level differences for an Existing row, a
        /// fallback free-text warning for any conflict field this function
        /// could not safely resolve into an exact editable value (spec:
        /// "surface a non-editable diagnostic rather than fabricating
        /// values"), and — Phase 5.4.5 — planned safe field enrichments for
        /// any field where the exact Registry value and the canonical
        /// Obsidian claim disagree on nothing yet Obsidian carries strictly
        /// more information. `differences`/`plannedEdits`/`fallbackWarnings`
        /// are disjoint per field — a field never appears in more than one.
        func existingRowDifferences(row: RegistryRowSnapshot, availableHeaders: Set<String>) -> (differences: [RegistryGrowthExistingDifference], fallbackWarnings: [String], plannedEdits: [RegistryGrowthExistingFieldEdit]) {
            var differences: [RegistryGrowthExistingDifference] = []
            var fallbackWarnings: [String] = []
            var plannedEdits: [RegistryGrowthExistingFieldEdit] = []
            for (obsidianField, mappingField) in existingDiffFieldMap {
                let humanLabel = RegistryGrowthFieldMapping.humanLabel(for: obsidianField)

                // PR #169 cumulative-review repair item 1: every field here
                // is compared directly against the exact matched
                // `RegistryRowSnapshot` (`row`, already identity-aware —
                // reached via `allMatches`'s peer-identifier lookup, so it
                // is the same physical row regardless of whether it was
                // found via `PN110` or a composite `PN110/SRO1` cell) and
                // the raw Obsidian claim, never `SampleDossierBuilder`'s
                // `batchDossier.growthFields[obsidianField]` verdict.
                // `SampleDossierBuilder`'s Batch join is intentionally exact
                // `batchId` equality (Phase 4 spec §13, unchanged here) — a
                // composite Registry cell's row is joined under Library's
                // own batch id (`PN110/SRO1`), not under either bare peer
                // identifier, so a dossier looked up by `PN110` alone is
                // `.obsidianOnly` for these fields even though the exact
                // row (found here via `row`) really does disagree. Gating
                // on that verdict silently dropped every genuine
                // temperature/distance/pressure/pulse disagreement whenever
                // the matched row's identifier cell was composite.
                let obsidianClaims = obsidianBatch?.growthClaims[obsidianField] ?? []
                guard !obsidianClaims.isEmpty else { continue }
                guard let header = RegistryGrowthFieldMapping.header(for: mappingField, availableHeaders: availableHeaders) else { continue }
                guard let obsidianRaw = Set(obsidianClaims.map(\.value)).count == 1 ? obsidianClaims.first?.value : nil else {
                    fallbackWarnings.append("Obsidian notes disagree with each other on \(humanLabel); the existing row is kept unchanged.")
                    continue
                }

                // PR #169 repair pass 5 item 2: a blank Registry cell is
                // missing evidence, not a synchronized field — skipping the
                // comparison here (as this used to) made a blank Registry
                // field with real Obsidian evidence look clean/Existing.
                // Obsidian's deterministic value is instead planned as a
                // compatible enrichment, same as a `.compatible` reconciler
                // verdict below — never through the reconciler itself, since
                // every reconciler treats an unparseable/absent Registry
                // side as `.conflict`/`.unresolved`, not "nothing to
                // disagree with."
                let existingRegistryValue = row.columnValues[header]
                if (existingRegistryValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let obsidianDisplayValue: String
                    switch obsidianField {
                    case .growthDate:
                        obsidianDisplayValue = RegistryGrowthDateMapper.registryDisplayString(fromISODate: obsidianRaw) ?? obsidianRaw
                    case .pulseCount:
                        obsidianDisplayValue = RegistryGrowthPulseMapper.registryDisplayString(fromRawClaim: obsidianRaw) ?? obsidianRaw
                    default:
                        obsidianDisplayValue = obsidianRaw
                    }
                    plannedEdits.append(RegistryGrowthExistingFieldEdit(
                        batchId: batchId, targetSheet: "", rowNumber: row.rowNumber, columnHeader: header,
                        field: mappingField, originalRegistryValue: existingRegistryValue ?? "", finalValue: obsidianDisplayValue,
                        obsidianValue: obsidianDisplayValue
                    ))
                    continue
                }
                guard let registryValue = existingRegistryValue else { continue }

                switch obsidianField {
                case .growthDate, .laserEnergy:
                    // Never gates on the Phase 4 `SampleDossierBuilder`
                    // verdict (spec: that projection is lossy for date/
                    // energy — e.g. it compares energy by leading magnitude
                    // only, so a Registry value that's a strict subset of a
                    // richer Obsidian claim with the SAME leading magnitude
                    // reads as `.agreement` there and would never reach a
                    // gate keyed on `.conflict`).
                    let reconciliation: RegistryGrowthFieldReconciliation = obsidianField == .growthDate
                        ? RegistryGrowthFieldReconciler.reconcileDate(registryRawText: registryValue, registrySemanticISODate: row.semanticDate, obsidianRawISO: obsidianRaw)
                        : RegistryGrowthFieldReconciler.reconcileEnergy(registryValue: registryValue, obsidianRaw: obsidianRaw)
                    switch reconciliation {
                    case .equal:
                        continue
                    case let .compatible(mergedValue):
                        // Display-ready Obsidian value for the review UI —
                        // same convention `.conflict` below already uses
                        // (registry display formatting for date, the raw
                        // claim text for energy since Registry's own energy
                        // notation and Obsidian's positional-triple notation
                        // are deliberately shown as distinct source claims).
                        let obsidianDisplayValue = obsidianField == .growthDate
                            ? (RegistryGrowthDateMapper.registryDisplayString(fromISODate: obsidianRaw) ?? obsidianRaw)
                            : obsidianRaw
                        plannedEdits.append(RegistryGrowthExistingFieldEdit(
                            batchId: batchId, targetSheet: "", rowNumber: row.rowNumber, columnHeader: header,
                            field: mappingField, originalRegistryValue: registryValue, finalValue: mergedValue,
                            obsidianValue: obsidianDisplayValue
                        ))
                    case let .conflict(registryValue, obsidianValue):
                        differences.append(RegistryGrowthExistingDifference(
                            field: mappingField, header: header, registryValue: registryValue, obsidianValue: obsidianValue
                        ))
                    case .unresolved:
                        fallbackWarnings.append("Obsidian and the existing Registry row disagree on \(humanLabel); the existing row is kept unchanged.")
                    }

                case .pulseCount:
                    // Obsidian side is shown in canonical Registry notation
                    // (spec §8) — falls back to the raw claim, unchanged,
                    // if it doesn't parse (fail-safe, never a guess).
                    let obsidianValue = RegistryGrowthPulseMapper.registryDisplayString(fromRawClaim: obsidianRaw) ?? obsidianRaw
                    // Semantic pulse identity (spec §4/§5): an omitted
                    // frequency means the confirmed default 2 Hz, so
                    // "1000/3000" and "1000 (2Hz) /3000 (2Hz)" are the same
                    // value even though their display strings differ. An
                    // explicit non-default frequency on either side is
                    // never silently normalized away — comparing the
                    // parsed `Pulse` structs (not the strings) preserves
                    // that distinction.
                    var semanticEqual: Bool?
                    if let registryPulse = RegistryGrowthPulseMapper.parse(registryValue),
                       let obsidianPulse = RegistryGrowthPulseMapper.parse(obsidianRaw) {
                        semanticEqual = (registryPulse == obsidianPulse)
                    }
                    let registryComparable = registryValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let obsidianComparable = obsidianValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isEqual = semanticEqual ?? (registryComparable == obsidianComparable)
                    guard !isEqual else { continue }
                    differences.append(RegistryGrowthExistingDifference(
                        field: mappingField, header: header, registryValue: registryValue, obsidianValue: obsidianValue
                    ))

                default:
                    // growthTemperature / targetSubstrateDistance /
                    // oxygenPressure: leading-magnitude comparison, same
                    // normalization `SampleDossierBuilder` uses (never a
                    // raw trimmed-string compare — that would newly flag a
                    // pure unit-format difference, e.g. "700 C" vs
                    // "700 °C", as a conflict now that this path no longer
                    // rides on the dossier's own pre-filtered `.conflict`
                    // verdict).
                    let reconciliation = RegistryGrowthFieldReconciler.reconcileMagnitude(registryValue: registryValue, obsidianRaw: obsidianRaw)
                    guard case let .conflict(registryValue, obsidianValue) = reconciliation else { continue }
                    differences.append(RegistryGrowthExistingDifference(
                        field: mappingField, header: header, registryValue: registryValue, obsidianValue: obsidianValue
                    ))
                }
            }

            // PR #169 repair pass 5 item 1: material identity is deliberately
            // excluded from `ObsidianGrowthField`/`existingDiffFieldMap`
            // (spec: material/substrate have no Phase 4 reconciliation), so
            // without this check a fundamental target-material mismatch
            // (Registry 靶 vs Obsidian material claim) could reach
            // `isCleanExisting`/ENRICH undetected. Reuses
            // `RegistryGrowthRouting.canonicalGrowthMaterialToken` — the
            // existing SRO alias normalization already used for PN routing —
            // rather than a raw string compare or a fresh alias table, so an
            // alias pair (e.g. "SRO" vs "SrRuO3") never false-flags. Only
            // ever contributes a `.differences` entry — never a planned
            // enrichment: a blank Registry 靶 cell is not handled here (fix
            // item 1 is scoped to conflict detection only; item 2's generic
            // blank-field enrichment does not apply to material, which has
            // no `ObsidianGrowthField`/`existingDiffFieldMap` entry to route
            // through).
            if let materialHeader = RegistryGrowthFieldMapping.header(for: .material, availableHeaders: availableHeaders),
               let registryMaterialValue = row.columnValues[materialHeader] {
                let trimmedRegistryMaterial = registryMaterialValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedRegistryMaterial.isEmpty {
                    let obsidianMaterialValues = Set(materialClaims.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                    if obsidianMaterialValues.count == 1, let obsidianMaterialRaw = obsidianMaterialValues.first {
                        let registryCanonical = RegistryGrowthRouting.canonicalGrowthMaterialToken(trimmedRegistryMaterial)
                        let obsidianCanonical = RegistryGrowthRouting.canonicalGrowthMaterialToken(obsidianMaterialRaw)
                        if registryCanonical != obsidianCanonical {
                            differences.append(RegistryGrowthExistingDifference(
                                field: .material, header: materialHeader, registryValue: registryMaterialValue, obsidianValue: obsidianMaterialRaw
                            ))
                        }
                    } else if obsidianMaterialValues.count > 1 {
                        fallbackWarnings.append("Obsidian notes disagree with each other on \(RegistryGrowthFieldMapping.materialHumanLabel); the existing row is kept unchanged.")
                    }
                }
            }

            return (differences, fallbackWarnings, plannedEdits)
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
            // Obsidian completeness). But a row whose own identifier cell
            // carries a malformed token (e.g. `"PN110/???"`) must never
            // collapse into a silent, compactable `.skipExisting` — the
            // malformed Registry state stays visible as `.blocked` instead
            // (never `isCleanExisting`, so it can't disappear through
            // Existing compaction).
            if !existingRow.malformedTokens.isEmpty {
                let reason = RegistryGrowthBlockingReason.populatedRowHasMalformedIdentifier(
                    sheet: existingSheet, rowNumber: existingRow.rowNumber, malformedTokens: existingRow.malformedTokens
                )
                return RegistryGrowthImportItem(
                    batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: existingSheet,
                    action: .blocked(reasons: [reason]), columnValues: [:], provenance: [],
                    blankColumns: [], expectedSampleKeys: [], warnings: [], blockingReasons: [reason]
                )
            }
            let availableHeaders = snapshots[existingSheet]?.availableHeaders ?? []
            let (differences, fallbackWarnings, plannedEdits) = existingRowDifferences(row: existingRow, availableHeaders: availableHeaders)
            // A row with any genuine conflict always stays `.skipExisting`
            // (spec §6: "if a real conflict exists, keep current Existing
            // conflict + Final editor behavior") — planned enrichments on
            // the same row are never auto-applied alongside an unresolved
            // conflict; the user resolves the conflict first, then a
            // subsequent preview re-evaluates enrichment on the now-clean row.
            // A row with any unresolved fallback (e.g. an unparsable
            // Registry value, or Obsidian notes disagreeing with each
            // other) also stays `.skipExisting` — ENRICH must mean every
            // field considered was judged equal or safely compatible, never
            // "mostly clean but something couldn't be checked".
            if differences.isEmpty, fallbackWarnings.isEmpty, !plannedEdits.isEmpty {
                let sheetScopedEdits = plannedEdits.map { edit -> RegistryGrowthExistingFieldEdit in
                    var edit = edit
                    edit.targetSheet = existingSheet
                    return edit
                }
                return RegistryGrowthImportItem(
                    batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: existingSheet,
                    action: .enrichExisting(targetSheet: existingSheet, rowNumber: existingRow.rowNumber, plannedFieldEdits: sheetScopedEdits),
                    // The current (pre-Apply) Registry row snapshot —
                    // presentation-only. `RegistryGrowthMutationService`
                    // never writes `.enrichExisting`'s `columnValues` (it
                    // writes via `plannedFieldEdits` exactly like a manual
                    // Existing edit, and explicitly `break`s on
                    // `.enrichExisting` in its per-item write switch), so
                    // populating this here only enables
                    // `RegistryGrowthImportPresentation
                    // .finalRegistryPreviewRows` to overlay the planned
                    // edits on top of the real current row.
                    columnValues: existingRow.columnValues, provenance: [], blankColumns: [], expectedSampleKeys: [],
                    warnings: fallbackWarnings, existingDifferences: [], blockingReasons: []
                )
            }
            return RegistryGrowthImportItem(
                batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: existingSheet,
                action: .skipExisting(targetSheet: existingSheet, rowNumber: existingRow.rowNumber),
                columnValues: [:], provenance: [], blankColumns: [], expectedSampleKeys: [],
                warnings: fallbackWarnings, existingDifferences: differences, blockingReasons: []
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
        } else if let incomplete = parsedSubstrates.first(where: { $0.material == nil || $0.orientation == nil }) {
            // Evidence exists and parsed (spec: `unresolvedSubstrateIdentity`
            // does not apply — `LibrarySubstrateParser.parse` treats a lone
            // orientation/treatment signal as sufficient to return a
            // result), but this NEW Sample's identity would still be
            // written with an unresolved material/orientation component
            // (PR #169 cumulative-review repair item 2) — e.g.
            // `substrate: 111` parses to `material: nil, orientation:
            // "111"`, which would otherwise reach `expectedSampleKeys`
            // below as a legacy `LNO11||UNKNOWN|111`-shaped key. Blocks
            // only the NEW append/fill path this branch is already scoped
            // to — a pre-existing historical row's own parse is untouched.
            reasons.append(.incompleteSubstrateIdentity(
                rawHint: substrateClaims.first?.raw,
                missingMaterial: incomplete.material == nil,
                missingOrientation: incomplete.orientation == nil
            ))
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
        // stronger fact than routing, but a row whose own identifier cell
        // carries a malformed token (e.g. `"PN110/???"`) must never be
        // silently filled — the malformed state is surfaced instead of
        // being paved over for the sake of a routing/fill decision.
        if let (existingSheet, existingRow) = allMatches.first, existingRow.isReserved,
           !existingRow.malformedTokens.isEmpty {
            reasons.append(.reservedRowHasMalformedIdentifier(
                sheet: existingSheet, rowNumber: existingRow.rowNumber, malformedTokens: existingRow.malformedTokens
            ))
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

        // PR #169 cumulative-review repair item 3: `setValue` below silently
        // drops a column whenever `RegistryGrowthFieldMapping.header` finds
        // no confirmed alias on `snapshot.availableHeaders` — fine for a
        // secondary field (spec: warning + blank cell is the designed
        // behavior), but a `requiredFields` entry with no header on the
        // sheet actually being written must block the item outright rather
        // than silently vanish from `columnValues`, since the later
        // read-contract only ever validates headers that made it into
        // `columnValues` and so can never catch this omission on its own.
        // Checked against the effective sheet — the row's own existing
        // sheet for a reserved-row fill, the resolved target sheet for an
        // append — never the nominally-routed sheet if the two disagree.
        let missingRequiredHeaders = RegistryGrowthFieldMapping.requiredFields
            .filter { RegistryGrowthFieldMapping.header(for: $0, availableHeaders: snapshot.availableHeaders) == nil }
            .sorted { $0.rawValue < $1.rawValue }
        if !missingRequiredHeaders.isEmpty {
            let headerReasons = missingRequiredHeaders.map {
                RegistryGrowthBlockingReason.missingRequiredRegistryHeader(
                    sheet: effectiveSheet, field: $0, humanLabel: RegistryGrowthFieldMapping.humanLabel(forField: $0)
                )
            }
            return RegistryGrowthImportItem(
                batchId: batchId, sourceNotePaths: notePaths, targetSheetHint: targetSheet,
                action: .blocked(reasons: headerReasons), columnValues: [:], provenance: [],
                blankColumns: [], expectedSampleKeys: [], warnings: warnings, blockingReasons: headerReasons
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

        setValue(.substrate, substrateJoined, notePath: substrateClaims.first?.provenance.notePath, rawKey: substrateClaims.first?.provenance.rawKey, rawValue: substrateClaims.first?.provenance.rawValue)

        for (_, mappingField) in secondaryFields {
            let claim = secondaryValues[mappingField]
            // Pulse count is written in the ONE canonical Registry
            // notation (spec §4/§6) — the same mapper the Existing
            // comparison uses — so Ready preview and the actual candidate
            // workbook write are always the same value (`columnValues` is
            // what `RegistryGrowthMutationService` writes verbatim). Falls
            // back to the raw claim, unchanged, if it doesn't parse
            // (fail-safe, never a guess).
            let mappedValue: String?
            if mappingField == .pulseCount, let raw = claim?.value {
                mappedValue = RegistryGrowthPulseMapper.registryDisplayString(fromRawClaim: raw) ?? raw
            } else {
                mappedValue = claim?.value
            }
            setValue(mappingField, mappedValue, notePath: claim?.provenance.notePath, rawKey: claim?.provenance.rawKey, rawValue: claim?.provenance.rawValue)
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
        /// The raw "编号" cell text, unsplit (e.g. `"PN110/SRO1"`).
        var batchId: String
        var isReserved: Bool
        /// This row's cell parsed into 1..N human identifiers via
        /// `RegistryIdentifierCell.parse(batchId)` — the single source used
        /// for exact-match/duplicate lookups (see `identifiers(matching:)`).
        var identifiers: [HumanIdentifier] = []
        /// Tokens inside `batchId` that did not parse under
        /// `RegistryBatchIdentity` (e.g. `"???"` in `"PN110/???"`).
        var malformedTokens: [String] = []
        /// This row's own cell values for every `RegistryGrowthFieldMapping`
        /// growth field whose confirmed header is present on this sheet —
        /// header → raw cell text, populated from the same single scan as
        /// everything else on this snapshot (Phase 5C). Never re-opens the
        /// workbook — this is what lets an Existing field difference show
        /// the exact Registry value being previewed, and lets
        /// `RegistryGrowthMutationService` re-verify a planned edit's
        /// "original Registry value" against a value the planner actually
        /// observed rather than a synthesized/cached copy.
        var columnValues: [String: String] = [:]
        /// The 日期 column's semantic `yyyy-MM-dd`, resolved from the raw
        /// cell's true underlying value (Excel date serial for a numeric
        /// cell, "yyyy.M.d" text for a text cell) rather than its display
        /// string — Phase 5.4.4. Nil when the sheet has no 日期 header, the
        /// row has no date cell, or the value can't be resolved without
        /// guessing (e.g. year-omitting text). Existing equality falls back
        /// to comparing `columnValues["日期"]` when this is nil.
        var semanticDate: String? = nil

        /// True if this row names the human identifier `series`+`number` —
        /// the identity-aware replacement for a raw `batchId == other`
        /// string comparison, since one cell may name more than one
        /// identifier and a row must be reachable via any of them.
        func matchesIdentifier(series: String, number: Int) -> Bool {
            identifiers.contains { $0.series == series && $0.number == number }
        }
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
        // header → column, for every confirmed growth field this sheet
        // actually has a header for. Reused both for the reserved-row check
        // above and for populating `RegistryRowSnapshot.columnValues` below —
        // one header resolution per sheet, not one per row.
        let mappedFieldColumns: [(field: RegistryGrowthFieldMapping.Field, header: String, column: Int)] = reservedCheckFields.compactMap { field in
            guard let header = RegistryGrowthFieldMapping.header(for: field, availableHeaders: availableHeaders),
                  let column = headerByColumn.first(where: { $0.value == header })?.key else { return nil }
            return (field, header, column)
        }
        let reservedCheckColumns: [Int] = mappedFieldColumns.map(\.column)

        var snapshotRows: [RegistryRowSnapshot] = []
        for row in rows.dropFirst() {
            guard let batchId = XLSXSheetValueReader.rowValue(row: row, atColumn: batchColumn, sharedStrings: sharedStrings) else { continue }
            let rowNumber = Int(row.reference)
            let isReserved = reservedCheckColumns.allSatisfy { column in
                XLSXSheetValueReader.rowValue(row: row, atColumn: column, sharedStrings: sharedStrings) == nil
            }
            let parsedCell = RegistryIdentifierCell.parse(batchId)
            var columnValues: [String: String] = [:]
            var semanticDate: String?
            for (field, header, column) in mappedFieldColumns {
                if let value = XLSXSheetValueReader.rowValue(row: row, atColumn: column, sharedStrings: sharedStrings) {
                    columnValues[header] = value
                    if field == .date, let isNumeric = XLSXSheetValueReader.isNumericCell(row: row, atColumn: column) {
                        semanticDate = RegistryGrowthDateMapper.semanticISODate(rawValue: value, isNumericCell: isNumeric)
                    }
                }
            }
            snapshotRows.append(RegistryRowSnapshot(
                rowNumber: rowNumber, batchId: batchId, isReserved: isReserved,
                identifiers: parsedCell.identifiers, malformedTokens: parsedCell.malformedTokens,
                columnValues: columnValues, semanticDate: semanticDate
            ))
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
