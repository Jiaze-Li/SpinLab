import Foundation

/// Structural helpers for migration/seed/repair of `library_import_rules.json`.
/// Source of truth for field values is always the bundled `library_import_rules.json`.
/// Never wire this into any runtime lookup path.
enum LegacyRegistryImportRulesDefaults {

    /// Returns `true` when any field the runtime depends on is empty.
    static func hasEmptyFields(_ draft: LibraryRegistryFileDraft) -> Bool {
        let r = draft.registry
        return r.sampleHeaderAliases.isEmpty
            || r.batchHeaderAliases.isEmpty
            || r.substrateHeaderAliases.isEmpty
            || r.sampleCellSeparators.isEmpty
            || r.numericKeyAliases.isEmpty
            || r.metadataLookupAliases.isEmpty
    }

    /// Returns a new draft with empty fields filled from `defaults`.
    /// Non-empty fields from `existing` are preserved.
    static func fillMissing(from defaults: LibraryRegistryFileDraft,
                             into existing: LibraryRegistryFileDraft) -> LibraryRegistryFileDraft {
        var r = existing
        if r.registry.sampleHeaderAliases.isEmpty    { r.registry.sampleHeaderAliases    = defaults.registry.sampleHeaderAliases }
        if r.registry.batchHeaderAliases.isEmpty     { r.registry.batchHeaderAliases     = defaults.registry.batchHeaderAliases }
        if r.registry.substrateHeaderAliases.isEmpty { r.registry.substrateHeaderAliases = defaults.registry.substrateHeaderAliases }
        if r.registry.excludedSheetNames.isEmpty     { r.registry.excludedSheetNames     = defaults.registry.excludedSheetNames }
        if r.registry.sampleCellSeparators.isEmpty   { r.registry.sampleCellSeparators   = defaults.registry.sampleCellSeparators }
        if r.registry.numericKeyAliases.isEmpty      { r.registry.numericKeyAliases      = defaults.registry.numericKeyAliases }
        if r.registry.metadataLookupAliases.isEmpty  { r.registry.metadataLookupAliases  = defaults.registry.metadataLookupAliases }
        return r
    }
}
