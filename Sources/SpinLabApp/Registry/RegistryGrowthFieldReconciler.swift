import Foundation

/// Registry-facing field reconciliation result — Phase 5.4.5 compatible-
/// completion. Replaces a plain agreement/conflict binary at the exact
/// Existing-row reconciliation boundary (`RegistryGrowthImportPlanner`) for
/// fields with real structured semantics (date, energy): two values can
/// disagree on nothing yet still differ in completeness, in which case the
/// richer/merged value is a safe automatic enrichment rather than a conflict
/// requiring manual review.
enum RegistryGrowthFieldReconciliation: Hashable, Sendable {
    /// Both sides resolve to the same semantic value; no write needed.
    case equal
    /// No semantic component known by both sides disagrees, and the merged
    /// value carries strictly more information than the exact Registry
    /// value alone — safe to write automatically.
    case compatible(mergedValue: String)
    /// The same semantic component is known by both sides with different
    /// values — never auto-resolved.
    case conflict(registryValue: String, obsidianValue: String)
    /// One or both sides could not be safely parsed into named semantic
    /// components — preserves prior fail-safe behavior (a non-editable
    /// diagnostic), never a guessed merge.
    case unresolved
}

/// The one place that computes `RegistryGrowthFieldReconciliation` for a
/// field with real structured semantics, consuming the exact Registry row
/// value and the canonical Obsidian claim directly — never the lossy
/// leading-magnitude/leading-number `SampleDossierBuilder` projection (Phase
/// 4), which is built for a different purpose (Library-vs-Obsidian dossier
/// overview) and is not information-preserving enough to tell a richer value
/// from a merely-differently-formatted one.
enum RegistryGrowthFieldReconciler {
    /// `registrySemanticISODate` is the same fully-resolved date
    /// `RegistryGrowthImportPlanner.RegistryRowSnapshot.semanticDate` already
    /// carries (Excel serial or full "yyyy.M.d" text) — nil only when the
    /// Registry cell is itself a year-omitting text (e.g. "8月2日") or
    /// otherwise unparseable by that path. `registryRawText` is the exact
    /// cell text either way.
    static func reconcileDate(
        registryRawText: String,
        registrySemanticISODate: String?,
        obsidianRawISO: String
    ) -> RegistryGrowthFieldReconciliation {
        guard let obsidianISO = RegistryGrowthDateMapper.canonicalISODate(fromObsidianISODate: obsidianRawISO),
              let obsidianDisplay = RegistryGrowthDateMapper.registryDisplayString(fromISODate: obsidianRawISO) else {
            return .unresolved
        }

        if let registrySemanticISODate {
            return registrySemanticISODate == obsidianISO
                ? .equal
                : .conflict(registryValue: registryRawText, obsidianValue: obsidianDisplay)
        }

        // Registry's own date has no fully-resolved semantic value — the
        // only remaining safely-parseable shape is the year-omitting "M月D日"
        // text convention (never an Excel serial; that always resolves
        // above). If it disagrees with Obsidian on month/day, that alone is
        // already enough to be a real conflict, independent of year.
        guard let registryPartial = RegistryGrowthDateMapper.partialComponents(fromRegistryRawText: registryRawText),
              let obsidianPartial = RegistryGrowthDateMapper.partialComponents(fromObsidianISODate: obsidianISO) else {
            return .unresolved
        }
        guard registryPartial.month == obsidianPartial.month, registryPartial.day == obsidianPartial.day else {
            return .conflict(registryValue: registryRawText, obsidianValue: obsidianDisplay)
        }
        guard let merged = RegistryGrowthDateMapper.registryDisplayString(fromComponents: obsidianPartial) else {
            return .unresolved
        }
        return .compatible(mergedValue: merged)
    }

    static func reconcileEnergy(registryValue: String, obsidianRaw: String) -> RegistryGrowthFieldReconciliation {
        guard let obsidian = RegistryGrowthEnergyMapper.parseObsidian(obsidianRaw),
              let registry = RegistryGrowthEnergyMapper.parseRegistry(registryValue) else {
            // Fail-safe generic rule (spec §2): a value this parser can't
            // safely structure still counts as equal on exact canonical
            // (trimmed) string equality — never guessed past that, and
            // never surfaced as a diagnostic just because the new
            // structured schema doesn't happen to recognize an
            // already-matching legacy value (e.g. a bare unitless "1.2").
            let registryComparable = registryValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let obsidianComparable = obsidianRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            return registryComparable == obsidianComparable ? .equal : .unresolved
        }

        let obsidianDisplay = RegistryGrowthEnergyMapper.registryDisplayString(obsidian)
        if let r = registry.primary, let o = obsidian.primary, r != o {
            return .conflict(registryValue: registryValue, obsidianValue: obsidianDisplay)
        }
        if let r = registry.voltage, let o = obsidian.voltage, r != o {
            return .conflict(registryValue: registryValue, obsidianValue: obsidianDisplay)
        }
        if let r = registry.output, let o = obsidian.output, r != o {
            return .conflict(registryValue: registryValue, obsidianValue: obsidianDisplay)
        }

        let merged = RegistryGrowthEnergyMapper.EnergyComponents(
            primary: registry.primary ?? obsidian.primary,
            voltage: registry.voltage ?? obsidian.voltage,
            output: registry.output ?? obsidian.output
        )
        guard merged != registry else { return .equal }
        return .compatible(mergedValue: RegistryGrowthEnergyMapper.registryDisplayString(merged))
    }
}
