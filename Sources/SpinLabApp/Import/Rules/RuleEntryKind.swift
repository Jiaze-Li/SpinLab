import Foundation

/// Describes the extraction strategy for a condition field definition.
///
/// Owned by the Import/Rules layer so that both `RuleCanonicalizer` and
/// `ConditionRulesHandbookStore` can reference it without an inverted dependency.
enum RuleEntryKind: String, Equatable {
    /// Value is a plain suffix appended to the extracted token (e.g. "80K").
    case unitSuffix = "unit_suffix"
    /// Value is derived from a token-map lookup table.
    case tokenMap = "token_map"
    /// Read-only entry synthesised from built-in catalog; not user-editable.
    case customReadOnly = "custom_read_only"
}
