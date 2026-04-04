import Foundation

struct SampleKeyNormalizer {
    private let rules = FileRoutingRuleBook()

    func canonicalKey(
        from sampleInput: String,
        fallbackBatchID: String? = nil,
        fallbackSampleTags: [String] = []
    ) -> String? {
        let trimmed = sampleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let exact = SampleSemanticDescriptor.fromSampleKey(trimmed)?.canonicalKey {
            return exact
        }

        if let descriptor = rules.resolvedDescriptor(sampleInput: trimmed, sampleTags: [], fallback: nil),
           descriptor.hasSubstrateSignal,
           let canonical = descriptor.canonicalKey {
            return canonical
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
        return fallbackDescriptor.canonicalKey
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
