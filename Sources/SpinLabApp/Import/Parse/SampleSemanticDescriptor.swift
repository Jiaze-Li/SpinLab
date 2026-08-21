import Foundation

struct SampleSemanticDescriptor: Hashable {
    private static let ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared
    private static var classifier: SubstrateSemanticClassifier {
        SubstrateSemanticClassifier(compiled: ruleProvider.ruleSet().compiled)
    }

    var batch: String?
    var processingTokens: Set<String>
    var material: String?
    var orientation: String?

    init(
        batch: String?,
        processingTokens: Set<String> = [],
        material: String?,
        orientation: String?
    ) {
        self.batch = Self.normalizedBatch(batch)
        self.processingTokens = Set(processingTokens.compactMap(Self.normalizedProcessingToken))
        self.material = Self.normalizedMaterial(material)
        self.orientation = Self.normalizedOrientation(orientation)
    }

    var canonicalKey: String? {
        guard let batch else {
            return nil
        }
        return [
            batch,
            processingComponent,
            material ?? "UNKNOWN",
            orientation ?? "UNKNOWN"
        ].joined(separator: "|")
    }

    var hasSubstrateSignal: Bool {
        !processingTokens.isEmpty || material != nil || orientation != nil
    }

    private var processingComponent: String {
        processingTokens.sorted().joined(separator: "+")
    }

    // Use when every field is already validated by an external rule provider (e.g.
    // FileRoutingRuleBook/LibrarySubstrateParser with injected rules) — bypasses the
    // global-singleton re-validation in init so injected-provider test scenarios work
    // correctly, and so a caller that already ran its own classifier lookup doesn't pay
    // for (or risk drifting from) a second lookup against a possibly different rule source.
    static func withPrevalidatedTokens(
        batch: String?,
        processingTokens: Set<String>,
        material: String?,
        orientation: String?
    ) -> SampleSemanticDescriptor {
        var d = SampleSemanticDescriptor(batch: batch, processingTokens: [], material: nil, orientation: nil)
        d.processingTokens = processingTokens
        d.material = trustedField(material)
        d.orientation = trustedField(orientation)
        return d
    }

    static func fromSampleKey(_ sampleKey: String) -> SampleSemanticDescriptor? {
        let parts = sampleKey.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else {
            return nil
        }

        // Tokens in a canonical sampleKey are already in their canonical form — bypass
        // rule-based re-validation entirely so they are preserved regardless of the
        // current rule set configuration (rules may have changed since the key was made).
        let rawTokens = parts[1]
            .split(separator: "+", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var descriptor = SampleSemanticDescriptor(
            batch: parts[0],
            processingTokens: [],
            material: nil,
            orientation: nil
        )
        descriptor.processingTokens = Set(rawTokens)
        descriptor.material = trustedField(parts[2])
        descriptor.orientation = trustedField(parts[3])
        return descriptor
    }

    private static func normalizedBatch(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.uppercased()
    }

    /// Trim/uppercase/"UNKNOWN"-to-nil only — no rule-based validation. Used by the trusted
    /// reconstruction paths (`fromSampleKey`, `withPrevalidatedTokens`) that must preserve an
    /// already-canonical value regardless of what the current rule set can (re)validate.
    private static func trustedField(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "UNKNOWN" else {
            return nil
        }
        return trimmed.uppercased()
    }

    /// Validates against the compiled material entries and returns the entry's canonical
    /// display name — the same equals-then-contains contract every other identity entry
    /// point uses, so material can no longer drift out of sync the way processing tokens
    /// used to be the only validated field.
    private static func normalizedMaterial(_ value: String?) -> String? {
        guard let trusted = trustedField(value) else { return nil }
        return classifier.material(inSegment: trusted)
    }

    /// Validates against the compiled orientation entries and returns the entry's canonical
    /// display name — see `normalizedMaterial`.
    private static func normalizedOrientation(_ value: String?) -> String? {
        guard let trusted = trustedField(value) else { return nil }
        return classifier.orientation(inSegment: trusted)
    }

    private static func normalizedProcessingToken(_ token: String?) -> String? {
        guard let trusted = trustedField(token) else { return nil }
        return classifier.treatment(inSegment: trusted)
    }

    static func normalizedProcessingTokenForRules(_ token: String?) -> String? {
        normalizedProcessingToken(token)
    }
}
