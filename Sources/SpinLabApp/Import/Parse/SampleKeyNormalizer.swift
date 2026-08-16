import Foundation

protocol SampleDescriptorResolving {
    func resolvedDescriptor(
        sampleInput: String?,
        sampleTags: [String],
        fallback: SampleSemanticDescriptor?
    ) -> SampleSemanticDescriptor?
}

extension FileRoutingRuleBook: SampleDescriptorResolving {}

struct SampleKeyNormalizer {
    private let rules: any SampleDescriptorResolving

    init(rules: any SampleDescriptorResolving = FileRoutingRuleBook()) {
        self.rules = rules
    }

    func canonicalKey(
        from sampleInput: String,
        fallbackBatchID: String? = nil,
        fallbackSampleTags: [String] = []
    ) -> String? {
        descriptor(
            from: sampleInput,
            fallbackBatchID: fallbackBatchID,
            fallbackSampleTags: fallbackSampleTags
        )?.canonicalKey
    }

    /// Same resolution order as `canonicalKey`, but returns the structured descriptor
    /// (batch / material / orientation / processing kept apart) instead of the joined
    /// string, so callers can compare fields without a numeric batch token (e.g. "PN110")
    /// colliding with an unrelated orientation value that happens to share the same digits.
    func descriptor(
        from sampleInput: String,
        fallbackBatchID: String? = nil,
        fallbackSampleTags: [String] = []
    ) -> SampleSemanticDescriptor? {
        let trimmed = sampleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let exact = SampleSemanticDescriptor.fromSampleKey(trimmed) {
            return exact
        }

        if let descriptor = rules.resolvedDescriptor(sampleInput: trimmed, sampleTags: [], fallback: nil),
           descriptor.hasSubstrateSignal {
            return withAuthoritativeBatch(descriptor, fallbackBatchID: fallbackBatchID)
        }

        guard let fallbackBatchID else {
            return nil
        }

        let fallbackDescriptor = rules.resolvedDescriptor(
            sampleInput: fallbackBatchID,
            sampleTags: fallbackSampleTags,
            fallback: nil
        )
        guard let fallbackDescriptor,
              fallbackDescriptor.hasSubstrateSignal else {
            return nil
        }
        return fallbackDescriptor
    }

    /// `sampleInput` here has already failed the exact-canonical-key check, so any
    /// batch the rule book infers from it is only a best-effort guess parsed out of
    /// free text (e.g. "legacy-pn50-hf-sto111" infers batch "LEGACY" from the token
    /// before the first hyphen). When the caller also supplies a `fallbackBatchID` —
    /// explicit structured Library metadata for the same sample — that value is
    /// authoritative over the inferred token; only the batch is replaced, parsed
    /// material/orientation/processing signal is kept as-is.
    private func withAuthoritativeBatch(
        _ descriptor: SampleSemanticDescriptor,
        fallbackBatchID: String?
    ) -> SampleSemanticDescriptor {
        guard let fallbackBatchID,
              !fallbackBatchID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return descriptor
        }
        return SampleSemanticDescriptor.withPrevalidatedTokens(
            batch: fallbackBatchID,
            processingTokens: descriptor.processingTokens,
            material: descriptor.material,
            orientation: descriptor.orientation
        )
    }

    func canonicalOrOriginal(
        from sampleInput: String,
        fallbackBatchID: String? = nil,
        fallbackSampleTags: [String] = []
    ) -> String {
        let trimmed = sampleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return sampleInput
        }
        return canonicalKey(
            from: trimmed,
            fallbackBatchID: fallbackBatchID,
            fallbackSampleTags: fallbackSampleTags
        ) ?? trimmed
    }
}
