import Foundation

/// Shared match.type-honoring substrate classifier, reused by every sample-identity entry
/// point (Registry substrate-cell parsing, filename/free-text parsing, canonical descriptor
/// validation) so a given rule config resolves to the same material/treatment/orientation
/// regardless of which import path invokes it. Wraps `FilenameRuleSet.compiled`'s three
/// entry arrays and applies one equals-then-contains precedence consistently.
struct SubstrateSemanticClassifier {
    private let materials: [FilenameRuleSet.CompiledSubstrateEntry]
    private let treatments: [FilenameRuleSet.CompiledSubstrateEntry]
    private let orientations: [FilenameRuleSet.CompiledSubstrateEntry]

    init(compiled: FilenameRuleSet.CompiledRules) {
        materials = compiled.substrateMaterialEntries
        treatments = compiled.substrateTreatmentEntries
        orientations = compiled.substrateOrientationEntries
    }

    init(
        materials: [FilenameRuleSet.CompiledSubstrateEntry],
        treatments: [FilenameRuleSet.CompiledSubstrateEntry],
        orientations: [FilenameRuleSet.CompiledSubstrateEntry]
    ) {
        self.materials = materials
        self.treatments = treatments
        self.orientations = orientations
    }

    // MARK: - Compound-segment matching
    //
    // This is the ONLY matching entry point — used identically for a full Registry substrate
    // cell ("HF STO(111)"), a single filename/free-text tag ("STO"), and an already-canonical
    // stored field value being re-validated ("STO"). A lone token is just a compound segment
    // with one token, so there is no separate single-token code path to drift out of sync with
    // this one: every caller (Registry substrate-cell parsing, filename/free-text parsing,
    // SampleSemanticDescriptor's own field validation) shares this exact implementation.

    /// First material entry that matches within `segment`, honoring equals-across-all-entries
    /// before contains-across-all-entries (so an exact token hit always outranks a substring
    /// collision from a different entry's `.contains` rule elsewhere in the segment).
    func material(inSegment segment: String) -> String? {
        Self.firstSegmentMatch(in: materials, segment: segment)
    }

    /// First orientation entry that matches within `segment`, same precedence as above.
    func orientation(inSegment segment: String) -> String? {
        Self.firstSegmentMatch(in: orientations, segment: segment)
    }

    /// First treatment entry that matches within `segment`, same precedence as above — for
    /// callers that need a single winner (e.g. validating one already-extracted processing
    /// token). Use `treatments(inSegment:)` when multiple co-applying treatments are wanted.
    func treatment(inSegment segment: String) -> String? {
        Self.firstSegmentMatch(in: treatments, segment: segment)
    }

    /// All treatment entries that match within `segment` (multiple treatments can co-apply).
    func treatments(inSegment segment: String) -> [String] {
        let (tokens, whole) = Self.tokenizeSegment(segment)
        guard !whole.isEmpty else { return [] }
        return treatments
            .filter { $0.matches(normalizedSegmentTokens: tokens, normalizedSegment: whole) }
            .map(\.displayName)
    }

    /// Whether `segment` looks like it carries any substrate signal at all (material, treatment,
    /// or orientation) — used to decide whether a free-text segment should be parsed as substrate
    /// content in the first place.
    func hasAnySubstrateSignal(inSegment segment: String) -> Bool {
        material(inSegment: segment) != nil
            || orientation(inSegment: segment) != nil
            || !treatments(inSegment: segment).isEmpty
    }

    // MARK: - Private

    /// Two-pass precedence: an exact token hit against ANY entry's `.equals` rules always
    /// outranks a `.contains` substring hit against any entry, so a `.contains` needle that
    /// happens to appear inside another entry's exact token (e.g. orientation alias "STO111"
    /// containing material needle "STO") never shadows the entry that's an exact match.
    private static func firstSegmentMatch(in entries: [FilenameRuleSet.CompiledSubstrateEntry], segment: String) -> String? {
        let (tokens, whole) = tokenizeSegment(segment)
        guard !whole.isEmpty else { return nil }
        for entry in entries where tokens.contains(where: { entry.equalsKeysNormalized.contains($0) }) {
            return entry.displayName
        }
        for entry in entries where entry.containsNeedlesNormalized.contains(where: { whole.contains($0) }) {
            return entry.displayName
        }
        return nil
    }

    private static func tokenizeSegment(_ segment: String) -> (tokens: [String], whole: String) {
        let whole = FilenameRuleSet.normalizeForSubstrate(segment)
        let tokens = segment
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(FilenameRuleSet.normalizeForSubstrate)
            .filter { !$0.isEmpty }
        return (tokens, whole)
    }
}
