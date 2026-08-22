import Foundation

/// Pure presentation projections for `RegistryGrowthImportItem` — Phase 5B
/// Obsidian → Registry import UI only. Every function here is a
/// deterministic, non-business-logic projection (enum → human-readable
/// string, action → UI filter bucket). Never re-derives
/// `RegistryGrowthImportAction`, `isExecutable`, or sample identity — those
/// stay owned by `RegistryGrowthImportPlanner`.
enum RegistryGrowthImportPresentation {

    /// The three UI-visible buckets, mapped 1:1 from `RegistryGrowthImportAction`.
    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case ready
        case existing
        case blocked

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ready: return "Ready"
            case .existing: return "Existing"
            case .blocked: return "Blocked"
            }
        }
    }

    /// Classifies a plan item into its UI bucket. The only place this
    /// mapping is allowed to happen — every list/tab in the UI must call
    /// this rather than pattern-matching `item.action` itself.
    static func filter(for item: RegistryGrowthImportItem) -> Filter {
        switch item.action {
        case .appendNewRow, .fillReservedRow:
            return .ready
        case .skipExisting:
            return .existing
        case .blocked:
            return .blocked
        }
    }

    static func actionTitle(for item: RegistryGrowthImportItem) -> String {
        switch item.action {
        case .appendNewRow:
            return "Add new row"
        case .fillReservedRow:
            return "Fill reserved row"
        case .skipExisting:
            return "Already in Registry · Skip"
        case .blocked:
            return "Blocked"
        }
    }

    static func actionIcon(for item: RegistryGrowthImportItem) -> String {
        switch item.action {
        case .appendNewRow:
            return "plus.circle"
        case .fillReservedRow:
            return "pencil.circle"
        case .skipExisting:
            return "checkmark.circle"
        case .blocked:
            return "xmark.octagon"
        }
    }

    static func targetSheetText(for item: RegistryGrowthImportItem) -> String {
        item.targetSheetHint ?? "—"
    }

    /// Order-preserving summary of the columns the planner already resolved
    /// for this item — never re-normalizes or re-derives a value, only picks
    /// which already-resolved `columnValues` to show inline.
    static func summarySubtitle(for item: RegistryGrowthImportItem) -> String {
        let order: [RegistryGrowthFieldMapping.Field] = [
            .date, .substrate, .growthTemperature, .oxygenPressure, .laserEnergy
        ]
        let availableHeaders = Set(item.columnValues.keys)
        var parts: [String] = []
        for field in order {
            guard let header = RegistryGrowthFieldMapping.header(for: field, availableHeaders: availableHeaders),
                  let value = item.columnValues[header], !value.isEmpty else { continue }
            parts.append(value)
        }
        return parts.joined(separator: " · ")
    }

    static func existingSummary(for item: RegistryGrowthImportItem) -> String {
        guard case let .skipExisting(sheet, rowNumber) = item.action else { return "" }
        return "\(sheet) row \(rowNumber)"
    }

    /// Short badge label for the row/detail-header action indicator. Purely
    /// a shorter rendering of the same `action` enum already used by
    /// `actionTitle` — introduces no new classification.
    static func actionBadgeTitle(for item: RegistryGrowthImportItem) -> String {
        switch item.action {
        case .appendNewRow:
            return "NEW"
        case .fillReservedRow:
            return "FILL"
        case .skipExisting:
            return "EXISTING"
        case .blocked:
            return "BLOCKED"
        }
    }

    /// First compact summary line: substrate · date. Same already-resolved
    /// `columnValues` lookup as `summarySubtitle`, just a narrower field set.
    static func compactPrimaryLine(for item: RegistryGrowthImportItem) -> String {
        joinedFields([.substrate, .date], for: item)
    }

    /// Second compact summary line: growth temperature · oxygen pressure ·
    /// laser energy.
    static func compactSecondaryLine(for item: RegistryGrowthImportItem) -> String {
        joinedFields([.growthTemperature, .oxygenPressure, .laserEnergy], for: item)
    }

    private static func joinedFields(_ fields: [RegistryGrowthFieldMapping.Field], for item: RegistryGrowthImportItem) -> String {
        let availableHeaders = Set(item.columnValues.keys)
        var parts: [String] = []
        for field in fields {
            guard let header = RegistryGrowthFieldMapping.header(for: field, availableHeaders: availableHeaders),
                  let value = item.columnValues[header], !value.isEmpty else { continue }
            parts.append(value)
        }
        return parts.joined(separator: " · ")
    }

    /// Registry Preview rows in the sheet's own canonical column order
    /// (`RegistryGrowthFieldMapping.Field.allCases`), falling back to any
    /// remaining resolved columns (alphabetical) that aren't part of the
    /// confirmed field mapping. Never drops or re-derives a value — only
    /// orders the same `columnValues` the planner already resolved.
    static func orderedRegistryPreviewRows(for item: RegistryGrowthImportItem) -> [(header: String, value: String)] {
        let availableHeaders = Set(item.columnValues.keys)
        var seenHeaders = Set<String>()
        var rows: [(header: String, value: String)] = []
        for field in RegistryGrowthFieldMapping.Field.allCases {
            guard let header = RegistryGrowthFieldMapping.header(for: field, availableHeaders: availableHeaders),
                  let value = item.columnValues[header] else { continue }
            rows.append((header, value))
            seenHeaders.insert(header)
        }
        for (header, value) in item.columnValues.sorted(by: { $0.key < $1.key }) where !seenHeaders.contains(header) {
            rows.append((header, value))
        }
        return rows
    }

    static func blockingReasonText(_ reason: RegistryGrowthBlockingReason) -> String {
        switch reason {
        case .missingBatchId:
            return "Missing batch id."
        case .missingDate:
            return "Missing date."
        case .missingMaterialEvidence:
            return "Missing material/target evidence."
        case .missingSubstrateEvidence:
            return "Missing substrate evidence."
        case let .unresolvedSubstrateIdentity(rawHint):
            if let rawHint, !rawHint.isEmpty {
                return "Unresolved substrate identity (\(rawHint))."
            }
            return "Unresolved substrate identity."
        case let .unroutableMaterialOrPrefix(rawHint):
            if let rawHint, !rawHint.isEmpty {
                return "Unroutable material/prefix (\(rawHint))."
            }
            return "Unroutable material/prefix."
        case let .ambiguousTargetSheet(batchSeries, candidateSheets):
            return "\(batchSeries) 系列同时出现在多个 Registry sheet（\(candidateSheets.joined(separator: "、"))），无法确定目标位置。"
        case let .routingEvidenceConflict(batchSeries, observedSheet, explicitSheet):
            return "Registry 历史编号（\(batchSeries) 系列）指向 \(observedSheet)，但显式路由规则指向 \(explicitSheet)。"
        case let .targetSheetNotFound(sheetName):
            return "Target sheet not found: \(sheetName)."
        case let .duplicateRegistryRow(sheet, rowNumbers):
            return "Duplicate Registry rows on \(sheet): \(rowNumbers.map(String.init).joined(separator: ", "))."
        case let .obsidianInternalConflict(field):
            return "Obsidian notes disagree on \(field)."
        case .obsidianDateConflict:
            return "Obsidian notes disagree on the date."
        case let .libraryObsidianConflictOnExistingBatch(field):
            return "Obsidian and the existing Registry batch disagree on \(field)."
        case let .other(message):
            return message
        }
    }

    static func blockingReasonsText(for item: RegistryGrowthImportItem) -> String {
        item.blockingReasons.map(blockingReasonText).joined(separator: "\n")
    }

    /// Human-readable rendering of a canonical sampleKey (e.g. `LNO15 · STO(001)`
    /// for `LNO15||STO|001`). Always goes through the shared
    /// `SampleSemanticDescriptor.fromSampleKey` parser — never re-implements
    /// `|`-splitting locally — and never echoes the raw canonical key back to
    /// the user, even on parse failure.
    ///
    /// Only guards against a missing batch (the one thing a real
    /// `expectedSampleKeys` entry can never lack). It does not re-validate
    /// material/orientation/processing tokens against the classifier —
    /// `fromSampleKey` deliberately trusts those as already-canonical (see
    /// its doc comment), and `expectedSampleKeys` is only ever populated by
    /// the planner from an already-validated `SampleSemanticDescriptor`.
    /// Re-validating semantic fields here would duplicate identity logic
    /// into the presentation layer, which this enum's own contract forbids.
    static func humanSampleLabel(for sampleKey: String) -> String {
        guard let descriptor = SampleSemanticDescriptor.fromSampleKey(sampleKey),
              let batch = descriptor.batch, !batch.isEmpty else {
            // A canonical sampleKey always carries a batch — a key that parses
            // structurally but has no batch is not a real sample identity, so
            // fall back rather than render whatever else the key happened to
            // contain (which could be an unrelated machine-looking string).
            return "Unrecognized sample"
        }
        var labels: [String] = [batch]
        if !descriptor.processingTokens.isEmpty {
            labels.append(descriptor.processingTokens.sorted().joined(separator: " · "))
        }
        switch (descriptor.material, descriptor.orientation) {
        case let (material?, orientation?):
            labels.append("\(material)(\(orientation))")
        case let (material?, nil):
            labels.append(material)
        case let (nil, orientation?):
            labels.append(orientation)
        case (nil, nil):
            break
        }
        return labels.joined(separator: " · ")
    }

    /// Groups an item's provenance entries by source note path, keeping only
    /// the human-readable Registry column headers each note contributed —
    /// never `rawKey`/`rawValue`/values (already shown in Registry Preview).
    /// Only returns notes that actually contributed at least one final
    /// Registry field: `sourceNotePaths` names every note *associated* with
    /// the batch, but `provenance` is what backs the selected values, so a
    /// note with an empty `fieldHeaders` group here would misrepresent an
    /// uninvolved note as a value source. Order follows `item.sourceNotePaths`
    /// (the item-level source contract); reads only `sourceNotePaths` and
    /// `provenance`, never recomputes an authoritative source, a value,
    /// routing, or identity.
    static func sourceFieldHeaders(for item: RegistryGrowthImportItem) -> [(notePath: String, fieldHeaders: [String])] {
        var orderedPaths: [String] = []
        for path in item.sourceNotePaths where !orderedPaths.contains(path) {
            orderedPaths.append(path)
        }
        return orderedPaths.compactMap { path in
            var headers: [String] = []
            for entry in item.provenance where entry.notePath == path && !headers.contains(entry.columnHeader) {
                headers.append(entry.columnHeader)
            }
            guard !headers.isEmpty else { return nil }
            return (notePath: path, fieldHeaders: headers)
        }
    }

    /// Every Obsidian note associated with an item, ordered and deduplicated,
    /// regardless of whether it contributed a final Registry field. Fallback
    /// display only — for items that carry no `provenance` at all (e.g.
    /// Existing/Blocked items never populate it), so the UI still shows
    /// which notes the batch came from without fabricating field
    /// attribution `sourceFieldHeaders` cannot support.
    static func associatedSourceNotePaths(for item: RegistryGrowthImportItem) -> [String] {
        var ordered: [String] = []
        for path in item.sourceNotePaths where !ordered.contains(path) {
            ordered.append(path)
        }
        return ordered
    }
}
