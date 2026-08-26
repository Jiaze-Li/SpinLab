import Foundation

// MARK: - Reconciliation projection
//
// `SampleDossierIndex` is a pure join of `LibraryIndex` and
// `ObsidianVaultIndex`. It is not a third source of truth — see Phase 4 spec
// §12. Authority is per-record, per-claim (§15): a field is "Library-owned"
// or "Obsidian-owned" only insofar as one side actually carries evidence for
// it, never as a global precedence rule.

enum DossierRecordSide: Hashable, Sendable {
    case library
    case obsidian
}

enum DossierFieldReconciliation<Value: Hashable & Sendable>: Hashable, Sendable {
    /// Only the Library side has a value for this field.
    case libraryOnly(Value)
    /// Only Obsidian has a value for this field.
    case obsidianOnly(Value)
    /// Both sides have a value and it agrees after light normalization.
    case agreement(Value)
    /// Both sides have a value and they disagree. Never silently resolved —
    /// must be surfaced to the caller.
    case conflict(library: Value, obsidian: Value)
    /// Two or more Obsidian notes disagree with each other on this field,
    /// independent of what Library says. `libraryValue` is carried alongside
    /// (present or nil) rather than forced into `.conflict`/`.agreement`,
    /// since the disagreement's source is Obsidian-internal, not
    /// Library-vs-Obsidian — collapsing it into `.obsidianOnly` with a
    /// first-wins value would silently discard the disagreement.
    case obsidianInternalConflict(claims: [ObsidianFieldClaim], libraryValue: Value?)
}

/// One Batch's growth-field reconciliation between Library and Obsidian.
struct BatchDossier: Hashable, Sendable {
    var batchId: String
    var hasLibraryRecord: Bool
    /// Obsidian note paths contributing to this batch (empty if Obsidian has
    /// no record for this batch at all).
    var obsidianNotePaths: [String]
    var growthFields: [ObsidianGrowthField: DossierFieldReconciliation<String>]
    /// Sample keys under this batch known to either side.
    var sampleKeys: [String]
    var diagnostics: [ObsidianDiagnostic]
}

/// One Sample's reconciliation between Library and Obsidian.
struct SampleDossier: Hashable, Sendable {
    var sampleKey: String
    var batchId: String
    var hasLibraryRecord: Bool
    var obsidianNotePaths: [String]
    /// Test/measurement-status claims from Obsidian, keyed by workflow token.
    /// Library today has no equivalent structured field, so these are always
    /// `obsidianOnly` — surfaced as-is rather than forced into a
    /// reconciliation shape with no Library counterpart to compare against.
    var obsidianTestStatus: [String: [ObsidianFieldClaim]]
    var obsidianSampleObservations: [ObsidianFieldClaim]
    var diagnostics: [ObsidianDiagnostic]
}

/// Runtime-rebuildable join result. Never persisted as a source of truth
/// (Phase 4 spec §19) — callers rebuild it from `LibraryIndex` +
/// `ObsidianVaultIndex` whenever needed.
struct SampleDossierIndex: Sendable {
    var batches: [BatchDossier]
    var samples: [SampleDossier]
    /// Diagnostics that are not attributable to one specific batch/sample
    /// (e.g. an Obsidian note whose batch identity never resolved at all).
    var unattachedDiagnostics: [ObsidianDiagnostic]
}
